-- EduSpace: resource library basics (doc section 16).
-- Run AFTER 0011_live_sessions.sql.

create table if not exists public.library_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  file_url text not null,
  file_type text not null default 'pdf'
    check (file_type in ('pdf','word','powerpoint','excel','image','video','audio','zip','link','other')),
  category text not null default 'general',
  size_bytes bigint,
  course_id uuid references public.courses (id) on delete set null,
  downloads int not null default 0,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.library_items enable row level security;

-- read: admins, items linked to a course the user is enrolled in (or a
-- published course), and items not linked to any course (public resources).
drop policy if exists library_read on public.library_items;
create policy library_read on public.library_items
  for select using (
    public.is_admin()
    or course_id is null
    or exists (
      select 1 from public.enrollments e
      where e.course_id = library_items.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
    or exists (
      select 1 from public.courses c
      where c.id = library_items.course_id and c.status = 'published'
    )
  );
drop policy if exists library_write_admin on public.library_items;
create policy library_write_admin on public.library_items
  for all using (public.is_admin());

create index if not exists library_created_idx on public.library_items (created_at desc);
create index if not exists library_category_idx on public.library_items (category);
