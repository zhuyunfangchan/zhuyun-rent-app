-- Add the optional public contact field to an existing Supabase project.
alter table public.listings add column if not exists contact_info varchar(200);
