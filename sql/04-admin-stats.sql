-- ============================================================
-- Marsella Conecta — Admin stats add-on
-- Run this once, in Supabase Studio SQL Editor, AFTER
-- admin-schema.sql. Just adds one policy: admins can read the
-- events_log table (searches, logins, business clicks, etc.)
-- to power the new Estadísticas tab in admin.html.
-- ============================================================

create policy "events_log_select_admin"
  on public.events_log for select
  using (public.is_admin());
