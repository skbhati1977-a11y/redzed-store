-- TEST70 V141: every active directory worker remains mapped to the canonical
-- home department. Operational inactivity controls assignment eligibility,
-- not directory visibility.

insert into public.rr_real_chat_department_membership_v70(
  department_code, worker_id, membership_side, source_rule, is_active,
  membership_scope, manual_lock, inactive_reason, created_at, updated_at
)
select
  public.rr_upm_core_department_v9077(d.department_code),
  d.worker_id,
  'WORKER',
  case when coalesce(c.manual_global_inactive,false) then 'ADMIN_INACTIVE'
       else 'CANONICAL_HOME_DEPARTMENT' end,
  not coalesce(c.manual_global_inactive,false),
  'DEPARTMENT',
  coalesce(c.manual_global_inactive,false),
  case when coalesce(c.manual_global_inactive,false)
       then coalesce(c.inactive_reason,'Admin inactive') end,
  now(), now()
from public.rr_worker_directory_unified_v1 d
left join public.rr_real_chat_worker_membership_control_v136 c
  on c.worker_id=d.worker_id
where coalesce(d.is_active,false)
  and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
  and public.rr_upm_core_department_v9077(d.department_code) is not null
on conflict(department_code,worker_id,membership_side) do nothing;

create or replace function public.rr_real_chat_directory_v85()
returns jsonb language plpgsql volatile security definer set search_path=''
as $function$
declare v_result jsonb; v_departments jsonb;
begin
  v_result:=public.rr_real_chat_directory_v84();

  select coalesce(jsonb_agg(
    jsonb_set(
      jsonb_set(dep,'{workers}',coalesce(home.workers,'[]'::jsonb),true),
      '{worker_count}',to_jsonb(coalesce(home.worker_count,0)),true
    ) order by (dep->>'sort_order')::integer
  ),'[]'::jsonb)
  into v_departments
  from jsonb_array_elements(coalesce(v_result->'departments','[]'::jsonb)) dep
  left join lateral (
    select count(*)::integer worker_count,
      jsonb_agg(jsonb_build_object(
        'worker_id',d.worker_id,
        'worker_code',d.worker_code,
        'worker_name',d.worker_name,
        'role_code',d.role_code,
        'home_department_code',public.rr_upm_core_department_v9077(d.department_code),
        'linked_login',d.linked_auth_user_id is not null,
        'membership_side','WORKER',
        'membership_active',coalesce(m.is_active,false),
        'manual_lock',coalesce(m.manual_lock,false),
        'inactive_reason',m.inactive_reason,
        'source_rule',m.source_rule
      ) order by d.worker_name) workers
    from public.rr_worker_directory_unified_v1 d
    left join public.rr_real_chat_department_membership_v70 m
      on m.worker_id=d.worker_id
     and m.department_code=dep->>'department_code'
     and m.membership_side='WORKER'
    where coalesce(d.is_active,false)
      and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
      and public.rr_upm_core_department_v9077(d.department_code)=dep->>'department_code'
  ) home on true;

  v_result:=jsonb_set(v_result,'{departments}',v_departments,true);
  return jsonb_set(v_result,'{version}',to_jsonb('TEST70_REAL_CHAT_DIRECTORY_V85_HOME_WORKER_VISIBILITY'::text),true);
end $function$;

revoke all on function public.rr_real_chat_directory_v85() from public,anon;
grant execute on function public.rr_real_chat_directory_v85() to authenticated;

comment on function public.rr_real_chat_directory_v85()
is 'Canonical home workers stay visible in their own department; membership_active controls assignment eligibility.';
