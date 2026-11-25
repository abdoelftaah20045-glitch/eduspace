-- EduSpace Stage 1: accounts, roles, languages.
-- Run in the Supabase SQL editor or via the CLI. Idempotent where possible.

-- ============ profiles ============
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  phone text,
  avatar_url text,
  birth_date date,
  country text,
  governorate text,
  institution text,
  faculty text,
  specialization text,
  stage text,
  level text,
  group_name text,
  bio text,
  status text not null default 'active'
    check (status in ('pending','active','rejected','suspended')),
  status_reason text,
  locale text not null default 'ar',
  theme text not null default 'system'
    check (theme in ('light','dark','system')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Create a profile automatically on sign up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'locale', 'ar')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ roles & permissions ============
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  user_id uuid not null references public.profiles (id) on delete cascade,
  role_id uuid not null references public.roles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles (id) on delete cascade,
  permission_id uuid not null references public.permissions (id) on delete cascade,
  primary key (role_id, permission_id)
);

insert into public.roles (name, is_system) values
  ('super_admin', true), ('admin', true), ('content_manager', true),
  ('exam_manager', true), ('instructor', true), ('finance', true),
  ('support', true), ('student', true)
on conflict (name) do nothing;

-- Admin check used by policies. security definer so it can read user_roles.
create or replace function public.is_admin()
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.name in ('super_admin','admin')
  );
$$;

-- ============ admin activity ============
create table if not exists public.admin_activity_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles (id),
  action text not null,
  target_type text,
  target_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

-- ============ languages & translations ============
create table if not exists public.languages (
  code text primary key,
  name text not null,
  direction text not null default 'ltr' check (direction in ('rtl','ltr')),
  is_active boolean not null default true,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.languages (code, name, direction, is_active, is_default) values
  ('ar', 'العربية', 'rtl', true, true),
  ('en', 'English', 'ltr', true, false)
on conflict (code) do nothing;

create table if not exists public.translation_keys (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  group_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.translations (
  id uuid primary key default gen_random_uuid(),
  key_id uuid not null references public.translation_keys (id) on delete cascade,
  language_code text not null references public.languages (code) on delete cascade,
  value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (key_id, language_code)
);

-- ============ row level security ============
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.admin_activity_logs enable row level security;
alter table public.languages enable row level security;
alter table public.translation_keys enable row level security;
alter table public.translations enable row level security;

-- profiles: everyone reads their own row; admins read all.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select using (auth.uid() = id or public.is_admin());

-- profiles: users update their own row...
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id);

-- ...but only admins may change account status (checked by trigger below).
create or replace function public.guard_profile_status()
returns trigger
language plpgsql
as $$
begin
  if (new.status is distinct from old.status
      or new.status_reason is distinct from old.status_reason)
     and not public.is_admin() then
    raise exception 'only admins can change account status';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_guard_status on public.profiles;
create trigger profiles_guard_status
  before update on public.profiles
  for each row execute function public.guard_profile_status();

-- roles/permissions/role_permissions: read for admins only.
drop policy if exists roles_read_admin on public.roles;
create policy roles_read_admin on public.roles
  for select using (public.is_admin());
drop policy if exists permissions_read_admin on public.permissions;
create policy permissions_read_admin on public.permissions
  for select using (public.is_admin());
drop policy if exists role_permissions_read_admin on public.role_permissions;
create policy role_permissions_read_admin on public.role_permissions
  for select using (public.is_admin());

-- user_roles: users read their own roles; admins read all.
drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles
  for select using (auth.uid() = user_id or public.is_admin());

-- admin_activity_logs: admins only.
drop policy if exists admin_logs_admin on public.admin_activity_logs;
create policy admin_logs_admin on public.admin_activity_logs
  for all using (public.is_admin());

-- languages and translations: readable by everyone (needed before login);
-- writes by admins only.
drop policy if exists languages_read_all on public.languages;
create policy languages_read_all on public.languages
  for select using (true);
drop policy if exists languages_write_admin on public.languages;
create policy languages_write_admin on public.languages
  for all using (public.is_admin());

drop policy if exists translation_keys_read_all on public.translation_keys;
create policy translation_keys_read_all on public.translation_keys
  for select using (true);
drop policy if exists translation_keys_write_admin on public.translation_keys;
create policy translation_keys_write_admin on public.translation_keys
  for all using (public.is_admin());

drop policy if exists translations_read_all on public.translations;
create policy translations_read_all on public.translations
  for select using (true);
drop policy if exists translations_write_admin on public.translations;
create policy translations_write_admin on public.translations
  for all using (public.is_admin());

-- indexes
create index if not exists profiles_status_idx on public.profiles (status);
create index if not exists admin_logs_admin_idx on public.admin_activity_logs (admin_id, created_at desc);
create index if not exists translations_key_lang_idx on public.translations (key_id, language_code);
