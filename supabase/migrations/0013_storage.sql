-- EduSpace: Supabase Storage buckets (exec guide section 17, Storage).
-- Run AFTER 0012_library.sql.
--
-- Buckets:
--   avatars      (public)  profile pictures; non-sensitive, shown everywhere.
--                          Each user manages only their own folder "<uid>/...".
--   resources    (private) library files; read via short-lived signed URLs.
--   course_media (private) lesson videos/images/files.
--   certificates (private) generated certificate PDFs.
--   submissions  (private) assignment submissions; owner + admins only.
--
-- Private buckets: any signed-in user can READ (single-organization stage;
-- per-course checks live in the table RLS, e.g. library_items), only admins
-- can write. Tighten to per-entitlement when the multi-tenant stage lands.

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('resources', 'resources', false),
  ('course-media', 'course-media', false),
  ('certificates', 'certificates', false),
  ('submissions', 'submissions', false)
on conflict (id) do nothing;

-- ---------- avatars ----------
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists avatars_own_insert on storage.objects;
create policy avatars_own_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_own_update on storage.objects;
create policy avatars_own_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_own_delete on storage.objects;
create policy avatars_own_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------- private buckets: read for signed-in users ----------
drop policy if exists private_files_read on storage.objects;
create policy private_files_read on storage.objects
  for select to authenticated
  using (bucket_id in ('resources', 'course-media', 'certificates', 'submissions'));

-- ---------- private buckets: write for admins only ----------
drop policy if exists private_files_admin_write on storage.objects;
create policy private_files_admin_write on storage.objects
  for all to authenticated
  using (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and public.is_admin()
  )
  with check (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and public.is_admin()
  );

-- ---------- submissions: students manage their own folder ----------
drop policy if exists submissions_own_insert on storage.objects;
create policy submissions_own_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'submissions'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
