-- EduSpace part 13: certificate templates, issue rules, server-side issue
-- and manual issue. Idempotent.

create table if not exists public.certificate_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default public.default_tenant_id()
    references public.tenants (id) on delete cascade,
  course_id uuid references public.courses (id) on delete cascade, -- null = all courses
  enabled boolean not null default true,
  template_url text,
  text_color text not null default 'dark' check (text_color in ('dark','light')),
  text_position text not null default 'center' check (text_position in ('top','center','low')),
  min_exam_percent numeric(5,2) not null default 0,
  hours_text text,
  updated_at timestamptz not null default now()
);
create unique index if not exists certificate_settings_scope_uidx
  on public.certificate_settings (tenant_id, coalesce(course_id, '00000000-0000-0000-0000-000000000000'::uuid));
alter table public.certificate_settings enable row level security;
drop policy if exists cert_settings_read on public.certificate_settings;
create policy cert_settings_read on public.certificate_settings
  for select to authenticated using (true);
drop policy if exists cert_settings_admin on public.certificate_settings;
create policy cert_settings_admin on public.certificate_settings
  for all to authenticated
  using (public.is_tenant_admin(tenant_id))
  with check (public.is_tenant_admin(tenant_id));

-- Effective settings for a course (course row wins over the global row).
create or replace function public.cert_effective_settings(p_course uuid)
returns public.certificate_settings
language sql stable security definer set search_path = public
as $$
  select cs.* from public.certificate_settings cs
   where cs.tenant_id = (select tenant_id from public.courses where id = p_course)
     and (cs.course_id = p_course or cs.course_id is null)
   order by (cs.course_id is null) asc
   limit 1;
$$;
grant execute on function public.cert_effective_settings(uuid) to authenticated;

create or replace function public._cert_serial()
returns text language plpgsql as $$
declare chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; t text := ''; i int;
begin
  for i in 1..6 loop
    t := t || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return 'EDU-' || extract(year from now())::int || '-' || t;
end $$;

-- Student: issue my certificate if the rules are met.
create or replace function public.issue_certificate(p_course uuid)
returns setof public.certificates
language plpgsql security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cs public.certificate_settings;
  c record;
  total int; done int;
  best numeric;
  nm text;
begin
  select * into c from public.certificates where user_id = uid and course_id = p_course;
  if found then return next c; return; end if;
  select * into cs from public.cert_effective_settings(p_course);
  if cs.id is not null and not cs.enabled then return; end if;
  if not exists (select 1 from public.enrollments e
                  where e.user_id = uid and e.course_id = p_course and e.status = 'active') then
    return;
  end if;
  select count(*) into total from public.lessons where course_id = p_course;
  select count(*) into done from public.lesson_progress lp
    join public.lessons l on l.id = lp.lesson_id
   where l.course_id = p_course and lp.user_id = uid and lp.completed;
  if total = 0 or done < total then return; end if;
  if coalesce(cs.min_exam_percent, 0) > 0 then
    select max(case when a.max_score > 0 then a.score / a.max_score * 100 else 0 end) into best
      from public.exam_attempts a join public.exams x on x.id = a.exam_id
     where a.user_id = uid and x.course_id = p_course
       and a.status in ('submitted','graded');
    if coalesce(best, 0) < cs.min_exam_percent then return; end if;
  end if;
  select coalesce(nullif(trim(full_name), ''), email) into nm from public.profiles where id = uid;
  return query
  insert into public.certificates
    (user_id, course_id, certificate_number, student_name, course_title, hours, tenant_id)
  select uid, p_course, public._cert_serial(), coalesce(nm, 'Student'), co.title, co.hours, co.tenant_id
    from public.courses co where co.id = p_course
  returning *;
end;
$$;
grant execute on function public.issue_certificate(uuid) to authenticated;

-- Admin: issue manually by student email (ignores the rules).
create or replace function public.admin_issue_certificate(p_email text, p_course uuid)
returns text
language plpgsql security definer set search_path = public
as $$
declare co record; pr record; serial text;
begin
  select * into co from public.courses where id = p_course;
  if co.id is null then raise exception 'course not found'; end if;
  if not public.is_tenant_admin(co.tenant_id) then raise exception 'not allowed'; end if;
  select * into pr from public.profiles where lower(email) = lower(trim(p_email));
  if pr.id is null then raise exception 'student not found'; end if;
  serial := public._cert_serial();
  insert into public.certificates
    (user_id, course_id, certificate_number, student_name, course_title, hours, tenant_id)
  values (pr.id, p_course, serial, coalesce(nullif(trim(pr.full_name), ''), pr.email), co.title, co.hours, co.tenant_id)
  on conflict (user_id, course_id) do nothing;
  return serial;
end;
$$;
grant execute on function public.admin_issue_certificate(text, uuid) to authenticated;

-- From now on certificates are issued only through issue_certificate, so the
-- exam-grade rule cannot be bypassed by a direct insert.
drop policy if exists certificates_insert_self_completed on public.certificates;

-- Announcements: several images per announcement (public URLs).
alter table public.announcements add column if not exists images jsonb not null default '[]'::jsonb;
alter table public.announcements add column if not exists slide_seconds int not null default 4;
