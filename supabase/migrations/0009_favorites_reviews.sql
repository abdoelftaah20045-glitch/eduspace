-- EduSpace: favorites + course reviews (doc section 20).
-- Run AFTER 0008_assignments.sql.

create table if not exists public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, course_id)
);

create table if not exists public.course_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  body text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, course_id)
);

alter table public.favorites enable row level security;
alter table public.course_reviews enable row level security;

-- favorites: strictly your own.
drop policy if exists favorites_all_own on public.favorites;
create policy favorites_all_own on public.favorites
  for all using (user_id = auth.uid());

-- reviews: readable by any signed-in user; writable by enrolled students
-- for their own review only.
drop policy if exists reviews_read on public.course_reviews;
create policy reviews_read on public.course_reviews
  for select using (true);
drop policy if exists reviews_insert on public.course_reviews;
create policy reviews_insert on public.course_reviews
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.enrollments e
      where e.course_id = course_reviews.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
  );
drop policy if exists reviews_update_own on public.course_reviews;
create policy reviews_update_own on public.course_reviews
  for update using (user_id = auth.uid() or public.is_admin());
drop policy if exists reviews_delete on public.course_reviews;
create policy reviews_delete on public.course_reviews
  for delete using (user_id = auth.uid() or public.is_admin());

create index if not exists favorites_user_idx on public.favorites (user_id);
create index if not exists reviews_course_idx on public.course_reviews (course_id);
