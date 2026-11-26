-- EduSpace part 11: granular staff permissions (scopes per role). Idempotent.
-- A role gets scopes such as courses, exams, support. Staff holding the role
-- can manage only those areas. The owner/admin keeps full access.
-- Scopes: courses, students, exams, lives, library, announcements, support,
--         certificates, reports, settings.  (team/roles stays admin-only.)

create table if not exists public.role_scopes (
  role_id uuid not null references public.roles (id) on delete cascade,
  scope text not null,
  primary key (role_id, scope)
);
alter table public.role_scopes enable row level security;

-- Built-in role names get default scopes while they have no explicit rows.
create or replace function public.has_scope(t uuid, sc text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_tenant_admin(t)
     or exists (
       select 1
       from public.user_roles ur
       join public.roles r on r.id = ur.role_id
       where ur.user_id = auth.uid()
         and r.tenant_id = t
         and (
           exists (select 1 from public.role_scopes rs
                   where rs.role_id = r.id and rs.scope = sc)
           or (
             not exists (select 1 from public.role_scopes rs2
                         where rs2.role_id = r.id)
             and (r.name, sc) in (
               ('content_manager','courses'), ('content_manager','library'),
               ('content_manager','announcements'),
               ('instructor','courses'), ('instructor','exams'),
               ('instructor','lives'),
               ('support_agent','support')
             )
           )
         )
     )
$$;

-- Scopes the current user has in a tenant (all of them for admins).
create or replace function public.my_scopes(t uuid default public.default_tenant_id())
returns text[]
language sql stable security definer set search_path = public
as $$
  select coalesce(array_agg(s), '{}')
  from unnest(array['courses','students','exams','lives','library',
                    'announcements','support','certificates','reports',
                    'settings']) s
  where public.has_scope(t, s)
$$;

grant execute on function public.has_scope(uuid, text) to authenticated;
grant execute on function public.my_scopes(uuid) to authenticated;

-- A ready-made customer-service role in every organization.
insert into public.roles (name, tenant_id, is_system, description)
select 'support_agent', t.id, false, 'Answers student support tickets only'
from public.tenants t
on conflict do nothing;

create or replace function public.handle_new_tenant_roles()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.roles (name, tenant_id, is_system, description)
  values
    ('admin', new.id, false, 'Organization admin'),
    ('content_manager', new.id, false, 'Manages courses and content'),
    ('instructor', new.id, false, 'Teaches courses'),
    ('support_agent', new.id, false, 'Answers student support tickets only')
  on conflict do nothing;
  return new;
end;
$$;

-- role_scopes policies
drop policy if exists role_scopes_read on public.role_scopes;
create policy role_scopes_read on public.role_scopes
  for select using (
    exists (select 1 from public.roles r
            where r.id = role_scopes.role_id
              and (public.is_tenant_admin(r.tenant_id)
                   or exists (select 1 from public.user_roles ur
                              where ur.role_id = r.id
                                and ur.user_id = auth.uid())))
  );
drop policy if exists role_scopes_write on public.role_scopes;
create policy role_scopes_write on public.role_scopes
  for all using (
    exists (select 1 from public.roles r
            where r.id = role_scopes.role_id
              and public.is_tenant_admin(r.tenant_id))
  ) with check (
    exists (select 1 from public.roles r
            where r.id = role_scopes.role_id
              and public.is_tenant_admin(r.tenant_id))
  );

-- Helper that adds an extra permissive policy only when the table exists.
create or replace function public._p11_policy(tbl text, scope text, expr text, cmd text default 'all')
returns void
language plpgsql
as $$
declare pname text := 'scope_' || tbl || '_' || scope || '_' || cmd;
begin
  if to_regclass('public.' || tbl) is null then return; end if;
  execute format('drop policy if exists %I on public.%I', pname, tbl);
  if cmd = 'select' then
    execute format('create policy %I on public.%I for select using (%s)', pname, tbl, expr);
  else
    execute format('create policy %I on public.%I for all using (%s) with check (%s)', pname, tbl, expr, expr);
  end if;
end;
$$;

do $$
begin
  -- courses
  perform public._p11_policy('courses', 'courses', 'public.has_scope(tenant_id, ''courses'')');
  perform public._p11_policy('course_sections', 'courses', 'exists (select 1 from public.courses c where c.id = course_id and public.has_scope(c.tenant_id, ''courses''))');
  perform public._p11_policy('lessons', 'courses', 'exists (select 1 from public.courses c where c.id = course_id and public.has_scope(c.tenant_id, ''courses''))');
  perform public._p11_policy('course_translations', 'courses', 'exists (select 1 from public.courses c where c.id = course_id and public.has_scope(c.tenant_id, ''courses''))');
  perform public._p11_policy('lesson_translations', 'courses', 'exists (select 1 from public.lessons l join public.courses c on c.id = l.course_id where l.id = lesson_id and public.has_scope(c.tenant_id, ''courses''))');
  -- students
  perform public._p11_policy('enrollments', 'students', 'public.has_scope(tenant_id, ''students'')');
  perform public._p11_policy('tenant_memberships', 'students', 'public.has_scope(tenant_id, ''students'')');
  -- exams
  perform public._p11_policy('exams', 'exams', 'public.has_scope(tenant_id, ''exams'')');
  perform public._p11_policy('question_banks', 'exams', 'public.has_scope(tenant_id, ''exams'')');
  perform public._p11_policy('questions', 'exams', 'public.has_scope(tenant_id, ''exams'')');
  perform public._p11_policy('question_options', 'exams', 'exists (select 1 from public.questions q where q.id = question_id and public.has_scope(q.tenant_id, ''exams''))');
  perform public._p11_policy('exam_questions', 'exams', 'exists (select 1 from public.exams e where e.id = exam_id and public.has_scope(e.tenant_id, ''exams''))');
  perform public._p11_policy('exam_attempts', 'exams', 'public.has_scope(tenant_id, ''exams'')');
  perform public._p11_policy('answers', 'exams', 'exists (select 1 from public.exam_attempts a where a.id = attempt_id and public.has_scope(a.tenant_id, ''exams''))');
  -- live sessions, library, announcements, certificates
  perform public._p11_policy('live_sessions', 'lives', 'public.has_scope(tenant_id, ''lives'')');
  perform public._p11_policy('library_items', 'library', 'public.has_scope(tenant_id, ''library'')');
  perform public._p11_policy('announcements', 'announcements', 'public.has_scope(tenant_id, ''announcements'')');
  perform public._p11_policy('certificates', 'certificates', 'public.has_scope(tenant_id, ''certificates'')');
  -- support: tickets and their messages
  perform public._p11_policy('support_tickets', 'support', 'public.has_scope(tenant_id, ''support'')');
  perform public._p11_policy('support_messages', 'support', 'exists (select 1 from public.support_tickets t where t.id = ticket_id and public.has_scope(t.tenant_id, ''support''))');
  -- reports and settings
  perform public._p11_policy('admin_activity_logs', 'reports', 'public.has_scope(tenant_id, ''reports'')', 'select');
  perform public._p11_policy('audit_log', 'reports', 'public.has_scope(tenant_id, ''reports'')', 'select');
  perform public._p11_policy('tenant_settings', 'settings', 'public.has_scope(tenant_id, ''settings'')');
end $$;

drop function if exists public._p11_policy(text, text, text, text);
