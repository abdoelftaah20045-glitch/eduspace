-- EduSpace Stage 2: courses, sections, lessons, enrollment, progress.
-- Run AFTER 0001_init.sql. Idempotent where possible.

-- ============ courses ============
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  cover_url text,
  field text,
  level text check (level in ('beginner','intermediate','advanced','all_levels') or level is null),
  instructor_id uuid references public.profiles (id),
  instructor_name text,
  language text not null default 'ar',
  prerequisites text,
  hours numeric(6,1),
  price numeric(10,2) not null default 0,
  currency text not null default 'EGP',
  is_free boolean generated always as (price <= 0) stored,
  status text not null default 'draft'
    check (status in ('draft','published','scheduled','archived','unavailable')),
  visibility text not null default 'everyone'
    check (visibility in ('everyone','registered','enrolled','group','manual')),
  lessons_sequential boolean not null default false,
  available_at timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.course_translations (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  language_code text not null references public.languages (code) on delete cascade,
  title text not null,
  description text not null default '',
  created_at timestamptz not null default now(),
  unique (course_id, language_code)
);

create table if not exists public.course_sections (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  title text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

-- ============ lessons ============
create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  section_id uuid references public.course_sections (id) on delete set null,
  title text not null,
  type text not null default 'text'
    check (type in ('video','text','pdf','document','presentation','audio','link','live','quiz','assignment')),
  content text not null default '',
  media_url text,
  duration_seconds int,
  is_free_preview boolean not null default false,
  availability text not null default 'open'
    check (availability in ('open','sequential','date')),
  available_at timestamptz,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lesson_translations (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons (id) on delete cascade,
  language_code text not null references public.languages (code) on delete cascade,
  title text not null,
  content text not null default '',
  created_at timestamptz not null default now(),
  unique (lesson_id, language_code)
);

-- ============ enrollment & progress ============
create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  status text not null default 'active'
    check (status in ('active','completed','suspended','refunded')),
  source text not null default 'self'
    check (source in ('self','manual','grant','payment')),
  granted_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, course_id)
);

create table if not exists public.lesson_progress (
  user_id uuid not null references public.profiles (id) on delete cascade,
  lesson_id uuid not null references public.lessons (id) on delete cascade,
  position_seconds int not null default 0,
  completed boolean not null default false,
  completed_at timestamptz,
  last_viewed_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

-- Progress summary per student per course. security_invoker so each user
-- sees only what the underlying table policies allow.
create or replace view public.course_progress_summary
with (security_invoker = true) as
select
  e.user_id,
  e.course_id,
  count(l.id) as total_lessons,
  count(lp.lesson_id) filter (where lp.completed) as completed_lessons,
  case
    when count(l.id) = 0 then 0
    else round(100.0 * count(lp.lesson_id) filter (where lp.completed) / count(l.id))::int
  end as percent
from public.enrollments e
left join public.lessons l on l.course_id = e.course_id
left join public.lesson_progress lp
  on lp.lesson_id = l.id and lp.user_id = e.user_id
where e.status = 'active'
group by e.user_id, e.course_id;

-- ============ row level security ============
alter table public.courses enable row level security;
alter table public.course_translations enable row level security;
alter table public.course_sections enable row level security;
alter table public.lessons enable row level security;
alter table public.lesson_translations enable row level security;
alter table public.enrollments enable row level security;
alter table public.lesson_progress enable row level security;

-- courses: published courses readable by any signed-in user; admins manage all.
drop policy if exists courses_read on public.courses;
create policy courses_read on public.courses
  for select using (status = 'published' or public.is_admin());
drop policy if exists courses_write_admin on public.courses;
create policy courses_write_admin on public.courses
  for all using (public.is_admin());

-- course translations follow their course's readability.
drop policy if exists course_translations_read on public.course_translations;
create policy course_translations_read on public.course_translations
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = course_id and (c.status = 'published' or public.is_admin())
    )
  );
drop policy if exists course_translations_write_admin on public.course_translations;
create policy course_translations_write_admin on public.course_translations
  for all using (public.is_admin());

-- sections follow their course's readability.
drop policy if exists course_sections_read on public.course_sections;
create policy course_sections_read on public.course_sections
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = course_id and (c.status = 'published' or public.is_admin())
    )
  );
drop policy if exists course_sections_write_admin on public.course_sections;
create policy course_sections_write_admin on public.course_sections
  for all using (public.is_admin());

-- lessons: admins read all; students read lessons of published courses when
-- the lesson is a free preview or they hold an active enrollment.
drop policy if exists lessons_read on public.lessons;
create policy lessons_read on public.lessons
  for select using (
    public.is_admin()
    or (
      exists (
        select 1 from public.courses c
        where c.id = lessons.course_id and c.status = 'published'
      )
      and (
        is_free_preview
        or exists (
          select 1 from public.enrollments e
          where e.course_id = lessons.course_id
            and e.user_id = auth.uid()
            and e.status = 'active'
        )
      )
    )
  );
drop policy if exists lessons_write_admin on public.lessons;
create policy lessons_write_admin on public.lessons
  for all using (public.is_admin());

-- lesson translations follow their lesson's readability.
drop policy if exists lesson_translations_read on public.lesson_translations;
create policy lesson_translations_read on public.lesson_translations
  for select using (
    exists (select 1 from public.lessons l where l.id = lesson_id)
  );
drop policy if exists lesson_translations_write_admin on public.lesson_translations;
create policy lesson_translations_write_admin on public.lesson_translations
  for all using (public.is_admin());

-- enrollments: students read their own and can self-enroll into free,
-- published courses. Everything else (grants, suspensions, paid access) is
-- admin-only until the payments stage lands.
drop policy if exists enrollments_read on public.enrollments;
create policy enrollments_read on public.enrollments
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists enrollments_insert_self_free on public.enrollments;
create policy enrollments_insert_self_free on public.enrollments
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.courses c
      where c.id = course_id and c.status = 'published' and c.price <= 0
    )
  );
drop policy if exists enrollments_write_admin on public.enrollments;
create policy enrollments_write_admin on public.enrollments
  for all using (public.is_admin());

-- lesson_progress: students manage their own rows; admins can read and clean up.
drop policy if exists lesson_progress_select on public.lesson_progress;
create policy lesson_progress_select on public.lesson_progress
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists lesson_progress_insert on public.lesson_progress;
create policy lesson_progress_insert on public.lesson_progress
  for insert with check (user_id = auth.uid());
drop policy if exists lesson_progress_update on public.lesson_progress;
create policy lesson_progress_update on public.lesson_progress
  for update using (user_id = auth.uid());
drop policy if exists lesson_progress_delete_admin on public.lesson_progress;
create policy lesson_progress_delete_admin on public.lesson_progress
  for delete using (public.is_admin());

-- indexes
create index if not exists courses_status_idx on public.courses (status);
create index if not exists courses_field_idx on public.courses (field);
create index if not exists course_sections_course_idx on public.course_sections (course_id, sort_order);
create index if not exists lessons_course_idx on public.lessons (course_id, sort_order);
create index if not exists lessons_section_idx on public.lessons (section_id, sort_order);
create index if not exists enrollments_user_idx on public.enrollments (user_id, status);
create index if not exists lesson_progress_recent_idx on public.lesson_progress (user_id, last_viewed_at desc);
