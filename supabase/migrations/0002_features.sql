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
