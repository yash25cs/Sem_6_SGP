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
