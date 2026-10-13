-- One-tap sign-in (Google): take the name from the provider when the sign-up form did not send one.
create or replace function public.handle_new_user()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb); v_nombre text; v_apellido text;
begin
  update public.profiles set auth_user_id = new.id, migrated = false
   where lower(email) = lower(new.email) and auth_user_id is null;
  if not found then
    v_nombre   := coalesce(nullif(m->>'nombre',''), nullif(m->>'given_name',''), split_part(coalesce(m->>'full_name', m->>'name', ''), ' ', 1), '');
    v_apellido := coalesce(nullif(m->>'apellido',''), nullif(m->>'family_name',''), nullif(btrim(substr(coalesce(m->>'full_name', m->>'name', ''), length(split_part(coalesce(m->>'full_name', m->>'name', ''), ' ', 1)) + 1)), ''), '');
    insert into public.profiles (auth_user_id, email, nombre, apellido, whatsapp, quartier, zona, source)
    values (new.id, new.email, v_nombre, v_apellido,
      coalesce(m->>'whatsapp',''), coalesce(m->>'quartier',''), coalesce(m->>'zona',''),
      coalesce(nullif(m->>'source',''), case when new.raw_app_meta_data->>'provider' = 'google' then 'google' else '' end));
  end if;
  return new;
end;
$function$;
