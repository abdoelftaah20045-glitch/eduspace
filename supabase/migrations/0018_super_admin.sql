-- EduSpace: platform super admin seed + membership update hardening.
-- Run AFTER 0017_tenant_rls.sql.

-- Seed the platform team from the existing legacy global admins so the
-- super admin panel has an owner from day one. The per-tenant roles stage
-- will refine this.
insert into public.super_admins (user_id)
select distinct ur.user_id
from public.user_roles ur
join public.roles r on r.id = ur.role_id
where r.name in ('super_admin', 'admin')
on conflict (user_id) do nothing;

-- Approval decisions may not move a membership to another tenant.
drop policy if exists memberships_admin_update on public.tenant_memberships;
create policy memberships_admin_update on public.tenant_memberships
  for update to authenticated
  using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));
