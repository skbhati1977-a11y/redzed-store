-- TEST71 V322: Worker Submit remains the existing V204 handover engine.
-- This adds only the missing salary-stop hook and Personal CLOSE projection.
begin;

create or replace function public.rr_salaried_team_finish_on_worker_submit_v322()
returns trigger
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_assignment_id uuid;
  v_completed_qty numeric;
begin
  if upper(coalesce(new.status,'')) not in ('WAITING_LM','ESCALATED') then
    return new;
  end if;
  foreach v_assignment_id in array coalesce(new.assignment_ids,'{}'::uuid[]) loop
    select greatest(coalesce(a.inbound_qty,0),coalesce(a.assigned_qty,0))
      into v_completed_qty
    from public.rr_upm_work_assignments_v8 a
    where a.id=v_assignment_id;
    perform public.rr_salaried_team_finish_if_applicable_v300(v_assignment_id,coalesce(v_completed_qty,0));
  end loop;
  return new;
end
$function$;

drop trigger if exists rr_salaried_team_finish_on_worker_submit_v322
on public.rr_upm_submit_requests_v794;
create trigger rr_salaried_team_finish_on_worker_submit_v322
after insert on public.rr_upm_submit_requests_v794
for each row execute function public.rr_salaried_team_finish_on_worker_submit_v322();

create or replace function public.rr_real_chat_operational_work_v319(
  p_worker_id uuid,
  p_status text default 'WORKING',
  p_department_code text default null
)
returns jsonb
language sql
stable
security definer
set search_path='public'
as $function$
with id as(
  select public.rr_canonical_worker_id_v264(p_worker_id) worker_id
), a as(
  select x.*,r.status receipt_status2,e.id event_id,
         s.id submit_request_id,s.status submit_status,s.selected_receiver_name
  from id
  join public.rr_upm_worker_operational_work_v280 x on x.worker_id=id.worker_id
  left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=x.assignment_id
  left join lateral(
    select q.id
    from public.rr_upm_responsibility_events_v800 q
    where q.assignment_id=x.assignment_id::text and q.event_type='ASSIGN_HANDOVER'
    order by q.created_at desc limit 1
  ) e on true
  left join lateral(
    select q.id,q.status,q.selected_receiver_name
    from public.rr_upm_submit_requests_v794 q
    where x.assignment_id=any(q.assignment_ids)
      and upper(q.status) in ('WAITING_LM','ESCALATED','LM_ACCEPTED','LM_COUNTED','COMPLETED')
    order by q.updated_at desc nulls last,q.created_at desc
    limit 1
  ) s on true
  where p_department_code is null
     or x.department_code=public.rr_upm_core_department_v9077(p_department_code)
), w as(
  select *,case
    when receipt_status2='PENDING' then 'ACCEPT_PENDING'
    when submit_request_id is not null then 'CLOSE'
    when receipt_status2='CONFIRMED' and status='IN_PROGRESS' then 'WORKING'
    when status in('COMPLETED','CANCELLED') then 'CLOSE'
    when receipt_status2 is null then 'LEGACY'
    else status
  end resolved
  from a
), f as(
  select * from w
  where case upper(coalesce(p_status,'WORKING'))
    when 'OPEN' then resolved='ACCEPT_PENDING'
    when 'WORKING' then resolved='WORKING' or(resolved='LEGACY' and status in('ASSIGNED','IN_PROGRESS'))
    when 'CLOSE' then resolved='CLOSE'
    else true
  end
)
select jsonb_build_object(
  'version','V322_PERSONAL_WORKER_SUBMIT_CLOSE',
  'worker_id',(select worker_id from id),
  'status',upper(coalesce(p_status,'WORKING')),
  'cards',coalesce(jsonb_agg(jsonb_build_object(
    'assignment_id',assignment_id,
    'canonical_lot_id',canonical_lot_id,
    'lot_no',lot_no,
    'department_code',department_code,
    'colour_code',colour_code,
    'assignment_status',status,
    'resolved_work_state',resolved,
    'good_qty',good_qty,
    'qty',good_qty,
    'receipt_status',coalesce(receipt_status2,receipt_status),
    'responsibility_event_id',event_id,
    'submit_request_id',submit_request_id,
    'submit_status',submit_status,
    'message',case
      when resolved='ACCEPT_PENDING' then 'काम मिला · Accept & Count बाकी'
      when resolved='WORKING' then 'काम जारी है'
      when resolved='CLOSE' and submit_request_id is not null then
        'काम जमा किया'||case when nullif(selected_receiver_name,'') is not null then ' · '||selected_receiver_name||' को count pending' else '' end
      else null
    end,
    'actions',case
      when resolved='ACCEPT_PENDING' and event_id is not null then jsonb_build_array('CONFIRM_RECEIVED_PCS')
      when resolved='WORKING' and good_qty>0 then jsonb_build_array('SUBMIT','ALTER','RECTIFY')
      when resolved='LEGACY' and upper(coalesce(p_status,'WORKING'))='WORKING' and good_qty>0 then jsonb_build_array('SUBMIT','ALTER','RECTIFY')
      else '[]'::jsonb
    end,
    'short_excess_accept',case when short_excess_accept_qty>0 then jsonb_build_object(
      'qty',short_excess_accept_qty,'action','ACCEPT','journey','SHORT_EXCESS_RECOVERY'
    ) else null end
  ) order by lot_no,colour_code,assignment_id),'[]'::jsonb),
  'count',count(*),
  'good_total',coalesce(sum(good_qty),0)
)
from f
$function$;

comment on function public.rr_salaried_team_finish_on_worker_submit_v322() is
'TEST71 V322: the canonical V204 Worker Submit request stops the V313 Accept-to-Submit salary session.';
comment on function public.rr_real_chat_operational_work_v319(uuid,text,text) is
'TEST71 V322: Personal Chat projects a canonical active Submit handover into CLOSE without creating a second Submit engine.';

commit;
