-- EduSpace part 14: student question bank (favorites and notes). Idempotent.
create table if not exists public.question_marks (
  user_id uuid not null references public.profiles (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  favorite boolean not null default false,
  note text,
  updated_at timestamptz not null default now(),
  primary key (user_id, question_id)
);
alter table public.question_marks enable row level security;
drop policy if exists question_marks_own on public.question_marks;
create policy question_marks_own on public.question_marks
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Notifications with images (data = {"images": [urls]}). Idempotent.
create or replace function public.admin_notify_audience_img(
  p_title text,
  p_body text,
  p_type text,
  p_tenant_id uuid,
  p_course_id uuid default null,
  p_user_id uuid default null,
  p_data jsonb default null
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
  insert into public.notifications (user_id, title, body, type, tenant_id, data)
  select m.user_id, p_title, coalesce(p_body, ''), coalesce(p_type, 'general'), p_tenant_id, p_data
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

grant execute on function public.admin_notify_audience_img(text, text, text, uuid, uuid, uuid, jsonb)
  to authenticated;
