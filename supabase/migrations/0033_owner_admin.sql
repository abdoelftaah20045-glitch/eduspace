-- EduSpace part 15: make the owner account a full admin everywhere. Idempotent.
--
-- WHICH ACCOUNT? Put the owner email between the quotes on the next line.
-- If you leave it empty, the FIRST account ever created is used.
-- (Run the whole file. The last SELECT shows the result: every column must be true.)

do $$
declare
  owner_email text := '';   -- <== e.g. 'you@gmail.com' (leave empty for the first account)
  uid uuid;
  t record;
  rid uuid;
begin
  if owner_email <> '' then
    select id into uid from public.profiles where lower(email) = lower(trim(owner_email)) limit 1;
  else
    select id into uid from public.profiles order by created_at asc limit 1;
  end if;
  if uid is null then
    raise exception 'owner account not found: check the email, it must already have signed up';
  end if;

  -- active profile
  update public.profiles set status = 'active' where id = uid;

  -- platform super admin
  insert into public.super_admins (user_id) values (uid) on conflict do nothing;

  -- global admin roles (legacy checks use these names)
  insert into public.roles (name, description, is_system)
  select n, n, true from (values ('admin'), ('super_admin')) v(n)
  where not exists (select 1 from public.roles where name = v.n and tenant_id is null);
  insert into public.user_roles (user_id, role_id)
  select uid, r.id from public.roles r
  where r.tenant_id is null and r.name in ('admin', 'super_admin')
  on conflict do nothing;

  -- every organization: active member + that organization's admin role
  for t in select id from public.tenants loop
    insert into public.tenant_memberships (tenant_id, user_id, status, approved_at)
    values (t.id, uid, 'active', now())
    on conflict (tenant_id, user_id)
    do update set status = 'active', approved_at = coalesce(public.tenant_memberships.approved_at, now());
    select id into rid from public.roles where tenant_id = t.id and name = 'admin' limit 1;
    if rid is null then
      insert into public.roles (name, tenant_id, is_system, description)
      values ('admin', t.id, false, 'Organization admin') returning id into rid;
    end if;
    insert into public.user_roles (user_id, role_id) values (uid, rid) on conflict do nothing;
  end loop;
end $$;

-- The first account that ever signs up on a fresh install becomes the owner.
create or replace function public.first_account_owner()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.super_admins) then
    insert into public.super_admins (user_id) values (new.id) on conflict do nothing;
    insert into public.user_roles (user_id, role_id)
    select new.id, r.id from public.roles r
    where r.tenant_id is null and r.name in ('admin', 'super_admin')
    on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists on_first_account_owner on public.profiles;
create trigger on_first_account_owner
  after insert on public.profiles
  for each row execute function public.first_account_owner();

-- Used by the app to explain "no permission" instead of showing empty lists.
create or replace function public.admin_access_check(p_tenant uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'is_admin', public.is_admin(),
    'is_super', public.is_super_admin(),
    'is_member', public.is_tenant_member(p_tenant),
    'is_tenant_admin', public.is_tenant_admin(p_tenant)
  )
$$;
grant execute on function public.admin_access_check(uuid) to authenticated;

-- Result: run as the owner in the app, or check here for the owner account.
select p.email,
       exists (select 1 from public.super_admins s where s.user_id = p.id) as super_admin,
       exists (select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
               where ur.user_id = p.id and r.name = 'admin') as has_admin_role,
       (select count(*) from public.tenant_memberships m
         where m.user_id = p.id and m.status = 'active') as active_orgs,
       (select count(*) from public.tenants) as total_orgs
from public.profiles p
where p.id in (select user_id from public.super_admins)
order by p.created_at;
