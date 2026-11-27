-- Real push for "new course" (run AFTER the send-push edge function is
-- deployed and the Firebase service-account secret is set).
create extension if not exists pg_net with schema extensions;

alter table public.courses add column if not exists push_sent_at timestamptz;

create or replace function public.push_new_course()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if new.notified_at is not null and old.notified_at is null then
    perform net.http_post(
      url := 'https://jyzfyaparlmokiebewdl.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object('course_id', new.id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_push_new_course on public.courses;
create trigger trg_push_new_course
  after update on public.courses
  for each row execute function public.push_new_course();
