-- Run once in Supabase SQL Editor to enable operator invitations.
create table if not exists public.admin_invites (
  email text primary key check (email = lower(trim(email))),
  created_by uuid not null references auth.users(id),
  assigned_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.admin_invites enable row level security;
revoke all on public.admin_invites from anon, authenticated;
grant select, insert, delete on public.admin_invites to authenticated;
drop policy if exists "operators can view admin invites" on public.admin_invites;
create policy "operators can view admin invites" on public.admin_invites
 for select to authenticated using (public.is_operator());
drop policy if exists "operators can create admin invites" on public.admin_invites;
create policy "operators can create admin invites" on public.admin_invites
 for insert to authenticated with check (public.is_operator() and created_by = (select auth.uid()));
drop policy if exists "operators can remove admin invites" on public.admin_invites;
create policy "operators can remove admin invites" on public.admin_invites
 for delete to authenticated using (public.is_operator());

create or replace function public.assign_invited_operator()
returns trigger language plpgsql security definer set search_path = public
as $$
declare matched_invite public.admin_invites%rowtype;
begin
  if tg_op = 'UPDATE' and (old.email_confirmed_at is not null or new.email_confirmed_at is null) then
    return new;
  end if;
  select * into matched_invite from public.admin_invites where email = lower(trim(new.email));
  insert into public.profiles(id, role)
  values (new.id, case when matched_invite.email is not null and new.email_confirmed_at is not null then 'operator' else 'tenant' end)
  on conflict (id) do update set role = case
    when matched_invite.email is not null and new.email_confirmed_at is not null then 'operator'
    else public.profiles.role end;
  if matched_invite.email is not null and new.email_confirmed_at is not null then
    update public.admin_invites set assigned_user_id = new.id where email = matched_invite.email;
  end if;
  return new;
end;
$$;
revoke all on function public.assign_invited_operator() from public, anon, authenticated;
drop trigger if exists assign_invited_operator_after_signup on auth.users;
create trigger assign_invited_operator_after_signup
after insert or update on auth.users for each row execute function public.assign_invited_operator();

create or replace function public.demote_removed_admin_invite()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if old.assigned_user_id is not null then
    update public.profiles set role = 'tenant'
    where id = old.assigned_user_id and role = 'operator';
  end if;
  return old;
end;
$$;
revoke all on function public.demote_removed_admin_invite() from public, anon, authenticated;
drop trigger if exists demote_admin_after_invite_removed on public.admin_invites;
create trigger demote_admin_after_invite_removed
after delete on public.admin_invites for each row execute function public.demote_removed_admin_invite();
