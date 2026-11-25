-- EduSpace: كل المايجريشنز من 0002 لحد 0008 في ملف واحد، بالترتيب.
-- شغّل 0001_init.sql الأول، وبعدين الصق الملف ده كله في SQL Editor مرة واحدة.
-- آمن لإعادة التشغيل (idempotent).

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

