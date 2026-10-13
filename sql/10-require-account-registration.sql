-- Businesses are registered by signed-in neighbors, who become the owner.
-- (Policies keep their original names; they now apply to signed-in users only.)
alter policy "businesses_insert_public" on public.businesses to authenticated
  with check (owner_profile_id in (select id from public.profiles where auth_user_id = auth.uid()));
alter policy "business_private_insert_public" on public.business_private to authenticated
  with check (exists (select 1 from public.businesses b join public.profiles p on p.id = b.owner_profile_id
                      where b.id = business_id and p.auth_user_id = auth.uid()));
alter policy "business_images_public_insert" on storage.objects to authenticated
  with check (bucket_id = 'business-images');
-- The claim flow was removed from the UI; revoke access to its function.
revoke execute on function public.claim_business(uuid, text) from authenticated;
