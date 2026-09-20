-- TEST71 Checkpoint 1: canonical staff mapping and effective Act As authorization.

-- Keep historical rows for audit, but remove only the four reproduced accidental
-- cross-department skills.  Home departments and correct skills stay untouched.
update public.rr_worker_department_map_v1 m
set is_active=false,updated_at=now()
from public.rr_worker_directory_unified_v1 d
where d.worker_id=m.worker_id and m.is_active and (
  (lower(d.worker_name)='imamul' and lower(m.department_code)='sticker') or
  (lower(d.worker_name)='akhtar' and lower(m.department_code)='overlock') or
  (lower(d.worker_name)='sharwan' and lower(m.department_code)='packing') or
  (lower(d.worker_name)='singh ji' and lower(m.department_code)='press')
);

create or replace function public.rr_upm_assignment_allowed_v200()
returns boolean language sql stable security definer set search_path=''
as $$
  select public.rr_upm_effective_role_v200() in(
    'OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','LINE MAN',
    'CUTTING_MASTER','DEPARTMENT_HEAD'
  )
$$;

create or replace function public.rr_upm_add_worker_v8_3(
  p_worker_name text,p_department_code text,p_role_code text default 'worker',p_mobile text default null
)
returns table(worker_id uuid,worker_code text,worker_name text,department_code text,role_code text,worker_source text)
language plpgsql security definer set search_path='public'
as $$
declare
  v_profile public.rr_user_profiles%rowtype;v_allowed boolean:=false;v_effective text;
  v_id uuid;v_code text;v_name text:=nullif(trim(p_worker_name),'');
  v_dept text:=upper(public.rr_upm_core_department_v9077(nullif(trim(p_department_code),'')));
  v_role text:=lower(coalesce(nullif(trim(p_role_code),''),'worker'));v_source text;
begin
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if not found then raise exception 'Active User Directory profile required.';end if;
  v_effective:=upper(coalesce(public.rr_upm_effective_role_v200(),''));
  v_allowed:=v_effective in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','LINE MAN','DEPARTMENT_HEAD','PRODUCTION','CUTTING_MASTER');
  if not v_allowed then raise exception 'Add Worker permission denied for effective Act As role %.',coalesce(v_effective,'NONE');end if;
  if v_name is null then raise exception 'Worker name is required.';end if;
  if nullif(v_dept,'') is null then raise exception 'Department is required.';end if;

  select p.auth_user_id,'WRK-'||upper(substr(replace(p.auth_user_id::text,'-',''),1,8)),'ROLE_DIRECTORY'
  into v_id,v_code,v_source from public.rr_user_profiles p
  where lower(trim(coalesce(p.full_name,p.email,'')))=lower(v_name)
    and public.rr_upm_core_department_v9077(p.department_code)=public.rr_upm_core_department_v9077(v_dept)
    and coalesce(p.is_active,false) limit 1;
  if v_id is null then
    select w.id,w.worker_code,coalesce(w.source,'ASSIGN_WORK') into v_id,v_code,v_source
    from public.rr_worker_directory_v1 w
    where lower(trim(w.worker_name))=lower(v_name)
      and public.rr_upm_core_department_v9077(w.department_code)=public.rr_upm_core_department_v9077(v_dept)
      and w.is_active limit 1;
  end if;
  if v_id is null then
    v_id:=gen_random_uuid();v_code:='WRK-'||upper(substr(replace(v_id::text,'-',''),1,8));v_source:='ASSIGN_WORK';
    insert into public.rr_worker_directory_v1
      (id,worker_code,worker_name,department_code,role_code,mobile,source,created_by,updated_by)
    values(v_id,v_code,v_name,v_dept,v_role,nullif(trim(p_mobile),''),v_source,auth.uid(),auth.uid());
  end if;

  insert into public.rr_worker_department_map_v1(worker_id,department_code,is_primary,is_active,assigned_by,updated_at)
  values(v_id,lower(public.rr_upm_core_department_v9077(v_dept)),true,true,auth.uid(),now())
  on conflict(worker_id,department_code) do update set is_primary=true,is_active=true,assigned_by=auth.uid(),updated_at=now();
  insert into public.rr_real_chat_department_membership_v70
    (department_code,worker_id,membership_side,source_rule,is_active,updated_by,membership_scope,manual_lock,updated_at)
  values(upper(public.rr_upm_core_department_v9077(v_dept)),v_id,'WORKER','ADD_WORKER_CANONICAL_V321',true,auth.uid(),'DEPARTMENT',false,now())
  on conflict(department_code,worker_id,membership_side) do update
  set is_active=true,source_rule=excluded.source_rule,updated_by=auth.uid(),membership_scope='DEPARTMENT',manual_lock=false,inactive_reason=null,updated_at=now();
  return query select v_id,v_code,v_name,v_dept,v_role,v_source;
end$$;

-- Staff Manage calls this canonical owner-facing wrapper.  Keep the signed-in
-- actor gate and let v8_3 enforce the effective Act As role as well.
create or replace function public.rr_owner_add_worker_v8_4(
  p_worker_name text,p_department_code text,p_role_code text default 'worker',p_mobile text default null
)
returns table(worker_id uuid,worker_code text,worker_name text,department_code text,role_code text,worker_source text)
language plpgsql security definer set search_path='public'
as $$
declare v_actual text;
begin
  select upper(coalesce(p.role_code,'')) into v_actual
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid() and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if coalesce(v_actual,'') not in('OWNER','SUPER_ADMIN','ADMIN') then
    raise exception 'Owner / Super Admin / Admin permission required.';
  end if;
  return query select * from public.rr_upm_add_worker_v8_3(
    p_worker_name,p_department_code,p_role_code,p_mobile
  );
end$$;

create or replace function public.rr_real_chat_membership_admin_v136(
 p_worker_id uuid,p_action text,p_scope text default 'DEPARTMENT',p_department_codes text[] default '{}',p_reason text default null
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_uid uuid:=auth.uid();v_role text;v_effective text;v_name text;v_action text:=upper(trim(coalesce(p_action,'')));
 v_scope text:=upper(trim(coalesce(p_scope,'DEPARTMENT')));v_home text;v_depts text[];v_code text;
 v_special constant text[]:=array['CUTTING','PRINTING','STICKER','METAL_ID'];
 v_general constant text[]:=array['STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING','DESPATCH'];
begin
 if v_uid is null then raise exception 'Login required.';end if;
 select upper(coalesce(p.role_code,'')),p.full_name into v_role,v_name from public.rr_user_profiles p
 where p.auth_user_id=v_uid and p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
 order by p.updated_at desc nulls last limit 1;
 v_effective:=upper(coalesce(public.rr_upm_effective_role_v200(),''));
 if v_role not in('OWNER','SUPER_ADMIN','ADMIN') or v_effective not in('OWNER','SUPER_ADMIN','ADMIN')
 then raise exception 'Only an effective Owner / Super Admin / Admin can manage group staff.';end if;
 if v_action not in('ADD','ACTIVE','INACTIVE','REMOVE') then raise exception 'Invalid membership action.';end if;
 if v_scope not in('DEPARTMENT','GLOBAL_WORKER','MULTI_DEPARTMENT','ALL_RELEVANT') then raise exception 'Invalid membership scope.';end if;
 select public.rr_upm_core_department_v9077(d.department_code) into v_home from public.rr_worker_directory_unified_v1 d
 where d.worker_id=p_worker_id and coalesce(d.is_active,false) limit 1;
 if v_home is null then raise exception 'Active worker not found.';end if;
 if v_action in('INACTIVE','REMOVE') then
  select coalesce(array_agg(distinct m.department_code),array[v_home]) into v_depts from public.rr_real_chat_department_membership_v70 m where m.worker_id=p_worker_id;
  insert into public.rr_real_chat_worker_membership_control_v136(worker_id,manual_global_inactive,inactive_action,inactive_reason,updated_by)
  values(p_worker_id,true,v_action,nullif(trim(p_reason),''),v_uid)
  on conflict(worker_id) do update set manual_global_inactive=true,inactive_action=excluded.inactive_action,inactive_reason=excluded.inactive_reason,updated_at=now(),updated_by=v_uid;
  update public.rr_real_chat_department_membership_v70 set is_active=false,manual_lock=true,
   source_rule=case when v_action='REMOVE' then 'ADMIN_REMOVED' else 'ADMIN_INACTIVE' end,
   inactive_reason=nullif(trim(p_reason),''),updated_at=now(),updated_by=v_uid where worker_id=p_worker_id;
 else
  if v_scope='DEPARTMENT' then
   if coalesce(array_length(p_department_codes,1),0)<>1 then raise exception 'Choose exactly one department.';end if;
   v_depts:=array[public.rr_upm_core_department_v9077(p_department_codes[1])];
  elsif v_scope='MULTI_DEPARTMENT' then
   if coalesce(array_length(p_department_codes,1),0)<2 then raise exception 'Choose two or more departments.';end if;
   select array_agg(distinct public.rr_upm_core_department_v9077(x)) into v_depts from unnest(p_department_codes)x;
  elsif v_scope='GLOBAL_WORKER' then v_depts:=v_general;
  else select coalesce(array_agg(distinct m.department_code),array[v_home]) into v_depts from public.rr_real_chat_department_membership_v70 m where m.worker_id=p_worker_id;
  end if;
  if v_home=any(v_special) and not(v_home=any(v_depts)) then v_depts:=array_append(v_depts,v_home);end if;
  insert into public.rr_real_chat_worker_membership_control_v136(worker_id,manual_global_inactive,inactive_action,inactive_reason,updated_by)
  values(p_worker_id,false,null,null,v_uid) on conflict(worker_id) do update
  set manual_global_inactive=false,inactive_action=null,inactive_reason=null,updated_at=now(),updated_by=v_uid;
  foreach v_code in array v_depts loop
   insert into public.rr_real_chat_department_membership_v70
    (department_code,worker_id,membership_side,source_rule,is_active,updated_by,membership_scope,manual_lock,inactive_reason,last_working_at)
   values(v_code,p_worker_id,case when v_code=v_home then 'WORKER' else 'STAFF' end,'ADMIN_'||v_action,true,v_uid,v_scope,false,null,now())
   on conflict(department_code,worker_id,membership_side) do update set is_active=true,source_rule='ADMIN_'||v_action,
    updated_at=now(),updated_by=v_uid,membership_scope=v_scope,manual_lock=false,inactive_reason=null;
  end loop;
 end if;
 insert into public.rr_real_chat_membership_audit_v136(worker_id,action,scope,department_codes,reason,actor_user_id,actor_name)
 values(p_worker_id,v_action,v_scope,coalesce(v_depts,'{}'),nullif(trim(p_reason),''),v_uid,v_name);
 return jsonb_build_object('ok',true,'worker_id',p_worker_id,'action',v_action,'scope',v_scope,'department_codes',coalesce(v_depts,'{}'));
end$$;

revoke execute on function public.rr_upm_add_worker_v8_3(text,text,text,text) from anon;
revoke execute on function public.rr_owner_add_worker_v8_4(text,text,text,text) from anon;
revoke execute on function public.rr_real_chat_membership_admin_v136(uuid,text,text,text[],text) from anon;
grant execute on function public.rr_upm_add_worker_v8_3(text,text,text,text) to authenticated;
grant execute on function public.rr_owner_add_worker_v8_4(text,text,text,text) to authenticated;
grant execute on function public.rr_real_chat_membership_admin_v136(uuid,text,text,text[],text) to authenticated;
