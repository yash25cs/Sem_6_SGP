-- StudyTrail — atomic multi-step writes.
--
-- Closes the first P1 finding in REVIEW.md. Creating a goal was three separate
-- round-trips from the client: deactivate the old goal, insert the new one,
-- insert its subjects. Every gap between them is a state a student can actually
-- end up in — network drops, app killed, token expires:
--
--   * after step 1 → no active goal at all. Home renders empty, and
--     `hasAnyGoal()` still says true, so onboarding won't offer to fix it.
--   * after step 2 → a goal with no subjects. The Pomodoro subject chip and the
--     Progress breakdown are both empty, and nothing tells the student why.
--
-- One RPC makes it one transaction: all three, or none. `complete_task` in
-- 0008 already did the same for the task/milestone pair.
--
-- Locals are `v_`, parameters `p_`, constants `c_` — same convention as 0008.

-- ---------------------------------------------------------------------------
-- create_goal — deactivate + insert + seed subjects, atomically.
-- ---------------------------------------------------------------------------
create or replace function public.create_goal(
  p_name       text,
  p_exam_date  date default null,
  p_pace       text default 'steady',
  p_subjects   text[] default '{}'
)
returns goals
language plpgsql
security definer
set search_path = public
as $$
declare
  -- A real exam has a handful of subjects. The bound is here so a malformed or
  -- hostile call can't seed thousands of rows in one statement.
  c_max_subjects constant int := 40;
  c_max_name     constant int := 120;

  v_user  uuid := auth.uid();
  v_pace  pace_enum;
  v_name  text := btrim(coalesce(p_name, ''));
  v_goal  goals;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if v_name = '' then
    raise exception 'a goal needs a name' using errcode = '22023';
  end if;
  if length(v_name) > c_max_name then
    raise exception 'goal name is longer than % characters', c_max_name
      using errcode = '22001';
  end if;

  -- Cast explicitly rather than typing the parameter as pace_enum: PostgREST
  -- sends JSON strings, and a clear error here beats a cast failure in the
  -- argument list that names no column.
  begin
    v_pace := coalesce(nullif(btrim(coalesce(p_pace, '')), ''), 'steady')::pace_enum;
  exception when invalid_text_representation then
    raise exception 'unknown pace %; expected relaxed, steady or intense', p_pace
      using errcode = '22023';
  end;

  -- An exam that has already happened is almost always a date-picker slip, but
  -- it's the student's call — the roadmap generator clamps, it doesn't refuse.

  update goals
    set is_active = false
    where user_id = v_user and is_active;

  insert into goals (user_id, name, exam_date, pace)
    values (v_user, v_name, p_exam_date, v_pace)
    returning * into v_goal;

  -- distinct on lower() so "DBMS" and "dbms" don't both become subjects; there
  -- is no unique constraint on (goal_id, name) to lean on.
  insert into subjects (user_id, goal_id, name)
  select v_user, v_goal.id, subject_name
  from (
    select distinct on (lower(btrim(s))) btrim(s) as subject_name
    from unnest(coalesce(p_subjects, '{}'::text[])) as s
    where btrim(s) <> ''
    order by lower(btrim(s))
  ) as cleaned
  limit c_max_subjects;

  return v_goal;
end $$;

comment on function public.create_goal(text, date, text, text[]) is
  'Creates a goal, retires the previous active one, and seeds its subjects in a '
  'single transaction. Replaces three client round-trips (REVIEW.md P1).';

grant execute on function public.create_goal(text, date, text, text[])
  to authenticated;
revoke all on function public.create_goal(text, date, text, text[]) from anon;

-- ---------------------------------------------------------------------------
-- materials.status — let a failed ingest be retried.
-- ---------------------------------------------------------------------------
--
-- `ingest_status_enum` already has `failed`; what was missing is anything that
-- sets it. The Phase C `embed-material` function marks its own failures, but a
-- function that never starts — invoke rejected, cold start timeout — leaves the
-- row on `uploaded` forever, indistinguishable from one still queued.
--
-- The client may move a row between these states because "my upload broke, try
-- again" is honest client knowledge, and nothing here is XP-bearing. It may not
-- claim `embedded`: that asserts chunks exist, which only the function can know.
revoke update on materials from anon, authenticated;
grant update (goal_id, title, status) on materials to authenticated;

-- Enforces that last sentence. The trigger fires for service_role too, so
-- `embed-material` must insert its chunks *before* flipping the status —
-- which is the order it wants anyway, so the row is never briefly lying.
create or replace function app_private.material_status_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'embedded'::ingest_status_enum
     and old.status is distinct from new.status
     and not exists (
       select 1 from material_chunks
       where material_id = new.id and embedding is not null
     )
  then
    raise exception 'material % has no embedded chunks', new.id
      using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists materials_status_guard on materials;
create trigger materials_status_guard
  before update of status on materials
  for each row execute function app_private.material_status_guard();

notify pgrst, 'reload schema';
