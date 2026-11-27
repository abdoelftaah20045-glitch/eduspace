-- Subscriptions (spec A14): plans (monthly/yearly) and subscribers.
-- A subscription gives access to every published course of the
-- organization until it ends or is cancelled. Payment is handled outside
-- the app (manual), the admin grants the plan when the money arrives.
create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  name text not null,
  months int not null default 1 check (months > 0),
  price numeric(10,2) not null default 0,
  currency text not null default 'EGP',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  plan_id uuid references public.subscription_plans (id) on delete set null,
  status text not null default 'active' check (status in ('active','cancelled','expired')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index if not exists subscriptions_tenant_idx on public.subscriptions (tenant_id, status);
alter table public.subscription_plans enable row level security;
alter table public.subscriptions enable row level security;

drop policy if exists plans_read on public.subscription_plans;
create policy plans_read on public.subscription_plans for select to authenticated
  using (true);
drop policy if exists plans_admin on public.subscription_plans;
create policy plans_admin on public.subscription_plans for all to authenticated
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));
drop policy if exists subs_read on public.subscriptions;
create policy subs_read on public.subscriptions for select to authenticated
  using (user_id = auth.uid() or public.is_tenant_admin(tenant_id));

create or replace function public.grant_subscription(p_email text, p_plan uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare pl record; uid uuid; sid uuid;
begin
  select * into pl from public.subscription_plans where id = p_plan;
  if pl.id is null then raise exception 'plan not found'; end if;
  if not public.is_tenant_admin(pl.tenant_id) then raise exception 'not allowed'; end if;
  select id into uid from public.profiles where lower(email) = lower(trim(p_email));
  if uid is null then raise exception 'user not found'; end if;
  insert into public.subscriptions (tenant_id, user_id, plan_id, ends_at, created_by)
  values (pl.tenant_id, uid, pl.id, now() + make_interval(months => pl.months), auth.uid())
  returning id into sid;
  insert into public.enrollments (user_id, course_id, status, source, granted_by, tenant_id)
  select uid, c.id, 'active', 'grant', auth.uid(), pl.tenant_id
    from public.courses c where c.tenant_id = pl.tenant_id and c.status = 'published'
  on conflict (user_id, course_id) do update set status = 'active';
  insert into public.notifications (user_id, title, body, type, tenant_id)
  values (uid, 'تم تفعيل اشتراكك / Subscription active', pl.name, 'general', pl.tenant_id);
end;
$$;
grant execute on function public.grant_subscription(text, uuid) to authenticated;

create or replace function public.cancel_subscription(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare s record;
begin
  select * into s from public.subscriptions where id = p_id;
  if s.id is null then raise exception 'not found'; end if;
  if not public.is_tenant_admin(s.tenant_id) then raise exception 'not allowed'; end if;
  update public.subscriptions set status = 'cancelled' where id = p_id;
  -- Remove the access given by subscription (grant source) on this org's courses.
  update public.enrollments e set status = 'suspended'
   where e.user_id = s.user_id and e.source = 'grant' and e.status = 'active'
     and e.course_id in (select id from public.courses where tenant_id = s.tenant_id);
end;
$$;
grant execute on function public.cancel_subscription(uuid) to authenticated;
