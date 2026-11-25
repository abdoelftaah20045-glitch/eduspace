-- EduSpace: assignments (doc section 15). Run AFTER 0007_admin_users.sql.

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  title text not null,
  description text not null default '',
  attachment_url text,
  available_from timestamptz,
  due_at timestamptz,
  max_points numeric(6,2) not null default 10,
  allow_late boolean not null default false,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create table if not exists public.assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  text_answer text not null default '',
  link_url text,
  status text not null default 'submitted'
    check (status in ('submitted','late','graded')),
  score numeric(6,2),
  feedback text,
  graded_by uuid references public.profiles (id),
  graded_at timestamptz,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (assignment_id, user_id)
);

alter table public.assignments enable row level security;
alter table public.assignment_submissions enable row level security;

-- assignments: readable by enrolled students of the course and admins.
drop policy if exists assignments_read on public.assignments;
create policy assignments_read on public.assignments
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.enrollments e
      where e.course_id = assignments.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
    or exists (
      select 1 from public.courses c
      where c.id = assignments.course_id and c.status = 'published'
    )
  );
drop policy if exists assignments_write_admin on public.assignments;
create policy assignments_write_admin on public.assignments
  for all using (public.is_admin());

-- submissions: students manage their own until graded; admins grade.
drop policy if exists submissions_select on public.assignment_submissions;
create policy submissions_select on public.assignment_submissions
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists submissions_insert on public.assignment_submissions;
create policy submissions_insert on public.assignment_submissions
  for insert with check (user_id = auth.uid());
drop policy if exists submissions_update_own on public.assignment_submissions;
create policy submissions_update_own on public.assignment_submissions
  for update using (
    (user_id = auth.uid() and status <> 'graded')
    or public.is_admin()
  );
drop policy if exists submissions_delete_admin on public.assignment_submissions;
create policy submissions_delete_admin on public.assignment_submissions
  for delete using (public.is_admin());

create index if not exists assignments_course_idx on public.assignments (course_id, due_at);
create index if not exists submissions_assignment_idx on public.assignment_submissions (assignment_id);
