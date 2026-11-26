-- Deki: automatic per-course discount (STAGED, not shipped until the owner approves).
-- Idempotent. Run after 0036.

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
