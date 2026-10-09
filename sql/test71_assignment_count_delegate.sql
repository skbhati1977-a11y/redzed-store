CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.confirm_assignment_batch(p_worker_id uuid,p_receipt_batch_id uuid, p_rows jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_worker uuid:=p_worker_id;v_pending int;v_input int;v_expected numeric:=0;v_accepted numeric:=0;v_short numeric:=0;v_excess numeric:=0;v_row jsonb;v_r record;v_lot text;v_claims jsonb:='[]';v_excesses jsonb:='[]';v_remaining int;
begin
 perform public.rr_assert_active_user_v1();
 if not public.rr_upm_fabrication_receiver_allowed_v770() and public.rr_upm_current_worker_id_v9112() is distinct from v_worker and not exists(select 1 from public.rr_upm_assignment_receipts_v9112 r where r.receipt_batch_id=p_receipt_batch_id and public.rr_upm_team_assignment_action_allowed_v774(r.assignment_id,public.rr_upm_current_worker_id_v9112())) then raise exception 'Assigned worker or authorized staff required.';end if;
 if auth.uid() is null or v_worker is null then raise exception 'Effective worker identity is required.';end if;
 if p_receipt_batch_id is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one colour to accept.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_receipt_batch_id::text,204));v_input:=jsonb_array_length(p_rows);
 select count(*) filter(where upper(r.status) in('PENDING','DISPUTED')) into v_pending from public.rr_upm_assignment_receipts_v9112 r where r.receipt_batch_id=p_receipt_batch_id and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker;
 if v_pending=0 then raise exception 'Receipt batch is not pending for this worker.';end if;
 if v_input>v_pending then raise exception 'Selected receipt rows exceed pending colours.';end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  select r.*,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,a.worker_name_snapshot,a.assigned_by,a.assigned_by_name into v_r from public.rr_upm_assignment_receipts_v9112 r join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id where r.assignment_id=nullif(v_row->>'assignment_id','')::uuid and r.receipt_batch_id=p_receipt_batch_id and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker and upper(r.status) in('PENDING','DISPUTED') for update of r,a;
  if not found then raise exception 'Selected receipt row does not belong to this pending handover.';end if;
  if nullif(v_row->>'confirmed_qty','') is null or (v_row->>'confirmed_qty')::numeric<0 then raise exception 'Accepted physical count for % must be zero or greater.',v_r.colour_code;end if;
  v_expected:=v_expected+v_r.expected_qty;v_accepted:=v_accepted+(v_row->>'confirmed_qty')::numeric;v_short:=v_short+greatest(v_r.expected_qty-(v_row->>'confirmed_qty')::numeric,0);v_excess:=v_excess+greatest((v_row->>'confirmed_qty')::numeric-v_r.expected_qty,0);v_lot:=v_r.canonical_lot_id;
 end loop;
 if (v_short>0 or v_excess>0) and nullif(trim(coalesce(p_note,'')),'') is null then raise exception 'Short / Excess remarks required.';end if;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  select r.*,a.canonical_lot_id,a.lot_no,a.department_code,a.colour_code,a.worker_name_snapshot,a.assigned_by,a.assigned_by_name into v_r from public.rr_upm_assignment_receipts_v9112 r join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id where r.assignment_id=(v_row->>'assignment_id')::uuid;
  update public.rr_upm_assignment_receipts_v9112 set confirmed_qty=(v_row->>'confirmed_qty')::numeric,status='CONFIRMED',confirmed_at=coalesce(confirmed_at,now()),confirmed_by=auth.uid(),note=p_note where assignment_id=v_r.assignment_id and upper(status) in('PENDING','DISPUTED');
  if (v_row->>'confirmed_qty')::numeric<v_r.expected_qty then v_claims:=v_claims||jsonb_build_array(public.rr_upm_register_custody_missing_v185(v_r.assignment_id,v_r.expected_qty,(v_row->>'confirmed_qty')::numeric,coalesce(v_r.source_custodian_worker_id,v_r.source_custodian_auth_id)::text,coalesce(v_r.source_custodian_name,'Previous Custodian'),coalesce(v_r.source_custodian_role,'STAFF'),'ASSIGN_RECEIPT'));
  elsif (v_row->>'confirmed_qty')::numeric>v_r.expected_qty then v_excesses:=v_excesses||jsonb_build_array(public.rr_upm_record_excess_count_v224(v_r.assignment_id,(v_row->>'confirmed_qty')::numeric,v_worker::text,v_r.worker_name_snapshot));end if;
  update public.rr_upm_work_assignments_v8 set status='IN_PROGRESS',updated_at=now() where id=v_r.assignment_id and status in('ASSIGNED','IN_PROGRESS');
  perform public.rr_upm_set_custody_v204(v_r.canonical_lot_id,v_r.colour_code,v_worker,(select linked_auth_user_id from public.rr_worker_directory_unified_v1 where worker_id=v_worker limit 1),v_r.worker_name_snapshot,'WORKER','WORK_IN_PROGRESS',p_receipt_batch_id,null,null,v_r.assignment_id,null);
 end loop;
 select count(*) into v_remaining from public.rr_upm_assignment_receipts_v9112 r where r.receipt_batch_id=p_receipt_batch_id and public.rr_canonical_worker_id_v264(r.worker_id)=v_worker and upper(r.status) in('PENDING','DISPUTED');
 return jsonb_build_object('ok',true,'version','V643_PARTIAL_COLOUR_ACCEPT','receipt_batch_id',p_receipt_batch_id,'expected_qty',v_expected,'confirmed_qty',v_accepted,'short_qty',v_short,'excess_qty',v_excess,'status',case when v_remaining=0 then 'CONFIRMED' else 'PARTIAL' end,'work_status','WORKING','remaining_pending_colours',v_remaining,'claims',v_claims,'excesses',v_excesses);
end $function$;

REVOKE ALL ON FUNCTION rr_chat_notifications_test71.confirm_assignment_batch(uuid,uuid,jsonb,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_chat_assignment_count_context_test71(p_assignment_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare a public.rr_upm_work_assignments_v8%rowtype; rows jsonb; worker uuid:=public.rr_upm_current_worker_id_v9112();
begin
 perform public.rr_assert_active_user_v1();
 if auth.uid() is null then raise exception 'Login required.';end if;
 if worker is null and not public.rr_upm_fabrication_receiver_allowed_v770() then raise exception 'Assigned worker mapping or authorized staff required.';end if;
 select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment_id;
 if a.id is null then raise exception 'Assignment missing.';end if;
 if not public.rr_upm_fabrication_receiver_allowed_v770() and worker is distinct from public.rr_canonical_worker_id_v264(a.worker_id) and not public.rr_upm_team_assignment_action_allowed_v774(a.id,worker) then raise exception 'Assigned worker or authorized staff required.';end if;
 select coalesce(jsonb_agg(jsonb_build_object('assignment_id',x.id,'receipt_batch_id',r.receipt_batch_id,'colour_code',x.colour_code,'expected_qty',r.expected_qty,'status',r.status) order by x.colour_code,x.id),'[]') into rows
 from public.rr_upm_work_assignments_v8 x join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=x.id
 where x.canonical_lot_id=a.canonical_lot_id and public.rr_upm_core_department_v9077(x.department_code)=public.rr_upm_core_department_v9077(a.department_code) and public.rr_canonical_worker_id_v264(x.worker_id)=public.rr_canonical_worker_id_v264(a.worker_id) and x.status in('ASSIGNED','IN_PROGRESS') and r.status in('PENDING','DISPUTED')
 and not exists(select 1 from public.rr_upm_submit_requests_v794 q where x.id=any(q.assignment_ids) and q.status not in('CANCELLED','CANCELED','REJECTED','VOID'));
 return jsonb_build_object('lot_no',a.lot_no,'canonical_lot_id',a.canonical_lot_id,'department_code',a.department_code,'worker_id',public.rr_canonical_worker_id_v264(a.worker_id),'rows',rows,'count',jsonb_array_length(rows));
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_assignment_count_context_test71(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_assignment_count_context_test71(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_chat_assignment_count_save_test71(p_assignment_id uuid,p_rows jsonb,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare ctx jsonb; x jsonb; b record; outrows jsonb:='[]'; worker uuid;
begin
 -- Serialize the whole worker/lot receipt Save before re-reading pending rows.
 select public.rr_canonical_worker_id_v264(worker_id) into worker from public.rr_upm_work_assignments_v8 where id=p_assignment_id;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('TEST71_RECEIPT:'||coalesce(worker::text,''),71));
 ctx:=public.rr_chat_assignment_count_context_test71(p_assignment_id);
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)=0 or jsonb_array_length(p_rows)<>jsonb_array_length(ctx->'rows') then raise exception 'Count required for every pending colour.';end if;
 for x in select value from jsonb_array_elements(ctx->'rows') loop
  if (select count(*) from jsonb_array_elements(p_rows) z where z->>'assignment_id'=x->>'assignment_id' and nullif(z->>'confirmed_qty','') is not null and (z->>'confirmed_qty')::numeric>=0 and (z->>'confirmed_qty')::numeric=trunc((z->>'confirmed_qty')::numeric) and (z->>'confirmed_qty')::numeric::text not in('NaN','Infinity','-Infinity'))<>1 then raise exception 'One whole non-negative Count required per colour.';end if;
 end loop;
 for b in select r.receipt_batch_id,jsonb_agg(z) rows from jsonb_array_elements(p_rows) z join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id::text=z->>'assignment_id' group by r.receipt_batch_id order by r.receipt_batch_id loop
  outrows:=outrows||jsonb_build_array(rr_chat_notifications_test71.confirm_assignment_batch((ctx->>'worker_id')::uuid,b.receipt_batch_id,b.rows,p_note));
 end loop;
 return jsonb_build_object('ok',true,'status','COMPLETED','accept_count_complete',true,'next_action','SUBMIT','results',outrows);
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_assignment_count_save_test71(uuid,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_assignment_count_save_test71(uuid,jsonb,text) TO authenticated;
