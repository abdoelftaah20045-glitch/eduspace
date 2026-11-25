-- EduSpace: course spec gaps. Run AFTER 0025_targeted_notifications.sql.
-- Safe to re-run.

alter table public.lessons add column if not exists is_hidden boolean not null default false;
alter table public.courses add column if not exists available_until timestamptz;

-- ---------- course discussion (threads + replies) ----------
create table if not exists public.course_threads (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text not null default '',
  pinned boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.course_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.course_threads (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create index if not exists course_threads_course_idx on public.course_threads (course_id, created_at desc);
create index if not exists course_replies_thread_idx on public.course_replies (thread_id, created_at);

alter table public.course_threads enable row level security;
alter table public.course_replies enable row level security;

create or replace function public.can_discuss_course(cid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.courses c
    where c.id = cid
      and (
        public.is_tenant_admin(c.tenant_id)
        or exists (
          select 1 from public.enrollments e
          where e.course_id = c.id and e.user_id = auth.uid()
            and e.status in ('active','completed')
        )
      )
  )
$$;

drop policy if exists threads_read on public.course_threads;
create policy threads_read on public.course_threads
  for select using (public.can_discuss_course(course_id));
drop policy if exists threads_insert on public.course_threads;
create policy threads_insert on public.course_threads
  for insert with check (user_id = auth.uid() and public.can_discuss_course(course_id));
drop policy if exists threads_update on public.course_threads;
create policy threads_update on public.course_threads
  for update using (
    exists (select 1 from public.courses c where c.id = course_id and public.is_tenant_admin(c.tenant_id))
  );
drop policy if exists threads_delete on public.course_threads;
create policy threads_delete on public.course_threads
  for delete using (
    user_id = auth.uid()
    or exists (select 1 from public.courses c where c.id = course_id and public.is_tenant_admin(c.tenant_id))
  );

drop policy if exists replies_read on public.course_replies;
create policy replies_read on public.course_replies
  for select using (
    exists (select 1 from public.course_threads t where t.id = thread_id and public.can_discuss_course(t.course_id))
  );
drop policy if exists replies_insert on public.course_replies;
create policy replies_insert on public.course_replies
  for insert with check (
    user_id = auth.uid()
    and exists (select 1 from public.course_threads t where t.id = thread_id and public.can_discuss_course(t.course_id))
  );
drop policy if exists replies_delete on public.course_replies;
create policy replies_delete on public.course_replies
  for delete using (
    user_id = auth.uid()
    or exists (
      select 1 from public.course_threads t join public.courses c on c.id = t.course_id
      where t.id = thread_id and public.is_tenant_admin(c.tenant_id)
    )
  );
