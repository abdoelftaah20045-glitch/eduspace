-- EduSpace part 14: student question bank (favorites and notes). Idempotent.
create table if not exists public.question_marks (
  user_id uuid not null references public.profiles (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  favorite boolean not null default false,
  note text,
  updated_at timestamptz not null default now(),
  primary key (user_id, question_id)
);
alter table public.question_marks enable row level security;
drop policy if exists question_marks_own on public.question_marks;
create policy question_marks_own on public.question_marks
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
