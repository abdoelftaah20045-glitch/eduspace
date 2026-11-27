-- Notify organization admins (and platform super admins) when someone
-- asks to join with an invite code.
create or replace function public.notify_on_join_request()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  who text;
begin
  if new.status <> 'pending' then
    return new;
  end if;
  select coalesce(nullif(full_name, ''), email, '') into who
    from public.profiles where id = new.user_id;
  insert into public.notifications (user_id, title, body, type, tenant_id)
  select distinct a.uid, 'طلب انضمام جديد / New join request', coalesce(who, ''), 'general', new.tenant_id
  from (
    select user_id as uid from public.super_admins
    union
    select ur.user_id from public.user_roles ur
      join public.roles r on r.id = ur.role_id
     where r.name = 'admin' and r.tenant_id = new.tenant_id
  ) a
  where a.uid <> new.user_id;
  return new;
end;
$$;

drop trigger if exists on_join_request_notify on public.tenant_memberships;
create trigger on_join_request_notify
  after insert on public.tenant_memberships
  for each row execute function public.notify_on_join_request();
