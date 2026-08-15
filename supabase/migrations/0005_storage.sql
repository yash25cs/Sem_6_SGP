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
