-- EduSpace: per-tenant roles (exec guide section 15).
-- Run AFTER 0018_super_admin.sql.
--
-- A role row with tenant_id set belongs to that tenant; the legacy rows
-- with tenant_id null stay platform-wide. Holding a tenant's "admin" role
-- makes the user an admin of that tenant only.

-- ---------- roles.name uniqueness becomes (tenant, name) ----------

alter table public.roles drop constraint if exists roles_name_key;
drop index if exists roles_name_key;
drop index if exists roles_name_idx;

create unique index if not exists roles_global_name_uidx
  on public.roles (name) where tenant_id is null;
create unique index if not exists roles_tenant_name_uidx
  on public.roles (tenant_id, name) where tenant_id is not null;

-- ---------- default roles for every tenant ----------

insert into public.roles (name, tenant_id, is_system, description)
select r.name, t.id, false, r.description
from public.tenants t
cross join (
  values
    ('admin', 'Organization admin'),
    ('content_manager', 'Manages courses and content'),
    ('instructor', 'Teaches courses')
) as r(name, description)
on conflict do nothing;

create or replace function public.handle_new_tenant_roles()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.roles (name, tenant_id, is_system, description)
  values
    ('admin', new.id, false, 'Organization admin'),
    ('content_manager', new.id, false, 'Manages courses and content'),
    ('instructor', new.id, false, 'Teaches courses')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_tenant_created_roles on public.tenants;
create trigger on_tenant_created_roles
  after insert on public.tenants
  for each row execute function public.handle_new_tenant_roles();

-- ---------- tenant admin check honors tenant roles ----------

create or replace function public.is_tenant_admin(t uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_super_admin()
     or (public.is_admin() and public.is_tenant_member(t))
     or exists (
       select 1
       from public.user_roles ur
       join public.roles r on r.id = ur.role_id
       where ur.user_id = auth.uid()
         and r.tenant_id = t
         and r.name = 'admin'
     )
$$;

-- ---------- RLS: tenant admins manage their tenant's roles ----------

drop policy if exists roles_read_admin on public.roles;
create policy roles_read_admin on public.roles
  for select using (
    public.is_admin()
    or (tenant_id is not null and public.is_tenant_member(tenant_id))
  );

drop policy if exists roles_tenant_admin_insert on public.roles;
create policy roles_tenant_admin_insert on public.roles
  for insert with check (
    tenant_id is not null and public.is_tenant_admin(tenant_id)
  );

drop policy if exists roles_tenant_admin_update on public.roles;
create policy roles_tenant_admin_update on public.roles
  for update using (
    tenant_id is not null and public.is_tenant_admin(tenant_id)
  );

drop policy if exists roles_tenant_admin_delete on public.roles;
create policy roles_tenant_admin_delete on public.roles
  for delete using (
    tenant_id is not null
    and is_system = false
    and public.is_tenant_admin(tenant_id)
  );

drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles
  for select using (
    auth.uid() = user_id
    or public.is_admin()
    or exists (
      select 1 from public.roles r
      where r.id = role_id
        and r.tenant_id is not null
        and public.is_tenant_admin(r.tenant_id)
    )
  );

drop policy if exists user_roles_tenant_admin_insert on public.user_roles;
create policy user_roles_tenant_admin_insert on public.user_roles
  for insert with check (
    public.is_admin()
    or exists (
      select 1 from public.roles r
      where r.id = role_id
        and r.tenant_id is not null
        and public.is_tenant_admin(r.tenant_id)
    )
  );

drop policy if exists user_roles_tenant_admin_delete on public.user_roles;
create policy user_roles_tenant_admin_delete on public.user_roles
  for delete using (
    public.is_admin()
    or exists (
      select 1 from public.roles r
      where r.id = role_id
        and r.tenant_id is not null
        and public.is_tenant_admin(r.tenant_id)
    )
  );
