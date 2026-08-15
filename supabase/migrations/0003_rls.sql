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
