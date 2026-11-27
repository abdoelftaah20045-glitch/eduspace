-- Exam attached to one lesson (shown right after the lesson, auto-graded).
alter table public.exams
  add column if not exists lesson_id uuid references public.lessons (id) on delete set null;
create index if not exists exams_lesson_idx on public.exams (lesson_id);
