-- EduSpace: multi-tenant foundation (exec guide sections 2 + 15).
-- Run AFTER 0015_submission_files.sql.
--
-- Additive and backward compatible: existing rows are backfilled into a
-- default "EduSpace" tenant, new tenant_id columns default to it, and a
-- trigger enrolls new signups into it. The current app keeps working
-- unchanged; per-tenant RLS tightening lands with the app-side tenant
-- context in the next stage.

-- ---------- tables ----------

create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  logo_key text,
  status text not null default 'active' check (status in ('active', 'suspended')),
  default_locale text not null default 'ar',
  timezone text not null default 'Africa/Cairo',
  invite_code text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.tenant_settings (
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  setting_key text not null,
  setting_value jsonb not null default '{}',
  updated_by uuid references public.profiles (id),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, setting_key)
);

create table if not exists public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected', 'suspended')),
  joined_at timestamptz not null default now(),
  approved_by uuid references public.profiles (id),
  approved_at timestamptz,
  unique (tenant_id, user_id)
);

-- Platform team; read only through security-definer helpers.
create table if not exists public.super_admins (
  user_id uuid primary key references public.profiles (id) on delete cascade
);

-- ---------- helpers ----------

create or replace function public.default_tenant_id()
returns uuid
language sql stable
as $$ select '00000000-0000-0000-0000-000000000001'::uuid $$;

create or replace function public.is_super_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.super_admins where user_id = auth.uid()) $$;

create or replace function public.is_tenant_member(t uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.tenant_memberships
    where tenant_id = t and user_id = auth.uid() and status = 'active'
  )
$$;

-- Transition rule: platform super admin, or a legacy global admin who is an
-- active member of that tenant. Per-tenant roles land with the roles stage.
create or replace function public.is_tenant_admin(t uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_super_admin()
     or (public.is_admin() and public.is_tenant_member(t))
$$;

-- Join by invite code without exposing codes: security definer, the app
-- never selects tenants.invite_code directly.
create or replace function public.join_tenant_by_code(p_code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  t uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select id into t from public.tenants
   where invite_code = upper(trim(p_code)) and status = 'active';
  if t is null then
    raise exception 'invalid_invite_code';
  end if;
  insert into public.tenant_memberships (tenant_id, user_id, status)
  values (t, auth.uid(), 'pending')
  on conflict (tenant_id, user_id) do nothing;
  return t;
end;
$$;

-- ---------- default tenant + backfill ----------

insert into public.tenants (id, name, slug, invite_code)
values ('00000000-0000-0000-0000-000000000001', 'EduSpace', 'eduspace', 'EDUSPACE')
on conflict (id) do nothing;

insert into public.tenant_memberships (tenant_id, user_id, status, approved_at)
select public.default_tenant_id(), id, 'active', now()
from public.profiles
on conflict (tenant_id, user_id) do nothing;

-- New signups join the default tenant as active members until the app's
-- tenant-selection flow (S03) replaces this path.
create or replace function public.handle_new_profile_tenant()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.tenant_memberships (tenant_id, user_id, status, approved_at)
  values (public.default_tenant_id(), new.id, 'active', now())
  on conflict (tenant_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_profile_created_tenant on public.profiles;
create trigger on_profile_created_tenant
  after insert on public.profiles
  for each row execute function public.handle_new_profile_tenant();

-- ---------- RLS on the new tables ----------

alter table public.tenants enable row level security;
alter table public.tenant_settings enable row level security;
alter table public.tenant_memberships enable row level security;
alter table public.super_admins enable row level security;

-- tenants: members can read their own tenants; only super admin writes.
-- The public directory for the join flow is the tenants_directory view
-- (no invite codes in it).
drop policy if exists tenants_read on public.tenants;
create policy tenants_read on public.tenants
  for select to authenticated
  using (public.is_tenant_member(id) or public.is_super_admin());

drop policy if exists tenants_super_write on public.tenants;
create policy tenants_super_write on public.tenants
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create or replace view public.tenants_directory as
  select id, name, slug, logo_key
  from public.tenants
  where status = 'active';

-- memberships: read own (or as tenant admin); self-join as pending;
-- approval decisions by tenant admins.
drop policy if exists memberships_read on public.tenant_memberships;
create policy memberships_read on public.tenant_memberships
  for select to authenticated
  using (user_id = auth.uid() or public.is_tenant_admin(tenant_id));

drop policy if exists memberships_self_join on public.tenant_memberships;
create policy memberships_self_join on public.tenant_memberships
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');

drop policy if exists memberships_admin_update on public.tenant_memberships;
create policy memberships_admin_update on public.tenant_memberships
  for update to authenticated
  using (public.is_tenant_admin(tenant_id));

-- settings: members read, tenant admins write.
drop policy if exists settings_read on public.tenant_settings;
create policy settings_read on public.tenant_settings
  for select to authenticated
  using (public.is_tenant_member(tenant_id) or public.is_tenant_admin(tenant_id));

drop policy if exists settings_admin_write on public.tenant_settings;
create policy settings_admin_write on public.tenant_settings
  for all to authenticated
  using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));

-- ---------- tenant_id on root-scoped tables ----------
-- Child tables (sections, lessons, options, answers, ...) stay scoped via
-- their parent, per the spec. Columns default to the EduSpace tenant so the
-- current app keeps inserting without changes.

alter table public.courses
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.enrollments
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.question_banks
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.questions
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.exams
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.exam_attempts
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.notifications
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.announcements
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.certificates
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.favorites
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.course_reviews
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.support_tickets
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.live_sessions
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.library_items
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.assignments
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.assignment_submissions
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
alter table public.admin_activity_logs
  add column if not exists tenant_id uuid not null
  default public.default_tenant_id() references public.tenants (id);
-- null = platform-wide role; set = tenant-specific role (spec section 15)
alter table public.roles
  add column if not exists tenant_id uuid references public.tenants (id);

create index if not exists courses_tenant_idx on public.courses (tenant_id);
create index if not exists enrollments_tenant_idx on public.enrollments (tenant_id);
create index if not exists exams_tenant_idx on public.exams (tenant_id);
create index if not exists notifications_tenant_idx on public.notifications (tenant_id);
create index if not exists memberships_user_idx on public.tenant_memberships (user_id);
