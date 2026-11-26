-- Admin adds an existing user to an organization directly (no invite code
-- or approval step), optionally as organization admin.
create or replace function public.admin_add_member(
  p_tenant uuid, p_email text, p_admin boolean default false)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  uid uuid;
  rid uuid;
begin
  if not public.is_tenant_admin(p_tenant) then
    raise exception 'not_allowed';
  end if;
  select id into uid from public.profiles
   where lower(email) = lower(trim(p_email)) limit 1;
  if uid is null then
    raise exception 'user_not_found';
  end if;
  insert into public.tenant_memberships (tenant_id, user_id, status, approved_at, approved_by)
  values (p_tenant, uid, 'active', now(), auth.uid())
  on conflict (tenant_id, user_id)
  do update set status = 'active',
    approved_at = coalesce(public.tenant_memberships.approved_at, now());
  if p_admin then
    select id into rid from public.roles
     where tenant_id = p_tenant and name = 'admin' limit 1;
    if rid is null then
      insert into public.roles (name, tenant_id, is_system, description)
      values ('admin', p_tenant, false, 'Organization admin') returning id into rid;
    end if;
    insert into public.user_roles (user_id, role_id) values (uid, rid)
    on conflict do nothing;
  end if;
  return 'ok';
end;
$$;
grant execute on function public.admin_add_member(uuid, text, boolean) to authenticated;
