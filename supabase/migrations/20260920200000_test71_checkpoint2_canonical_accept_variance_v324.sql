-- Accepted physical quantity stays operational while variance is separate.
create unique index if not exists rr_upm_excess_count_v224_assignment_unique
on public.rr_upm_excess_count_v224(assignment_id);

create or replace function public.rr_upm_record_excess_count_v224(
 p_assignment_id uuid,p_counted_qty numeric,p_worker_id text default null,p_worker_name text default null
) returns jsonb language plpgsql security definer set search_path='public' as $$
declare a public.rr_upm_work_assignments_v8%rowtype;r public.rr_upm_assignment_receipts_v9112%rowtype;
 v_expected numeric;v_excess numeric;v_effective uuid:=public.rr_upm_current_worker_id_v9112();
begin
 if auth.uid() is null or v_effective is null then raise exception 'Effective worker identity is required.';end if;
 select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment_id for update;
 select * into r from public.rr_upm_assignment_receipts_v9112 where assignment_id=p_assignment_id order by created_at desc limit 1;
 if not found then raise exception 'Assignment receipt not found.';end if;
 if public.rr_canonical_worker_id_v264(r.worker_id)<>v_effective
   or public.rr_canonical_worker_id_v264(coalesce(nullif(p_worker_id,'')::uuid,v_effective))<>v_effective
 then raise exception 'Only the mapped effective receiver can record excess.';end if;
 v_expected:=coalesce(r.expected_qty,a.assigned_qty,0);v_excess:=p_counted_qty-v_expected;
 if v_excess<=0 then raise exception 'Excess requires counted Qty greater than expected %',v_expected;end if;
 insert into public.rr_upm_excess_count_v224(
  assignment_id,receipt_batch_id,canonical_lot_id,lot_no,department_code,colour_code,
  expected_qty,counted_qty,excess_qty,counted_by,counted_worker_id,counted_worker_name,payload
 ) values(a.id,r.receipt_batch_id,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,
  v_expected,p_counted_qty,v_excess,auth.uid(),v_effective::text,coalesce(nullif(p_worker_name,''),a.worker_name_snapshot),
  jsonb_build_object('type','EXCESS','expected',v_expected,'accepted',p_counted_qty,'difference',v_excess,
   'colour',a.colour_code,'actor_auth_user_id',auth.uid(),'assigner_auth_user_id',a.assigned_by,
   'receiver_worker_id',v_effective,'responsible_worker_id',v_effective,
   'resolution','GOOD_IMMEDIATE_MERGE','recorded_at',now()))
 on conflict(assignment_id) do update set receipt_batch_id=excluded.receipt_batch_id,
  counted_qty=excluded.counted_qty,excess_qty=excluded.excess_qty,counted_by=excluded.counted_by,
  counted_worker_id=excluded.counted_worker_id,counted_worker_name=excluded.counted_worker_name,payload=excluded.payload;
 return jsonb_build_object('ok',true,'assignment_id',a.id,'expected_qty',v_expected,
  'counted_qty',p_counted_qty,'excess_qty',v_excess,'good_qty',p_counted_qty,
  'colour_code',a.colour_code,'resolution','GOOD_IMMEDIATE_MERGE');
end$$;

create or replace function public.rr_upm_confirm_assignment_receipt_batch_v204(
 p_receipt_batch_id uuid,p_rows jsonb,p_note text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_worker uuid:=public.rr_upm_current_worker_id_v9112();v_pending int;v_total int;v_input int;
 v_expected numeric:=0;v_accepted numeric:=0;v_short numeric:=0;v_excess numeric:=0;
 v_row jsonb;v_r record;v_lot text;v_claims jsonb:='[]';v_excesses jsonb:='[]';v_fabrication boolean:=false;
begin
 if auth.uid() is null or v_worker is null then raise exception 'Effective worker identity is required.';end if;
 if p_receipt_batch_id is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0
 then raise exception 'Complete receipt batch count is required.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_receipt_batch_id::text,204));v_input:=jsonb_array_length(p_rows);
 select count(*),count(*) filter(where upper(r.status) in('PENDING','DISPUTED')) into v_total,v_pending
 from public.rr_upm_assignment_receipts_v9112 r where r.receipt_batch_id=p_receipt_batch_id
 and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker;
 if v_pending=0 then
  if v_input=v_total and not exists(select 1 from jsonb_array_elements(p_rows)x
   left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=nullif(x->>'assignment_id','')::uuid
   and r.receipt_batch_id=p_receipt_batch_id and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker
   where upper(coalesce(r.status,''))<>'CONFIRMED' or r.confirmed_qty<>(x->>'confirmed_qty')::numeric) then
   select coalesce(sum(expected_qty),0),coalesce(sum(confirmed_qty),0) into v_expected,v_accepted
   from public.rr_upm_assignment_receipts_v9112 r where r.receipt_batch_id=p_receipt_batch_id
   and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker;
   return jsonb_build_object('ok',true,'already_applied',true,'receipt_batch_id',p_receipt_batch_id,
    'expected_qty',v_expected,'confirmed_qty',v_accepted,'short_qty',greatest(v_expected-v_accepted,0),
    'excess_qty',greatest(v_accepted-v_expected,0),'status','CONFIRMED','work_status','WORKING');
  end if;raise exception 'Receipt batch is not pending for this worker.';
 end if;
 if v_input<>v_pending then raise exception 'Count every colour in this atomic handover together (% required).',v_pending;end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  select r.*,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,a.worker_name_snapshot,
   a.assigned_by,a.status assignment_status into v_r
  from public.rr_upm_assignment_receipts_v9112 r join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
  where r.assignment_id=nullif(v_row->>'assignment_id','')::uuid and r.receipt_batch_id=p_receipt_batch_id
   and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker and upper(r.status) in('PENDING','DISPUTED')
  for update of r,a;
  if not found then raise exception 'Receipt row does not belong to this pending handover.';end if;
  if nullif(v_row->>'confirmed_qty','') is null or (v_row->>'confirmed_qty')::numeric<0
  then raise exception 'Accepted physical count for % must be zero or greater.',v_r.colour_code;end if;
  v_expected:=v_expected+v_r.expected_qty;v_accepted:=v_accepted+(v_row->>'confirmed_qty')::numeric;
  v_short:=v_short+greatest(v_r.expected_qty-(v_row->>'confirmed_qty')::numeric,0);
  v_excess:=v_excess+greatest((v_row->>'confirmed_qty')::numeric-v_r.expected_qty,0);
  v_fabrication:=v_fabrication or public.rr_upm_core_department_v9077(v_r.department_code)='FABRICATION';
 end loop;
 if (v_short>0 or v_excess>0) and nullif(trim(coalesce(p_note,'')),'') is null
 then raise exception 'Short / Excess remarks required.';end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  select r.*,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,a.worker_name_snapshot,a.assigned_by,
   a.assigned_by_name into v_r from public.rr_upm_assignment_receipts_v9112 r
  join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id where r.assignment_id=(v_row->>'assignment_id')::uuid;
  v_lot:=v_r.canonical_lot_id;
  update public.rr_upm_assignment_receipts_v9112 set confirmed_qty=(v_row->>'confirmed_qty')::numeric,
   status='CONFIRMED',confirmed_at=coalesce(confirmed_at,now()),confirmed_by=auth.uid(),note=p_note
  where assignment_id=v_r.assignment_id;
  if (v_row->>'confirmed_qty')::numeric<v_r.expected_qty then
   v_claims:=v_claims||jsonb_build_array(public.rr_upm_register_custody_missing_v185(v_r.assignment_id,
    v_r.expected_qty,(v_row->>'confirmed_qty')::numeric,
    coalesce(v_r.source_custodian_worker_id,v_r.source_custodian_auth_id)::text,
    coalesce(v_r.source_custodian_name,'Previous Custodian'),coalesce(v_r.source_custodian_role,'STAFF'),'ASSIGN_RECEIPT'));
   update public.rr_upm_missing_qty_v800 m set payload=coalesce(m.payload,'{}')||jsonb_build_object(
    'type','SHORT','expected',v_r.expected_qty,'accepted',(v_row->>'confirmed_qty')::numeric,
    'difference',v_r.expected_qty-(v_row->>'confirmed_qty')::numeric,'colour',v_r.colour_code,
    'actor_auth_user_id',auth.uid(),'assigner_auth_user_id',v_r.assigned_by,'receiver_worker_id',v_worker,
    'remarks',p_note,'recorded_at',now()) where m.assignment_id=v_r.assignment_id::text
    and upper(m.colour_code)=upper(v_r.colour_code) and m.size_code='ASSIGN_ALL';
  elsif (v_row->>'confirmed_qty')::numeric>v_r.expected_qty then
   v_excesses:=v_excesses||jsonb_build_array(public.rr_upm_record_excess_count_v224(v_r.assignment_id,
    (v_row->>'confirmed_qty')::numeric,v_worker::text,v_r.worker_name_snapshot));
  end if;
  if public.rr_upm_core_department_v9077(v_r.department_code)='FABRICATION' then
   update public.rr_upm_work_assignments_v8 set status='COMPLETED',completed_at=coalesce(completed_at,now()),updated_at=now() where id=v_r.assignment_id;
   perform public.rr_upm_set_custody_v204(v_r.canonical_lot_id,v_r.colour_code,v_worker,
    nullif(public.rr_upm_effective_identity_v200()->>'effective_auth_user_id','')::uuid,v_r.worker_name_snapshot,
    'LINE_MAN','STAFF_CUSTODY',p_receipt_batch_id,null,null,v_r.assignment_id,null);
  else
   update public.rr_upm_work_assignments_v8 set status='IN_PROGRESS',updated_at=now() where id=v_r.assignment_id and status in('ASSIGNED','IN_PROGRESS');
   perform public.rr_upm_set_custody_v204(v_r.canonical_lot_id,v_r.colour_code,v_worker,
    nullif(public.rr_upm_effective_identity_v200()->>'effective_auth_user_id','')::uuid,v_r.worker_name_snapshot,
    'WORKER','WORK_IN_PROGRESS',p_receipt_batch_id,null,null,v_r.assignment_id,null);
  end if;
 end loop;
 if v_fabrication and v_lot is not null then perform public.rr_upm_sync_colour_queue_v741(v_lot);end if;
 return jsonb_build_object('ok',true,'version','V324_ACCEPTED_VARIANCE_WORKING','receipt_batch_id',p_receipt_batch_id,
  'expected_qty',v_expected,'confirmed_qty',v_accepted,'short_qty',v_short,'excess_qty',v_excess,
  'status','CONFIRMED','work_status',case when v_fabrication then 'CLOSE' else 'WORKING' end,
  'claims',v_claims,'excesses',v_excesses);
end$$;

create or replace function public.rr_upm_assignment_operational_qty_v280(p_assignment_id uuid)
returns jsonb language sql stable security definer set search_path='public' as $$
select coalesce((select jsonb_build_object(
 'assignment_id',a.id,'canonical_lot_id',a.canonical_lot_id,'lot_no',a.lot_no,
 'department_code',public.rr_upm_core_department_v9077(a.department_code),
 'worker_id',public.rr_canonical_worker_id_v264(a.worker_id),'worker_name',a.worker_name_snapshot,
 'assignment_status',a.status,'assigned_qty',coalesce(a.assigned_qty,0),
 'good_qty',case when r.status='CONFIRMED' and r.confirmed_qty is not null then r.confirmed_qty else coalesce(m.submitted_good_qty,a.inbound_qty,a.assigned_qty,0) end,
 'accepted_qty',r.confirmed_qty,'expected_qty',r.expected_qty,'colour_code',a.colour_code,
 'short_qty',case when r.status='CONFIRMED' then greatest(coalesce(r.expected_qty,0)-coalesce(r.confirmed_qty,0),0) else 0 end,
 'found_qty',coalesce((m.payload->>'found_qty')::numeric,0),'confirmed_short_qty',coalesce(m.confirmed_short_qty,0),
 'recovery_pending_qty',coalesce(m.recovery_pending_qty,0),'unresolved_short_qty',coalesce((m.payload->>'unresolved_short_qty')::numeric,0),
 'excess_qty',coalesce(e.excess_qty,0),'dispute_resolved',r.status='CONFIRMED',
 'operational_receipt_status',coalesce(r.status,'PENDING'),
 'main_card_actions',case when (case when r.status='CONFIRMED' then coalesce(r.confirmed_qty,0) else coalesce(m.submitted_good_qty,a.inbound_qty,a.assigned_qty,0) end)>0 then jsonb_build_array('SUBMIT','ALTER','RECTIFY') else '[]'::jsonb end,
 'short_excess_accept_qty',coalesce(m.recovery_pending_qty,0),
 'quantity_rule','CONFIRMED_PHYSICAL_QTY_IS_OPERATIONAL; ASSIGNED_QTY_IS_HISTORY')
 from public.rr_upm_work_assignments_v8 a
 left join lateral(select * from public.rr_upm_assignment_receipts_v9112 x where x.assignment_id=a.id order by x.confirmed_at desc nulls last,x.created_at desc limit 1)r on true
 left join lateral(select * from public.rr_upm_missing_qty_v800 x where x.assignment_id=a.id::text order by x.updated_at desc limit 1)m on true
 left join lateral(select * from public.rr_upm_excess_count_v224 x where x.assignment_id=a.id order by x.created_at desc limit 1)e on true
 where a.id=p_assignment_id limit 1),'{}'::jsonb)
$$;

revoke all on function public.rr_upm_record_excess_count_v224(uuid,numeric,text,text) from public,anon;
revoke all on function public.rr_upm_confirm_assignment_receipt_batch_v204(uuid,jsonb,text) from public,anon;
revoke all on function public.rr_upm_assignment_operational_qty_v280(uuid) from public,anon;
grant execute on function public.rr_upm_record_excess_count_v224(uuid,numeric,text,text) to authenticated;
grant execute on function public.rr_upm_confirm_assignment_receipt_batch_v204(uuid,jsonb,text) to authenticated;
grant execute on function public.rr_upm_assignment_operational_qty_v280(uuid) to authenticated;

-- Every UI mirror reads accepted physical quantity and variance from this one projection.
create or replace view public.rr_upm_worker_operational_work_v280 as
select a.id assignment_id,a.canonical_lot_id,a.lot_no,
 public.rr_upm_core_department_v9077(a.department_code) department_code,
 public.rr_canonical_worker_id_v264(a.worker_id) worker_id,a.colour_code,a.status,
 coalesce((public.rr_upm_assignment_operational_qty_v280(a.id)->>'good_qty')::numeric,0) good_qty,
 coalesce((public.rr_upm_assignment_operational_qty_v280(a.id)->>'found_qty')::numeric,0) found_qty,
 coalesce((public.rr_upm_assignment_operational_qty_v280(a.id)->>'confirmed_short_qty')::numeric,0) confirmed_short_qty,
 coalesce((public.rr_upm_assignment_operational_qty_v280(a.id)->>'short_excess_accept_qty')::numeric,0) short_excess_accept_qty,
 public.rr_upm_assignment_operational_qty_v280(a.id)->>'operational_receipt_status' receipt_status,
 coalesce((public.rr_upm_assignment_operational_qty_v280(a.id)->>'expected_qty')::numeric,a.assigned_qty,0) expected_qty,
 (public.rr_upm_assignment_operational_qty_v280(a.id)->>'accepted_qty')::numeric accepted_qty,
 coalesce((public.rr_upm_assignment_operational_qty_v280(a.id)->>'excess_qty')::numeric,0) excess_qty,
 coalesce((public.rr_upm_assignment_operational_qty_v280(a.id)->>'short_qty')::numeric,0) short_qty
from public.rr_upm_work_assignments_v8 a;

create or replace function public.rr_real_chat_operational_work_v319(
 p_worker_id uuid,p_status text default 'WORKING',p_department_code text default null
) returns jsonb language sql stable security definer set search_path='public' as $$
with id as(select public.rr_canonical_worker_id_v264(p_worker_id) worker_id),a as(
 select x.*,r.status receipt_status2,e.id event_id,s.id submit_request_id,s.status submit_status,s.selected_receiver_name
 from id join public.rr_upm_worker_operational_work_v280 x on x.worker_id=id.worker_id
 left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=x.assignment_id
 left join lateral(select q.id from public.rr_upm_responsibility_events_v800 q where q.assignment_id=x.assignment_id::text
  and q.event_type='ASSIGN_HANDOVER' order by q.created_at desc limit 1)e on true
 left join lateral(select q.id,q.status,q.selected_receiver_name from public.rr_upm_submit_requests_v794 q
  where x.assignment_id=any(q.assignment_ids) and upper(q.status) in('WAITING_LM','ESCALATED','LM_ACCEPTED','LM_COUNTED','COMPLETED')
  order by q.updated_at desc nulls last,q.created_at desc limit 1)s on true
 where p_department_code is null or x.department_code=public.rr_upm_core_department_v9077(p_department_code)
),w as(select *,case when receipt_status2='PENDING' then 'ACCEPT_PENDING' when submit_request_id is not null then 'CLOSE'
 when receipt_status2='CONFIRMED' and status='IN_PROGRESS' then 'WORKING' when status in('COMPLETED','CANCELLED') then 'CLOSE'
 when receipt_status2 is null then 'LEGACY' else status end resolved from a),f as(select * from w where case upper(coalesce(p_status,'WORKING'))
 when 'OPEN' then resolved='ACCEPT_PENDING' when 'WORKING' then resolved='WORKING' or(resolved='LEGACY' and status in('ASSIGNED','IN_PROGRESS'))
 when 'CLOSE' then resolved='CLOSE' else true end)
select jsonb_build_object('version','V324_ACCEPTED_VARIANCE_MIRROR','worker_id',(select worker_id from id),
 'status',upper(coalesce(p_status,'WORKING')),'cards',coalesce(jsonb_agg(jsonb_build_object(
  'assignment_id',assignment_id,'canonical_lot_id',canonical_lot_id,'lot_no',lot_no,'department_code',department_code,
  'colour_code',colour_code,'assignment_status',status,'resolved_work_state',resolved,'good_qty',good_qty,'qty',good_qty,
  'expected_qty',expected_qty,'accepted_qty',accepted_qty,'receipt_status',coalesce(receipt_status2,receipt_status),
  'responsibility_event_id',event_id,'submit_request_id',submit_request_id,'submit_status',submit_status,
  'message',case when resolved='ACCEPT_PENDING' then 'काम मिला · Accept & Count बाकी' when resolved='WORKING' then 'काम जारी है'
   when resolved='CLOSE' and submit_request_id is not null then 'काम जमा किया'||case when nullif(selected_receiver_name,'') is not null then ' · '||selected_receiver_name||' को count pending' else '' end else null end,
  'actions',case when resolved='ACCEPT_PENDING' and event_id is not null then jsonb_build_array('CONFIRM_RECEIVED_PCS')
   when resolved in('WORKING','LEGACY') and good_qty>0 then jsonb_build_array('SUBMIT','ALTER','RECTIFY') else '[]'::jsonb end,
  'short_excess_accept',case when short_excess_accept_qty>0 then jsonb_build_object('type','SHORT','qty',short_excess_accept_qty,'action','ACCEPT','journey','SHORT_EXCESS_RECOVERY','colour_code',colour_code) end,
  'variance',case when excess_qty>0 then jsonb_build_object('type','EXCESS','qty',excess_qty,'expected',expected_qty,'accepted',accepted_qty,'colour_code',colour_code,'action',null)
   when short_qty>0 then jsonb_build_object('type','SHORT','qty',short_qty,'expected',expected_qty,'accepted',accepted_qty,'colour_code',colour_code,'action',null) end
 ) order by lot_no,colour_code,assignment_id),'[]'::jsonb),'count',count(*),'good_total',coalesce(sum(good_qty),0)) from f
$$;

revoke all on function public.rr_real_chat_operational_work_v319(uuid,text,text) from public,anon;
grant execute on function public.rr_real_chat_operational_work_v319(uuid,text,text) to authenticated;
