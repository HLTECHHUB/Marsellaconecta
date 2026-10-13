-- Phone (SMS code) sign-in. Phone users have no email, so the profile gets a placeholder address
-- (tel503XXXXXXXX@phone.conectamarsella.local) and the phone number as WhatsApp/contact number.
-- Also links an existing neighbor profile that was registered with the same phone number.
create or replace function public.handle_new_user()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb); v_nombre text; v_apellido text;
        v_email text := nullif(new.email, ''); v_digits text := regexp_replace(coalesce(new.phone, ''), '\D', '', 'g');
        v_local text;
begin
  v_local := right(v_digits, 8);
  if v_email is not null then
    update public.profiles set auth_user_id = new.id, migrated = false
     where lower(email) = lower(v_email) and auth_user_id is null;
  elsif v_local <> '' then
    update public.profiles set auth_user_id = new.id, migrated = false
     where right(regexp_replace(coalesce(whatsapp, ''), '\D', '', 'g'), 8) = v_local and auth_user_id is null
       and id = (select id from public.profiles where right(regexp_replace(coalesce(whatsapp, ''), '\D', '', 'g'), 8) = v_local and auth_user_id is null order by created_at limit 1);
  end if;
  if not found then
    v_nombre   := coalesce(nullif(m->>'nombre',''), nullif(m->>'given_name',''), split_part(coalesce(m->>'full_name', m->>'name', ''), ' ', 1), '');
    v_apellido := coalesce(nullif(m->>'apellido',''), nullif(m->>'family_name',''), nullif(btrim(substr(coalesce(m->>'full_name', m->>'name', ''), length(split_part(coalesce(m->>'full_name', m->>'name', ''), ' ', 1)) + 1)), ''), '');
    insert into public.profiles (auth_user_id, email, nombre, apellido, whatsapp, quartier, zona, source)
    values (new.id, coalesce(v_email, 'tel' || v_digits || '@phone.conectamarsella.local'), v_nombre, v_apellido,
      coalesce(nullif(m->>'whatsapp',''), v_local, ''), coalesce(m->>'quartier',''), coalesce(m->>'zona',''),
      coalesce(nullif(m->>'source',''), case when new.raw_app_meta_data->>'provider' = 'google' then 'google' when v_email is null then 'telefono' else '' end));
  end if;
  return new;
end;
$function$;
