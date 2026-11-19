-- Add editable move-in information and allow WeChat as a tenant contact method.
alter table public.listings
  add column if not exists move_in_info varchar(100) not null default '可协商';

alter table public.inquiries
  drop constraint if exists inquiries_contact_method_check;

alter table public.inquiries
  add constraint inquiries_contact_method_check
  check (contact_method in ('whatsapp', 'phone', 'wechat', 'email'));
