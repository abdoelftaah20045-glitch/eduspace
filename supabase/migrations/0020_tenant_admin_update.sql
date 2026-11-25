-- EduSpace: tenant admins manage their own organization's profile fields.
-- Run AFTER 0019_tenant_roles.sql.
-- Status stays super-admin only; invite code rotation stays super-admin
-- only for now.

drop policy if exists tenants_admin_update on public.tenants;
create policy tenants_admin_update on public.tenants
  for update to authenticated
  using (public.is_tenant_admin(id))
  with check (public.is_tenant_admin(id));

-- Guard: tenant admins may not flip status or invite_code through this
-- policy; those columns must keep their old values unless the writer is a
-- super admin.
create or replace function public.guard_tenant_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if public.is_super_admin() then
    return new;
  end if;
  if new.status is distinct from old.status
     or new.invite_code is distinct from old.invite_code then
    raise exception 'only super admins can change status or invite code';
  end if;
  return new;
end;
$$;

drop trigger if exists on_tenant_update_guard on public.tenants;
create trigger on_tenant_update_guard
  before update on public.tenants
  for each row execute function public.guard_tenant_update();
