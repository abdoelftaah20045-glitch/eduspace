-- EduSpace: drop the pre-tenancy broadcast overload.
-- Run AFTER 0022_notification_triggers.sql.
--
-- 0017 added a 4-parameter tenant-scoped admin_broadcast_notification, but
-- CREATE OR REPLACE does not remove the old 3-parameter function: it kept
-- existing as a separate overload that fans out to EVERY profile across
-- all tenants. The app calls the 4-parameter version; drop the old one.

drop function if exists public.admin_broadcast_notification(text, text, text);
