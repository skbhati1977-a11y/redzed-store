-- TEST70 department staff administration and automatic membership lifecycle.
-- MAIN remains untouched. Manual ADMIN inactivation is a hard lock; assignment cannot bypass it.

alter table public.rr_real_chat_department_membership_v70
  add column if not exists membership_scope text not null default 'DEPARTMENT',
  add column if not exists manual_lock boolean not null default false,
  add column if not exists inactive_reason text,
  add column if not exists last_working_at timestamptz,
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.rr_real_chat_membership_audit_v136 (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  action text not null,
  scope text not null,
  department_codes text[] not null default '{}',
  reason text,
  actor_user_id uuid not null,
  actor_name text,
  created_at timestamptz not null default now()
);
alter table public.rr_real_chat_membership_audit_v136 enable row level security;
revoke all on public.rr_real_chat_membership_audit_v136 from public,anon,authenticated;

create table if not exists public.rr_real_chat_worker_membership_control_v136 (
  worker_id uuid primary key,
  manual_global_inactive boolean not null default false,
  inactive_action text,
  inactive_reason text,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.rr_real_chat_worker_membership_control_v136 enable row level security;
revoke all on public.rr_real_chat_worker_membership_control_v136 from public,anon,authenticated;

create or replace function public.rr_real_chat_membership_admin_v136(
  p_worker_id uuid,
  p_action text,
  p_scope text default 'DEPARTMENT',
  p_department_codes text[] default '{}',
  p_reason text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid(); v_role text; v_name text; v_action text:=upper(trim(coalesce(p_action,'')));
  v_scope text:=upper(trim(coalesce(p_scope,'DEPARTMENT'))); v_home text; v_depts text[]; v_code text;
  v_special constant text[]:=array['CUTTING','PRINTING','STICKER','METAL_ID'];
  v_general constant text[]:=array['STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING','DISPATCH'];
begin
  if v_uid is null then raise exception 'Login required.'; end if;
  select upper(coalesce(p.role_code,'')),p.full_name into v_role,v_name
  from public.rr_user_profiles p where p.auth_user_id=v_uid and p.is_active
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if v_role not in ('OWNER','SUPER_ADMIN','ADMIN') then raise exception 'Only Owner / Super Admin / Admin can manage group staff.'; end if;
  if v_action not in ('ADD','ACTIVE','INACTIVE','REMOVE') then raise exception 'Invalid membership action.'; end if;
  if v_scope not in ('DEPARTMENT','GLOBAL_WORKER','MULTI_DEPARTMENT','ALL_RELEVANT') then raise exception 'Invalid membership scope.'; end if;

  select public.rr_upm_core_department_v9077(d.department_code) into v_home
  from public.rr_worker_directory_unified_v1 d
  where d.worker_id=p_worker_id and coalesce(d.is_active,false) limit 1;
  if v_home is null then raise exception 'Active worker not found.'; end if;

  if v_action in ('INACTIVE','REMOVE') then
    select coalesce(array_agg(distinct m.department_code),array[v_home]) into v_depts
    from public.rr_real_chat_department_membership_v70 m where m.worker_id=p_worker_id;
    insert into public.rr_real_chat_worker_membership_control_v136(worker_id,manual_global_inactive,inactive_action,inactive_reason,updated_by)
    values(p_worker_id,true,v_action,nullif(trim(p_reason),''),v_uid)
    on conflict(worker_id) do update set manual_global_inactive=true,inactive_action=excluded.inactive_action,
      inactive_reason=excluded.inactive_reason,updated_at=now(),updated_by=v_uid;
    update public.rr_real_chat_department_membership_v70 set is_active=false,manual_lock=true,
      source_rule=case when v_action='REMOVE' then 'ADMIN_REMOVED' else 'ADMIN_INACTIVE' end,
      inactive_reason=nullif(trim(p_reason),''),updated_at=now(),updated_by=v_uid
    where worker_id=p_worker_id;
  else
    if v_scope='DEPARTMENT' then
      if coalesce(array_length(p_department_codes,1),0)<>1 then raise exception 'Choose exactly one department.'; end if;
      v_depts:=array[public.rr_upm_core_department_v9077(p_department_codes[1])];
    elsif v_scope='MULTI_DEPARTMENT' then
      if coalesce(array_length(p_department_codes,1),0)<2 then raise exception 'Choose two or more departments.'; end if;
      select array_agg(distinct public.rr_upm_core_department_v9077(x)) into v_depts from unnest(p_department_codes) x;
    elsif v_scope='GLOBAL_WORKER' then
      -- General production overlay deliberately excludes specialist departments.
      v_depts:=v_general;
    else
      select coalesce(array_agg(distinct m.department_code),array[v_home]) into v_depts
      from public.rr_real_chat_department_membership_v70 m where m.worker_id=p_worker_id;
    end if;
    if v_home=any(v_special) and not (v_home=any(v_depts)) then v_depts:=array_append(v_depts,v_home); end if;

    insert into public.rr_real_chat_worker_membership_control_v136(worker_id,manual_global_inactive,inactive_action,inactive_reason,updated_by)
    values(p_worker_id,false,null,null,v_uid)
    on conflict(worker_id) do update set manual_global_inactive=false,inactive_action=null,inactive_reason=null,updated_at=now(),updated_by=v_uid;

    foreach v_code in array v_depts loop
      insert into public.rr_real_chat_department_membership_v70(
        department_code,worker_id,membership_side,source_rule,is_active,updated_by,membership_scope,manual_lock,inactive_reason,last_working_at)
      values(v_code,p_worker_id,case when v_code=v_home then 'WORKER' else 'STAFF' end,
        'ADMIN_'||v_action,true,v_uid,v_scope,false,null,now())
      on conflict(department_code,worker_id,membership_side) do update set is_active=true,source_rule='ADMIN_'||v_action,
        updated_at=now(),updated_by=v_uid,membership_scope=v_scope,manual_lock=false,inactive_reason=null;
    end loop;
  end if;

  insert into public.rr_real_chat_membership_audit_v136(worker_id,action,scope,department_codes,reason,actor_user_id,actor_name)
  values(p_worker_id,v_action,v_scope,coalesce(v_depts,'{}'),nullif(trim(p_reason),''),v_uid,v_name);
  return jsonb_build_object('ok',true,'worker_id',p_worker_id,'action',v_action,'scope',v_scope,'department_codes',coalesce(v_depts,'{}'));
end $function$;
revoke all on function public.rr_real_chat_membership_admin_v136(uuid,text,text,text[],text) from public,anon;
grant execute on function public.rr_real_chat_membership_admin_v136(uuid,text,text,text[],text) to authenticated;

create or replace function public.rr_real_chat_assignment_membership_guard_v136()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_dept text:=public.rr_upm_core_department_v9077(new.department_code); v_home text; v_locked boolean;
begin
  if upper(coalesce(new.status,'')) not in ('ASSIGNED','IN_PROGRESS') then return new; end if;
  select coalesce(c.manual_global_inactive,false) into v_locked
  from public.rr_real_chat_worker_membership_control_v136 c where c.worker_id=new.worker_id;
  if coalesce(v_locked,false) or exists(select 1 from public.rr_real_chat_department_membership_v70 m
      where m.worker_id=new.worker_id and m.manual_lock) then
    raise exception 'Worker was manually made inactive. Admin must ACTIVE the worker before assignment.';
  end if;
  select public.rr_upm_core_department_v9077(d.department_code) into v_home
  from public.rr_worker_directory_unified_v1 d where d.worker_id=new.worker_id and coalesce(d.is_active,false) limit 1;
  insert into public.rr_real_chat_department_membership_v70(
    department_code,worker_id,membership_side,source_rule,is_active,updated_by,membership_scope,manual_lock,inactive_reason,last_working_at)
  values(v_dept,new.worker_id,case when v_dept=v_home then 'WORKER' else 'STAFF' end,
    'AUTO_ASSIGN_REACTIVATE',true,new.assigned_by,'DEPARTMENT',false,null,now())
  on conflict(department_code,worker_id,membership_side) do update set is_active=true,source_rule='AUTO_ASSIGN_REACTIVATE',
    updated_at=now(),updated_by=new.assigned_by,manual_lock=false,inactive_reason=null,last_working_at=now();
  return new;
end $function$;
revoke all on function public.rr_real_chat_assignment_membership_guard_v136() from public,anon,authenticated;
drop trigger if exists rr_real_chat_assignment_membership_guard_v136 on public.rr_upm_work_assignments_v8;
create trigger rr_real_chat_assignment_membership_guard_v136
before insert or update of worker_id,status on public.rr_upm_work_assignments_v8
for each row execute function public.rr_real_chat_assignment_membership_guard_v136();

create or replace function public.rr_real_chat_auto_inactive_v136()
returns integer language plpgsql security definer set search_path=''
as $function$
declare v_count integer;
begin
  with last_work as (
    select a.worker_id,max(coalesce(a.updated_at,a.completed_at,a.assigned_at)) last_at,
      bool_or(a.status in ('ASSIGNED','IN_PROGRESS')) has_working
    from public.rr_upm_work_assignments_v8 a group by a.worker_id
  ), due as (
    select m.department_code,m.worker_id,m.membership_side
    from public.rr_real_chat_department_membership_v70 m
    left join last_work w on w.worker_id=m.worker_id
    left join public.rr_real_chat_worker_membership_control_v136 c on c.worker_id=m.worker_id
    where m.is_active and not m.manual_lock and not coalesce(c.manual_global_inactive,false)
      and not coalesce(w.has_working,false)
      and coalesce(w.last_at,m.last_working_at,m.updated_at,m.created_at)<now()-interval '6 days'
  )
  update public.rr_real_chat_department_membership_v70 m set is_active=false,source_rule='AUTO_INACTIVE_6_DAYS',
    inactive_reason='No active work for 6 continuous days',updated_at=now()
  from due d where m.department_code=d.department_code and m.worker_id=d.worker_id and m.membership_side=d.membership_side;
  get diagnostics v_count=row_count;
  return v_count;
end $function$;
revoke all on function public.rr_real_chat_auto_inactive_v136() from public,anon,authenticated;

create or replace function public.rr_real_chat_membership_roster_v136()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_role text; v_rows jsonb;
begin
  select upper(coalesce(p.role_code,'')) into v_role from public.rr_user_profiles p
  where p.auth_user_id=v_uid and p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
  if v_role not in ('OWNER','SUPER_ADMIN','ADMIN') then raise exception 'Admin permission required.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id',d.worker_id,'worker_name',d.worker_name,'worker_code',d.worker_code,'role_code',d.role_code,
    'home_department_code',public.rr_upm_core_department_v9077(d.department_code),
    'manual_global_inactive',coalesce(c.manual_global_inactive,false),
    'memberships',coalesce((select jsonb_agg(jsonb_build_object('department_code',m.department_code,'side',m.membership_side,
      'is_active',m.is_active,'source_rule',m.source_rule,'manual_lock',m.manual_lock) order by m.department_code)
      from public.rr_real_chat_department_membership_v70 m where m.worker_id=d.worker_id),'[]'::jsonb)
  ) order by d.worker_name),'[]'::jsonb) into v_rows
  from public.rr_worker_directory_unified_v1 d
  left join public.rr_real_chat_worker_membership_control_v136 c on c.worker_id=d.worker_id
  where coalesce(d.is_active,false);
  return jsonb_build_object('version','V136','workers',v_rows);
end $function$;
revoke all on function public.rr_real_chat_membership_roster_v136() from public,anon;
grant execute on function public.rr_real_chat_membership_roster_v136() to authenticated;

create or replace function public.rr_real_chat_directory_v84()
returns jsonb language plpgsql volatile security definer set search_path=''
as $function$
declare v_result jsonb;
begin
  perform public.rr_real_chat_auto_inactive_v136();
  v_result:=public.rr_real_chat_directory_v83();
  return jsonb_set(v_result,'{version}','\"TEST70_REAL_CHAT_DIRECTORY_V84_STAFF_LIFECYCLE\"'::jsonb);
end $function$;
revoke all on function public.rr_real_chat_directory_v84() from public,anon;
grant execute on function public.rr_real_chat_directory_v84() to authenticated;

comment on function public.rr_real_chat_membership_admin_v136(uuid,text,text,text[],text)
is 'Admin-only soft membership lifecycle with department/global/multi scope and immutable audit.';
