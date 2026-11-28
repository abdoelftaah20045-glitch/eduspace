-- Part 46b: OPTIONAL. Run ONLY after part46a and after you agree with the numbers.
-- Moves published books that fail the strict rule back to status 'review' (hidden from students, visible to
-- admins, reversible: nothing is deleted, links and attribution stay). Requires part46a's function.
-- To undo, set status back to 'published' on the books you approve in the admin Books screen.
update public.library_items
   set status = 'review'
 where kind = 'book' and status = 'published'
   and not public._rights_ok(license, rights_url);
select count(*) as moved_to_review from public.library_items where kind = 'book' and status = 'review';
