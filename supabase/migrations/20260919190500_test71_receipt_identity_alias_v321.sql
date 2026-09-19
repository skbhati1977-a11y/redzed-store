-- TEST71 V321: keep historical receipt identities intact while comparing them
-- through the existing canonical worker resolver during Accept & Count.
begin;

create or replace function public.rr_upm_my_pending_receipts_v9112()
returns jsonb language sql stable security definer set search_path=''
as $function$
with me as(
  select public.rr_upm_current_worker_id_v9112() worker_id
), grouped as(
  select coalesce(r.receipt_batch_id,a.assignment_batch_id,a.id) receipt_batch_id,
         a.canonical_lot_id,a.lot_no,public.rr_upm_core_department_v9077(a.department_code) department_code,
         public.rr_canonical_worker_id_v264(r.worker_id) worker_id,min(a.assigned_at) assigned_at,
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
               and public.rr_canonical_worker_id_v264(nullif(e.receiver_worker_id,'')::uuid)=public.rr_canonical_worker_id_v264(r.worker_id)
               and upper(e.status) in ('OFFERED','GIVER_CONFIRMED')
             order by e.created_at desc limit 1
           ),
           'colour_code',a.colour_code,
           'expected_qty',r.expected_qty,'confirmed_qty',r.confirmed_qty,'status',r.status,
           'size_breakup',coalesce(a.inbound_breakup,a.size_breakup,'[]'::jsonb)
         ) order by a.colour_code) colour_rows
  from public.rr_upm_assignment_receipts_v9112 r
  join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
  where public.rr_canonical_worker_id_v264(r.worker_id)=(select worker_id from me)
    and upper(r.status) in('PENDING','DISPUTED')
  group by coalesce(r.receipt_batch_id,a.assignment_batch_id,a.id),a.canonical_lot_id,a.lot_no,
           public.rr_upm_core_department_v9077(a.department_code),public.rr_canonical_worker_id_v264(r.worker_id)
)
select jsonb_build_object(
  'ok',true,
  'version','V321_CANONICAL_RECEIPT_IDENTITY',
  'rows',coalesce(jsonb_agg(to_jsonb(grouped) order by assigned_at),'[]'::jsonb)
) from grouped
$function$;

create or replace function public.rr_upm_confirm_assignment_receipt_batch_v204(
  p_receipt_batch_id uuid,
  p_rows jsonb,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_receipt_count int;v_input_count int;v_has_short boolean:=false;
  v_expected numeric:=0;v_confirmed numeric:=0;v_row jsonb;v_r record;v_a record;
  v_claims jsonb:='[]'::jsonb;v_fabrication boolean:=false;v_auto_note text;
begin
  if auth.uid() is null then raise exception 'Login required.';end if;
  if v_worker is null then raise exception 'Effective worker identity is required.';end if;
  if p_receipt_batch_id is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Complete receipt batch count is required.';end if;
  select count(*) into v_receipt_count
  from public.rr_upm_assignment_receipts_v9112 r
  where r.receipt_batch_id=p_receipt_batch_id
    and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker
    and upper(r.status) in('PENDING','DISPUTED');
  v_input_count:=jsonb_array_length(p_rows);
  if v_receipt_count=0 then raise exception 'Receipt batch is not pending for this worker.';end if;
  if v_input_count<>v_receipt_count then raise exception 'Count every colour in this handover together (% required).',v_receipt_count;end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    select r.*,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,a.status assignment_status into v_r
    from public.rr_upm_assignment_receipts_v9112 r
    join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
    where r.assignment_id=nullif(v_row->>'assignment_id','')::uuid
      and r.receipt_batch_id=p_receipt_batch_id
      and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker
    for update of r,a;
    if not found then raise exception 'Receipt row does not belong to this handover.';end if;
    if nullif(v_row->>'confirmed_qty','') is null or (v_row->>'confirmed_qty')::numeric<0 or (v_row->>'confirmed_qty')::numeric>v_r.expected_qty then raise exception 'Count for % must be between 0 and %.',v_r.colour_code,v_r.expected_qty;end if;
    v_expected:=v_expected+v_r.expected_qty;v_confirmed:=v_confirmed+(v_row->>'confirmed_qty')::numeric;
    v_has_short:=v_has_short or (v_row->>'confirmed_qty')::numeric<>v_r.expected_qty;
    v_fabrication:=v_fabrication or public.rr_upm_core_department_v9077(v_r.department_code)='FABRICATION';
  end loop;
  v_auto_note:=case when v_has_short then format('AUTO COUNT · Expected %s · Received %s · Short %s',v_expected,v_confirmed,greatest(v_expected-v_confirmed,0)) else null end;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    select r.*,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,a.worker_name_snapshot,a.assigned_qty,a.inbound_qty into v_r
    from public.rr_upm_assignment_receipts_v9112 r
    join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
    where r.assignment_id=(v_row->>'assignment_id')::uuid
    for update of r,a;
    update public.rr_upm_assignment_receipts_v9112
    set confirmed_qty=(v_row->>'confirmed_qty')::numeric,
        status=case when v_has_short then 'DISPUTED' else 'CONFIRMED' end,
        confirmed_at=now(),confirmed_by=auth.uid(),
        note=coalesce(nullif(trim(coalesce(p_note,'')),''),v_auto_note)
    where assignment_id=v_r.assignment_id;
    if v_has_short then
      update public.rr_upm_work_assignments_v8 set status='ASSIGNED',updated_at=now()
      where id=v_r.assignment_id and status in('ASSIGNED','IN_PROGRESS');
      if (v_row->>'confirmed_qty')::numeric<v_r.expected_qty then
        v_claims:=v_claims||jsonb_build_array(public.rr_upm_register_custody_missing_v185(v_r.assignment_id,v_r.expected_qty,(v_row->>'confirmed_qty')::numeric,coalesce(v_r.source_custodian_worker_id,v_r.source_custodian_auth_id)::text,coalesce(v_r.source_custodian_name,'Previous Custodian'),coalesce(v_r.source_custodian_role,'STAFF'),'ASSIGN_RECEIPT'));
      end if;
      perform public.rr_upm_set_custody_v204(v_r.canonical_lot_id,v_r.colour_code,v_r.source_custodian_worker_id,v_r.source_custodian_auth_id,v_r.source_custodian_name,v_r.source_custodian_role,'ASSIGN_DISPUTED',p_receipt_batch_id,v_worker,v_r.worker_name_snapshot,v_r.assignment_id,null);
    elsif public.rr_upm_core_department_v9077(v_r.department_code)='FABRICATION' then
      update public.rr_upm_work_assignments_v8 set status='COMPLETED',completed_at=now(),updated_at=now() where id=v_r.assignment_id;
      perform public.rr_upm_set_custody_v204(v_r.canonical_lot_id,v_r.colour_code,v_worker,nullif(public.rr_upm_effective_identity_v200()->>'effective_auth_user_id','')::uuid,v_r.worker_name_snapshot,'LINE_MAN','STAFF_CUSTODY',p_receipt_batch_id,null,null,v_r.assignment_id,null);
    else
      update public.rr_upm_work_assignments_v8 set status='IN_PROGRESS',updated_at=now() where id=v_r.assignment_id and status='ASSIGNED';
      perform public.rr_upm_set_custody_v204(v_r.canonical_lot_id,v_r.colour_code,v_worker,nullif(public.rr_upm_effective_identity_v200()->>'effective_auth_user_id','')::uuid,v_r.worker_name_snapshot,'WORKER','WORK_IN_PROGRESS',p_receipt_batch_id,null,null,v_r.assignment_id,null);
    end if;
  end loop;
  if v_fabrication and not v_has_short then
    select a.canonical_lot_id into v_a
    from public.rr_upm_work_assignments_v8 a
    where a.assignment_batch_id=p_receipt_batch_id limit 1;
    if v_a.canonical_lot_id is not null then perform public.rr_upm_sync_colour_queue_v741(v_a.canonical_lot_id);end if;
  end if;
  return jsonb_build_object(
    'ok',true,'version','V321_BATCH_RECEIPT_CANONICAL_IDENTITY','receipt_batch_id',p_receipt_batch_id,
    'expected_qty',v_expected,'confirmed_qty',v_confirmed,'short_qty',greatest(v_expected-v_confirmed,0),
    'auto_note',v_auto_note,'status',case when v_has_short then 'DISPUTED' else 'CONFIRMED' end,
    'work_status',case when v_has_short then 'OPEN' when v_fabrication then 'CLOSE' else 'WORKING' end,
    'claims',v_claims
  );
end
$function$;

comment on function public.rr_upm_my_pending_receipts_v9112() is
'V321: pending receipts preserve raw historical identities and compare through rr_canonical_worker_id_v264.';
comment on function public.rr_upm_confirm_assignment_receipt_batch_v204(uuid,jsonb,text) is
'V321: receipt confirmation keeps backend authority while accepting canonical worker/auth aliases.';

commit;
