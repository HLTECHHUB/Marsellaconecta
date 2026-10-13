-- ============================================================
-- Marsella Conecta — Business claim add-on
-- Run this once, in Supabase Studio SQL Editor, AFTER
-- supabase-schema.sql and admin-schema.sql.
--
-- Lets a logged-in neighbor "claim" a business listing by
-- confirming the email address that was entered when the
-- business was originally registered — without ever exposing
-- that private email to the browser. The check happens entirely
-- inside this function on the database side.
-- ============================================================

create or replace function public.claim_business(p_business_id uuid, p_claim_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_match boolean;
begin
  select id into v_profile_id from public.profiles where auth_user_id = auth.uid();
  if v_profile_id is null then
    raise exception 'No se encontró un perfil de vecino para esta cuenta. Crea tu cuenta de vecino primero.';
  end if;

  select exists (
    select 1 from public.business_private
    where business_id = p_business_id
      and lower(email) = lower(trim(p_claim_email))
  ) into v_match;

  if not v_match then
    return false;
  end if;

  update public.businesses
     set owner_profile_id = v_profile_id
   where id = p_business_id
     and owner_profile_id is null;

  return found;
end;
$$;

grant execute on function public.claim_business(uuid, text) to authenticated;
