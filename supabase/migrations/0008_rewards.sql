-- StudyTrail — server-controlled rewards.
--
-- Closes the P0 finding in REVIEW.md. Before this migration XP, activity, and
-- badges were all reachable with client-supplied values: `award_xp(999999)`,
-- `log_activity(999999,…)`, `unlock_badge('goal_crusher')`. RLS stopped a
-- student touching *someone else's* rows but never stopped them lying about
-- their own.
--
-- The fix has three parts:
--
--   1. The privileged helpers move into `app_private`, a schema PostgREST is
--      not configured to expose and which `anon`/`authenticated` have no USAGE
--      on. They are unreachable over the API, by any URL.
--   2. Every reward is now derived from rows the server can see — a task that
--      is really unfinished, a focus block within believable bounds, a card
--      that was really due, an answer really matching `correct_index`. The
--      client says *what it did*, never *what it earned*.
--   3. Table privileges are narrowed so the reward tables can't be written
--      around the RPCs. This is the part RLS alone could never do: column and
--      table privileges are checked before policies, so `PATCH /profiles
--      {xp: 999999}` now fails on privilege, not on policy.
--
-- Locals are prefixed `v_` and parameters `p_` throughout: plpgsql raises at
-- runtime on a name that matches both a variable and a column, and most of
-- these functions write to tables whose columns share the obvious names.

-- ---------------------------------------------------------------------------
-- 1. app_private — helpers the API cannot see.
-- ---------------------------------------------------------------------------
create schema if not exists app_private;

-- Postgres grants EXECUTE on new functions to PUBLIC by default, so the schema
-- itself is the boundary: without USAGE the grant is unusable.
revoke all on schema app_private from public;
revoke all on schema app_private from anon, authenticated;
grant usage on schema app_private to postgres, service_role;

comment on schema app_private is
  'Privileged reward helpers. Not exposed by PostgREST and not granted to '
  'anon/authenticated — only SECURITY DEFINER functions in public may call in.';

-- ---------------------------------------------------------------------------
-- 2. xp_rules — the one place XP amounts are defined.
--
-- REVIEW.md P2 asked for a single documented home for the XP rules; this is it.
-- Clients may read it (so the UI can show "+15 XP" without hardcoding) but
-- cannot write it, and the RPCs below never accept an amount as an argument.
-- ---------------------------------------------------------------------------
create table if not exists xp_rules (
  action      text primary key,
  xp          int  not null check (xp >= 0 and xp <= 1000),
  unit        text not null default 'each',
  description text not null
);

comment on table xp_rules is
  'Single source of truth for XP payouts, read-only to clients.';

insert into xp_rules (action, xp, unit, description) values
  ('task_completed',  15, 'task',   'Ticking off a daily task. Paid once per task, ever.'),
  ('focus_minute',     1, 'minute', 'Per minute of a Pomodoro focus block that ran to completion.'),
  ('flashcard_review', 2, 'card',   'Grading a card that was genuinely due.'),
  ('quiz_correct',    10, 'answer', 'Ceiling for one correct quiz answer.')
on conflict (action) do update
  set xp          = excluded.xp,
      unit        = excluded.unit,
      description = excluded.description;

alter table xp_rules enable row level security;
drop policy if exists xp_rules_read on xp_rules;
create policy xp_rules_read on xp_rules for select to authenticated using (true);
revoke insert, update, delete on xp_rules from anon, authenticated;

create or replace function app_private.xp_for(p_action text)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce((select xp from public.xp_rules where action = p_action), 0);
$$;

-- ---------------------------------------------------------------------------
-- 3. One-shot task rewards.
--
-- Without this a student could tick a task off and on all afternoon and be paid
-- every time. `rewarded_at` records the first completion and is never cleared,
-- so re-completing is worth nothing.
-- ---------------------------------------------------------------------------
alter table daily_tasks add column if not exists rewarded_at timestamptz;

comment on column daily_tasks.rewarded_at is
  'When this task first paid out XP. Non-null blocks re-payment.';

-- Tasks already ticked off before this migration are treated as paid, so
-- deploying it doesn't hand out a retroactive windfall on the next toggle.
update daily_tasks set rewarded_at = now() where done and rewarded_at is null;

-- ---------------------------------------------------------------------------
-- 4. Internal helpers.
--
-- Each takes the user explicitly rather than reading auth.uid(): they run
-- inside SECURITY DEFINER callers that have already established who the caller
-- is, and an explicit argument makes that dependency visible at every call.
-- ---------------------------------------------------------------------------

-- Records activity for today and rolls the streak forward in one statement.
-- Read-then-write from the client would race between the Pomodoro timer, task
-- toggles, and quiz completion all logging at once.
create or replace function app_private.log_activity(
  p_user    uuid,
  p_minutes int default 0,
  p_tasks   int default 0,
  p_xp      int default 0
)
returns activity_log
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := current_date;
  v_row   activity_log;
  v_last  date;
  v_cur   int;
begin
  insert into activity_log (user_id, activity_date, minutes_studied,
                            tasks_completed, xp_earned)
  values (p_user, v_today, greatest(0, p_minutes), greatest(0, p_tasks),
          greatest(0, p_xp))
  on conflict (user_id, activity_date) do update
    set minutes_studied = activity_log.minutes_studied + greatest(0, p_minutes),
        tasks_completed = activity_log.tasks_completed + greatest(0, p_tasks),
        xp_earned       = activity_log.xp_earned + greatest(0, p_xp)
  returning * into v_row;

  -- Roll the streak: same day = no-op, yesterday = +1, older/never = reset to 1.
  select last_active_date, current_streak
    into v_last, v_cur
    from streaks where user_id = p_user;

  if found and v_last is distinct from v_today then
    v_cur := case
      when v_last = v_today - 1 then coalesce(v_cur, 0) + 1
      else 1
    end;
    update streaks
      set current_streak   = v_cur,
          best_streak      = greatest(best_streak, v_cur),
          last_active_date = v_today
      where user_id = p_user;
  end if;

  return v_row;
end $$;

-- Adds XP and levels up. Each level costs 20% more than the last.
create or replace function app_private.award_xp(p_user uuid, p_amount int)
returns profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_xp    int;
  v_level int;
  v_next  int;
  v_row   profiles;
begin
  select xp, level, xp_to_next into v_xp, v_level, v_next
    from profiles where id = p_user;
  if not found then
    raise exception 'no profile for %', p_user;
  end if;

  -- Guard the loop: a zero/negative threshold would never be reached.
  if v_next is null or v_next <= 0 then
    v_next := 100;
  end if;

  v_xp := v_xp + greatest(0, p_amount);
  while v_xp >= v_next loop
    v_xp    := v_xp - v_next;
    v_level := v_level + 1;
    v_next  := round(v_next * 1.2);
  end loop;

  update profiles
    set xp = v_xp, level = v_level, xp_to_next = v_next, updated_at = now()
    where id = p_user
    returning * into v_row;

  return v_row;
end $$;

-- Idempotent unlock. Returns true only the first time, which is the cue for the
-- "unlocked!" toast.
create or replace function app_private.unlock_badge(p_user uuid, p_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_badge   uuid;
  v_changed int;
begin
  select id into v_badge from badges where key = p_key;
  if v_badge is null then
    return false;
  end if;

  insert into user_badges (user_id, badge_id, unlocked, unlocked_at)
  values (p_user, v_badge, true, now())
  on conflict (user_id, badge_id) do update
    set unlocked    = true,
        unlocked_at = coalesce(user_badges.unlocked_at, now())
    where user_badges.unlocked = false;

  get diagnostics v_changed = row_count;
  return v_changed > 0;
end $$;

-- ---------------------------------------------------------------------------
-- Badge evaluation.
--
-- This replaces `unlock_badge(key)` as the client-facing entry point. Every
-- condition below is checked against real rows, so asking for a badge you
-- haven't earned returns nothing rather than granting it. Conditions mirror the
-- catalog descriptions in 0006_seed.sql.
--
-- Returns the keys unlocked *by this call* — an empty set on every call after
-- the first.
-- ---------------------------------------------------------------------------
create or replace function app_private.evaluate_badges(p_user uuid)
returns setof text
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Hour-of-day badges are judged in the cohort's local time; started_at is
  -- timestamptz, so without this "study after 10 PM" would mean 10 PM UTC.
  v_tz  constant text := 'Asia/Kolkata';
  v_key text;
begin
  for v_key in
    select k from (values
      -- 'Complete your first study task.'
      ('first_step',
       exists (select 1 from daily_tasks
                where user_id = p_user and done)),
      -- 'Maintain a 7-day streak.' — best_streak, so it survives a lapse.
      ('week_warrior',
       exists (select 1 from streaks
                where user_id = p_user and best_streak >= 7)),
      -- 'Score 100% on any quiz.'
      ('quiz_ace',
       exists (select 1 from quiz_attempts
                where user_id = p_user and completed_at is not null
                  and total > 0 and score = total)),
      -- 'Review 100 flashcards.' — repetitions only ever move via the SR RPC.
      ('card_master',
       coalesce((select sum(repetitions) from flashcards
                  where user_id = p_user), 0) >= 100),
      -- 'Study after 10 PM.'
      ('night_owl',
       exists (select 1 from study_sessions
                where user_id = p_user and started_at is not null
                  and extract(hour from started_at at time zone v_tz) >= 22)),
      -- 'Study before 7 AM.'
      ('early_bird',
       exists (select 1 from study_sessions
                where user_id = p_user and started_at is not null
                  and extract(hour from started_at at time zone v_tz) < 7)),
      -- 'Finish 10 Pomodoro sessions.'
      ('focused_mind',
       coalesce((select sum(sessions_count) from study_sessions
                  where user_id = p_user), 0) >= 10),
      -- 'Generate your first AI roadmap.'
      ('roadmap_ready',
       exists (select 1 from milestones where user_id = p_user)),
      -- 'Ask the AI tutor 25 questions.'
      ('curious_learner',
       (select count(*) from chat_messages
         where user_id = p_user and role = 'user') >= 25),
      -- 'Reach 100% on a goal.'
      ('goal_crusher',
       exists (select 1 from goals
                where user_id = p_user and overall_percent >= 100))
    ) as t(k, earned)
    where earned
  loop
    if app_private.unlock_badge(p_user, v_key) then
      return next v_key;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Retire the client-callable reward RPCs.
--
-- Dropped rather than revoked so a stale build fails loudly with "function not
-- found" instead of silently doing nothing. plpgsql resolves function names at
-- runtime, so recreating the callers below is enough to keep them working.
-- ---------------------------------------------------------------------------
drop function if exists public.award_xp(int);
drop function if exists public.log_activity(int, int, int);
drop function if exists public.unlock_badge(text);

-- ---------------------------------------------------------------------------
-- 6. Public RPCs — the only way to earn anything.
--
-- All SECURITY DEFINER, which means RLS does *not* apply inside them. Every one
-- therefore re-checks ownership explicitly against auth.uid(); the `and
-- user_id = v_user` clauses below are load-bearing, not decoration.
-- ---------------------------------------------------------------------------

-- Ticks a daily task off (or back on) and pays out at most once.
create or replace function public.complete_task(p_task uuid, p_done boolean)
returns daily_tasks
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  -- Tasks are student-authored, so "complete a task" is XP the student can mint
  -- by typing. The cap is what keeps that honest: 20 paid completions a day is
  -- more than any real checklist, and the 21st still counts toward the streak.
  c_daily_paid_tasks constant int := 20;

  v_user       uuid := auth.uid();
  v_before     daily_tasks;
  v_row        daily_tasks;
  v_first      boolean;
  v_paid_today int;
  v_minutes    int;
  v_xp         int;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_before
    from daily_tasks where id = p_task and user_id = v_user;
  if not found then
    raise exception 'task % not found', p_task using errcode = 'no_data_found';
  end if;

  if v_before.done = p_done then
    return v_before;  -- idempotent; never a second payout
  end if;

  -- Whether this is the first completion has to be read before the update.
  v_first := p_done and v_before.rewarded_at is null;

  update daily_tasks
    set done        = p_done,
        tag         = case when p_done then 'done'::task_tag_enum
                           else 'now'::task_tag_enum end,
        rewarded_at = case when v_first then now() else rewarded_at end
    where id = p_task
    returning * into v_row;

  -- Keep the roadmap checkbox in step. Same transaction, so the two screens
  -- can't disagree the way two separate client calls could.
  if v_row.milestone_task_id is not null then
    update milestone_tasks
      set done = p_done
      where id = v_row.milestone_task_id and user_id = v_user;
  end if;

  if v_first then
    -- duration_min is student-entered, so it's clamped before it reaches the
    -- study log: a task claiming 99999 minutes is worth at most four hours.
    v_minutes := least(greatest(coalesce(v_row.duration_min, 0), 0), 240);

    select count(*) into v_paid_today
      from daily_tasks
      where user_id = v_user
        and rewarded_at is not null
        and rewarded_at >= date_trunc('day', now());

    -- Over the cap the work still lands in the log — it happened — but it is
    -- worth no XP. rewarded_at is set either way, so the same task can't come
    -- back tomorrow for a second try at the payout.
    v_xp := case when v_paid_today > c_daily_paid_tasks
                 then 0
                 else app_private.xp_for('task_completed') end;

    perform app_private.log_activity(v_user, v_minutes, 1, v_xp);
    if v_xp > 0 then
      perform app_private.award_xp(v_user, v_xp);
    end if;
    perform app_private.evaluate_badges(v_user);
  end if;

  return v_row;
end $$;

-- Persists one finished Pomodoro focus block and pays for the minutes in it.
create or replace function public.record_focus_session(
  p_subject     uuid default null,
  p_length_min  int  default 25,
  p_focused_min int  default null
)
returns study_sessions
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_focused int;
  v_today   int;
  v_xp      int;
  v_row     study_sessions;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- A focus block longer than three hours isn't a Pomodoro, it's a forged one.
  if p_length_min is null or p_length_min < 1 or p_length_min > 180 then
    raise exception 'length_min must be between 1 and 180, got %', p_length_min
      using errcode = 'check_violation';
  end if;

  v_focused := coalesce(p_focused_min, p_length_min);
  if v_focused < 0 or v_focused > p_length_min then
    raise exception 'focused_min must be between 0 and length_min'
      using errcode = 'check_violation';
  end if;

  -- Parent-ownership check (REVIEW.md P2): a known subject id belonging to
  -- someone else must not become the parent of the caller's session.
  if p_subject is not null
     and not exists (select 1 from subjects
                      where id = p_subject and user_id = v_user) then
    raise exception 'subject % not found', p_subject using errcode = 'no_data_found';
  end if;

  -- Sixteen hours of logged focus in one day is the outer edge of plausible;
  -- past that, stop counting rather than trust the clock the client sent.
  select coalesce(sum(focused_min), 0) into v_today
    from study_sessions
    where user_id = v_user and session_date = current_date;

  if v_today + v_focused > 960 then
    raise exception 'daily focus limit reached' using errcode = 'check_violation';
  end if;

  insert into study_sessions (user_id, subject_id, length_min, sessions_count,
                              focused_min, started_at, ended_at)
  values (v_user, p_subject, p_length_min, 1, v_focused,
          now() - make_interval(mins => v_focused), now())
  returning * into v_row;

  v_xp := v_focused * app_private.xp_for('focus_minute');
  perform app_private.log_activity(v_user, v_focused, 0, v_xp);
  perform app_private.award_xp(v_user, v_xp);
  perform app_private.evaluate_badges(v_user);

  return v_row;
end $$;

-- Spaced repetition (SM-2), now also the only writer of a card's SR state.
--
-- Maps the 4-button grade to SM-2 quality, updates ease / interval /
-- repetitions / due_at, and pays for the review. Parameter names are unchanged
-- from 0004 because `create or replace` cannot rename them — and because the
-- client already calls it this way.
create or replace function public.apply_sr_grade(card_id uuid, grade sr_grade_enum)
returns flashcards
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_card    flashcards;
  v_was_due boolean;
  v_quality int;
  v_ease    numeric(4,2);
  v_reps    int;
  v_int     int;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_card
    from flashcards where id = card_id and user_id = v_user;
  if not found then
    raise exception 'flashcard % not found', card_id using errcode = 'no_data_found';
  end if;

  -- Only a card that had actually come up for review pays out. Grading pushes
  -- due_at at least a day forward, so this caps earnings at one payment per
  -- card per day without needing a counter to track it.
  v_was_due := v_card.due_at <= now();

  v_quality := case grade
    when 'again' then 1
    when 'hard'  then 3
    when 'good'  then 4
    when 'easy'  then 5
  end;

  -- Ease update, floored at 1.3.
  v_ease := greatest(1.3,
    v_card.ease + (0.1 - (5 - v_quality) * (0.08 + (5 - v_quality) * 0.02)));

  if v_quality < 3 then
    v_reps := 0;
    v_int  := 1;
  else
    v_reps := v_card.repetitions + 1;
    v_int  := case
      when v_reps = 1 then 1
      when v_reps = 2 then 6
      else greatest(1, round(v_card.interval_days * v_ease))
    end;
  end if;

  update flashcards
    set ease          = v_ease,
        repetitions   = v_reps,
        interval_days = v_int,
        due_at        = now() + make_interval(days => v_int),
        last_grade    = grade
    where id = card_id
    returning * into v_card;

  if v_was_due then
    perform app_private.log_activity(
      v_user, 0, 0, app_private.xp_for('flashcard_review'));
    perform app_private.award_xp(
      v_user, app_private.xp_for('flashcard_review'));
    perform app_private.evaluate_badges(v_user);
  end if;

  return v_card;
end $$;

-- Scores a finished quiz attempt. The client sends what it picked; correctness
-- is decided here against quiz_questions.
create or replace function public.finish_quiz_attempt(attempt uuid, picks jsonb)
returns quiz_attempts
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user     uuid := auth.uid();
  v_row      quiz_attempts;
  v_score    int := 0;
  v_total    int := 0;
  v_earned   int := 0;
  v_cap      int;
  v_question record;
  v_picked   int;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_row
    from quiz_attempts where id = attempt and user_id = v_user;
  if not found then
    raise exception 'attempt % not found', attempt using errcode = 'no_data_found';
  end if;
  if v_row.completed_at is not null then
    return v_row;  -- already scored; don't double-award
  end if;

  -- xp_reward is a client-writable column, so the rules table caps it. Without
  -- this, inserting a question worth 999999 XP would be a payout of 999999.
  v_cap := app_private.xp_for('quiz_correct');

  for v_question in
    select id, correct_index, xp_reward
      from quiz_questions
      -- Ownership of the parent question set, not just of the attempt.
      where quiz_id = v_row.quiz_id and user_id = v_user
      order by order_index
  loop
    v_total  := v_total + 1;
    v_picked := nullif(picks ->> v_question.id::text, '')::int;

    insert into quiz_answers (user_id, attempt_id, question_id, picked_index,
                              is_correct)
    values (v_user, attempt, v_question.id, v_picked,
            v_picked is not distinct from v_question.correct_index);

    if v_picked is not distinct from v_question.correct_index then
      v_score  := v_score + 1;
      v_earned := v_earned + least(greatest(coalesce(v_question.xp_reward, 0), 0), v_cap);
    end if;
  end loop;

  update quiz_attempts
    set score = v_score, total = v_total, xp_earned = v_earned,
        completed_at = now()
    where id = attempt
    returning * into v_row;

  perform app_private.award_xp(v_user, v_earned);
  perform app_private.log_activity(v_user, 0, 0, v_earned);
  perform app_private.evaluate_badges(v_user);

  return v_row;
end $$;

-- Re-derives a goal's completion from its roadmap tasks.
--
-- Was computed client-side and written straight to goals.overall_percent, which
-- is the input to the goal_crusher badge — so the badge was effectively
-- self-certified. Now the percentage is counted server-side and the column is
-- no longer client-writable.
create or replace function public.recompute_goal_progress(p_goal uuid)
returns numeric
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user    uuid := auth.uid();
  v_total   int;
  v_done    int;
  v_percent numeric(5,2);
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if not exists (select 1 from goals where id = p_goal and user_id = v_user) then
    raise exception 'goal % not found', p_goal using errcode = 'no_data_found';
  end if;

  select count(*), count(*) filter (where mt.done)
    into v_total, v_done
    from milestone_tasks mt
    join milestones m on m.id = mt.milestone_id
    where m.goal_id = p_goal and mt.user_id = v_user;

  v_percent := case when v_total = 0 then 0
                    else round((v_done::numeric / v_total) * 100, 2) end;

  update goals set overall_percent = v_percent where id = p_goal;
  perform app_private.evaluate_badges(v_user);

  return v_percent;
end $$;

-- Client-facing badge check, for the Achievements screen to call on open.
-- Returns only the keys this call newly unlocked.
create or replace function public.evaluate_badges()
returns setof text
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  return query select app_private.evaluate_badges(v_user);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Narrow the table privileges.
--
-- The RPCs above are pointless if the same rows are writable directly. These
-- revokes are what actually closes the hole; the DEFINER functions are
-- unaffected because they execute as the owner.
-- ---------------------------------------------------------------------------

-- Reward state: readable by its owner, written only by the RPCs.
revoke insert, update, delete on activity_log   from anon, authenticated;
revoke insert, update, delete on streaks        from anon, authenticated;
revoke insert, update, delete on user_badges    from anon, authenticated;
revoke insert, update, delete on study_sessions from anon, authenticated;
revoke insert, update, delete on quiz_answers   from anon, authenticated;

-- Attempts are opened by the client and scored by finish_quiz_attempt, so
-- insert stays and update goes.
revoke update on quiz_attempts from anon, authenticated;

-- profiles: level/xp/xp_to_next become server-only. Column-level grants are the
-- only way to say this — an RLS policy can restrict *which rows* you may update
-- but not which columns.
revoke update on profiles from anon, authenticated;
grant update (full_name, enrollment_id, branch, college, avatar_initial,
              class_id, updated_at)
  on profiles to authenticated;

-- flashcards: content is the student's, SM-2 state is the server's. Leaving
-- `repetitions` writable would have made the card_master badge self-certified.
revoke update on flashcards from anon, authenticated;
grant update (deck_id, unit_label, front, back) on flashcards to authenticated;

-- goals: overall_percent (and the roadmap counters) move behind
-- recompute_goal_progress and the Phase C roadmap generator.
revoke update on goals from anon, authenticated;
grant update (name, exam_date, pace, is_active) on goals to authenticated;

-- subjects: progress/accuracy are derived from quiz and task history, so they
-- are not the client's to assert.
revoke update on subjects from anon, authenticated;
grant update (goal_id, name, icon_key, color_key, is_focus)
  on subjects to authenticated;

-- Revoking UPDATE alone would have left the same forgery reachable one step
-- earlier, at INSERT: `POST /quiz_attempts {score:10,total:10,completed_at:…}`
-- self-certifies quiz_ace without a quiz existing. Postgres has column-level
-- INSERT grants too, so each table below is narrowed to exactly the columns the
-- Flutter repositories actually send.
revoke insert on quiz_attempts from anon, authenticated;
grant insert (user_id, quiz_id) on quiz_attempts to authenticated;

revoke insert on flashcards from anon, authenticated;
grant insert (user_id, deck_id, unit_label, front, back, source_chunk_id)
  on flashcards to authenticated;

revoke insert on goals from anon, authenticated;
grant insert (user_id, name, exam_date, pace, roadmap_days)
  on goals to authenticated;

revoke insert on subjects from anon, authenticated;
grant insert (user_id, goal_id, name, icon_key, color_key, is_focus)
  on subjects to authenticated;

-- daily_tasks: `done` and `rewarded_at` belong to complete_task. A task created
-- pre-ticked would otherwise hand out first_step for free.
revoke insert on daily_tasks from anon, authenticated;
grant insert (user_id, goal_id, subject_id, milestone_task_id, title,
              duration_min, tag, scheduled_date)
  on daily_tasks to authenticated;

-- profiles rows come from the handle_new_user trigger (SECURITY DEFINER, so it
-- writes past this), never from the app.
revoke insert on profiles from anon, authenticated;

-- Roadmaps and quizzes are generated artefacts: nothing in the app creates one
-- by hand, and both are XP-bearing if forged — a self-authored quiz with known
-- answers would be a free 10 XP a question. The client keeps only the two
-- checkbox writes it genuinely makes, plus DELETE for regenerating a roadmap.
--
-- Phase C consequence: generate-roadmap and generate-quiz must write with the
-- service_role key after verifying the JWT, not by forwarding the user's token.
revoke insert on milestones, milestone_tasks, quizzes, quiz_questions
  from anon, authenticated;

revoke update on milestones from anon, authenticated;
grant update (state) on milestones to authenticated;

revoke update on milestone_tasks from anon, authenticated;
grant update (done) on milestone_tasks to authenticated;

revoke update on quizzes, quiz_questions from anon, authenticated;

-- DELETE is the same forgery from the other side: drop the roadmap tasks you
-- haven't done and recompute_goal_progress reports 100%; drop the questions you
-- got wrong before finishing and the attempt scores full marks. Deleting the
-- parent still works — the FK cascade doesn't consult these privileges — so the
-- app keeps regenerating a roadmap and deleting a quiz.
revoke delete on milestone_tasks, quiz_questions from anon, authenticated;

-- Left deliberately open, and worth naming so the next reader doesn't assume
-- they were missed:
--   * daily_tasks / flashcards INSERT — creating a task or a card is a real
--     feature, so both are still routes to XP through actual typing. The daily
--     caps in complete_task and the due-date gate in apply_sr_grade bound them.
--   * chat_messages INSERT (role='user') — curious_learner counts these, and the
--     app inserts its own outgoing messages today. Phase C moves that write into
--     the chat function; the grant can be narrowed then.

-- Policies for the read-only reward tables, narrowed from `for all` to match
-- the privileges above. Defence in depth, and it documents the intent in the
-- place a reader looks first.
do $$
declare
  v_table text;
  v_read_only text[] := array[
    'activity_log','streaks','user_badges','study_sessions','quiz_answers'
  ];
begin
  foreach v_table in array v_read_only loop
    execute format('drop policy if exists owner_all on %I;', v_table);
    execute format('drop policy if exists owner_read on %I;', v_table);
    execute format($f$
      create policy owner_read on %I
        for select to authenticated
        using (auth.uid() = user_id);
    $f$, v_table);
  end loop;
end $$;

-- New functions are executable by PUBLIC by default; name the grants anyway so
-- the intended surface is explicit and reviewable.
grant execute on function public.complete_task(uuid, boolean)          to authenticated;
grant execute on function public.record_focus_session(uuid, int, int)  to authenticated;
grant execute on function public.apply_sr_grade(uuid, sr_grade_enum)   to authenticated;
grant execute on function public.finish_quiz_attempt(uuid, jsonb)      to authenticated;
grant execute on function public.recompute_goal_progress(uuid)         to authenticated;
grant execute on function public.evaluate_badges()                     to authenticated;

revoke all on function public.complete_task(uuid, boolean)         from anon;
revoke all on function public.record_focus_session(uuid, int, int) from anon;
revoke all on function public.apply_sr_grade(uuid, sr_grade_enum)  from anon;
revoke all on function public.finish_quiz_attempt(uuid, jsonb)     from anon;
revoke all on function public.recompute_goal_progress(uuid)        from anon;
revoke all on function public.evaluate_badges()                    from anon;

-- PostgREST caches the schema; without this the new RPCs 404 until it restarts.
notify pgrst, 'reload schema';
