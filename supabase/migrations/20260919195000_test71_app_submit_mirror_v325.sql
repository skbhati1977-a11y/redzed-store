-- TEST71 V325: App board mirrors canonical worker Submit while Line Man count is pending.
begin;

create or replace function public.rr_upm_board_lot_status_v743(p_canonical_lot_id text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare ident_json jsonb; statuses jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  begin
    ident_json:=to_jsonb(public.rr_upm_resolve_identity_v740(p_canonical_lot_id,false,null));
  exception when others then
    select to_jsonb(l) into ident_json from public.rr_upm_lot_board_v1 l where l.canonical_lot_id=p_canonical_lot_id limit 1;
  end;
  with allc as(
    select count(distinct colour_code)::int total from(
      select upper(q.colour_code) colour_code from public.rr_upm_colour_queue_v741 q where q.canonical_lot_id=p_canonical_lot_id
      union select upper(a.colour_code) from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id
    ) colours
  ), deps as(
    select d.department_code,d.department_name from public.rr_upm_departments d
    where d.is_active and coalesce(d.colour_assignment_enabled,true) and coalesce(d.worker_assignment_enabled,true)
      and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION' and not coalesce(d.is_start_department,false)
      and (not exists(select 1 from public.rr_upm_departments ch where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code))
        or exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(d.department_code)))
  ), submitted_assignments as(
    select distinct aid assignment_id
    from public.rr_upm_submit_requests_v794 q
    cross join lateral unnest(q.assignment_ids) aid
    where upper(q.status) in ('WAITING_LM','ESCALATED','LM_ACCEPTED','LM_COUNTED','COMPLETED')
  ), raw_active as(
    select upper(a.department_code) department_code,upper(a.colour_code) colour_code,upper(a.status) assignment_status
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id and upper(a.status) in ('ASSIGNED','IN_PROGRESS')
      and not exists(select 1 from submitted_assignments s where s.assignment_id=a.id)
  ), active as(
    select department_code,colour_code,case when bool_or(assignment_status='IN_PROGRESS') then 'IN_PROGRESS' else 'ASSIGNED' end assignment_status
    from raw_active group by department_code,colour_code
  ), completed_raw as(
    select upper(a.department_code) department_code,upper(a.colour_code) colour_code from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id and upper(a.status)='COMPLETED'
    union select upper(h.department_code),upper(h.colour_code) from public.rr_upm_dynamic_submit_history_v741 h where h.canonical_lot_id=p_canonical_lot_id
    union select upper(a.department_code),upper(a.colour_code) from public.rr_upm_work_assignments_v8 a join submitted_assignments s on s.assignment_id=a.id where a.canonical_lot_id=p_canonical_lot_id
  ), x as(
    select d.department_code,d.department_name,
      coalesce((select array_agg(a.colour_code order by a.colour_code) from active a where a.department_code=upper(d.department_code) and a.assignment_status='ASSIGNED'),array[]::text[]) assigned_codes,
      coalesce((select array_agg(a.colour_code order by a.colour_code) from active a where a.department_code=upper(d.department_code) and a.assignment_status='IN_PROGRESS'),array[]::text[]) running_codes,
      coalesce((select array_agg(c.colour_code order by c.colour_code) from completed_raw c where c.department_code=upper(d.department_code) and not exists(select 1 from active a where a.department_code=c.department_code and a.colour_code=c.colour_code)),array[]::text[]) submitted_codes,
      (select total from allc) total_colours from deps d
  ), y as(
    select x.*,cardinality(assigned_codes) assigned_count,cardinality(running_codes) running_count,cardinality(submitted_codes) submitted_count,cardinality(assigned_codes||running_codes) active_count from x
  ), visible as(
    select y.*,
      case when submitted_count=total_colours and total_colours>0 and active_count=0 then 'RED' when active_count=total_colours and total_colours>0 then 'GREEN' when active_count+submitted_count>0 then 'ORANGE' else 'BASE' end status_colour,
      case when submitted_count=total_colours and total_colours>0 and active_count=0 then 'ALL COLOURS SUBMITTED'
        when running_count=total_colours and total_colours>0 then 'ALL COLOURS RUNNING'
        when assigned_count=total_colours and total_colours>0 then 'ALL COLOURS ASSIGNED'
        when active_count=total_colours and total_colours>0 then trim(concat(case when cardinality(running_codes)>0 then 'RUNNING '||array_to_string(running_codes,' ') end,case when cardinality(assigned_codes)>0 then ' · ASSIGNED '||array_to_string(assigned_codes,' ') end))
        else trim(concat(case when cardinality(running_codes)>0 then 'RUNNING '||array_to_string(running_codes,' ') end,case when cardinality(assigned_codes)>0 then case when cardinality(running_codes)>0 then ' · ' else '' end||'ASSIGNED '||array_to_string(assigned_codes,' ') end,case when cardinality(submitted_codes)>0 then case when cardinality(running_codes)+cardinality(assigned_codes)>0 then ' · ' else '' end||'SUBMITTED '||array_to_string(submitted_codes,' ') end)) end board_detail
    from y where active_count+submitted_count>0
  )
  select coalesce(jsonb_agg(jsonb_build_object('department_code',v.department_code,'department_name',v.department_name,'status_colour',v.status_colour,'assigned_codes',v.assigned_codes,'running_codes',v.running_codes,'submitted_codes',v.submitted_codes,'total_colours',v.total_colours,'board_detail',v.board_detail) order by case v.status_colour when 'GREEN' then 1 when 'ORANGE' then 2 when 'RED' then 3 else 4 end,v.department_name),'[]'::jsonb) into statuses from visible v;
  return jsonb_build_object('identity',coalesce(ident_json,'{}'::jsonb),'department_statuses',statuses,'version','V325_APP_CANONICAL_SUBMIT_MIRROR');
end
$function$;

revoke all on function public.rr_upm_board_lot_status_v743(text) from public;
grant execute on function public.rr_upm_board_lot_status_v743(text) to authenticated;
comment on function public.rr_upm_board_lot_status_v743(text) is 'TEST71 V325: App board treats an active canonical V794 Submit handover as submitted, without changing assignment authority.';
commit;
