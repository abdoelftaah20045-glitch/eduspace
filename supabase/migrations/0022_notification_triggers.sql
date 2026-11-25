-- EduSpace: automatic notification fan-out + broadcast fix.
-- Run AFTER 0021_storage_covers.sql.
--
-- 1. Fixes admin_broadcast_notification: the tenant-scoped rewrite in 0017
--    referenced a prefs jsonb column that does not exist; preferences live
--    in dedicated boolean columns. Same behavior as before, tenant-scoped.
-- 2. New triggers: publishing an announcement, earning a certificate, and
--    being granted an enrollment now create in-app notifications,
--    honoring each user's notification_preferences.

-- ---------- 1. broadcast, tenant-scoped, column prefs ----------

create or replace function public.admin_broadcast_notification(
  p_title text,
  p_body text default '',
  p_type text default 'general',
  p_tenant_id uuid default public.default_tenant_id()
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
  select m.user_id, p_title, p_body, p_type, p_tenant_id
  from public.tenant_memberships m
  left join public.notification_preferences np on np.user_id = m.user_id
  where m.tenant_id = p_tenant_id
    and m.status = 'active'
    and coalesce(
      case p_type
        when 'announcements' then np.announcements
        when 'courses' then np.courses
        when 'exams' then np.exams
        when 'certificates' then np.certificates
        else np.general
      end,
      true
    );
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.admin_broadcast_notification(text, text, text, uuid) from public;
grant execute on function public.admin_broadcast_notification(text, text, text, uuid) to authenticated;

-- ---------- 2. announcement fan-out ----------

create or replace function public.notify_on_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Scheduled announcements notify when they become visible; skip future ones.
  if new.starts_at > now() then
    return new;
  end if;

  insert into public.notifications (user_id, title, body, type, tenant_id)
  select m.user_id, new.title, new.body, 'announcements', new.tenant_id
  from public.tenant_memberships m
  left join public.notification_preferences np on np.user_id = m.user_id
  where m.tenant_id = new.tenant_id
    and m.status = 'active'
    and (new.created_by is null or m.user_id <> new.created_by)
    and (
      new.audience in ('all', 'students')
      or (new.audience = 'course' and exists (
        select 1 from public.enrollments e
        where e.course_id = new.course_id
          and e.user_id = m.user_id
          and e.status = 'active'
      ))
    )
    and coalesce(np.announcements, true);
  return new;
end;
$$;

drop trigger if exists on_announcement_notify on public.announcements;
create trigger on_announcement_notify
  after insert on public.announcements
  for each row execute function public.notify_on_announcement();

-- ---------- 3. certificate earned ----------

create or replace function public.notify_on_certificate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(
    (select np.certificates from public.notification_preferences np
     where np.user_id = new.user_id),
    true
  ) then
    insert into public.notifications (user_id, title, body, type, tenant_id)
    values (
      new.user_id,
      'مبروك! شهادتك جاهزة',
      'شهادة كورس "' || coalesce(new.course_title, '') || '" اتاحت في حسابك',
      'certificates',
      new.tenant_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_certificate_notify on public.certificates;
create trigger on_certificate_notify
  after insert on public.certificates
  for each row execute function public.notify_on_certificate();

-- ---------- 4. enrollment granted ----------

create or replace function public.notify_on_enrollment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  course_title text;
begin
  if new.source is distinct from 'manual' then
    return new;
  end if;
  if not coalesce(
    (select np.courses from public.notification_preferences np
     where np.user_id = new.user_id),
    true
  ) then
    return new;
  end if;
  select c.title into course_title
  from public.courses c where c.id = new.course_id;
  insert into public.notifications (user_id, title, body, type, tenant_id)
  values (
    new.user_id,
    'اتفتح لك كورس جديد',
    'تم منحك الوصول لكورس "' || coalesce(course_title, '') || '"',
    'courses',
    new.tenant_id
  );
  return new;
end;
$$;

drop trigger if exists on_enrollment_notify on public.enrollments;
create trigger on_enrollment_notify
  after insert on public.enrollments
  for each row execute function public.notify_on_enrollment();
