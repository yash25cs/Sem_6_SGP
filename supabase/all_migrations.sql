-- StudyTrail — core schema
-- Extensions, enums, and all tables (identity, planning, materials+RAG,
-- flashcards, quizzes, gamification/analytics, chat).

create extension if not exists vector;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type pace_enum          as enum ('relaxed','steady','intense');
  create type milestone_state    as enum ('done','active','upcoming');
  create type task_tag_enum      as enum ('now','quiz','done');
  create type sr_grade_enum       as enum ('again','hard','good','easy');
  create type material_type_enum as enum ('syllabus_pdf','notes','video_link');
  create type ingest_status_enum as enum ('uploaded','processing','embedded','failed');
  create type chat_role_enum      as enum ('user','ai');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Identity & class
-- ---------------------------------------------------------------------------
create table if not exists classes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  college text,
  branch text,
  batch text,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  enrollment_id text,
  branch text,
  college text,
  email text,
  avatar_initial text,
  level int not null default 1,
  xp int not null default 0,
  xp_to_next int not null default 500,
  class_id uuid references classes(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Planning core
-- ---------------------------------------------------------------------------
create table if not exists goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  exam_date date,
  pace pace_enum not null default 'steady',
  roadmap_days int,
  current_day int not null default 1,
  overall_percent numeric(5,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists goals_user_idx on goals(user_id);

create table if not exists subjects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  name text not null,
  icon_key text,
  color_key text,
  is_focus boolean not null default true,
  progress numeric(5,2) not null default 0,
  accuracy numeric(5,2) not null default 0
);
create index if not exists subjects_user_idx on subjects(user_id);

create table if not exists milestones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  week_label text,
  title text not null,
  state milestone_state not null default 'upcoming',
  order_index int not null default 0,
  color_key text
);
create index if not exists milestones_goal_idx on milestones(goal_id);

create table if not exists milestone_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  milestone_id uuid not null references milestones(id) on delete cascade,
  name text not null,
  done boolean not null default false,
  order_index int not null default 0
);
create index if not exists milestone_tasks_milestone_idx on milestone_tasks(milestone_id);

create table if not exists daily_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  milestone_task_id uuid references milestone_tasks(id) on delete set null,
  title text not null,
  duration_min int,
  tag task_tag_enum not null default 'now',
  scheduled_date date not null default current_date,
  done boolean not null default false
);
create index if not exists daily_tasks_user_date_idx on daily_tasks(user_id, scheduled_date);
-- StudyTrail — materials + RAG (pgvector), flashcards, quizzes,
-- gamification/analytics, and AI chat.

-- ---------------------------------------------------------------------------
-- Materials + RAG
-- ---------------------------------------------------------------------------
create table if not exists materials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  source_type material_type_enum not null,
  title text,
  storage_path text,
  external_url text,
  status ingest_status_enum not null default 'uploaded',
  created_at timestamptz not null default now()
);
create index if not exists materials_user_idx on materials(user_id);

-- text-embedding-004 = 768 dims. Only table needing pgvector.
create table if not exists material_chunks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  material_id uuid not null references materials(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  unit_label text,
  chunk_index int not null default 0,
  content text not null,
  embedding vector(768)
);
create index if not exists material_chunks_user_idx on material_chunks(user_id);
create index if not exists material_chunks_embedding_idx
  on material_chunks using hnsw (embedding vector_cosine_ops);

-- ---------------------------------------------------------------------------
-- Flashcards (SM-2 spaced repetition)
-- ---------------------------------------------------------------------------
create table if not exists flashcard_decks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  name text not null,
  created_at timestamptz not null default now()
);
create index if not exists flashcard_decks_user_idx on flashcard_decks(user_id);

create table if not exists flashcards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  deck_id uuid not null references flashcard_decks(id) on delete cascade,
  unit_label text,
  front text not null,
  back text not null,
  source_chunk_id uuid references material_chunks(id) on delete set null,
  ease numeric(4,2) not null default 2.5,
  interval_days int not null default 0,
  repetitions int not null default 0,
  due_at timestamptz not null default now(),
  last_grade sr_grade_enum
);
create index if not exists flashcards_deck_idx on flashcards(deck_id);
create index if not exists flashcards_due_idx on flashcards(user_id, due_at);

-- total / due counts per deck.
-- security_invoker: without it the view runs as its owner (postgres) and would
-- bypass RLS on flashcards, exposing every user's counts. Requires PG15+.
create or replace view deck_stats
with (security_invoker = true) as
select
  d.id as deck_id,
  d.user_id,
  count(c.id) as total,
  count(c.id) filter (where c.due_at <= now()) as due
from flashcard_decks d
left join flashcards c on c.deck_id = d.id
group by d.id, d.user_id;

-- ---------------------------------------------------------------------------
-- Quizzes
-- ---------------------------------------------------------------------------
create table if not exists quizzes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  title text,
  length int,
  timer_sec int not null default 30,
  created_at timestamptz not null default now()
);
create index if not exists quizzes_user_idx on quizzes(user_id);

create table if not exists quiz_questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  quiz_id uuid not null references quizzes(id) on delete cascade,
  question text not null,
  options text[] not null check (array_length(options,1) = 4),
  correct_index int not null check (correct_index between 0 and 3),
  explanation text,
  xp_reward int not null default 10,
  order_index int not null default 0
);
create index if not exists quiz_questions_quiz_idx on quiz_questions(quiz_id);

create table if not exists quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  quiz_id uuid not null references quizzes(id) on delete cascade,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  score int,
  total int,
  xp_earned int
);
create index if not exists quiz_attempts_user_idx on quiz_attempts(user_id);

create table if not exists quiz_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  attempt_id uuid not null references quiz_attempts(id) on delete cascade,
  question_id uuid not null references quiz_questions(id) on delete cascade,
  picked_index int,
  is_correct boolean
);

-- ---------------------------------------------------------------------------
-- Gamification & analytics
-- ---------------------------------------------------------------------------
create table if not exists streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak int not null default 0,
  best_streak int not null default 0,
  last_active_date date
);

create table if not exists activity_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  minutes_studied int not null default 0,
  tasks_completed int not null default 0,
  xp_earned int not null default 0,
  unique (user_id, activity_date)
);

create table if not exists badges (
  id uuid primary key default gen_random_uuid(),
  key text unique not null,
  name text not null,
  icon_key text,
  color_key text,
  description text
);

create table if not exists user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references badges(id) on delete cascade,
  unlocked boolean not null default false,
  unlocked_at timestamptz,
  primary key (user_id, badge_id)
);

create table if not exists study_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  length_min int,
  sessions_count int,
  focused_min int,
  started_at timestamptz,
  ended_at timestamptz,
  session_date date not null default current_date
);
create index if not exists study_sessions_user_idx on study_sessions(user_id, session_date);

-- ---------------------------------------------------------------------------
-- AI chat
-- ---------------------------------------------------------------------------
create table if not exists chat_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid references goals(id) on delete cascade,
  title text,
  created_at timestamptz not null default now()
);

create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid not null references chat_threads(id) on delete cascade,
  role chat_role_enum not null,
  text text not null,
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_thread_idx on chat_messages(thread_id, created_at);

create table if not exists chat_citations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null references chat_messages(id) on delete cascade,
  chunk_id uuid references material_chunks(id) on delete set null,
  unit_label text
);
-- StudyTrail — Row Level Security.
-- Owner-only access on every user-owned table; read-all on catalogs.

-- Owner-only policy applied uniformly to all tables with a user_id column.
do $$
declare
  t text;
  owner_tables text[] := array[
    'goals','subjects','milestones','milestone_tasks','daily_tasks',
    'materials','material_chunks','flashcard_decks','flashcards',
    'quizzes','quiz_questions','quiz_attempts','quiz_answers',
    'streaks','activity_log','user_badges','study_sessions',
    'chat_threads','chat_messages','chat_citations'
  ];
begin
  foreach t in array owner_tables loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists owner_all on %I;', t);
    execute format($f$
      create policy owner_all on %I
        for all to authenticated
        using (auth.uid() = user_id)
        with check (auth.uid() = user_id);
    $f$, t);
  end loop;
end $$;

-- profiles: owner reads/updates own row (class-scoped reads go through an RPC).
alter table profiles enable row level security;
drop policy if exists profiles_select_own on profiles;
create policy profiles_select_own on profiles
  for select to authenticated using (auth.uid() = id);
drop policy if exists profiles_update_own on profiles;
create policy profiles_update_own on profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists profiles_insert_own on profiles;
create policy profiles_insert_own on profiles
  for insert to authenticated with check (auth.uid() = id);

-- Catalog tables: read-only for any authenticated user.
alter table badges enable row level security;
drop policy if exists badges_read on badges;
create policy badges_read on badges for select to authenticated using (true);

alter table classes enable row level security;
drop policy if exists classes_read on classes;
create policy classes_read on classes for select to authenticated using (true);
-- StudyTrail — functions, triggers, and RPCs.

-- ---------------------------------------------------------------------------
-- New-user bootstrap: seed profiles + streaks when an auth.users row appears.
-- SECURITY DEFINER so it can write past RLS during the auth transaction.
-- ---------------------------------------------------------------------------
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, avatar_initial)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    upper(left(coalesce(new.raw_user_meta_data->>'full_name', new.email, '?'), 1))
  )
  on conflict (id) do nothing;

  insert into public.streaks (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- RAG retrieval: cosine similarity over the caller's own chunks.
-- SECURITY INVOKER (default) → RLS on material_chunks scopes rows to auth.uid();
-- the explicit user_id filter is defensive belt-and-suspenders.
-- ---------------------------------------------------------------------------
create or replace function match_material_chunks(
  query_embedding vector(768),
  match_count int default 6,
  filter_subject uuid default null
)
returns table (
  id uuid,
  material_id uuid,
  subject_id uuid,
  unit_label text,
  content text,
  similarity float
)
language sql
stable
as $$
  select
    c.id,
    c.material_id,
    c.subject_id,
    c.unit_label,
    c.content,
    1 - (c.embedding <=> query_embedding) as similarity
  from material_chunks c
  where c.user_id = auth.uid()
    and c.embedding is not null
    and (filter_subject is null or c.subject_id = filter_subject)
  order by c.embedding <=> query_embedding
  limit match_count;
$$;

-- ---------------------------------------------------------------------------
-- Class leaderboard: exposes only safe columns for peers in the caller's class.
-- SECURITY DEFINER so it can read past the owner-only profiles policy, but it
-- hard-scopes to the caller's own class_id — no cross-class leakage.
-- ---------------------------------------------------------------------------
create or replace function get_class_leaderboard(limit_count int default 20)
returns table (
  user_id uuid,
  full_name text,
  avatar_initial text,
  level int,
  xp int,
  is_me boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  my_class uuid;
begin
  select class_id into my_class from profiles where id = auth.uid();
  if my_class is null then
    return;
  end if;

  return query
    select p.id, p.full_name, p.avatar_initial, p.level, p.xp,
           (p.id = auth.uid()) as is_me
    from profiles p
    where p.class_id = my_class
    order by p.xp desc, p.level desc
    limit limit_count;
end $$;

-- ---------------------------------------------------------------------------
-- Spaced repetition (SM-2). Maps the 4-button grade to SM-2 quality, updates
-- ease / interval / repetitions / due_at, and returns the updated row.
-- SECURITY INVOKER → RLS ensures a user can only grade their own cards.
-- ---------------------------------------------------------------------------
create or replace function apply_sr_grade(card_id uuid, grade sr_grade_enum)
returns flashcards
language plpgsql
as $$
declare
  card       flashcards;
  quality    int;
  new_ease   numeric(4,2);
  new_reps   int;
  new_int    int;
begin
  select * into card from flashcards where id = card_id;
  if not found then
    raise exception 'flashcard % not found', card_id;
  end if;

  quality := case grade
    when 'again' then 1
    when 'hard'  then 3
    when 'good'  then 4
    when 'easy'  then 5
  end;

  -- Ease update, floored at 1.3.
  new_ease := greatest(1.3,
    card.ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)));

  if quality < 3 then
    new_reps := 0;
    new_int  := 1;
  else
    new_reps := card.repetitions + 1;
    new_int  := case
      when new_reps = 1 then 1
      when new_reps = 2 then 6
      else greatest(1, round(card.interval_days * new_ease))
    end;
  end if;

  update flashcards
    set ease          = new_ease,
        repetitions   = new_reps,
        interval_days = new_int,
        due_at        = now() + (new_int || ' days')::interval,
        last_grade    = grade
    where id = card_id
    returning * into card;

  return card;
end $$;
-- StudyTrail — private Storage bucket for uploaded materials.
-- Objects live under /{uid}/... so ownership is derivable from the path.
--
-- Note: storage.objects is owned by supabase_storage_admin. If this file fails
-- with "must be owner of table objects", create the bucket + these four
-- policies through Storage → Policies in the dashboard instead; the using/
-- with-check expressions below are what to paste in.

insert into storage.buckets (id, name, public)
values ('materials', 'materials', false)
on conflict (id) do nothing;

-- Owner-only access, scoped to the caller's uid folder prefix.
drop policy if exists materials_read on storage.objects;
create policy materials_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists materials_insert on storage.objects;
create policy materials_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists materials_update on storage.objects;
create policy materials_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists materials_delete on storage.objects;
create policy materials_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
-- StudyTrail — seed catalog data (badges + a default class).
-- Idempotent: safe to re-run.

-- Default class for the CSPIT / Charusat cohort so the leaderboard has a home.
insert into classes (name, college, branch, batch)
select 'CE-A 2025', 'CSPIT, Charusat University', 'Computer Engineering', '2025'
where not exists (select 1 from classes where name = 'CE-A 2025');

-- Achievement catalog. icon_key / color_key mirror the UI's token names.
insert into badges (key, name, icon_key, color_key, description) values
  ('first_step',    'First Step',      'flag',          'sky',    'Complete your first study task.'),
  ('week_warrior',  'Week Warrior',    'local_fire_department', 'amber', 'Maintain a 7-day streak.'),
  ('quiz_ace',      'Quiz Ace',        'quiz',          'violet', 'Score 100% on any quiz.'),
  ('card_master',   'Card Master',     'style',         'emerald','Review 100 flashcards.'),
  ('night_owl',     'Night Owl',       'nightlight',    'indigo', 'Study after 10 PM.'),
  ('early_bird',    'Early Bird',      'wb_sunny',      'orange', 'Study before 7 AM.'),
  ('focused_mind',  'Focused Mind',    'self_improvement','teal', 'Finish 10 Pomodoro sessions.'),
  ('roadmap_ready', 'Roadmap Ready',   'map',           'rose',   'Generate your first AI roadmap.'),
  ('curious_learner','Curious Learner','chat',          'cyan',   'Ask the AI tutor 25 questions.'),
  ('goal_crusher',  'Goal Crusher',    'emoji_events',  'gold',   'Reach 100% on a goal.')
on conflict (key) do nothing;
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
