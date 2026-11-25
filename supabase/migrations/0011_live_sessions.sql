-- EduSpace: live sessions basics (doc section 13).
-- Run AFTER 0010_support.sql.

create table if not exists public.live_sessions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references public.courses (id) on delete cascade,
  title text not null,
  description text not null default '',
  host_name text,
  platform text not null default 'other'
    check (platform in ('zoom','google_meet','other')),
  join_url text not null,
  starts_at timestamptz not null,
  duration_minutes int not null default 60,
  status text not null default 'scheduled'
    check (status in ('scheduled','live','ended','cancelled')),
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.live_sessions enable row level security;

-- read: admins, students enrolled in the course, or anyone signed-in when
-- the session is not tied to a course (platform-wide announcement lives).
drop policy if exists live_sessions_read on public.live_sessions;
create policy live_sessions_read on public.live_sessions
  for select using (
    public.is_admin()
    or course_id is null
    or exists (
      select 1 from public.enrollments e
      where e.course_id = live_sessions.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
    or exists (
      select 1 from public.courses c
      where c.id = live_sessions.course_id and c.status = 'published'
    )
  );
drop policy if exists live_sessions_write_admin on public.live_sessions;
create policy live_sessions_write_admin on public.live_sessions
  for all using (public.is_admin());

create index if not exists live_sessions_starts_idx on public.live_sessions (starts_at);
