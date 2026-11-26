-- Deki part 26: automatic per-course discount (percent + optional start/end dates).
-- Safe to run more than once. Run after part 25 / migration 0036.

alter table public.courses
  add column if not exists discount_percent numeric(5,2)
    check (discount_percent is null or (discount_percent > 0 and discount_percent < 100)),
  add column if not exists discount_starts_at timestamptz,
  add column if not exists discount_ends_at timestamptz;

-- Price after the automatic discount (the discount applies only while active).
create or replace function public.course_effective_price(p_course uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select case
    when c.discount_percent is not null
     and (c.discount_starts_at is null or c.discount_starts_at <= now())
     and (c.discount_ends_at is null or c.discount_ends_at > now())
    then round(c.price - c.price * c.discount_percent / 100, 2)
    else c.price end
  from public.courses c where c.id = p_course;
$$;
grant execute on function public.course_effective_price(uuid) to authenticated;

-- Coupons now apply on top of the discounted price.
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
  select public.course_effective_price(co.id), co.tenant_id into price, tid
    from public.courses co where co.id = p_course;
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

-- The server recomputes the charged amount from the discounted price.
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
  select tenant_id into tid from public.courses where id = p_course;
  if tid is null then raise exception 'course not found'; end if;
  price := public.course_effective_price(p_course);
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
