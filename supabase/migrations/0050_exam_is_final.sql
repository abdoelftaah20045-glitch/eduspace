-- part50: marks an exam as a big / final exam.
-- Adds exams.is_final (default false). Safe to run more than once.
alter table public.exams
  add column if not exists is_final boolean not null default false;
