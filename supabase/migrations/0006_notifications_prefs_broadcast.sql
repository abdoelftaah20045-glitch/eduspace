-- EduSpace: notification preferences + admin broadcast (doc section 18).
-- Run AFTER 0005_certificate_verify.sql.

-- ============ notification preferences ============
create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  announcements boolean not null default true,
  courses boolean not null default true,
  exams boolean not null default true,
  certificates boolean not null default true,
  general boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists notification_prefs_select on public.notification_preferences;
create policy notification_prefs_select on public.notification_preferences
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists notification_prefs_insert on public.notification_preferences;
create policy notification_prefs_insert on public.notification_preferences
  for insert with check (user_id = auth.uid());
drop policy if exists notification_prefs_update on public.notification_preferences;
create policy notification_prefs_update on public.notification_preferences
  for update using (user_id = auth.uid());

-- ============ admin broadcast ============
-- Inserts one notification row per user, honoring their preferences for the
-- given category. Admin-only; returns how many users received it.
create or replace function public.admin_broadcast_notification(
  p_title text,
  p_body text default '',
  p_type text default 'general'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count int;
begin
  if not public.is_admin() then
    raise exception 'not authorized';
  end if;

  insert into public.notifications (user_id, title, body, type)
  select p.id, p_title, p_body, p_type
  from public.profiles p
  left join public.notification_preferences np on np.user_id = p.id
  where coalesce(
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

revoke all on function public.admin_broadcast_notification(text, text, text) from public;
grant execute on function public.admin_broadcast_notification(text, text, text) to authenticated;
