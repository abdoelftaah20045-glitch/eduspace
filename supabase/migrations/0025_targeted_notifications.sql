-- EduSpace: targeted notifications (A26). Run AFTER 0024_admin_tools.sql.
-- Safe to re-run (create or replace of a NEW function name; nothing dropped).

create or replace function public.admin_notify_audience(
  p_title text,
  p_body text,
  p_type text,
  p_tenant_id uuid,
  p_course_id uuid default null,
  p_user_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count int;
begin
  if not public.is_tenant_admin(p_tenant_id) then
    raise exception 'not authorized';
  end if;
  insert into public.notifications (user_id, title, body, type, tenant_id)
  select m.user_id, p_title, coalesce(p_body, ''), coalesce(p_type, 'general'), p_tenant_id
  from public.tenant_memberships m
  where m.tenant_id = p_tenant_id
    and m.status = 'active'
    and (p_user_id is null or m.user_id = p_user_id)
    and (
      p_course_id is null
      or exists (
        select 1 from public.enrollments e
        where e.user_id = m.user_id
          and e.course_id = p_course_id
          and e.tenant_id = p_tenant_id
          and e.status in ('active', 'completed')
      )
    );
  get diagnostics inserted_count = row_count;
  insert into public.audit_log (tenant_id, actor_id, action, entity, details)
  values (p_tenant_id, auth.uid(), 'notification.targeted', 'notification',
          jsonb_build_object('title', p_title, 'recipients', inserted_count,
                             'course_id', p_course_id, 'user_id', p_user_id));
  return inserted_count;
end;
$$;

grant execute on function public.admin_notify_audience(text, text, text, uuid, uuid, uuid)
  to authenticated;
