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
