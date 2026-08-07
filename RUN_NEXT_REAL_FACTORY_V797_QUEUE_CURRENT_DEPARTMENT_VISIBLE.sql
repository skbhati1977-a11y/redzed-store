-- REAL FACTORY V797
-- Random Queue correction: only the latest submitted department is excluded.
-- The current dashboard/target department remains visible and assignable.

begin;

create or replace function public.rr_upm_universal_form_v741(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  base jsonb; outrows jsonb:='[]'::jsonb; r jsonb; a record; q record;
  eligible boolean; completed_here boolean; statuses jsonb; v_last_submitted_department text;
begin
 perform public.rr_upm_sync_colour_queue_v741(p_canonical_lot_id);
 base:=public.rr_upm_universal_form_v740(p_canonical_lot_id,p_department_code);

 select upper(h.department_code) into v_last_submitted_department
 from public.rr_upm_dynamic_submit_history_v741 h
 where h.canonical_lot_id=p_canonical_lot_id
 order by h.submitted_at desc,h.id desc limit 1;

 select exists(select 1 from public.rr_upm_departments d where upper(d.department_code)=upper(p_department_code) and d.is_active and coalesce(d.colour_assignment_enabled,true) and coalesce(d.worker_assignment_enabled,true) and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION' and not coalesce(d.is_start_department,false)
    and not exists(select 1 from public.rr_upm_departments ch where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code))) into eligible;

 completed_here:=upper(p_department_code)=coalesce(v_last_submitted_department,'');

 for r in select value from jsonb_array_elements(coalesce(base->'rows','[]'::jsonb)) loop
  select * into q from public.rr_upm_colour_queue_v741 where canonical_lot_id=p_canonical_lot_id and upper(colour_code)=upper(r->>'colour_code');
  select * into a from public.rr_upm_work_assignments_v8 x where x.canonical_lot_id=p_canonical_lot_id and upper(x.colour_code)=upper(r->>'colour_code') and x.status in('ASSIGNED','IN_PROGRESS') order by x.assigned_at desc limit 1;
  if q.queue_state='OPEN' or (a.id is not null and upper(a.department_code)=upper(p_department_code)) then
    r:=r||jsonb_build_object(
      'is_locked',(a.id is not null and upper(a.department_code)=upper(p_department_code)),
      'can_assign',(q.queue_state='OPEN' and eligible and not completed_here),
      'assignment_id',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.id else null end,
      'worker_id',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_id else null end,
      'worker_name',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_name_snapshot else null end,
      'worker_code',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_code else null end,
      'assigned_qty',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then (r->>'main_qty')::numeric else 0 end,
      'assignment_status',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.status else null end,
      'status',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then 'ASSIGNED / IN PROGRESS' when completed_here then 'LAST SUBMITTED DEPARTMENT' else 'OPEN FOR ASSIGNMENT' end,
      'queue_state',q.queue_state,
      'owner_department_code',q.owner_department_code
    );
    outrows:=outrows||jsonb_build_array(r);
  end if;
 end loop;
 select coalesce(jsonb_agg(to_jsonb(s) order by s.department_name),'[]'::jsonb) into statuses from public.rr_upm_department_status_v741(p_canonical_lot_id)s;
 base:=jsonb_set(base,'{rows}',outrows,true);
 base:=base||jsonb_build_object('department_statuses',statuses,'dynamic_queue','FIRST_ASSIGNMENT_WINS','last_submitted_department_code',v_last_submitted_department,'route_locked_to',null,'next_department_code',null,'versions',coalesce(base->'versions','{}'::jsonb)||jsonb_build_object('dynamic_queue','V797_CURRENT_VISIBLE_LAST_SUBMIT_HIDDEN'));
 return base;
end;$$;

grant execute on function public.rr_upm_universal_form_v741(text,text) to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V797',
  'current_department_visible',true,
  'only_last_submitted_department_hidden',true,
  'other_departments_hidden',false
) as result;
