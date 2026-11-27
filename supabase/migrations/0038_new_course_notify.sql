-- New-course notifications.
-- When an admin publishes a course with "notify users" switched on, every
-- active member of the course's organization gets an in-app notification
-- ("new course"), once per course. Publishing with the switch off, or
-- publishing a draft in bulk with the switch off, sends nothing.

alter table public.courses
  add column if not exists notify_on_publish boolean not null default false;
alter table public.courses
  add column if not exists notified_at timestamptz;

create or replace function public.notify_new_course()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status = 'published'
     and coalesce(new.notify_on_publish, false)
     and new.notified_at is null
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    new.notified_at := now();
    insert into public.notifications (user_id, title, body, type, data, tenant_id)
    select m.user_id, 'كورس جديد / New course', coalesce(new.title, ''),
           'new_course', jsonb_build_object('course_id', new.id), new.tenant_id
      from public.tenant_memberships m
     where m.tenant_id = new.tenant_id and m.status = 'active';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_new_course on public.courses;
create trigger trg_notify_new_course
  before insert or update on public.courses
  for each row execute function public.notify_new_course();
