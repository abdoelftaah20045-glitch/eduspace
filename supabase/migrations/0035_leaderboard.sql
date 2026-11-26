-- Part 17: leaderboard (points per student in an organization).
-- Points = 10 per completed lesson + best score percent per exam.
-- security definer so students can see ranks without reading other
-- students' private rows; only name, avatar and points are returned and
-- only to active members of that organization. Safe to run more than once.
create or replace function public.leaderboard_top(p_tenant uuid, p_limit int default 30)
returns table (user_id uuid, full_name text, avatar_url text, points int,
               lessons_done int, exams_taken int)
language sql stable security definer set search_path = public as $$
  with allowed as (
    select 1 where public.is_tenant_member(p_tenant) or public.is_tenant_admin(p_tenant)
  ),
  members as (
    select m.user_id from public.tenant_memberships m
    where m.tenant_id = p_tenant and m.status = 'active'
      and exists (select 1 from allowed)
  ),
  les as (
    select lp.user_id, count(*)::int as n
    from public.lesson_progress lp
    join public.lessons l on l.id = lp.lesson_id
    join public.courses c on c.id = l.course_id
    where lp.completed and c.tenant_id = p_tenant
    group by lp.user_id
  ),
  best as (
    select a.user_id, a.exam_id,
           max(case when a.max_score > 0 then a.score / a.max_score * 100 else 0 end) as pct
    from public.exam_attempts a
    join public.exams e on e.id = a.exam_id
    where a.status in ('submitted','graded') and e.tenant_id = p_tenant
    group by a.user_id, a.exam_id
  ),
  ex as (
    select user_id, count(*)::int as n, coalesce(sum(pct), 0)::int as pts
    from best group by user_id
  )
  select p.id, coalesce(nullif(p.full_name, ''), split_part(p.email, '@', 1)),
         p.avatar_url,
         coalesce(les.n, 0) * 10 + coalesce(ex.pts, 0),
         coalesce(les.n, 0), coalesce(ex.n, 0)
  from members mb
  join public.profiles p on p.id = mb.user_id
  left join les on les.user_id = p.id
  left join ex on ex.user_id = p.id
  order by 4 desc, 1
  limit greatest(1, least(p_limit, 100));
$$;
grant execute on function public.leaderboard_top(uuid, int) to authenticated;
