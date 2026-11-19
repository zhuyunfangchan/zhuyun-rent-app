-- Run this once in the Supabase SQL Editor for the project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'tenant' check (role in ('tenant', 'operator')),
  created_at timestamptz not null default now()
);

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 140),
  district text not null,
  price numeric(10,2) not null check (price > 0),
  rooms smallint not null check (rooms > 0),
  bathrooms smallint not null default 1 check (bathrooms > 0),
  area_sqm numeric(8,2) not null check (area_sqm > 0),
  rental_type text not null check (rental_type in ('整租', '合租')),
  fees_included jsonb not null default '{"water":false,"electricity":false,"internet":false,"property":false}'::jsonb,
  address text not null,
  contact_info varchar(200),
  move_in_info varchar(100) not null default '可协商',
  tag text not null default '华西找房',
  image_urls text[] not null default '{}',
  description text not null default '',
  status text not null default 'draft' check (status in ('draft', 'published', 'unlisted')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listings(id) on delete set null,
  listing_title_snapshot text not null,
  tenant_name text not null check (char_length(tenant_name) between 1 and 100),
  contact text not null check (char_length(contact) between 3 and 200),
  contact_method text not null check (contact_method in ('whatsapp', 'phone', 'wechat', 'email')),
  message text not null check (char_length(message) between 5 and 3000),
  privacy_consent boolean not null default false check (privacy_consent),
  status text not null default 'new' check (status in ('new', 'contacted', 'closed')),
  created_at timestamptz not null default now()
);

create index if not exists listings_public_search_idx on public.listings(status, district, price, rooms);
create index if not exists inquiries_created_at_idx on public.inquiries(created_at desc);

create or replace function public.is_operator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'operator'
  );
$$;
revoke all on function public.is_operator() from public;
grant execute on function public.is_operator() to anon, authenticated;

alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.inquiries enable row level security;

revoke all on public.profiles, public.listings, public.inquiries from anon, authenticated;
grant select on public.profiles to authenticated;
grant select on public.listings to anon, authenticated;
grant insert, update, delete on public.listings to authenticated;
grant insert on public.inquiries to anon, authenticated;
grant select, update on public.inquiries to authenticated;

drop policy if exists "profile owner can read own role" on public.profiles;
create policy "profile owner can read own role" on public.profiles
  for select to authenticated using (id = (select auth.uid()));

drop policy if exists "public can read published listings" on public.listings;
create policy "public can read published listings" on public.listings
  for select to anon, authenticated using (status = 'published' or public.is_operator());
drop policy if exists "operators can create listings" on public.listings;
create policy "operators can create listings" on public.listings
  for insert to authenticated with check (public.is_operator() and created_by = (select auth.uid()));
drop policy if exists "operators can update listings" on public.listings;
create policy "operators can update listings" on public.listings
  for update to authenticated using (public.is_operator()) with check (public.is_operator());
drop policy if exists "operators can delete listings" on public.listings;
create policy "operators can delete listings" on public.listings
  for delete to authenticated using (public.is_operator());

drop policy if exists "visitors can submit inquiries for published listings" on public.inquiries;
create policy "visitors can submit inquiries for published listings" on public.inquiries
  for insert to anon, authenticated with check (
    exists (select 1 from public.listings l where l.id = listing_id and l.status = 'published')
  );
drop policy if exists "operators can read inquiries" on public.inquiries;
create policy "operators can read inquiries" on public.inquiries
  for select to authenticated using (public.is_operator());
drop policy if exists "operators can update inquiry status" on public.inquiries;
create policy "operators can update inquiry status" on public.inquiries
  for update to authenticated using (public.is_operator()) with check (public.is_operator());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('property-images', 'property-images', true, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "public can view listing photos" on storage.objects;
create policy "public can view listing photos" on storage.objects
  for select to anon, authenticated using (bucket_id = 'property-images');
drop policy if exists "operators can upload listing photos" on storage.objects;
create policy "operators can upload listing photos" on storage.objects
  for insert to authenticated with check (bucket_id = 'property-images' and public.is_operator());
drop policy if exists "operators can update listing photos" on storage.objects;
create policy "operators can update listing photos" on storage.objects
  for update to authenticated using (bucket_id = 'property-images' and public.is_operator())
  with check (bucket_id = 'property-images' and public.is_operator());
drop policy if exists "operators can remove listing photos" on storage.objects;
create policy "operators can remove listing photos" on storage.objects
  for delete to authenticated using (bucket_id = 'property-images' and public.is_operator());
