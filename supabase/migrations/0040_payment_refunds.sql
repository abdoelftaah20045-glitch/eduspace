-- Refunds (spec A16): an admin marks an approved payment as refunded with a
-- reason; the student's enrollment becomes 'refunded' (access removed) and
-- a notification is sent. The money itself is returned outside the app.
alter table public.payment_requests drop constraint if exists payment_requests_status_check;
alter table public.payment_requests add constraint payment_requests_status_check
  check (status in ('pending','approved','rejected','refunded'));

create or replace function public.refund_payment(p_id uuid, p_reason text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare r record;
begin
  select * into r from public.payment_requests where id = p_id;
  if r.id is null then raise exception 'not found'; end if;
  if not public.is_tenant_admin(r.tenant_id) then raise exception 'not allowed'; end if;
  if r.status <> 'approved' then raise exception 'only approved payments can be refunded'; end if;
  update public.payment_requests
     set status = 'refunded', admin_note = coalesce(p_reason, admin_note),
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id;
  update public.enrollments set status = 'refunded'
   where user_id = r.user_id and course_id = r.course_id;
  insert into public.notifications (user_id, title, body, type, tenant_id)
  values (r.user_id, 'تم رد المبلغ / Payment refunded', coalesce(p_reason, ''), 'general', r.tenant_id);
end;
$$;
grant execute on function public.refund_payment(uuid, text) to authenticated;
