-- Part 33: fix garbled text (&#1601; style codes) in imported data,
-- and add the teacher picture column. Safe to run more than once.

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

update public.courses set
  title = public._decode_html(title),
  description = public._decode_html(description),
  field = public._decode_html(field),
  instructor_name = public._decode_html(instructor_name)
where title like '%&%' or description like '%&%' or field like '%&%' or instructor_name like '%&%';

update public.course_sections set title = public._decode_html(title)
where title like '%&%';

update public.lessons set
  title = public._decode_html(title),
  content = public._decode_html(content)
where title like '%&%' or content like '%&%';

do $$
declare c record;
begin
  for c in select id, name from public.categories where name like '%&%' loop
    begin
      update public.categories set name = public._decode_html(c.name) where id = c.id;
    exception when others then
      null; -- a decoded name that already exists is left as it is
    end;
  end loop;
end $$;

-- Teacher picture: copy it to every course of the same teacher
-- once at least one course of that teacher has it.
update public.courses c set instructor_photo_url = p.url
from (
  select tenant_id, instructor_name, max(instructor_photo_url) as url
  from public.courses
  where coalesce(instructor_photo_url, '') <> ''
  group by tenant_id, instructor_name
) p
where c.tenant_id = p.tenant_id and c.instructor_name = p.instructor_name
  and coalesce(c.instructor_photo_url, '') = '';
