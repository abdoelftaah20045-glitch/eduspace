-- EduSpace: admin tools - audit log (A33) and categories/levels (A11).
-- Run AFTER 0023_drop_old_broadcast.sql. Safe to re-run.

create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  entity text,
  entity_id text,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists audit_log_tenant_created
  on public.audit_log (tenant_id, created_at desc);
alter table public.audit_log enable row level security;

drop policy if exists audit_admin_read on public.audit_log;
create policy audit_admin_read on public.audit_log
  for select to authenticated
  using (public.is_tenant_admin(tenant_id));

drop policy if exists audit_admin_insert on public.audit_log;
create policy audit_admin_insert on public.audit_log
  for insert to authenticated
  with check (public.is_tenant_admin(tenant_id) and actor_id = auth.uid());

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind text not null default 'category' check (kind in ('category', 'level', 'tag')),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists categories_tenant_kind
  on public.categories (tenant_id, kind);
alter table public.categories enable row level security;

drop policy if exists categories_read on public.categories;
create policy categories_read on public.categories
  for select to authenticated
  using (public.is_tenant_member(tenant_id) or public.is_tenant_admin(tenant_id));

drop policy if exists categories_admin_write on public.categories;
create policy categories_admin_write on public.categories
  for all to authenticated
  using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));

alter table public.courses
  add column if not exists category_id uuid references public.categories (id) on delete set null;
