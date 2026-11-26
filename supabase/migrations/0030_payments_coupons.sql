-- EduSpace part 12: manual payments (receipt upload + admin approval) and
-- coupons. No payment gateway, no fees. Idempotent.

-- ---------- coupons ----------
create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  code text not null,
  percent_off numeric(5,2),
  amount_off numeric(10,2),
  course_id uuid references public.courses (id) on delete cascade,
  max_uses int,
  uses int not null default 0,
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (percent_off is not null or amount_off is not null)
);
create unique index if not exists coupons_tenant_code_uidx
  on public.coupons (tenant_id, lower(code));
alter table public.coupons enable row level security;

drop policy if exists coupons_admin on public.coupons;
create policy coupons_admin on public.coupons
  for all using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));

-- ---------- payment requests ----------
create table if not exists public.payment_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  amount numeric(10,2) not null default 0,
  coupon_code text,
  method text not null default 'manual',
  receipt_path text,
  note text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references public.profiles (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists payment_requests_tenant_idx
  on public.payment_requests (tenant_id, status, created_at desc);
alter table public.payment_requests enable row level security;

drop policy if exists pay_select on public.payment_requests;
create policy pay_select on public.payment_requests
  for select using (user_id = auth.uid() or public.is_tenant_admin(tenant_id));
drop policy if exists pay_insert on public.payment_requests;
create policy pay_insert on public.payment_requests
  for insert with check (user_id = auth.uid() and status = 'pending');
drop policy if exists pay_admin_update on public.payment_requests;
create policy pay_admin_update on public.payment_requests
  for update using (public.is_tenant_admin(tenant_id));

-- ---------- coupon check (students never read the coupons table) ----------
create or replace function public.validate_coupon(p_code text, p_course uuid)
returns table (ok boolean, percent_off numeric, amount_off numeric, final_price numeric)
language plpgsql stable security definer set search_path = public
as $$
declare
  c record;
  price numeric;
  tid uuid;
  res numeric;
begin
  select co.price, co.tenant_id into price, tid from public.courses co where co.id = p_course;
  if price is null then
    return query select false, null::numeric, null::numeric, null::numeric; return;
  end if;
  select * into c from public.coupons
   where tenant_id = tid and lower(code) = lower(trim(p_code)) and active
     and (expires_at is null or expires_at > now())
     and (max_uses is null or uses < max_uses)
     and (course_id is null or course_id = p_course)
   limit 1;
  if not found then
    return query select false, null::numeric, null::numeric, price; return;
  end if;
  res := price;
  if c.percent_off is not null then res := res - res * c.percent_off / 100; end if;
  if c.amount_off is not null then res := res - c.amount_off; end if;
  if res < 0 then res := 0; end if;
  return query select true, c.percent_off, c.amount_off, round(res, 2);
end;
$$;
grant execute on function public.validate_coupon(text, uuid) to authenticated;

-- ---------- submit a request (recomputes the price on the server) ----------
create or replace function public.submit_payment(
  p_course uuid, p_coupon text, p_receipt text, p_note text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  tid uuid;
  price numeric;
  final numeric;
  v record;
  pid uuid;
begin
  select tenant_id, c.price into tid, price from public.courses c where c.id = p_course;
  if tid is null then raise exception 'course not found'; end if;
  final := price;
  if p_coupon is not null and length(trim(p_coupon)) > 0 then
    select * into v from public.validate_coupon(p_coupon, p_course);
    if v.ok then final := v.final_price; else p_coupon := null; end if;
  end if;
  insert into public.payment_requests
    (tenant_id, user_id, course_id, amount, coupon_code, receipt_path, note)
  values (tid, auth.uid(), p_course, final, nullif(trim(coalesce(p_coupon,'')), ''), p_receipt, p_note)
  returning id into pid;
  return pid;
end;
$$;
grant execute on function public.submit_payment(uuid, text, text, text) to authenticated;

-- ---------- admin decision ----------
create or replace function public.review_payment(p_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare r record;
begin
  select * into r from public.payment_requests where id = p_id;
  if r.id is null then raise exception 'not found'; end if;
  if not public.is_tenant_admin(r.tenant_id) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then raise exception 'already reviewed'; end if;
  update public.payment_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         admin_note = p_note, reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id;
  if p_approve then
    insert into public.enrollments (user_id, course_id, status, source, granted_by, tenant_id)
    values (r.user_id, r.course_id, 'active', 'payment', auth.uid(), r.tenant_id)
    on conflict (user_id, course_id) do update set status = 'active', source = 'payment';
    if r.coupon_code is not null then
      update public.coupons set uses = uses + 1
       where tenant_id = r.tenant_id and lower(code) = lower(r.coupon_code);
    end if;
  end if;
end;
$$;
grant execute on function public.review_payment(uuid, boolean, text) to authenticated;

-- ---------- receipts bucket (private) ----------
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

drop policy if exists receipts_own_insert on storage.objects;
create policy receipts_own_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts'
              and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists receipts_read on storage.objects;
create policy receipts_read on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or public.is_admin()));

-- ---------- files attached under each lesson ----------
create table if not exists public.lesson_files (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  lesson_id uuid not null references public.lessons (id) on delete cascade,
  name text not null,
  file_url text not null,
  created_at timestamptz not null default now()
);
create index if not exists lesson_files_lesson_idx on public.lesson_files (lesson_id);
alter table public.lesson_files enable row level security;
drop policy if exists lesson_files_read on public.lesson_files;
create policy lesson_files_read on public.lesson_files
  for select to authenticated using (true);
drop policy if exists lesson_files_admin on public.lesson_files;
create policy lesson_files_admin on public.lesson_files
  for all to authenticated
  using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));
