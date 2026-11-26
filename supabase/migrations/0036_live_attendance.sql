-- Part 18: live session attendance (who joined). Safe to run more than once.
create table if not exists public.live_attendance (
  live_id uuid not null references public.live_sessions (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (live_id, user_id)
);
alter table public.live_attendance enable row level security;

drop policy if exists live_attendance_insert_own on public.live_attendance;
create policy live_attendance_insert_own on public.live_attendance
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists live_attendance_select on public.live_attendance;
create policy live_attendance_select on public.live_attendance
  for select to authenticated using (
    user_id = auth.uid()
    or public.is_tenant_admin((select s.tenant_id from public.live_sessions s where s.id = live_id))
  );
