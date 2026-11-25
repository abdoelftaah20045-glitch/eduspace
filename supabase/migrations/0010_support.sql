-- EduSpace: support tickets (doc section 19). Run AFTER 0009_favorites_reviews.sql.

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  subject text not null,
  category text not null default 'general',
  status text not null default 'new'
    check (status in ('new','in_progress','waiting_user','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;

-- tickets: owner or admin.
drop policy if exists tickets_select on public.support_tickets;
create policy tickets_select on public.support_tickets
  for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists tickets_insert on public.support_tickets;
create policy tickets_insert on public.support_tickets
  for insert with check (user_id = auth.uid());
drop policy if exists tickets_update on public.support_tickets;
create policy tickets_update on public.support_tickets
  for update using (user_id = auth.uid() or public.is_admin());

-- messages: on tickets you own, or admin anywhere.
drop policy if exists ticket_messages_select on public.support_messages;
create policy ticket_messages_select on public.support_messages
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id and t.user_id = auth.uid()
    )
  );
drop policy if exists ticket_messages_insert on public.support_messages;
create policy ticket_messages_insert on public.support_messages
  for insert with check (
    sender_id = auth.uid()
    and (
      public.is_admin()
      or exists (
        select 1 from public.support_tickets t
        where t.id = support_messages.ticket_id and t.user_id = auth.uid()
      )
    )
  );

create index if not exists tickets_user_idx on public.support_tickets (user_id, created_at desc);
create index if not exists ticket_messages_idx on public.support_messages (ticket_id, created_at);
