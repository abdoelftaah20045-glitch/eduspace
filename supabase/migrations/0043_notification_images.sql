-- Part 34: notifications carry a picture (course cover, else the teacher's
-- picture, else the organization's picture). Safe to run more than once.
-- Run it after part 33 (it also works if part 33 was not run).

alter table public.courses add column if not exists instructor_photo_url text;

create or replace function public._decode_html(t text) returns text
language plpgsql immutable as $$
declare
  r text := t;
  prev text;
  m text[];
  i int := 0;
begin
  if r is null or position('&' in r) = 0 then return r; end if;
  loop
    prev := r;
    -- numeric: &#1601;
    while r ~ '&#[0-9]{1,7};' loop
      m := regexp_match(r, '&#([0-9]{1,7});');
      r := replace(r, '&#' || m[1] || ';', chr(m[1]::int));
    end loop;
    -- hex: &#x641;
    while r ~* '&#x[0-9a-f]{1,6};' loop
      m := regexp_match(r, '&#[xX]([0-9a-fA-F]{1,6});');
      r := replace(replace(r, '&#x' || m[1] || ';', chr(('x' || lpad(m[1], 8, '0'))::bit(32)::int)),
                   '&#X' || m[1] || ';', chr(('x' || lpad(m[1], 8, '0'))::bit(32)::int));
    end loop;
    r := replace(r, '&lt;', '<');
    r := replace(r, '&gt;', '>');
    r := replace(r, '&quot;', '"');
    r := replace(r, '&apos;', '''');
    r := replace(r, '&nbsp;', ' ');
    r := replace(r, '&amp;', '&');
    i := i + 1;
    exit when r = prev or i >= 6;
  end loop;
  return r;
end $$;

create or replace function public.notify_new_course()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  img text;
  org_logo text;
begin
  if new.status = 'published'
     and coalesce(new.notify_on_publish, false)
     and new.notified_at is null
     and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    new.notified_at := now();
    select setting_value ->> 'logo_url' into org_logo
      from public.tenant_settings
     where tenant_id = new.tenant_id and setting_key = 'branding';
    img := coalesce(nullif(new.cover_url, ''), nullif(new.instructor_photo_url, ''),
                    nullif(org_logo, ''));
    insert into public.notifications (user_id, title, body, type, data, tenant_id)
    select m.user_id, 'كورس جديد / New course',
           'تم إضافة كورس ' || coalesce(public._decode_html(new.title), '') ||
           case when coalesce(new.instructor_name, '') <> ''
                then ' للمدرس ' || public._decode_html(new.instructor_name)
                else '' end,
           'new_course',
           jsonb_build_object('course_id', new.id) ||
             case when img is not null then jsonb_build_object('images', jsonb_build_array(img))
                  else '{}'::jsonb end,
           new.tenant_id
      from public.tenant_memberships m
     where m.tenant_id = new.tenant_id and m.status = 'active';
  end if;
  return new;
end;
$$;
