-- EduSpace: notifications, announcements, certificates.
-- Run AFTER 0003_exams.sql. Idempotent where possible.

-- ============ announcements ============
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  audience text not null default 'all'
    check (audience in ('all','students','course')),
  course_id uuid references public.courses (id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

-- ============ notifications ============
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text not null default '',
  type text not null default 'general',
  data jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============ certificates ============
create table if not exists public.certificates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  certificate_number text not null unique,
  student_name text not null,
  course_title text not null,
  hours numeric(6,1),
  status text not null default 'valid'
    check (status in ('valid','cancelled')),
  cancel_reason text,
  issued_at timestamptz not null default now(),
  unique (user_id, course_id)
);

-- ============ row level security ============
alter table public.announcements enable row level security;
alter table public.notifications enable row level security;
alter table public.certificates enable row level security;

-- announcements: active ones readable by any signed-in user; admins manage.
drop policy if exists announcements_read on public.announcements;
create policy announcements_read on public.announcements
  for select using (
    public.is_admin()
    or (starts_at <= now() and (ends_at is null or ends_at > now()))
  );
drop policy if exists announcements_write_admin on public.announcements;
create policy announcements_write_admin on public.announcements
  for all using (public.is_admin());

-- notifications: users read and mark their own; admins and server jobs insert.
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update using (user_id = auth.uid() or public.is_admin());
drop policy if exists notifications_insert_admin on public.notifications;
create policy notifications_insert_admin on public.notifications
  for insert with check (public.is_admin());
drop policy if exists notifications_delete_admin on public.notifications;
create policy notifications_delete_admin on public.notifications
  for delete using (public.is_admin());

-- certificates: students read their own. Issue is self-service ONLY when the
-- course has lessons and every one of them is completed by this user.
drop policy if exists certificates_select on public.certificates;
create policy certificates_select on public.certificates
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists certificates_insert_self_completed on public.certificates;
create policy certificates_insert_self_completed on public.certificates
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.enrollments e
      where e.course_id = certificates.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
    and (select count(*) from public.lessons l
         where l.course_id = certificates.course_id) > 0
    and (select count(*) from public.lessons l
         where l.course_id = certificates.course_id)
      = (select count(*)
         from public.lesson_progress lp
         join public.lessons l2 on l2.id = lp.lesson_id
         where l2.course_id = certificates.course_id
           and lp.user_id = auth.uid()
           and lp.completed)
  );
drop policy if exists certificates_write_admin on public.certificates;
create policy certificates_write_admin on public.certificates
  for update using (public.is_admin());

-- indexes
create index if not exists announcements_active_idx on public.announcements (starts_at, ends_at);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);
create index if not exists notifications_unread_idx on public.notifications (user_id, is_read);
create index if not exists certificates_user_idx on public.certificates (user_id);
create index if not exists certificates_number_idx on public.certificates (certificate_number);
