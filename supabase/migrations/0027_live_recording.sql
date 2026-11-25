-- Live session recording link (played inside the app). Idempotent.
alter table public.live_sessions add column if not exists recording_url text;
