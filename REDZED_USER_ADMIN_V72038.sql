-- REDZED USER ADMIN V720.38
-- Additive migration. Run in Supabase SQL Editor as postgres.

begin;

create extension if not exists pgcrypto;

alter table if exists public.rr_user_profiles
  add column if not exists email text,
  add column if not exists department_code text,
  add column if not exists access_status text not null default 'ACTIVE',
  add column if not exists access_version bigint not null default 1,
  add column if not exists access_reason text,
  add column if not exists access_changed_at timestamptz,
  add column if not exists access_changed_by uuid,
  add column if not exists last_sign_in_at timestamptz;

create index if not exists rr_user_profiles_auth_user_id_idx
  on public.rr_user_profiles(auth_user_id);

create index if not exists rr_user_profiles_email_idx
  on public.rr_user_profiles(lower(email));

create table if not exists public.rr_user_admin_audit_v1 (
  id uuid primary key default gen_random_uuid(),
  actor_auth_user_id uuid not null default auth.uid(),
  target_profile_id uuid,
  target_auth_user_id uuid,
  action_code text not null,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.rr_user_admin_audit_v1 enable row level security;

drop policy if exists rr_user_admin_audit_owner_admin_select on public.rr_user_admin_audit_v1;
create policy rr_user_admin_audit_owner_admin_select
on public.rr_user_admin_audit_v1
for select
to authenticated
using (lower(coalesce(public.rr_current_role(),'')) in ('owner','admin'));

-- Writes are made by SECURITY DEFINER RPC or service-role Edge Function.
revoke insert, update, delete on public.rr_user_admin_audit_v1 from anon, authenticated;
grant select on public.rr_user_admin_audit_v1 to authenticated;

create or replace function public.rr_owner_set_user_access_v1(
  p_profile_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(coalesce(public.rr_current_role(),''));
  v_action text := upper(trim(coalesce(p_action,'')));
  v_status text;
  v_active boolean;
  v_row public.rr_user_profiles%rowtype;
begin
  if v_role not in ('owner','admin') then
    raise exception 'Owner/Admin access required.';
  end if;

  if p_profile_id is null then
    raise exception 'Profile ID is required.';
  end if;

  if coalesce(trim(p_reason),'') = '' then
    raise exception 'Reason is required.';
  end if;

  select * into v_row
  from public.rr_user_profiles
  where id = p_profile_id
  for update;

  if not found then raise exception 'User profile not found.'; end if;

  if v_row.auth_user_id = auth.uid() and v_action in ('TEMP_BLOCK','DEACTIVATE','ARCHIVE') then
    raise exception 'You cannot block, deactivate or archive your own login.';
  end if;

  case v_action
    when 'ACTIVATE' then v_status := 'ACTIVE'; v_active := true;
    when 'TEMP_BLOCK' then v_status := 'TEMP_BLOCKED'; v_active := false;
    when 'DEACTIVATE' then v_status := 'INACTIVE'; v_active := false;
    when 'ARCHIVE' then v_status := 'ARCHIVED'; v_active := false;
    else raise exception 'Invalid access action: %', v_action;
  end case;

  update public.rr_user_profiles
  set is_active = v_active,
      access_status = v_status,
      access_reason = p_reason,
      access_version = coalesce(access_version,0) + 1,
      access_changed_at = now(),
      access_changed_by = auth.uid()
  where id = p_profile_id
  returning * into v_row;

  insert into public.rr_user_admin_audit_v1(
    target_profile_id,target_auth_user_id,action_code,reason,details
  ) values (
    v_row.id,v_row.auth_user_id,v_action,p_reason,
    jsonb_build_object('status',v_status,'is_active',v_active)
  );

  return jsonb_build_object(
    'ok',true,
    'profile_id',v_row.id,
    'auth_user_id',v_row.auth_user_id,
    'status',v_status,
    'is_active',v_active,
    'access_version',v_row.access_version
  );
end;
$$;

grant execute on function public.rr_owner_set_user_access_v1(uuid,text,text) to authenticated;

-- Simple access check usable by app pages.
create or replace function public.rr_assert_active_user_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare v_profile public.rr_user_profiles%rowtype;
begin
  select * into v_profile
  from public.rr_user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if not found then raise exception 'ERP user profile is missing.'; end if;
  if not coalesce(v_profile.is_active,false)
     or upper(coalesce(v_profile.access_status,'ACTIVE')) <> 'ACTIVE' then
    raise exception 'ERP access is blocked.';
  end if;

  return jsonb_build_object(
    'profile_id',v_profile.id,
    'role_code',v_profile.role_code,
    'department_code',v_profile.department_code,
    'access_status',v_profile.access_status,
    'access_version',v_profile.access_version
  );
end;
$$;

grant execute on function public.rr_assert_active_user_v1() to authenticated;

commit;
