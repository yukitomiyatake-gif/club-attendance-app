-- Run this after the base members / attendance_records tables exist.
-- This lets the browser app use the anon key safely without Supabase Auth.

create extension if not exists pgcrypto with schema extensions;

alter table public.members
add column if not exists password_hash text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'members_name_unique'
  ) then
    alter table public.members
    add constraint members_name_unique unique (name);
  end if;
end $$;

create or replace view public.members_public as
select
  id,
  name,
  sort_order,
  created_at,
  updated_at
from public.members;

create or replace function public.create_member_with_password(
  member_name text,
  plain_password text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  next_order integer;
  clean_name text;
begin
  clean_name := btrim(coalesce(member_name, ''));

  if clean_name = '' or char_length(clean_name) > 40 then
    raise exception 'Name must be 1 to 40 characters';
  end if;

  if plain_password is null
    or char_length(plain_password) < 4
    or char_length(plain_password) > 72 then
    raise exception 'Password must be 4 to 72 characters';
  end if;

  select coalesce(max(sort_order), 0) + 1
  into next_order
  from public.members;

  insert into public.members (name, password_hash, sort_order)
  values (
    clean_name,
    extensions.crypt(plain_password, extensions.gen_salt('bf')),
    next_order
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.verify_member_password(
  member_name text,
  plain_password text
)
returns table (
  member_id uuid,
  name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text;
begin
  clean_name := btrim(coalesce(member_name, ''));

  if clean_name = ''
    or char_length(clean_name) > 40
    or plain_password is null
    or char_length(plain_password) < 4
    or char_length(plain_password) > 72 then
    return;
  end if;

  return query
  select members.id, members.name
  from public.members
  where members.name = clean_name
    and password_hash = extensions.crypt(plain_password, password_hash);
end;
$$;

create or replace function public.save_member_attendance(
  member_name text,
  plain_password text,
  record_date date,
  record_status text,
  record_reason text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_member_id uuid;
  clean_name text;
  clean_reason text;
begin
  clean_name := btrim(coalesce(member_name, ''));
  clean_reason := btrim(coalesce(record_reason, ''));

  if clean_name = '' or char_length(clean_name) > 40 then
    raise exception 'Name must be 1 to 40 characters';
  end if;

  if plain_password is null
    or char_length(plain_password) < 4
    or char_length(plain_password) > 72 then
    raise exception 'Password must be 4 to 72 characters';
  end if;

  if char_length(clean_reason) > 200 then
    raise exception 'Reason must be 200 characters or fewer';
  end if;

  if record_status not in ('present', 'late', 'absent') then
    raise exception 'Invalid attendance status';
  end if;

  if record_date is null then
    raise exception 'Record date is required';
  end if;

  select id
  into target_member_id
  from public.members
  where members.name = clean_name
    and password_hash = extensions.crypt(plain_password, password_hash);

  if target_member_id is null then
    raise exception 'Invalid member name or password';
  end if;

  insert into public.attendance_records (
    member_id,
    date,
    status,
    reason
  )
  values (
    target_member_id,
    record_date,
    record_status,
    clean_reason
  )
  on conflict (member_id, date)
  do update set
    status = excluded.status,
    reason = excluded.reason,
    updated_at = now();
end;
$$;

alter table public.members enable row level security;
alter table public.attendance_records enable row level security;

drop policy if exists "anon can read public members" on public.members;
revoke all on table public.members from anon;
revoke all on table public.members from authenticated;

drop policy if exists "anon can read attendance records" on public.attendance_records;
create policy "anon can read attendance records"
on public.attendance_records
for select
to anon
using (true);

revoke insert, update, delete on table public.attendance_records from anon;
revoke insert, update, delete on table public.attendance_records from authenticated;

grant select on public.members_public to anon;
grant select on public.attendance_records to anon;

grant execute on function public.create_member_with_password(text, text) to anon;
grant execute on function public.verify_member_password(text, text) to anon;
grant execute on function public.save_member_attendance(text, text, date, text, text) to anon;

do $$
begin
  if exists (
    select 1
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname = 'set_member_password'
      and pg_get_function_identity_arguments(pg_proc.oid) = 'member_name text, plain_password text'
  ) then
    revoke execute on function public.set_member_password(text, text) from anon;
  end if;
end $$;
