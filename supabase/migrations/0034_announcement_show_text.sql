-- Part 16: optional "show text on banner" flag for announcements.
-- Safe to run more than once.
alter table public.announcements add column if not exists show_text boolean not null default false;
