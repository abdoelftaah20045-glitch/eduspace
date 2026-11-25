-- EduSpace: per-tenant RLS tightening (exec guide sections 2, 14, 18).
-- Run AFTER 0016_tenancy_foundation.sql.
--
-- Every root table's policies now require active membership in the row's
-- tenant for student access, and is_tenant_admin(tenant_id) for admin
-- access. Child tables inherit the tenant scope through their parent row.
-- Legacy global admins keep full power inside tenants they belong to;
-- the platform team uses super_admins.

-- ============ courses & content ============

drop policy if exists courses_read on public.courses;
create policy courses_read on public.courses
  for select using (
    public.is_tenant_admin(tenant_id)
    or (status = 'published' and public.is_tenant_member(tenant_id))
  );
drop policy if exists courses_write_admin on public.courses;
create policy courses_write_admin on public.courses
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists course_translations_read on public.course_translations;
create policy course_translations_read on public.course_translations
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = course_id
        and (
          public.is_tenant_admin(c.tenant_id)
          or (c.status = 'published' and public.is_tenant_member(c.tenant_id))
        )
    )
  );
drop policy if exists course_translations_write_admin on public.course_translations;
create policy course_translations_write_admin on public.course_translations
  for all using (
    exists (
      select 1 from public.courses c
      where c.id = course_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists course_sections_read on public.course_sections;
create policy course_sections_read on public.course_sections
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = course_id
        and (
          public.is_tenant_admin(c.tenant_id)
          or (c.status = 'published' and public.is_tenant_member(c.tenant_id))
        )
    )
  );
drop policy if exists course_sections_write_admin on public.course_sections;
create policy course_sections_write_admin on public.course_sections
  for all using (
    exists (
      select 1 from public.courses c
      where c.id = course_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists lessons_read on public.lessons;
create policy lessons_read on public.lessons
  for select using (
    exists (
      select 1 from public.courses c
      where c.id = lessons.course_id
        and (
          public.is_tenant_admin(c.tenant_id)
          or (
            c.status = 'published'
            and public.is_tenant_member(c.tenant_id)
            and (
              lessons.is_free_preview
              or exists (
                select 1 from public.enrollments e
                where e.course_id = lessons.course_id
                  and e.user_id = auth.uid()
                  and e.status = 'active'
              )
            )
          )
        )
    )
  );
drop policy if exists lessons_write_admin on public.lessons;
create policy lessons_write_admin on public.lessons
  for all using (
    exists (
      select 1 from public.courses c
      where c.id = lessons.course_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists lesson_translations_read on public.lesson_translations;
create policy lesson_translations_read on public.lesson_translations
  for select using (
    exists (select 1 from public.lessons l where l.id = lesson_id)
  );
drop policy if exists lesson_translations_write_admin on public.lesson_translations;
create policy lesson_translations_write_admin on public.lesson_translations
  for all using (
    exists (
      select 1 from public.lessons l
      join public.courses c on c.id = l.course_id
      where l.id = lesson_id and public.is_tenant_admin(c.tenant_id)
    )
  );

drop policy if exists enrollments_read on public.enrollments;
create policy enrollments_read on public.enrollments
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists enrollments_insert_self_free on public.enrollments;
create policy enrollments_insert_self_free on public.enrollments
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.courses c
      where c.id = course_id
        and c.status = 'published'
        and c.price <= 0
        and c.tenant_id = enrollments.tenant_id
    )
  );
drop policy if exists enrollments_write_admin on public.enrollments;
create policy enrollments_write_admin on public.enrollments
  for all using (public.is_tenant_admin(tenant_id));

-- lesson_progress stays per-user (scoped through its lesson's course).
drop policy if exists lesson_progress_select on public.lesson_progress;
create policy lesson_progress_select on public.lesson_progress
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.lessons l
      join public.courses c on c.id = l.course_id
      where l.id = lesson_progress.lesson_id
        and public.is_tenant_admin(c.tenant_id)
    )
  );
drop policy if exists lesson_progress_delete_admin on public.lesson_progress;
create policy lesson_progress_delete_admin on public.lesson_progress
  for delete using (
    exists (
      select 1 from public.lessons l
      join public.courses c on c.id = l.course_id
      where l.id = lesson_progress.lesson_id
        and public.is_tenant_admin(c.tenant_id)
    )
  );

-- ============ exams & question bank ============

drop policy if exists question_banks_admin on public.question_banks;
create policy question_banks_admin on public.question_banks
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists questions_read on public.questions;
create policy questions_read on public.questions
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and exists (
        select 1
        from public.exam_questions eq
        join public.exams e on e.id = eq.exam_id
        where eq.question_id = questions.id and e.status = 'published'
      )
    )
  );
drop policy if exists questions_write_admin on public.questions;
create policy questions_write_admin on public.questions
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists question_options_read on public.question_options;
create policy question_options_read on public.question_options
  for select using (
    exists (
      select 1 from public.questions q
      where q.id = question_options.question_id
        and (
          public.is_tenant_admin(q.tenant_id)
          or (
            public.is_tenant_member(q.tenant_id)
            and exists (
              select 1
              from public.exam_questions eq
              join public.exams e on e.id = eq.exam_id
              where eq.question_id = q.id and e.status = 'published'
            )
          )
        )
    )
  );
drop policy if exists question_options_write_admin on public.question_options;
create policy question_options_write_admin on public.question_options
  for all using (
    exists (
      select 1 from public.questions q
      where q.id = question_options.question_id
        and public.is_tenant_admin(q.tenant_id)
    )
  );

drop policy if exists exams_read on public.exams;
create policy exams_read on public.exams
  for select using (
    public.is_tenant_admin(tenant_id)
    or (status = 'published' and public.is_tenant_member(tenant_id))
  );
drop policy if exists exams_write_admin on public.exams;
create policy exams_write_admin on public.exams
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists exam_questions_read on public.exam_questions;
create policy exam_questions_read on public.exam_questions
  for select using (
    exists (
      select 1 from public.exams e
      where e.id = exam_questions.exam_id
        and (
          public.is_tenant_admin(e.tenant_id)
          or (e.status = 'published' and public.is_tenant_member(e.tenant_id))
        )
    )
  );
drop policy if exists exam_questions_write_admin on public.exam_questions;
create policy exam_questions_write_admin on public.exam_questions
  for all using (
    exists (
      select 1 from public.exams e
      where e.id = exam_questions.exam_id
        and public.is_tenant_admin(e.tenant_id)
    )
  );

drop policy if exists attempts_select on public.exam_attempts;
create policy attempts_select on public.exam_attempts
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists attempts_insert on public.exam_attempts;
create policy attempts_insert on public.exam_attempts
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.exams e
      where e.id = exam_id
        and e.status = 'published'
        and e.tenant_id = exam_attempts.tenant_id
    )
  );
drop policy if exists attempts_update on public.exam_attempts;
create policy attempts_update on public.exam_attempts
  for update using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists attempts_delete_admin on public.exam_attempts;
create policy attempts_delete_admin on public.exam_attempts
  for delete using (public.is_tenant_admin(tenant_id));

drop policy if exists answers_select on public.answers;
create policy answers_select on public.answers
  for select using (
    exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id
        and (
          public.is_tenant_admin(a.tenant_id)
          or (a.user_id = auth.uid() and public.is_tenant_member(a.tenant_id))
        )
    )
  );
drop policy if exists answers_insert on public.answers;
create policy answers_insert on public.answers
  for insert with check (
    exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id
        and a.user_id = auth.uid()
        and public.is_tenant_member(a.tenant_id)
    )
  );
drop policy if exists answers_update on public.answers;
create policy answers_update on public.answers
  for update using (
    exists (
      select 1 from public.exam_attempts a
      where a.id = attempt_id
        and (
          public.is_tenant_admin(a.tenant_id)
          or (a.user_id = auth.uid() and public.is_tenant_member(a.tenant_id))
        )
    )
  );

-- ============ notifications, announcements, certificates ============

drop policy if exists announcements_read on public.announcements;
create policy announcements_read on public.announcements
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and starts_at <= now()
      and (ends_at is null or ends_at > now())
    )
  );
drop policy if exists announcements_write_admin on public.announcements;
create policy announcements_write_admin on public.announcements
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists notifications_insert_admin on public.notifications;
create policy notifications_insert_admin on public.notifications
  for insert with check (public.is_tenant_admin(tenant_id));
drop policy if exists notifications_delete_admin on public.notifications;
create policy notifications_delete_admin on public.notifications
  for delete using (public.is_tenant_admin(tenant_id));

drop policy if exists certificates_select on public.certificates;
create policy certificates_select on public.certificates
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists certificates_insert_self_completed on public.certificates;
create policy certificates_insert_self_completed on public.certificates
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.enrollments e
      where e.course_id = certificates.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
    and (select count(*) from public.lessons l
         where l.course_id = certificates.course_id) > 0
    and (select count(*) from public.lessons l
         where l.course_id = certificates.course_id)
      = (select count(*)
         from public.lesson_progress lp
         join public.lessons l2 on l2.id = lp.lesson_id
         where l2.course_id = certificates.course_id
           and lp.user_id = auth.uid()
           and lp.completed)
  );
drop policy if exists certificates_write_admin on public.certificates;
create policy certificates_write_admin on public.certificates
  for update using (public.is_tenant_admin(tenant_id));

-- ============ favorites & reviews ============

drop policy if exists favorites_all_own on public.favorites;
create policy favorites_all_own on public.favorites
  for all using (
    user_id = auth.uid() and public.is_tenant_member(tenant_id)
  );

drop policy if exists reviews_read on public.course_reviews;
create policy reviews_read on public.course_reviews
  for select using (
    public.is_tenant_member(tenant_id) or public.is_super_admin()
  );
drop policy if exists reviews_insert on public.course_reviews;
create policy reviews_insert on public.course_reviews
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.enrollments e
      where e.course_id = course_reviews.course_id
        and e.user_id = auth.uid()
        and e.status = 'active'
    )
  );
drop policy if exists reviews_update_own on public.course_reviews;
create policy reviews_update_own on public.course_reviews
  for update using (
    (user_id = auth.uid() and public.is_tenant_member(tenant_id))
    or public.is_tenant_admin(tenant_id)
  );
drop policy if exists reviews_delete on public.course_reviews;
create policy reviews_delete on public.course_reviews
  for delete using (
    (user_id = auth.uid() and public.is_tenant_member(tenant_id))
    or public.is_tenant_admin(tenant_id)
  );

-- ============ assignments ============

drop policy if exists assignments_read on public.assignments;
create policy assignments_read on public.assignments
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and (
        exists (
          select 1 from public.enrollments e
          where e.course_id = assignments.course_id
            and e.user_id = auth.uid()
            and e.status = 'active'
        )
        or exists (
          select 1 from public.courses c
          where c.id = assignments.course_id and c.status = 'published'
        )
      )
    )
  );
drop policy if exists assignments_write_admin on public.assignments;
create policy assignments_write_admin on public.assignments
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists submissions_select on public.assignment_submissions;
create policy submissions_select on public.assignment_submissions
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists submissions_insert on public.assignment_submissions;
create policy submissions_insert on public.assignment_submissions
  for insert with check (
    user_id = auth.uid()
    and public.is_tenant_member(tenant_id)
    and exists (
      select 1 from public.assignments a
      where a.id = assignment_id
        and a.tenant_id = assignment_submissions.tenant_id
    )
  );
drop policy if exists submissions_update_own on public.assignment_submissions;
create policy submissions_update_own on public.assignment_submissions
  for update using (
    (user_id = auth.uid() and status <> 'graded' and public.is_tenant_member(tenant_id))
    or public.is_tenant_admin(tenant_id)
  );
drop policy if exists submissions_delete_admin on public.assignment_submissions;
create policy submissions_delete_admin on public.assignment_submissions
  for delete using (public.is_tenant_admin(tenant_id));

-- ============ support ============

drop policy if exists tickets_select on public.support_tickets;
create policy tickets_select on public.support_tickets
  for select using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );
drop policy if exists tickets_insert on public.support_tickets;
create policy tickets_insert on public.support_tickets
  for insert with check (
    user_id = auth.uid() and public.is_tenant_member(tenant_id)
  );
drop policy if exists tickets_update on public.support_tickets;
create policy tickets_update on public.support_tickets
  for update using (
    public.is_tenant_admin(tenant_id)
    or (user_id = auth.uid() and public.is_tenant_member(tenant_id))
  );

drop policy if exists ticket_messages_select on public.support_messages;
create policy ticket_messages_select on public.support_messages
  for select using (
    exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id
        and (
          public.is_tenant_admin(t.tenant_id)
          or (t.user_id = auth.uid() and public.is_tenant_member(t.tenant_id))
        )
    )
  );
drop policy if exists ticket_messages_insert on public.support_messages;
create policy ticket_messages_insert on public.support_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id
        and (
          public.is_tenant_admin(t.tenant_id)
          or (t.user_id = auth.uid() and public.is_tenant_member(t.tenant_id))
        )
    )
  );

-- ============ live sessions & library ============

drop policy if exists live_sessions_read on public.live_sessions;
create policy live_sessions_read on public.live_sessions
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and (
        course_id is null
        or exists (
          select 1 from public.enrollments e
          where e.course_id = live_sessions.course_id
            and e.user_id = auth.uid()
            and e.status = 'active'
        )
        or exists (
          select 1 from public.courses c
          where c.id = live_sessions.course_id and c.status = 'published'
        )
      )
    )
  );
drop policy if exists live_sessions_write_admin on public.live_sessions;
create policy live_sessions_write_admin on public.live_sessions
  for all using (public.is_tenant_admin(tenant_id));

drop policy if exists library_read on public.library_items;
create policy library_read on public.library_items
  for select using (
    public.is_tenant_admin(tenant_id)
    or (
      public.is_tenant_member(tenant_id)
      and (
        course_id is null
        or exists (
          select 1 from public.enrollments e
          where e.course_id = library_items.course_id
            and e.user_id = auth.uid()
            and e.status = 'active'
        )
        or exists (
          select 1 from public.courses c
          where c.id = library_items.course_id and c.status = 'published'
        )
      )
    )
  );
drop policy if exists library_write_admin on public.library_items;
create policy library_write_admin on public.library_items
  for all using (public.is_tenant_admin(tenant_id));

-- ============ admin activity log ============

drop policy if exists admin_logs_admin on public.admin_activity_logs;
create policy admin_logs_admin on public.admin_activity_logs
  for all using (public.is_tenant_admin(tenant_id));

-- ============ broadcast: tenant-scoped ============
-- Now targets the active members of one tenant instead of every profile.

create or replace function public.admin_broadcast_notification(
  p_title text,
  p_body text default '',
  p_type text default 'general',
  p_tenant_id uuid default public.default_tenant_id()
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count int;
begin
  if not public.is_tenant_admin(p_tenant_id) then
    raise exception 'not authorized';
  end if;
  insert into public.notifications (user_id, title, body, type, tenant_id)
  select m.user_id, p_title, p_body, p_type, p_tenant_id
  from public.tenant_memberships m
  where m.tenant_id = p_tenant_id
    and m.status = 'active'
    and coalesce(
      (select (np.prefs ->> p_type)::boolean
       from public.notification_preferences np
       where np.user_id = m.user_id),
      true
    );
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;
