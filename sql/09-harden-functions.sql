revoke execute on function public.enforce_business_review_status() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.trigger_notify_new_business() from public, anon, authenticated;
revoke execute on function public.claim_business(uuid, text) from public, anon;
grant execute on function public.claim_business(uuid, text) to authenticated;
