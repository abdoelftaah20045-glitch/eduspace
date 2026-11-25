-- EduSpace: public certificate verification (doc section 17.2/17.3).
-- Run AFTER 0004_notifications_certificates.sql.
-- A stable SECURITY DEFINER function so anyone with the link can check a
-- certificate number over PostgREST (GET), while RLS on certificates stays
-- tight. Returns privacy-minimal data only.

create or replace function public.verify_certificate(p_number text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c public.certificates%rowtype;
begin
  select * into c
  from public.certificates
  where certificate_number = p_number;

  if not found then
    return json_build_object(
      'status', 'not_found',
      'certificate_number', p_number
    );
  end if;

  return json_build_object(
    'status', c.status,
    'certificate_number', c.certificate_number,
    'student_name', c.student_name,
    'course_title', c.course_title,
    'hours', c.hours,
    'issued_at', c.issued_at
  );
end;
$$;

revoke all on function public.verify_certificate(text) from public;
grant execute on function public.verify_certificate(text) to anon, authenticated;
