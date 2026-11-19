-- Run once in Supabase SQL Editor to enable tenant profile avatars.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 3145728,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "users can upload own avatars" on storage.objects;
create policy "users can upload own avatars" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "users can update own avatars" on storage.objects;
create policy "users can update own avatars" on storage.objects
  for update to authenticated using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
  ) with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists "users can remove own avatars" on storage.objects;
create policy "users can remove own avatars" on storage.objects
  for delete to authenticated using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
  );
