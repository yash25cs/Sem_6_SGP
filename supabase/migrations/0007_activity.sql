-- StudyTrail — activity, streaks, XP, and quiz scoring RPCs.
-- Split out from 0004 so the core schema stays stable while these evolve.
--
-- Locals are prefixed `v_` throughout: plpgsql resolves an unqualified name
-- that matches both a variable and a column as an error, so `set score = score`
-- would fail at runtime.

-- ---------------------------------------------------------------------------
-- Records study activity for today and rolls the streak forward in one
-- statement. Read-then-write from the client would race between the Pomodoro
-- timer, task toggles, and quiz completion all logging at once.
-- SECURITY INVOKER → RLS confines every write to the caller's own rows.
-- ---------------------------------------------------------------------------
create or replace function log_activity(
  minutes int default 0,
  tasks int default 0,
  xp int default 0
)
returns activity_log
language plpgsql
as $$
declare
  v_today date := current_date;
  v_row   activity_log;
  v_last  date;
  v_cur   int;
begin
  insert into activity_log (user_id, activity_date, minutes_studied,
                            tasks_completed, xp_earned)
  values (auth.uid(), v_today, greatest(0, minutes), greatest(0, tasks),
          greatest(0, xp))
  on conflict (user_id, activity_date) do update
    set minutes_studied = activity_log.minutes_studied + greatest(0, minutes),
        tasks_completed = activity_log.tasks_completed + greatest(0, tasks),
        xp_earned       = activity_log.xp_earned + greatest(0, xp)
  returning * into v_row;

  -- Roll the streak: same day = no-op, yesterday = +1, older/never = reset to 1.
  select last_active_date, current_streak
    into v_last, v_cur
    from streaks where user_id = auth.uid();

  if found and v_last is distinct from v_today then
    v_cur := case
      when v_last = v_today - 1 then coalesce(v_cur, 0) + 1
      else 1
    end;
    update streaks
      set current_streak   = v_cur,
          best_streak      = greatest(best_streak, v_cur),
          last_active_date = v_today
      where user_id = auth.uid();
  end if;

  return v_row;
end $$;

-- ---------------------------------------------------------------------------
-- Awards XP and levels up. Same race argument as log_activity: quiz results,
-- task completion, and Pomodoro all grant XP independently.
-- Each level costs 20% more than the last.
-- ---------------------------------------------------------------------------
create or replace function award_xp(amount int)
returns profiles
language plpgsql
as $$
declare
  v_xp    int;
  v_level int;
  v_next  int;
  v_row   profiles;
begin
  select xp, level, xp_to_next into v_xp, v_level, v_next
    from profiles where id = auth.uid();
  if not found then
    raise exception 'no profile for %', auth.uid();
  end if;

  -- Guard the loop: a zero/negative threshold would never be reached.
  if v_next is null or v_next <= 0 then
    v_next := 100;
  end if;

  v_xp := v_xp + greatest(0, amount);
  while v_xp >= v_next loop
    v_xp    := v_xp - v_next;
    v_level := v_level + 1;
    v_next  := round(v_next * 1.2);
  end loop;

  update profiles
    set xp = v_xp, level = v_level, xp_to_next = v_next, updated_at = now()
    where id = auth.uid()
    returning * into v_row;

  return v_row;
end $$;

-- ---------------------------------------------------------------------------
-- Scores a finished quiz attempt server-side. The client sends what it picked;
-- correctness is decided here against quiz_questions so a tampered client
-- can't inflate its own score or XP.
-- picks: jsonb object of {question_id: picked_index}.
-- ---------------------------------------------------------------------------
create or replace function finish_quiz_attempt(attempt uuid, picks jsonb)
returns quiz_attempts
language plpgsql
as $$
declare
  v_row      quiz_attempts;
  v_score    int := 0;
  v_total    int := 0;
  v_earned   int := 0;
  v_question record;
  v_picked   int;
begin
  select * into v_row from quiz_attempts where id = attempt;
  if not found then
    raise exception 'attempt % not found', attempt;
  end if;
  if v_row.completed_at is not null then
    return v_row;  -- already scored; don't double-award
  end if;

  for v_question in
    select id, correct_index, xp_reward
      from quiz_questions where quiz_id = v_row.quiz_id
  loop
    v_total  := v_total + 1;
    v_picked := nullif(picks ->> v_question.id::text, '')::int;

    insert into quiz_answers (user_id, attempt_id, question_id, picked_index,
                              is_correct)
    values (auth.uid(), attempt, v_question.id, v_picked,
            v_picked is not distinct from v_question.correct_index);

    if v_picked is not distinct from v_question.correct_index then
      v_score  := v_score + 1;
      v_earned := v_earned + v_question.xp_reward;
    end if;
  end loop;

  update quiz_attempts
    set score = v_score, total = v_total, xp_earned = v_earned,
        completed_at = now()
    where id = attempt
    returning * into v_row;

  perform award_xp(v_earned);
  perform log_activity(0, 0, v_earned);

  return v_row;
end $$;

-- ---------------------------------------------------------------------------
-- Unlocks a badge by its stable key. Idempotent — re-unlocking is a no-op, so
-- the client can call this whenever a milestone is hit without checking first.
-- Returns true only the first time, which is the cue to show the "unlocked!"
-- toast.
-- ---------------------------------------------------------------------------
create or replace function unlock_badge(badge_key text)
returns boolean
language plpgsql
as $$
declare
  v_badge   uuid;
  v_changed int;
begin
  select id into v_badge from badges where key = badge_key;
  if v_badge is null then
    return false;
  end if;

  insert into user_badges (user_id, badge_id, unlocked, unlocked_at)
  values (auth.uid(), v_badge, true, now())
  on conflict (user_id, badge_id) do update
    set unlocked    = true,
        unlocked_at = coalesce(user_badges.unlocked_at, now())
    where user_badges.unlocked = false;

  get diagnostics v_changed = row_count;
  return v_changed > 0;
end $$;
