-- TEST71 V326: existing App colour-owner resolver mirrors canonical Submit handover.
begin;

create or replace function public.rr_upm_colour_owner_v755(p_canonical_lot_id text,p_colour_id uuid,p_colour_code text)
returns table(department_code text,department_name text,ownership_status text,assignment_id uuid,worker_id uuid,worker_name text,source_name text)
language sql stable security definer set search_path='public' as $function$
with active_assignment as(
  select public.rr_upm_v755_valid_department(a.department_code) department_code,
    case when exists(
      select 1 from public.rr_upm_submit_requests_v794 q
      where a.id=any(q.assignment_ids) and upper(q.status) in ('WAITING_LM','ESCALATED','LM_ACCEPTED','LM_COUNTED','COMPLETED')
    ) then 'SUBMITTED'
    when upper(a.status)='IN_PROGRESS' then 'RUNNING' else 'ASSIGNED' end ownership_status,
    a.id assignment_id,a.worker_id,coalesce(nullif(a.worker_name_snapshot,''),w.worker_name) worker_name,
    case when exists(
      select 1 from public.rr_upm_submit_requests_v794 q
      where a.id=any(q.assignment_ids) and upper(q.status) in ('WAITING_LM','ESCALATED','LM_ACCEPTED','LM_COUNTED','COMPLETED')
    ) then 'CANONICAL_SUBMIT_HANDOVER' else 'ACTIVE_ASSIGNMENT' end source_name
  from public.rr_upm_work_assignments_v8 a
  left join public.rr_worker_directory_unified_v1 w on w.worker_id=a.worker_id
  where a.canonical_lot_id=p_canonical_lot_id and upper(a.status) in ('ASSIGNED','IN_PROGRESS')
    and ((p_colour_id is not null and a.colour_id=p_colour_id) or upper(a.colour_code)=upper(p_colour_code))
    and public.rr_upm_v755_valid_department(a.department_code) is not null
  order by a.assigned_at desc,a.updated_at desc limit 1
), resolved as(
  select * from active_assignment
  union all
  select null::text,'OPEN'::text,null::uuid,null::uuid,null::text,'RANDOM_OPEN_QUEUE'::text
  where not exists(select 1 from active_assignment)
  limit 1
)
select r.department_code,
  case when r.department_code is null then 'OPEN RANDOM QUEUE' when r.department_code='STITCHING' then 'Karigar / Stitching' when r.department_code='QC' then 'QC'
    else coalesce((select d.department_name from public.rr_departments_v1 d where upper(d.department_code)=upper(r.department_code) and coalesce(d.is_active,false) limit 1),(select d.department_name from public.rr_upm_departments d where upper(d.department_code)=upper(r.department_code) and coalesce(d.is_active,false) limit 1),r.department_code) end,
  r.ownership_status,r.assignment_id,r.worker_id,r.worker_name,r.source_name
from resolved r
$function$;

revoke all on function public.rr_upm_colour_owner_v755(text,uuid,text) from public;
grant execute on function public.rr_upm_colour_owner_v755(text,uuid,text) to authenticated;
comment on function public.rr_upm_colour_owner_v755(text,uuid,text) is 'TEST71 V326: App ownership projection marks active canonical V794 handover as SUBMITTED; no workflow mutation.';
commit;
