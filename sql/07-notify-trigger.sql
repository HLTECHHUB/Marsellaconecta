-- ============================================================
-- Marsella Conecta — Notify webhook (SQL version)
-- Run this AFTER deploying the notify-new-business Edge Function
-- (see NOTIFY-SETUP.md steps 1-3 first — you still need Resend +
-- the function deployed + secrets set for this to actually send
-- an email). This step just wires up the trigger, replacing the
-- "Database > Webhooks" dashboard step if you can't find that UI.
-- ============================================================

create extension if not exists pg_net;

create or replace function public.trigger_notify_new_business()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://kydazssjktgsagayuupo.supabase.co/functions/v1/notify-new-business',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt5ZGF6c3Nqa3Rnc2FnYXl1dXBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4NTg2NTYsImV4cCI6MjEwMDQzNDY1Nn0.YPXJ2cJjTcKZDPTo2o6Wkhs3-9CGZISujsPvAwKWpx4'
    ),
    body := jsonb_build_object('record', to_jsonb(new))
  );
  return new;
end;
$$;

create trigger on_business_created_notify
  after insert on public.businesses
  for each row execute function public.trigger_notify_new_business();

-- ------------------------------------------------------------
-- To test: submit a business through register.html, then check:
--   select * from net._http_response order by created desc limit 5;
-- status_code 200 means it worked. Anything else (or no rows)
-- means the function call itself failed — check Edge Functions >
-- notify-new-business > Logs in Studio for the actual error.
-- ------------------------------------------------------------
