-- Part 35: clean &#1606; style codes from ALL text in the app data
-- (courses, categories, levels, assignments, subscription plans, imports,
-- lessons, exams, library, announcements ...). Also fixes double-encoded
-- text (&amp;#1606;) and codes missing the ending ;  Safe to run again.

create or replace function public._decode_html(t text) returns text
language plpgsql immutable as $$
declare
  r text := t; prev text; m text[]; i int := 0;
begin
  if r is null or position('&' in r) = 0 then return r; end if;
  loop
    prev := r;
    r := replace(r, '&amp;', '&');
    -- numeric, with or without the ending ;
    loop
      m := regexp_match(r, '&#([0-9]{1,7});?');
      exit when m is null;
      r := regexp_replace(r, '&#' || m[1] || ';?',
             case when m[1]::int between 1 and 1114111 and m[1]::int not between 55296 and 57343
                  then chr(m[1]::int) else '' end);
    end loop;
    -- hex
    loop
      m := regexp_match(r, '&#[xX]([0-9a-fA-F]{1,6});?');
      exit when m is null;
      r := regexp_replace(r, '&#[xX]' || m[1] || ';?',
             case when ('x' || lpad(m[1], 8, '0'))::bit(32)::int between 1 and 1114111
                       and ('x' || lpad(m[1], 8, '0'))::bit(32)::int not between 55296 and 57343
                  then chr(('x' || lpad(m[1], 8, '0'))::bit(32)::int) else '' end);
    end loop;
    r := replace(r, '&lt;', '<');
    r := replace(r, '&gt;', '>');
    r := replace(r, '&quot;', '"');
    r := replace(r, '&apos;', '''');
    r := replace(r, '&nbsp;', ' ');
    i := i + 1;
    exit when r = prev or i >= 6;
  end loop;
  return r;
end $$;

-- Every text column of every table in the app, row by row.
-- A row whose decoded text would clash with another one (same name)
-- is simply left as it is.
do $$
declare c record; rw record; fixed int := 0;
begin
  for c in
    select table_name, column_name
    from information_schema.columns
    where table_schema = 'public'
      and data_type in ('text', 'character varying')
      and table_name in (select table_name from information_schema.tables
                         where table_schema = 'public' and table_type = 'BASE TABLE')
      and table_name not in ('push_tokens', 'audit_log', 'admin_activity_logs',
                             'translations', 'translation_keys')
      and column_name not in ('email', 'password', 'token', 'url', 'video_url',
                              'cover_url', 'logo_url', 'avatar_url', 'instructor_photo_url')
  loop
    for rw in execute format(
      'select ctid as rid, %I as v from public.%I where %I like %L',
      c.column_name, c.table_name, c.column_name, '%&%')
    loop
      begin
        execute format('update public.%I set %I = $1 where ctid = $2',
                       c.table_name, c.column_name)
          using public._decode_html(rw.v), rw.rid;
        fixed := fixed + 1;
      exception when others then
        null;
      end;
    end loop;
  end loop;
  raise notice 'fixed % values', fixed;
end $$;

-- tags / levels stored in arrays or json (if any)
do $$
begin
  begin
    update public.courses set tags = (
      select array_agg(public._decode_html(x)) from unnest(tags) x)
    where exists (select 1 from unnest(tags) x where x like '%&%');
  exception when others then null;
  end;
end $$;
