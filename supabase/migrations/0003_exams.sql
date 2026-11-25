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
