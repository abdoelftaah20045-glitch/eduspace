-- EduSpace: public course-cover bucket + tenant-aware storage writes.
-- Run AFTER 0020_tenant_admin_update.sql.

-- Public bucket for course covers (marketing images, no signed URLs).
insert into storage.buckets (id, name, public)
values ('covers', 'covers', true)
on conflict (id) do nothing;

drop policy if exists covers_read on storage.objects;
create policy covers_read on storage.objects
  for select using (bucket_id = 'covers');

-- Helper: first path segment as uuid, null when it is not one.
create or replace function public.storage_tenant_from_path(p_name text)
returns uuid
language sql stable
as $$
  select case
    when (storage.foldername(p_name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then ((storage.foldername(p_name))[1])::uuid
    else null
  end
$$;

drop policy if exists covers_write on storage.objects;
create policy covers_write on storage.objects
  for all to authenticated
  using (
    bucket_id = 'covers'
    and public.is_tenant_admin(public.storage_tenant_from_path(name))
  )
  with check (
    bucket_id = 'covers'
    and public.is_tenant_admin(public.storage_tenant_from_path(name))
  );

-- Private media buckets: tenant-role admins write inside their tenant
-- folder (first path segment = tenant id); legacy global admins keep
-- writing anywhere.
drop policy if exists private_files_admin_write on storage.objects;
create policy private_files_admin_write on storage.objects
  for all to authenticated
  using (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and (
      public.is_admin()
      or public.is_super_admin()
      or public.is_tenant_admin(public.storage_tenant_from_path(name))
    )
  )
  with check (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and (
      public.is_admin()
      or public.is_super_admin()
      or public.is_tenant_admin(public.storage_tenant_from_path(name))
    )
  );
