-- Extra analytics columns: anonymous visitor id, category and page.
alter table public.events_log add column if not exists session_id text, add column if not exists categoria text, add column if not exists pagina text;
create index if not exists events_log_created_idx on public.events_log (created_at desc);
create index if not exists events_log_profile_idx on public.events_log (profile_id, created_at desc);
