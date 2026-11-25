-- EduSpace: let admins update other users' profiles (account status review).
-- The guard trigger still prevents non-admins from changing status fields.
-- Run AFTER 0006_notifications_prefs_broadcast.sql.

drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles
  for update using (public.is_admin());
