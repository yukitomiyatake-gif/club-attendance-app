-- Run this after the base members / attendance_records tables exist.
-- This lets the browser app use the anon key safely without Supabase Auth.

create extension if not exists pgcrypto with schema extensions;

alter table public.members
add column if not exists password_hash text;

create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 初回だけ使います。まずこの関数で管理者を作り、その後は同じ名前では作れません。
-- 例:
-- select public.bootstrap_admin('admin', 'ここに自分だけが知っているパスワード');
create or replace function public.bootstrap_admin(
  admin_name text,
  plain_password text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text;
  new_id uuid;
begin
  clean_name := btrim(coalesce(admin_name, ''));

  if clean_name = '' or char_length(clean_name) > 40 then
    raise exception 'Admin name must be 1 to 40 characters';
  end if;

  if plain_password is null
    or char_length(plain_password) < 4
    or char_length(plain_password) > 72 then
    raise exception 'Admin password must be 4 to 72 characters';
  end if;

  if exists (select 1 from public.admins) then
    raise exception 'Admin already exists';
  end if;

  insert into public.admins (name, password_hash)
  values (
    clean_name,
    extensions.crypt(plain_password, extensions.gen_salt('bf'))
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.verify_admin_password(
  admin_name text,
  plain_password text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text;
begin
  clean_name := btrim(coalesce(admin_name, ''));

  if clean_name = ''
    or char_length(clean_name) > 40
    or plain_password is null
    or char_length(plain_password) < 4
    or char_length(plain_password) > 72 then
    return false;
  end if;

  return exists (
    select 1
    from public.admins
    where admins.name = clean_name
      and password_hash = extensions.crypt(plain_password, password_hash)
  );
end;
$$;

create or replace function public.admin_create_member_with_password(
  admin_name text,
  admin_password text,
  member_name text,
  member_password text
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
  if not public.verify_admin_password(admin_name, admin_password) then
    raise exception 'Invalid admin name or password';
  end if;

  clean_name := btrim(coalesce(member_name, ''));

  if clean_name = '' or char_length(clean_name) > 40 then
    raise exception 'Name must be 1 to 40 characters';
  end if;

  if member_password is null
    or char_length(member_password) < 4
    or char_length(member_password) > 72 then
    raise exception 'Password must be 4 to 72 characters';
  end if;

  select coalesce(max(sort_order), 0) + 1
  into next_order
  from public.members;

  insert into public.members (name, password_hash, sort_order)
  values (
    clean_name,
    extensions.crypt(member_password, extensions.gen_salt('bf')),
    next_order
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.admin_delete_member(
  admin_name text,
  admin_password text,
  target_member_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.verify_admin_password(admin_name, admin_password) then
    raise exception 'Invalid admin name or password';
  end if;

  if target_member_id is null then
    raise exception 'Target member is required';
  end if;

  delete from public.attendance_records
  where member_id = target_member_id;

  delete from public.members
  where id = target_member_id;
end;
$$;

create or replace function public.admin_move_member(
  admin_name text,
  admin_password text,
  target_member_id uuid,
  move_direction integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_order integer;
  other_id uuid;
  other_order integer;
begin
  if not public.verify_admin_password(admin_name, admin_password) then
    raise exception 'Invalid admin name or password';
  end if;

  if move_direction not in (-1, 1) then
    raise exception 'Move direction must be -1 or 1';
  end if;

  select sort_order
  into current_order
  from public.members
  where id = target_member_id;

  if current_order is null then
    raise exception 'Target member not found';
  end if;

  if move_direction < 0 then
    select id, sort_order
    into other_id, other_order
    from public.members
    where sort_order < current_order
    order by sort_order desc
    limit 1;
  else
    select id, sort_order
    into other_id, other_order
    from public.members
    where sort_order > current_order
    order by sort_order asc
    limit 1;
  end if;

  if other_id is null then
    return;
  end if;

  update public.members
  set sort_order = other_order,
      updated_at = now()
  where id = target_member_id;

  update public.members
  set sort_order = current_order,
      updated_at = now()
  where id = other_id;
end;
$$;

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
alter table public.admins enable row level security;

drop policy if exists "anon can read public members" on public.members;
revoke all on table public.members from anon;
revoke all on table public.members from authenticated;
revoke all on table public.admins from anon;
revoke all on table public.admins from authenticated;

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

revoke execute on function public.create_member_with_password(text, text) from anon;
revoke execute on function public.create_member_with_password(text, text) from public;
grant execute on function public.verify_member_password(text, text) to anon;
grant execute on function public.save_member_attendance(text, text, date, text, text) to anon;
grant execute on function public.bootstrap_admin(text, text) to anon;
grant execute on function public.verify_admin_password(text, text) to anon;
grant execute on function public.admin_create_member_with_password(text, text, text, text) to anon;
grant execute on function public.admin_delete_member(text, text, uuid) to anon;
grant execute on function public.admin_move_member(text, text, uuid, integer) to anon;

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
