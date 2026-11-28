-- Part 46a: READ-ONLY audit of the library rights gate. Changes nothing.
-- Shows, per source, how many published books would NOT pass the strict rule
-- (allowed: CC0, CC BY, CC BY-SA, public domain; everything else = review).
create or replace function public._rights_ok(p_license text, p_url text)
returns boolean language plpgsql immutable as $$
declare t text := lower(regexp_replace(coalesce(p_license, ''), '\s+', ' ', 'g')); u text := lower(coalesce(p_url, ''));
begin
  if u ~ 'creativecommons\.org/publicdomain/(zero|mark)/' then return true; end if;
  if u ~ 'creativecommons\.org/licenses/by(-sa)?/' then return true; end if;
  if u ~ 'creativecommons\.org/' then return false; end if;
  if t ~ 'creativecommons\.org/publicdomain/(zero|mark)/' or t ~ 'creativecommons\.org/licenses/by(-sa)?/' then return true; end if;
  if t = '' or t ~ 'non ?-?commercial|no ?-?deriv|\mnc\M|\mnd\M|by-nc|by-nd|all rights|unknown|review|licen[cs]e per|verify|/|\mor\M' then return false; end if;
  return t ~ '^(cc0( 1\.0)?|public domain( \(cc0\))?|public domain mark( 1\.0)?)$'
      or t ~ '^cc[ -]by([ -]sa)?( [0-9.]+)?$'
      or t ~ '^creative commons attribution([ -]share ?alike)?( licen[cs]e)?( [0-9.]+)?$';
end $$;

-- 1) Per source: published books, and how many fail the strict rule.
select coalesce(source, '(none)') as source, status, count(*) as books,
       count(*) filter (where not public._rights_ok(license, rights_url)) as fail_strict
  from public.library_items
 where kind = 'book'
 group by 1, 2
 order by 1, 2;

-- 2) The most common licence texts among PUBLISHED books that fail.
select left(coalesce(license, ''), 90) as license, left(coalesce(rights_url, ''), 70) as rights_url, count(*) as books
  from public.library_items
 where kind = 'book' and status = 'published' and not public._rights_ok(license, rights_url)
 group by 1, 2 order by 3 desc limit 25;

-- 3) Is auto-publish on?
select tenant_id, auto_publish_open from public.book_import_settings;
