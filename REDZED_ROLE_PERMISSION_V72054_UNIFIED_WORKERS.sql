-- REDZED ROLE & PERMISSION V720.54 / UPM V8.4
-- Owner/Admin unified worker directory management.
-- Requires V8.3 unified worker directory SQL to be installed first.
begin;

create or replace function public.rr_owner_worker_directory_v8_4(
  p_department_code text default null,
  p_include_inactive boolean default true
) returns table(
  worker_id uuid, worker_code text, worker_name text, department_code text,
  role_code text, is_active boolean, access_status text, worker_source text,
  linked_auth_user_id uuid, mobile text, created_at timestamptz
)
language plpgsql security definer set search_path=public as $$
declare v_role text;
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if coalesce(v_role,'') not in ('owner','admin') then
    raise exception 'Owner/Admin permission required.';
  end if;
  return query
  select u.worker_id,u.worker_code,u.worker_name,u.department_code,u.role_code,
         u.is_active,u.access_status,u.source,u.linked_auth_user_id,
         w.mobile,coalesce(w.created_at,p.created_at)
  from public.rr_worker_directory_unified_v1 u
  left join public.rr_worker_directory_v1 w on w.id=u.worker_id and u.source<>'ROLE_DIRECTORY'
  left join public.rr_user_profiles p on p.auth_user_id=u.linked_auth_user_id and u.source='ROLE_DIRECTORY'
  where (nullif(trim(p_department_code),'') is null or lower(u.department_code)=lower(trim(p_department_code)))
    and (p_include_inactive or (coalesce(u.is_active,false) and upper(coalesce(u.access_status,'ACTIVE'))='ACTIVE'))
  order by u.worker_name,u.worker_code;
end;$$;
grant execute on function public.rr_owner_worker_directory_v8_4(text,boolean) to authenticated;

create or replace function public.rr_owner_add_worker_v8_4(
  p_worker_name text,p_department_code text,p_role_code text default 'worker',p_mobile text default null
) returns table(worker_id uuid,worker_code text,worker_name text,department_code text,role_code text,worker_source text)
language plpgsql security definer set search_path=public as $$
declare v_role text;
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if coalesce(v_role,'') not in ('owner','admin') then raise exception 'Owner/Admin permission required.'; end if;
  return query select * from public.rr_upm_add_worker_v8_3(p_worker_name,p_department_code,p_role_code,p_mobile);
end;$$;
grant execute on function public.rr_owner_add_worker_v8_4(text,text,text,text) to authenticated;

create or replace function public.rr_owner_set_worker_access_v8_4(
  p_worker_id uuid,p_action text,p_reason text default null
) returns public.rr_worker_directory_v1
language plpgsql security definer set search_path=public as $$
declare v_role text;v_out public.rr_worker_directory_v1;v_action text:=upper(trim(p_action));
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if coalesce(v_role,'') not in ('owner','admin') then raise exception 'Owner/Admin permission required.'; end if;
  if not exists(select 1 from public.rr_worker_directory_v1 where id=p_worker_id) then
    raise exception 'Role Directory login users must be controlled from Users & Access.';
  end if;
  update public.rr_worker_directory_v1 set
    is_active=case when v_action='ACTIVATE' then true when v_action in ('DEACTIVATE','BLOCK') then false else is_active end,
    access_status=case when v_action='ACTIVATE' then 'ACTIVE' when v_action='BLOCK' then 'BLOCKED' when v_action='DEACTIVATE' then 'INACTIVE' else access_status end,
    updated_at=now(),updated_by=auth.uid()
  where id=p_worker_id returning * into v_out;
  if v_action not in ('ACTIVATE','DEACTIVATE','BLOCK') then raise exception 'Invalid worker action.'; end if;
  return v_out;
end;$$;
grant execute on function public.rr_owner_set_worker_access_v8_4(uuid,text,text) to authenticated;

commit;
