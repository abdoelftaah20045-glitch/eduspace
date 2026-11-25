-- EduSpace: assignment submission file uploads (exec guide S39 + section 17
-- Storage). Run AFTER 0014_push_tokens.sql.
-- Files live in the private `submissions` bucket (0013) under
-- <user_id>/<assignment_id>/<filename>; this column stores the path.

alter table public.assignment_submissions
  add column if not exists file_path text;
