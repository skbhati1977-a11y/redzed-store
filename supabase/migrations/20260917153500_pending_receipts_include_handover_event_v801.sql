-- V801: App + Real Chat pending receipt rows expose the canonical ASSIGN_HANDOVER event.
-- This lets the frontend call rr_upm_accept_physical_count_v801 without guessing an event id.
create or replace function public.rr_upm_my_pending_receipts_v9112()
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
with me as(select public.rr_upm_current_worker_id_v9112() worker_id), grouped as(
  select coalesce(r.receipt_batch_id,a.assignment_batch_id,a.id) receipt_batch_id,
         a.canonical_lot_id,a.lot_no,public.rr_upm_core_department_v9077(a.department_code) department_code,
         r.worker_id,min(a.assigned_at) assigned_at,
         (array_agg(r.source_custodian_worker_id order by a.colour_code))[1] source_custodian_worker_id,
         max(r.source_custodian_name) source_custodian_name,max(r.source_custodian_role) source_custodian_role,
         sum(r.expected_qty) expected_qty,sum(coalesce(r.confirmed_qty,0)) confirmed_qty,
         case when bool_or(upper(r.status)='DISPUTED') then 'DISPUTED' else 'PENDING' end status,
         jsonb_agg(jsonb_build_object(
           'assignment_id',r.assignment_id,
           'responsibility_event_id',(
             select e.id from public.rr_upm_responsibility_events_v800 e
             where e.assignment_id=r.assignment_id::text
               and upper(e.event_type)='ASSIGN_HANDOVER'
               and nullif(e.receiver_worker_id,'')::uuid=r.worker_id
               and upper(e.status) in ('OFFERED','GIVER_CONFIRMED')
             order by e.created_at desc limit 1
           ),
           'colour_code',a.colour_code,
           'expected_qty',r.expected_qty,'confirmed_qty',r.confirmed_qty,'status',r.status,
           'size_breakup',coalesce(a.inbound_breakup,a.size_breakup,'[]'::jsonb)
         ) order by a.colour_code) colour_rows
  from public.rr_upm_assignment_receipts_v9112 r
  join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
  where r.worker_id=(select worker_id from me) and upper(r.status) in('PENDING','DISPUTED')
  group by coalesce(r.receipt_batch_id,a.assignment_batch_id,a.id),a.canonical_lot_id,a.lot_no,
           public.rr_upm_core_department_v9077(a.department_code),r.worker_id
)
select jsonb_build_object('ok',true,'version','V801_CANONICAL_ACCEPT_COUNT','rows',coalesce(jsonb_agg(to_jsonb(grouped) order by assigned_at),'[]'::jsonb)) from grouped
$function$;
comment on function public.rr_upm_my_pending_receipts_v9112() is
'Pending assignment receipts for App/Real Chat. Each colour row includes canonical ASSIGN_HANDOVER responsibility_event_id for V801 Accept & Count.';
