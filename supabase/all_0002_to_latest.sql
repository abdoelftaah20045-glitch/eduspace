-- EduSpace: كل المايجريشنز في ملف واحد، بالترتيب.
-- الصق الملف ده كله في SQL Editor مرة واحدة. آمن لإعادة التشغيل (idempotent).
-- يشمل 0001 لحد 0023 (تعدد المؤسسات والأدوار والتخزين والإشعارات).

-- ============================================================
-- FILE: supabase/migrations/0001_init.sql
-- ============================================================
-- EduSpace Stage 1: accounts, roles, languages.
-- Run in the Supabase SQL editor or via the CLI. Idempotent where possible.

-- ============ profiles ============
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  phone text,
  avatar_url text,
  birth_date date,
  country text,
  governorate text,
  institution text,
  faculty text,
  specialization text,
  stage text,
  level text,
  group_name text,
  bio text,
  status text not null default 'active'
    check (status in ('pending','active','rejected','suspended')),
  status_reason text,
  locale text not null default 'ar',
  theme text not null default 'system'
    check (theme in ('light','dark','system')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Create a profile automatically on sign up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'locale', 'ar')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ roles & permissions ============
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  user_id uuid not null references public.profiles (id) on delete cascade,
  role_id uuid not null references public.roles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles (id) on delete cascade,
  permission_id uuid not null references public.permissions (id) on delete cascade,
  primary key (role_id, permission_id)
);

insert into public.roles (name, is_system) values
  ('super_admin', true), ('admin', true), ('content_manager', true),
  ('exam_manager', true), ('instructor', true), ('finance', true),
  ('support', true), ('student', true)
on conflict (name) do nothing;

-- Admin check used by policies. security definer so it can read user_roles.
create or replace function public.is_admin()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.name in ('super_admin','admin')
  );
$$;

-- ============ admin activity ============
create table if not exists public.admin_activity_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles (id),
  action text not null,
  target_type text,
  target_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

-- ============ languages & translations ============
create table if not exists public.languages (
  code text primary key,
  name text not null,
  direction text not null default 'ltr' check (direction in ('rtl','ltr')),
  is_active boolean not null default true,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.languages (code, name, direction, is_active, is_default) values
  ('ar', 'العربية', 'rtl', true, true),
  ('en', 'English', 'ltr', true, false)
on conflict (code) do nothing;

create table if not exists public.translation_keys (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  group_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.translations (
  id uuid primary key default gen_random_uuid(),
  key_id uuid not null references public.translation_keys (id) on delete cascade,
  language_code text not null references public.languages (code) on delete cascade,
  value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (key_id, language_code)
);

-- ============ row level security ============
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.admin_activity_logs enable row level security;
alter table public.languages enable row level security;
alter table public.translation_keys enable row level security;
alter table public.translations enable row level security;

-- profiles: everyone reads their own row; admins read all.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select using (auth.uid() = id or public.is_admin());

-- profiles: users update their own row...
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id);

-- ...but only admins may change account status (checked by trigger below).
create or replace function public.guard_profile_status()
returns trigger
language plpgsql
as $$
begin
  if (new.status is distinct from old.status
      or new.status_reason is distinct from old.status_reason)
     and not public.is_admin() then
    raise exception 'only admins can change account status';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_guard_status on public.profiles;
create trigger profiles_guard_status
  before update on public.profiles
  for each row execute function public.guard_profile_status();

-- roles/permissions/role_permissions: read for admins only.
drop policy if exists roles_read_admin on public.roles;
create policy roles_read_admin on public.roles
  for select using (public.is_admin());
drop policy if exists permissions_read_admin on public.permissions;
create policy permissions_read_admin on public.permissions
  for select using (public.is_admin());
drop policy if exists role_permissions_read_admin on public.role_permissions;
create policy role_permissions_read_admin on public.role_permissions
  for select using (public.is_admin());

-- user_roles: users read their own roles; admins read all.
drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles
  for select using (auth.uid() = user_id or public.is_admin());

-- admin_activity_logs: admins only.
drop policy if exists admin_logs_admin on public.admin_activity_logs;
create policy admin_logs_admin on public.admin_activity_logs
  for all using (public.is_admin());

-- languages and translations: readable by everyone (needed before login);
-- writes by admins only.
drop policy if exists languages_read_all on public.languages;
create policy languages_read_all on public.languages
  for select using (true);
drop policy if exists languages_write_admin on public.languages;
create policy languages_write_admin on public.languages
  for all using (public.is_admin());

drop policy if exists translation_keys_read_all on public.translation_keys;
create policy translation_keys_read_all on public.translation_keys
  for select using (true);
drop policy if exists translation_keys_write_admin on public.translation_keys;
create policy translation_keys_write_admin on public.translation_keys
  for all using (public.is_admin());

drop policy if exists translations_read_all on public.translations;
create policy translations_read_all on public.translations
  for select using (true);
drop policy if exists translations_write_admin on public.translations;
create policy translations_write_admin on public.translations
  for all using (public.is_admin());

-- indexes
create index if not exists profiles_status_idx on public.profiles (status);
create index if not exists admin_logs_admin_idx on public.admin_activity_logs (admin_id, created_at desc);
create index if not exists translations_key_lang_idx on public.translations (key_id, language_code);

-- ============================================================
-- FILE: supabase/migrations/0002_courses.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0003_exams.sql
-- ============================================================
-- EduSpace Stage 3 (exams basics): question bank, exams, attempts, answers.
-- Run AFTER 0002_courses.sql. Idempotent where possible.

-- ============ question bank ============
create table if not exists public.question_banks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  bank_id uuid references public.question_banks (id) on delete set null,
  type text not null
    check (type in ('mcq','true_false','multi','fill_blank','essay')),
  body text not null,
  points numeric(6,2) not null default 1,
  explanation text,
  created_at timestamptz not null default now()
);

create table if not exists public.question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions (id) on delete cascade,
  body text not null,
  is_correct boolean not null default false,
  sort_order int not null default 0
);

-- ============ exams ============
create table if not exists public.exams (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references public.courses (id) on delete cascade,
  title text not null,
  description text not null default '',
  duration_minutes int,
  pass_grade numeric(6,2) not null default 0,
  max_attempts int not null default 1,
  shuffle_questions boolean not null default false,
  status text not null default 'draft'
    check (status in ('draft','published','closed')),
  available_from timestamptz,
  available_until timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.exam_questions (
  exam_id uuid not null references public.exams (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  sort_order int not null default 0,
  primary key (exam_id, question_id)
);

-- ============ attempts & answers ============
create table if not exists public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'in_progress'
    check (status in ('in_progress','submitted','graded')),
  score numeric(8,2),
  max_score numeric(8,2),
  passed boolean,
  started_at timestamptz not null default now(),
  submitted_at timestamptz
);

create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.exam_attempts (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  selected_option_ids uuid[],
  text_answer text,
  is_correct boolean,
  points_awarded numeric(6,2) not null default 0,
  created_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);

-- ============ row level security ============
alter table public.question_banks enable row level security;
alter table public.questions enable row level security;
alter table public.question_options enable row level security;
alter table public.exams enable row level security;
alter table public.exam_questions enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.answers enable row level security;

-- banks: admin only (students never query banks directly).
drop policy if exists question_banks_admin on public.question_banks;
create policy question_banks_admin on public.question_banks
  for all using (public.is_admin());

-- questions/options: admins manage; students read questions of published exams.
drop policy if exists questions_read on public.questions;
create policy questions_read on public.questions
  for select using (
    public.is_admin()
    or exists (
      select 1
      from public.exam_questions eq
      join public.exams e on e.id = eq.exam_id
      where eq.question_id = questions.id and e.status = 'published'
    )
  );
drop policy if exists questions_write_admin on public.questions;
create policy questions_write_admin on public.questions
  for all using (public.is_admin());

drop policy if exists question_options_read on public.question_options;
create policy question_options_read on public.question_options
  for select using (
    public.is_admin()
    or exists (
      select 1
      from public.questions q
      join public.exam_questions eq on eq.question_id = q.id
      join public.exams e on e.id = eq.exam_id
      where q.id = question_options.question_id and e.status = 'published'
    )
  );
drop policy if exists question_options_write_admin on public.question_options;
create policy question_options_write_admin on public.question_options
  for all using (public.is_admin());

-- exams: published readable by any signed-in user; admins manage all.
drop policy if exists exams_read on public.exams;
create policy exams_read on public.exams
  for select using (status = 'published' or public.is_admin());
drop policy if exists exams_write_admin on public.exams;
create policy exams_write_admin on public.exams
  for all using (public.is_admin());

drop policy if exists exam_questions_read on public.exam_questions;
create policy exam_questions_read on public.exam_questions
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.exams e
      where e.id = exam_questions.exam_id and e.status = 'published'
    )
  );
drop policy if exists exam_questions_write_admin on public.exam_questions;
create policy exam_questions_write_admin on public.exam_questions
  for all using (public.is_admin());

-- attempts: students manage their own; admins read all.
drop policy if exists attempts_select on public.exam_attempts;
create policy attempts_select on public.exam_attempts
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists attempts_insert on public.exam_attempts;
create policy attempts_insert on public.exam_attempts
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.exams e
      where e.id = exam_id and e.status = 'published'
    )
  );
drop policy if exists attempts_update on public.exam_attempts;
create policy attempts_update on public.exam_attempts
  for update using (user_id = auth.uid() or public.is_admin());
drop policy if exists attempts_delete_admin on public.exam_attempts;
create policy attempts_delete_admin on public.exam_attempts
  for delete using (public.is_admin());

-- answers: students insert/read answers of their own attempts; admins read all.
drop policy if exists answers_select on public.answers;
create policy answers_select on public.answers
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id and a.user_id = auth.uid()
    )
  );
drop policy if exists answers_insert on public.answers;
create policy answers_insert on public.answers
  for insert with check (
    exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id and a.user_id = auth.uid()
    )
  );
drop policy if exists answers_update on public.answers;
create policy answers_update on public.answers
  for update using (
    public.is_admin()
    or exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id and a.user_id = auth.uid()
    )
  );

-- indexes
create index if not exists questions_bank_idx on public.questions (bank_id);
create index if not exists question_options_question_idx on public.question_options (question_id, sort_order);
create index if not exists exams_status_idx on public.exams (status);
create index if not exists exams_course_idx on public.exams (course_id);
create index if not exists attempts_user_idx on public.exam_attempts (user_id, exam_id);
create index if not exists answers_attempt_idx on public.answers (attempt_id);

-- ============================================================
-- FILE: supabase/migrations/0004_notifications_certificates.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0005_certificate_verify.sql
-- ============================================================
-- EduSpace: public certificate verification (doc section 17.2/17.3).
-- Run AFTER 0004_notifications_certificates.sql.
-- A stable SECURITY DEFINER function so anyone with the link can check a
-- certificate number over PostgREST (GET), while RLS on certificates stays
-- tight. Returns privacy-minimal data only.

create or replace function public.verify_certificate(p_number text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c public.certificates%rowtype;
begin
  select * into c
  from public.certificates
  where certificate_number = p_number;

  if not found then
    return json_build_object(
      'status', 'not_found',
      'certificate_number', p_number
    );
  end if;

  return json_build_object(
    'status', c.status,
    'certificate_number', c.certificate_number,
    'student_name', c.student_name,
    'course_title', c.course_title,
    'hours', c.hours,
    'issued_at', c.issued_at
  );
end;
$$;

revoke all on function public.verify_certificate(text) from public;
grant execute on function public.verify_certificate(text) to anon, authenticated;

-- ============================================================
-- FILE: supabase/migrations/0006_notifications_prefs_broadcast.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0007_admin_users.sql
-- ============================================================
-- EduSpace: let admins update other users' profiles (account status review).
-- The guard trigger still prevents non-admins from changing status fields.
-- Run AFTER 0006_notifications_prefs_broadcast.sql.

drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles
  for update using (public.is_admin());

-- ============================================================
-- FILE: supabase/migrations/0008_assignments.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0009_favorites_reviews.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0010_support.sql
-- ============================================================
-- EduSpace: support tickets (doc section 19). Run AFTER 0009_favorites_reviews.sql.

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  subject text not null,
  category text not null default 'general',
  status text not null default 'new'
    check (status in ('new','in_progress','waiting_user','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;

-- tickets: owner or admin.
drop policy if exists tickets_select on public.support_tickets;
create policy tickets_select on public.support_tickets
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists tickets_insert on public.support_tickets;
create policy tickets_insert on public.support_tickets
  for insert with check (user_id = auth.uid());
drop policy if exists tickets_update on public.support_tickets;
create policy tickets_update on public.support_tickets
  for update using (user_id = auth.uid() or public.is_admin());

-- messages: on tickets you own, or admin anywhere.
drop policy if exists ticket_messages_select on public.support_messages;
create policy ticket_messages_select on public.support_messages
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id and t.user_id = auth.uid()
    )
  );
drop policy if exists ticket_messages_insert on public.support_messages;
create policy ticket_messages_insert on public.support_messages
  for insert with check (
    sender_id = auth.uid()
    and (
      public.is_admin()
      or exists (
        select 1 from public.support_tickets t
        where t.id = support_messages.ticket_id and t.user_id = auth.uid()
      )
    )
  );

create index if not exists tickets_user_idx on public.support_tickets (user_id, created_at desc);
create index if not exists ticket_messages_idx on public.support_messages (ticket_id, created_at);

-- ============================================================
-- FILE: supabase/migrations/0011_live_sessions.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0012_library.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0013_storage.sql
-- ============================================================
-- EduSpace: Supabase Storage buckets (exec guide section 17, Storage).
-- Run AFTER 0012_library.sql.
--
-- Buckets:
--   avatars      (public)  profile pictures; non-sensitive, shown everywhere.
--                          Each user manages only their own folder "<uid>/...".
--   resources    (private) library files; read via short-lived signed URLs.
--   course_media (private) lesson videos/images/files.
--   certificates (private) generated certificate PDFs.
--   submissions  (private) assignment submissions; owner + admins only.
--
-- Private buckets: any signed-in user can READ (single-organization stage;
-- per-course checks live in the table RLS, e.g. library_items), only admins
-- can write. Tighten to per-entitlement when the multi-tenant stage lands.

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('resources', 'resources', false),
  ('course-media', 'course-media', false),
  ('certificates', 'certificates', false),
  ('submissions', 'submissions', false)
on conflict (id) do nothing;

-- ---------- avatars ----------
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists avatars_own_insert on storage.objects;
create policy avatars_own_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_own_update on storage.objects;
create policy avatars_own_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_own_delete on storage.objects;
create policy avatars_own_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------- private buckets: read for signed-in users ----------
drop policy if exists private_files_read on storage.objects;
create policy private_files_read on storage.objects
  for select to authenticated
  using (bucket_id in ('resources', 'course-media', 'certificates', 'submissions'));

-- ---------- private buckets: write for admins only ----------
drop policy if exists private_files_admin_write on storage.objects;
create policy private_files_admin_write on storage.objects
  for all to authenticated
  using (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and public.is_admin()
  )
  with check (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and public.is_admin()
  );

-- ---------- submissions: students manage their own folder ----------
drop policy if exists submissions_own_insert on storage.objects;
create policy submissions_own_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'submissions'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ============================================================
-- FILE: supabase/migrations/0014_push_tokens.sql
-- ============================================================
-- EduSpace: device push tokens (exec guide section 17, Push).
-- Run AFTER 0013_storage.sql.
-- FCM stays off until the owner's Firebase keys land; this table just
-- stores one row per device token per user when it is enabled.

create table if not exists public.push_tokens (
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

alter table public.push_tokens enable row level security;

-- users manage only their own device tokens
drop policy if exists push_tokens_own on public.push_tokens;
create policy push_tokens_own on public.push_tokens
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ============================================================
-- FILE: supabase/migrations/0015_submission_files.sql
-- ============================================================
-- EduSpace: assignment submission file uploads (exec guide S39 + section 17
-- Storage). Run AFTER 0014_push_tokens.sql.
-- Files live in the private `submissions` bucket (0013) under
-- <user_id>/<assignment_id>/<filename>; this column stores the path.

alter table public.assignment_submissions
  add column if not exists file_path text;

-- ============================================================
-- FILE: supabase/migrations/0016_tenancy_foundation.sql
-- ============================================================
-- EduSpace: multi-tenant foundation (exec guide sections 2 + 15).
-- Run AFTER 0015_submission_files.sql.
--
-- Additive and backward compatible: existing rows are backfilled into a
-- default "EduSpace" tenant, new tenant_id columns default to it, and a
-- trigger enrolls new signups into it. The current app keeps working
-- unchanged; per-tenant RLS tightening lands with the app-side tenant
-- context in the next stage.

-- ---------- tables ----------

create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  logo_key text,
  status text not null default 'active' check (status in ('active', 'suspended')),
  default_locale text not null default 'ar',
  timezone text not null default 'Africa/Cairo',
  invite_code text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.tenant_settings (
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  setting_key text not null,
  setting_value jsonb not null default '{}',
  updated_by uuid references public.profiles (id),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, setting_key)
);

create table if not exists public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected', 'suspended')),
  joined_at timestamptz not null default now(),
  approved_by uuid references public.profiles (id),
  approved_at timestamptz,
  unique (tenant_id, user_id)
);

-- Platform team; read only through security-definer helpers.
create table if not exists public.super_admins (
  user_id uuid primary key references public.profiles (id) on delete cascade
);

-- ---------- helpers ----------

create or replace function public.default_tenant_id()
returns uuid
language sql stable
as $$ select '00000000-0000-0000-0000-000000000001'::uuid $$;

create or replace function public.is_super_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.super_admins where user_id = auth.uid()) $$;

create or replace function public.is_tenant_member(t uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.tenant_memberships
    where tenant_id = t and user_id = auth.uid() and status = 'active'
  )
$$;

-- Transition rule: platform super admin, or a legacy global admin who is an
-- active member of that tenant. Per-tenant roles land with the roles stage.
create or replace function public.is_tenant_admin(t uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_super_admin()
     or (public.is_admin() and public.is_tenant_member(t))
$$;

-- Join by invite code without exposing codes: security definer, the app
-- never selects tenants.invite_code directly.
create or replace function public.join_tenant_by_code(p_code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  t uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select id into t from public.tenants
   where invite_code = upper(trim(p_code)) and status = 'active';
  if t is null then
    raise exception 'invalid_invite_code';
  end if;
  insert into public.tenant_memberships (tenant_id, user_id, status)
  values (t, auth.uid(), 'pending')
  on conflict (tenant_id, user_id) do nothing;
  return t;
end;
$$;

-- ---------- default tenant + backfill ----------

insert into public.tenants (id, name, slug, invite_code)
values ('00000000-0000-0000-0000-000000000001', 'EduSpace', 'eduspace', 'EDUSPACE')
on conflict (id) do nothing;

insert into public.tenant_memberships (tenant_id, user_id, status, approved_at)
select public.default_tenant_id(), id, 'active', now()
from public.profiles
on conflict (tenant_id, user_id) do nothing;

-- New signups join the default tenant as active members until the app's
-- tenant-selection flow (S03) replaces this path.
create or replace function public.handle_new_profile_tenant()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.tenant_memberships (tenant_id, user_id, status, approved_at)
  values (public.default_tenant_id(), new.id, 'active', now())
  on conflict (tenant_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_profile_created_tenant on public.profiles;
create trigger on_profile_created_tenant
  after insert on public.profiles
  for each row execute function public.handle_new_profile_tenant();

-- ---------- RLS on the new tables ----------

alter table public.tenants enable row level security;
alter table public.tenant_settings enable row level security;
alter table public.tenant_memberships enable row level security;
alter table public.super_admins enable row level security;

-- tenants: members can read their own tenants; only super admin writes.
-- The public directory for the join flow is the tenants_directory view
-- (no invite codes in it).
drop policy if exists tenants_read on public.tenants;
create policy tenants_read on public.tenants
  for select to authenticated
  using (public.is_tenant_member(id) or public.is_super_admin());

drop policy if exists tenants_super_write on public.tenants;
create policy tenants_super_write on public.tenants
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create or replace view public.tenants_directory as
  select id, name, slug, logo_key
  from public.tenants
  where status = 'active';

-- memberships: read own (or as tenant admin); self-join as pending;
-- approval decisions by tenant admins.
drop policy if exists memberships_read on public.tenant_memberships;
create policy memberships_read on public.tenant_memberships
  for select to authenticated
  using (user_id = auth.uid() or public.is_tenant_admin(tenant_id));

drop policy if exists memberships_self_join on public.tenant_memberships;
create policy memberships_self_join on public.tenant_memberships
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');

drop policy if exists memberships_admin_update on public.tenant_memberships;
create policy memberships_admin_update on public.tenant_memberships
  for update to authenticated
  using (public.is_tenant_admin(tenant_id));

-- settings: members read, tenant admins write.
drop policy if exists settings_read on public.tenant_settings;
create policy settings_read on public.tenant_settings
  for select to authenticated
  using (public.is_tenant_member(tenant_id) or public.is_tenant_admin(tenant_id));

drop policy if exists settings_admin_write on public.tenant_settings;
create policy settings_admin_write on public.tenant_settings
  for all to authenticated
  using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));

-- ---------- tenant_id on root-scoped tables ----------
-- Child tables (sections, lessons, options, answers, ...) stay scoped via
-- their parent, per the spec. Columns default to the EduSpace tenant so the
-- current app keeps inserting without changes.

alter table public.courses
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.enrollments
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.question_banks
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.questions
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.exams
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.exam_attempts
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.notifications
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.announcements
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.certificates
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.favorites
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.course_reviews
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.support_tickets
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.live_sessions
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.library_items
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.assignments
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.assignment_submissions
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.admin_activity_logs
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
-- null = platform-wide role; set = tenant-specific role (spec section 15)
alter table public.roles
  add column if not exists tenant_id uuid references public.tenants (id);

create index if not exists courses_tenant_idx on public.courses (tenant_id);
create index if not exists enrollments_tenant_idx on public.enrollments (tenant_id);
create index if not exists exams_tenant_idx on public.exams (tenant_id);
create index if not exists notifications_tenant_idx on public.notifications (tenant_id);
create index if not exists memberships_user_idx on public.tenant_memberships (user_id);

-- ============================================================
-- FILE: supabase/migrations/0017_tenant_rls.sql
-- ============================================================
-- EduSpace: per-tenant RLS tightening (exec guide sections 2, 14, 18).
-- Run AFTER 0016_tenancy_foundation.sql.
--
-- Every root table's policies now require active membership in the row's
-- tenant for student access, and is_tenant_admin(tenant_id) for admin
-- access. Child tables inherit the tenant scope through their parent row.
-- Legacy global admins keep full power inside tenants they belong to;
-- the platform team uses super_admins.

-- ============ courses & content ============

drop policy if exists courses_read on public.courses;
create policy courses_read on public.courses
  for select using (
    public.is_tenant_admin(tenant_id)
    or (status = 'published' and public.is_tenant_member(tenant_id))
  );
drop policy if exists courses_write_admin on public.courses;
create policy courses_write_admin on public.courses
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists course_translations_read on public.course_translations;
create policy course_translations_read on public.course_translations
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = course_id
        and (
          public.is_tenant_admin(c.tenant_id)
          or (c.status = 'published' and public.is_tenant_member(c.tenant_id))
        )
    )
  );
drop policy if exists course_translations_write_admin on public.course_translations;
create policy course_translations_write_admin on public.course_translations
  for all using (
    exists (
      select 1 from public.courses c
      where c.id = course_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists course_sections_read on public.course_sections;
create policy course_sections_read on public.course_sections
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = course_id
        and (
          public.is_tenant_admin(c.tenant_id)
          or (c.status = 'published' and public.is_tenant_member(c.tenant_id))
        )
    )
  );
drop policy if exists course_sections_write_admin on public.course_sections;
create policy course_sections_write_admin on public.course_sections
  for all using (
    exists (
      select 1 from public.courses c
      where c.id = course_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists lessons_read on public.lessons;
create policy lessons_read on public.lessons
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = lessons.course_id
        and (
          public.is_tenant_admin(c.tenant_id)
          or (
            c.status = 'published'
            and public.is_tenant_member(c.tenant_id)
            and (
              lessons.is_free_preview
              or exists (
                select 1 from public.enrollments e
                where e.course_id = lessons.course_id
                  and e.user_id = auth.uid()
                  and e.status = 'active'
              )
            )
          )
        )
    )
  );
drop policy if exists lessons_write_admin on public.lessons;
create policy lessons_write_admin on public.lessons
  for all using (
    exists (
      select 1 from public.courses c
      where c.id = lessons.course_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists lesson_translations_read on public.lesson_translations;
create policy lesson_translations_read on public.lesson_translations
  for select using (
    exists (select 1 from public.lessons l where l.id = lesson_id)
  );
drop policy if exists lesson_translations_write_admin on public.lesson_translations;
create policy lesson_translations_write_admin on public.lesson_translations
  for all using (
    exists (
      select 1 from public.lessons l
      join public.courses c on c.id = l.course_id
      where l.id = lesson_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists enrollments_read on public.enrollments;
create policy enrollments_read on public.enrollments
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists enrollments_insert_self_free on public.enrollments;
create policy enrollments_insert_self_free on public.enrollments
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.courses c
      where c.id = course_id
        and c.status = 'published'
        and c.price <= 0
        and c.tenant_id = enrollments.tenant_id
    )
  );
drop policy if exists enrollments_write_admin on public.enrollments;
create policy enrollments_write_admin on public.enrollments
  for all using (public.is_tenant_admin(tenant_id));

-- lesson_progress stays per-user (scoped through its lesson's course).
drop policy if exists lesson_progress_select on public.lesson_progress;
create policy lesson_progress_select on public.lesson_progress
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.lessons l
      join public.courses c on c.id = l.course_id
      where l.id = lesson_progress.lesson_id
        and public.is_tenant_admin(c.tenant_id)
    )
  );
drop policy if exists lesson_progress_delete_admin on public.lesson_progress;
create policy lesson_progress_delete_admin on public.lesson_progress
  for delete using (
    exists (
      select 1 from public.lessons l
      join public.courses c on c.id = l.course_id
      where l.id = lesson_progress.lesson_id
        and public.is_tenant_admin(c.tenant_id)
    )
  );

-- ============ exams & question bank ============

drop policy if exists question_banks_admin on public.question_banks;
create policy question_banks_admin on public.question_banks
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists questions_read on public.questions;
create policy questions_read on public.questions
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and exists (
        select 1
        from public.exam_questions eq
        join public.exams e on e.id = eq.exam_id
        where eq.question_id = questions.id and e.status = 'published'
      )
    )
  );
drop policy if exists questions_write_admin on public.questions;
create policy questions_write_admin on public.questions
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists question_options_read on public.question_options;
create policy question_options_read on public.question_options
  for select using (
    exists (
      select 1 from public.questions q
      where q.id = question_options.question_id
        and (
          public.is_tenant_admin(q.tenant_id)
          or (
            public.is_tenant_member(q.tenant_id)
            and exists (
              select 1
              from public.exam_questions eq
              join public.exams e on e.id = eq.exam_id
              where eq.question_id = q.id and e.status = 'published'
            )
          )
        )
    )
  );
drop policy if exists question_options_write_admin on public.question_options;
create policy question_options_write_admin on public.question_options
  for all using (
    exists (
      select 1 from public.questions q
      where q.id = question_options.question_id
        and public.is_tenant_admin(q.tenant_id)
    )
  );

drop policy if exists exams_read on public.exams;
create policy exams_read on public.exams
  for select using (
    public.is_tenant_admin(tenant_id)
    or (status = 'published' and public.is_tenant_member(tenant_id))
  );
drop policy if exists exams_write_admin on public.exams;
create policy exams_write_admin on public.exams
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists exam_questions_read on public.exam_questions;
create policy exam_questions_read on public.exam_questions
  for select using (
    exists (
      select 1 from public.exams e
      where e.id = exam_questions.exam_id
        and (
          public.is_tenant_admin(e.tenant_id)
          or (e.status = 'published' and public.is_tenant_member(e.tenant_id))
        )
    )
  );
drop policy if exists exam_questions_write_admin on public.exam_questions;
create policy exam_questions_write_admin on public.exam_questions
  for all using (
    exists (
      select 1 from public.exams e
      where e.id = exam_questions.exam_id
        and public.is_tenant_admin(e.tenant_id)
    )
  );

drop policy if exists attempts_select on public.exam_attempts;
create policy attempts_select on public.exam_attempts
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists attempts_insert on public.exam_attempts;
create policy attempts_insert on public.exam_attempts
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.exams e
      where e.id = exam_id
        and e.status = 'published'
        and e.tenant_id = exam_attempts.tenant_id
    )
  );
drop policy if exists attempts_update on public.exam_attempts;
create policy attempts_update on public.exam_attempts
  for update using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists attempts_delete_admin on public.exam_attempts;
create policy attempts_delete_admin on public.exam_attempts
  for delete using (public.is_tenant_admin(tenant_id));

drop policy if exists answers_select on public.answers;
create policy answers_select on public.answers
  for select using (
    exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id
        and (
          public.is_tenant_admin(a.tenant_id)
          or (a.user_id = auth.uid() and public.is_tenant_member(a.tenant_id))
        )
    )
  );
drop policy if exists answers_insert on public.answers;
create policy answers_insert on public.answers
  for insert with check (
    exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id
        and a.user_id = auth.uid()
        and public.is_tenant_member(a.tenant_id)
    )
  );
drop policy if exists answers_update on public.answers;
create policy answers_update on public.answers
  for update using (
    exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id
        and (
          public.is_tenant_admin(a.tenant_id)
          or (a.user_id = auth.uid() and public.is_tenant_member(a.tenant_id))
        )
    )
  );

-- ============ notifications, announcements, certificates ============

drop policy if exists announcements_read on public.announcements;
create policy announcements_read on public.announcements
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and starts_at <= now()
      and (ends_at is null or ends_at > now())
    )
  );
drop policy if exists announcements_write_admin on public.announcements;
create policy announcements_write_admin on public.announcements
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists notifications_insert_admin on public.notifications;
create policy notifications_insert_admin on public.notifications
  for insert with check (public.is_tenant_admin(tenant_id));
drop policy if exists notifications_delete_admin on public.notifications;
create policy notifications_delete_admin on public.notifications
  for delete using (public.is_tenant_admin(tenant_id));

drop policy if exists certificates_select on public.certificates;
create policy certificates_select on public.certificates
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists certificates_insert_self_completed on public.certificates;
create policy certificates_insert_self_completed on public.certificates
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
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
  for update using (public.is_tenant_admin(tenant_id));

-- ============ favorites & reviews ============

drop policy if exists favorites_all_own on public.favorites;
create policy favorites_all_own on public.favorites
  for all using (
    user_id = auth.uid() and public.is_tenant_member(tenant_id)
  );

drop policy if exists reviews_read on public.course_reviews;
create policy reviews_read on public.course_reviews
  for select using (
    public.is_tenant_member(tenant_id) or public.is_super_admin()
  );
drop policy if exists reviews_insert on public.course_reviews;
create policy reviews_insert on public.course_reviews
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.enrollments e
      where e.course_id = course_reviews.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
  );
drop policy if exists reviews_update_own on public.course_reviews;
create policy reviews_update_own on public.course_reviews
  for update using (
    (user_id = auth.uid() and public.is_tenant_member(tenant_id))
    or public.is_tenant_admin(tenant_id)
  );
drop policy if exists reviews_delete on public.course_reviews;
create policy reviews_delete on public.course_reviews
  for delete using (
    (user_id = auth.uid() and public.is_tenant_member(tenant_id))
    or public.is_tenant_admin(tenant_id)
  );

-- ============ assignments ============

drop policy if exists assignments_read on public.assignments;
create policy assignments_read on public.assignments
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and (
        exists (
          select 1 from public.enrollments e
          where e.course_id = assignments.course_id
            and e.user_id = auth.uid()
            and e.status = 'active'
        )
        or exists (
          select 1 from public.courses c
          where c.id = assignments.course_id and c.status = 'published'
        )
      )
    )
  );
drop policy if exists assignments_write_admin on public.assignments;
create policy assignments_write_admin on public.assignments
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists submissions_select on public.assignment_submissions;
create policy submissions_select on public.assignment_submissions
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists submissions_insert on public.assignment_submissions;
create policy submissions_insert on public.assignment_submissions
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.assignments a
      where a.id = assignment_id
        and a.tenant_id = assignment_submissions.tenant_id
    )
  );
drop policy if exists submissions_update_own on public.assignment_submissions;
create policy submissions_update_own on public.assignment_submissions
  for update using (
    (user_id = auth.uid() and status <> 'graded' and public.is_tenant_member(tenant_id))
    or public.is_tenant_admin(tenant_id)
  );
drop policy if exists submissions_delete_admin on public.assignment_submissions;
create policy submissions_delete_admin on public.assignment_submissions
  for delete using (public.is_tenant_admin(tenant_id));

-- ============ support ============

drop policy if exists tickets_select on public.support_tickets;
create policy tickets_select on public.support_tickets
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists tickets_insert on public.support_tickets;
create policy tickets_insert on public.support_tickets
  for insert with check (
    user_id = auth.uid() and public.is_tenant_member(tenant_id)
  );
drop policy if exists tickets_update on public.support_tickets;
create policy tickets_update on public.support_tickets
  for update using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );

drop policy if exists ticket_messages_select on public.support_messages;
create policy ticket_messages_select on public.support_messages
  for select using (
    exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id
        and (
          public.is_tenant_admin(t.tenant_id)
          or (t.user_id = auth.uid() and public.is_tenant_member(t.tenant_id))
        )
    )
  );
drop policy if exists ticket_messages_insert on public.support_messages;
create policy ticket_messages_insert on public.support_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id
        and (
          public.is_tenant_admin(t.tenant_id)
          or (t.user_id = auth.uid() and public.is_tenant_member(t.tenant_id))
        )
    )
  );

-- ============ live sessions & library ============

drop policy if exists live_sessions_read on public.live_sessions;
create policy live_sessions_read on public.live_sessions
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and (
        course_id is null
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
      )
    )
  );
drop policy if exists live_sessions_write_admin on public.live_sessions;
create policy live_sessions_write_admin on public.live_sessions
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists library_read on public.library_items;
create policy library_read on public.library_items
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and (
        course_id is null
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
      )
    )
  );
drop policy if exists library_write_admin on public.library_items;
create policy library_write_admin on public.library_items
  for all using (public.is_tenant_admin(tenant_id));

-- ============ admin activity log ============

drop policy if exists admin_logs_admin on public.admin_activity_logs;
create policy admin_logs_admin on public.admin_activity_logs
  for all using (public.is_tenant_admin(tenant_id));

-- ============ broadcast: tenant-scoped ============
-- Now targets the active members of one tenant instead of every profile.

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
  where m.tenant_id = p_tenant_id
    and m.status = 'active'
    and coalesce(
      (select (np.prefs ->> p_type)::boolean
       from public.notification_preferences np
       where np.user_id = m.user_id),
      true
    );
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

-- ============================================================
-- FILE: supabase/migrations/0018_super_admin.sql
-- ============================================================
-- EduSpace: platform super admin seed + membership update hardening.
-- Run AFTER 0017_tenant_rls.sql.

-- Seed the platform team from the existing legacy global admins so the
-- super admin panel has an owner from day one. The per-tenant roles stage
-- will refine this.
insert into public.super_admins (user_id)
select distinct ur.user_id
from public.user_roles ur
join public.roles r on r.id = ur.role_id
where r.name in ('super_admin', 'admin')
on conflict (user_id) do nothing;

-- Approval decisions may not move a membership to another tenant.
drop policy if exists memberships_admin_update on public.tenant_memberships;
create policy memberships_admin_update on public.tenant_memberships
  for update to authenticated
  using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));

-- ============================================================
-- FILE: supabase/migrations/0019_tenant_roles.sql
-- ============================================================
-- EduSpace: per-tenant roles (exec guide section 15).
-- Run AFTER 0018_super_admin.sql.
--
-- A role row with tenant_id set belongs to that tenant; the legacy rows
-- with tenant_id null stay platform-wide. Holding a tenant's "admin" role
-- makes the user an admin of that tenant only.

-- ---------- roles.name uniqueness becomes (tenant, name) ----------

alter table public.roles drop constraint if exists roles_name_key;
drop index if exists roles_name_key;
drop index if exists roles_name_idx;

create unique index if not exists roles_global_name_uidx
  on public.roles (name) where tenant_id is null;
create unique index if not exists roles_tenant_name_uidx
  on public.roles (tenant_id, name) where tenant_id is not null;

-- ---------- default roles for every tenant ----------

insert into public.roles (name, tenant_id, is_system, description)
select r.name, t.id, false, r.description
from public.tenants t
cross join (
  values
    ('admin', 'Organization admin'),
    ('content_manager', 'Manages courses and content'),
    ('instructor', 'Teaches courses')
) as r(name, description)
on conflict do nothing;

create or replace function public.handle_new_tenant_roles()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.roles (name, tenant_id, is_system, description)
  values
    ('admin', new.id, false, 'Organization admin'),
    ('content_manager', new.id, false, 'Manages courses and content'),
    ('instructor', new.id, false, 'Teaches courses')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_tenant_created_roles on public.tenants;
create trigger on_tenant_created_roles
  after insert on public.tenants
  for each row execute function public.handle_new_tenant_roles();

-- ---------- tenant admin check honors tenant roles ----------

create or replace function public.is_tenant_admin(t uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_super_admin()
     or (public.is_admin() and public.is_tenant_member(t))
     or exists (
       select 1
       from public.user_roles ur
       join public.roles r on r.id = ur.role_id
       where ur.user_id = auth.uid()
         and r.tenant_id = t
         and r.name = 'admin'
     )
$$;

-- ---------- RLS: tenant admins manage their tenant's roles ----------

drop policy if exists roles_read_admin on public.roles;
create policy roles_read_admin on public.roles
  for select using (
    public.is_admin()
    or (tenant_id is not null and public.is_tenant_member(tenant_id))
  );

drop policy if exists roles_tenant_admin_insert on public.roles;
create policy roles_tenant_admin_insert on public.roles
  for insert with check (
    tenant_id is not null and public.is_tenant_admin(tenant_id)
  );

drop policy if exists roles_tenant_admin_update on public.roles;
create policy roles_tenant_admin_update on public.roles
  for update using (
    tenant_id is not null and public.is_tenant_admin(tenant_id)
  );

drop policy if exists roles_tenant_admin_delete on public.roles;
create policy roles_tenant_admin_delete on public.roles
  for delete using (
    tenant_id is not null
    and is_system = false
    and public.is_tenant_admin(tenant_id)
  );

drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles
  for select using (
    auth.uid() = user_id
    or public.is_admin()
    or exists (
      select 1 from public.roles r
      where r.id = role_id
        and r.tenant_id is not null
        and public.is_tenant_admin(r.tenant_id)
    )
  );

drop policy if exists user_roles_tenant_admin_insert on public.user_roles;
create policy user_roles_tenant_admin_insert on public.user_roles
  for insert with check (
    public.is_admin()
    or exists (
      select 1 from public.roles r
      where r.id = role_id
        and r.tenant_id is not null
        and public.is_tenant_admin(r.tenant_id)
    )
  );

drop policy if exists user_roles_tenant_admin_delete on public.user_roles;
create policy user_roles_tenant_admin_delete on public.user_roles
  for delete using (
    public.is_admin()
    or exists (
      select 1 from public.roles r
      where r.id = role_id
        and r.tenant_id is not null
        and public.is_tenant_admin(r.tenant_id)
    )
  );

-- ============================================================
-- FILE: supabase/migrations/0020_tenant_admin_update.sql
-- ============================================================
-- EduSpace: tenant admins manage their own organization's profile fields.
-- Run AFTER 0019_tenant_roles.sql.
-- Status stays super-admin only; invite code rotation stays super-admin
-- only for now.

drop policy if exists tenants_admin_update on public.tenants;
create policy tenants_admin_update on public.tenants
  for update to authenticated
  using (public.is_tenant_admin(id))
  with check (public.is_tenant_admin(id));

-- Guard: tenant admins may not flip status or invite_code through this
-- policy; those columns must keep their old values unless the writer is a
-- super admin.
create or replace function public.guard_tenant_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if public.is_super_admin() then
    return new;
  end if;
  if new.status is distinct from old.status
     or new.invite_code is distinct from old.invite_code then
    raise exception 'only super admins can change status or invite code';
  end if;
  return new;
end;
$$;

drop trigger if exists on_tenant_update_guard on public.tenants;
create trigger on_tenant_update_guard
  before update on public.tenants
  for each row execute function public.guard_tenant_update();

-- ============================================================
-- FILE: supabase/migrations/0021_storage_covers.sql
-- ============================================================
-- EduSpace: public course-cover bucket + tenant-aware storage writes.
-- Run AFTER 0020_tenant_admin_update.sql.

-- Public bucket for course covers (marketing images, no signed URLs).
insert into storage.buckets (id, name, public)
values ('covers', 'covers', true)
on conflict (id) do nothing;

drop policy if exists covers_read on storage.objects;
create policy covers_read on storage.objects
  for select using (bucket_id = 'covers');

-- Helper: first path segment as uuid, null when it is not one.
create or replace function public.storage_tenant_from_path(p_name text)
returns uuid
language sql stable
as $$
  select case
    when (storage.foldername(p_name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then ((storage.foldername(p_name))[1])::uuid
    else null
  end
$$;

drop policy if exists covers_write on storage.objects;
create policy covers_write on storage.objects
  for all to authenticated
  using (
    bucket_id = 'covers'
    and public.is_tenant_admin(public.storage_tenant_from_path(name))
  )
  with check (
    bucket_id = 'covers'
    and public.is_tenant_admin(public.storage_tenant_from_path(name))
  );

-- Private media buckets: tenant-role admins write inside their tenant
-- folder (first path segment = tenant id); legacy global admins keep
-- writing anywhere.
drop policy if exists private_files_admin_write on storage.objects;
create policy private_files_admin_write on storage.objects
  for all to authenticated
  using (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and (
      public.is_admin()
      or public.is_super_admin()
      or public.is_tenant_admin(public.storage_tenant_from_path(name))
    )
  )
  with check (
    bucket_id in ('resources', 'course-media', 'certificates', 'submissions')
    and (
      public.is_admin()
      or public.is_super_admin()
      or public.is_tenant_admin(public.storage_tenant_from_path(name))
    )
  );

-- ============================================================
-- FILE: supabase/migrations/0022_notification_triggers.sql
-- ============================================================
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

-- ============================================================
-- FILE: supabase/migrations/0023_drop_old_broadcast.sql
-- ============================================================
-- EduSpace: drop the pre-tenancy broadcast overload.
-- Run AFTER 0022_notification_triggers.sql.
--
-- 0017 added a 4-parameter tenant-scoped admin_broadcast_notification, but
-- CREATE OR REPLACE does not remove the old 3-parameter function: it kept
-- existing as a separate overload that fans out to EVERY profile across
-- all tenants. The app calls the 4-parameter version; drop the old one.

drop function if exists public.admin_broadcast_notification(text, text, text);
