-- TEST71 adapter only; shared legacy production functions remain unchanged.
CREATE OR REPLACE FUNCTION public.rr_chat_department_projection_test71(p_department_code text,p_status text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare d text:=public.rr_upm_core_department_v9077(p_department_code); s text:=upper(p_status);
 payload jsonb; cards jsonb:='[]'; x jsonb; dep text; a public.rr_upm_work_assignments_v8%rowtype; q public.rr_upm_submit_requests_v794%rowtype; rate_missing boolean;
begin
 perform public.rr_assert_active_user_v1();
 if auth.uid() is null then raise exception 'Login required.';end if;
 if s not in('OPEN','WORKING','CLOSE') then raise exception 'Invalid queue.';end if;
 if s='CLOSE' then return public.rr_real_chat_department_projection_v709(d,s);end if;
 if d='FABRICATION' and s='WORKING' then
  foreach dep in array array['PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING'] loop
   payload:=public.rr_chat_department_projection_test71(dep,s); cards:=cards||coalesce(payload->'cards','[]');
  end loop;
 else
  payload:=public.rr_real_chat_department_projection_v709(d,s);
  for x in select value from jsonb_array_elements(coalesce(payload->'cards','[]')) loop
   if s='OPEN' then
    -- OPEN is exclusively unassigned goods; initial receipt work is WORKING.
    if not exists(select 1 from jsonb_array_elements(coalesce(x->'actions','[]')) z where coalesce(z->>'code',z#>>'{}')='ASSIGN_WORKER') then continue;end if;
    if public.rr_upm_lot_is_terminal_v125(x->>'lot_no') then continue;end if;
    if d in('PRINTING','STICKER','METAL_ID') and not public.rr_upm_lot_department_applicable_v9167(x->>'lot_no',d) then continue;end if;
    cards:=cards||jsonb_build_array(x||jsonb_build_object('resolved_work_state','READY_TO_ASSIGN','work_category','READY_TO_ASSIGN'));
   else
    select * into a from public.rr_upm_work_assignments_v8 where id::text=x->>'assignment_id';
    -- Any live submit supersedes the source assignment, including DISPUTED.
    if a.id is not null and exists(select 1 from public.rr_upm_submit_requests_v794 z where a.id=any(z.assignment_ids) and upper(z.status) not in('CANCELLED','CANCELED','REJECTED','VOID')) then continue;end if;
    cards:=cards||jsonb_build_array(x||jsonb_strip_nulls(jsonb_build_object('worker_id',a.worker_id,'worker_name',a.worker_name_snapshot,'source_type',a.source_type,'pending_actor_name',a.worker_name_snapshot)));
   end if;
  end loop;
  if s='WORKING' then
   payload:=public.rr_real_chat_department_operational_v685(d,'OPEN');
   for x in select value from jsonb_array_elements(coalesce(payload->'cards','[]')) loop
    if not exists(select 1 from jsonb_array_elements(coalesce(x->'actions','[]')) z where coalesce(z->>'code',z#>>'{}')='CONFIRM_RECEIVED_PCS') then continue;end if;
    select * into a from public.rr_upm_work_assignments_v8 where id::text=x->>'assignment_id';
    if a.id is null or exists(select 1 from public.rr_upm_submit_requests_v794 z where a.id=any(z.assignment_ids) and upper(z.status) not in('CANCELLED','CANCELED','REJECTED','VOID')) then continue;end if;
    cards:=cards||jsonb_build_array(x||jsonb_build_object('worker_id',a.worker_id,'worker_name',a.worker_name_snapshot,'source_type',a.source_type,'resolved_work_state','WORKING','work_category','RECEIPT_PENDING','queue_lane','WORKER','pending_actor_name',a.worker_name_snapshot,'next_action','ASSIGNED RECEIPT / COUNT','receipt_kind','ASSIGNED_GOODS','qty',x->'expected_qty','message','Assigned माल · receipt/count बाकी · इसके बाद Worker Submit'));
   end loop;
  end if;
 end if;
 if s='WORKING' then
  for q in select * from public.rr_upm_submit_requests_v794 z where public.rr_upm_core_department_v9077(coalesce(z.target_department_code,'FABRICATION'))=d and z.status in('WAITING_LM','ESCALATED','LM_ACCEPTED','DISPUTED') loop
   rate_missing:=public.rr_costing_canonical_department_v760(q.department_code)<>'PRINTING' and exists(select 1 from public.rr_upm_work_assignments_v8 z where z.canonical_lot_id=q.canonical_lot_id and public.rr_upm_core_department_v9077(z.department_code)=public.rr_upm_core_department_v9077(q.department_code) and z.status not in('CANCELLED','CANCELED','REJECTED','VOID') and coalesce(z.actual_rate,0)<=0);
   cards:=cards||jsonb_build_array(jsonb_build_object('rate_pending',rate_missing,'assignment_ids',q.assignment_ids,'event_key','FAB_RECEIVE:'||q.id,'canonical_lot_id',q.canonical_lot_id,'lot_no',q.lot_no,'department_code',d,'source_department_code',q.department_code,'worker_id',q.selected_receiver_worker_id,'worker_name',q.selected_receiver_name,'pending_actor_name',coalesce(q.selected_receiver_name,'Fabrication Staff'),'submit_request_id',q.id,'submit_status',case when q.status='DISPUTED' then 'DISPUTED' else 'NOT_ACCEPTED' end,'resolved_work_state',case when q.status='DISPUTED' then 'DECISION_PENDING' else 'WORKING' end,'accept_count_complete',false,'queue_lane','STAFF','receipt_kind','SUBMITTED_HANDOVER','work_category','RECEIPT_PENDING','qty',q.worker_ready_total,'message',case when q.status='DISPUTED' then 'Short / Excess final decision बाकी · Not Accepted' else case when rate_missing then 'Actual Rate बाकी · ' else '' end||coalesce(q.worker_name,'Worker')||' ने Submit किया · Staff Accept & Count बाकी · इसके बाद Open assignment' end,'actions',case when q.status='DISPUTED' then '[]'::jsonb else (case when rate_missing then jsonb_build_array(jsonb_build_object('code','FILL_ACTUAL_RATE','label','FILL ACTUAL RATE','department_code',q.department_code,'canonical_lot_id',q.canonical_lot_id)) else '[]'::jsonb end)||jsonb_build_array(jsonb_build_object('code','ACCEPT_AND_COUNT','label','ACCEPT & COUNT','request_id',q.id)) end));
  end loop;
 end if;
 return jsonb_build_object('version','TEST71_ACTION_QUEUE_CONTRACT','department_code',d,'status',s,'cards',cards,'count',jsonb_array_length(cards));
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_department_projection_test71(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_department_projection_test71(text,text) TO authenticated;

-- Do not persist a claim when opening. Null-target legacy handovers default to
-- the same shared Fabrication receiver policy used by preparation/projection.
CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.accept_queue_handover(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare q public.rr_upm_submit_requests_v794%rowtype; rate_missing boolean;
begin
 perform public.rr_chat_prepare_accept_count_test71(p_request_id);
 select * into q from public.rr_upm_submit_requests_v794 where id=p_request_id for update;
 if q.target_department_code is null then
  update public.rr_upm_submit_requests_v794 set target_department_code='FABRICATION' where id=q.id;
 end if;
 return public.rr_upm_accept_submit_authorized_v770(p_request_id);
end $$;
REVOKE ALL ON FUNCTION rr_chat_notifications_test71.accept_queue_handover(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_chat_accept_count_test71(p_request_id uuid,p_count_rows jsonb,p_material_rows jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare q public.rr_upm_submit_requests_v794%rowtype; rate_missing boolean; prepared jsonb; result jsonb;
 c jsonb; z jsonb; x jsonb; n int; qty numeric;
begin
 select * into q from public.rr_upm_submit_requests_v794 where id=p_request_id for update;
 prepared:=public.rr_chat_prepare_accept_count_test71(p_request_id);
 if prepared->>'status'='COMPLETED' then
  return prepared||jsonb_build_object('duplicate_blocked',true,'target_department_code',q.target_department_code);
 end if;
 if jsonb_typeof(p_count_rows) is distinct from 'array' or jsonb_array_length(p_count_rows)=0 then raise exception 'Count required for every colour and size.'; end if;
 if jsonb_typeof(q.colour_rows) is distinct from 'array' or jsonb_array_length(q.colour_rows)=0 then raise exception 'Receive colours unavailable.'; end if;
 n:=0;
 for c in select value from jsonb_array_elements(q.colour_rows) loop
  if jsonb_typeof(c->'sizes') is distinct from 'array' or jsonb_array_length(c->'sizes')=0 then raise exception 'Size-wise count mapping required.'; end if;
  for z in select value from jsonb_array_elements(c->'sizes') loop
   if (select count(*) from jsonb_array_elements(p_count_rows) a where upper(a->>'colour_code')=upper(c->>'colour_code') and upper(a->>'size_code')=upper(z->>'size_code'))<>1 then
    raise exception 'One Count required for % / %.',c->>'colour_code',z->>'size_code';
   end if;
   select a into x from jsonb_array_elements(p_count_rows) a where upper(a->>'colour_code')=upper(c->>'colour_code') and upper(a->>'size_code')=upper(z->>'size_code');
   qty:=nullif(trim(x->>'qty'),'')::numeric;
   if qty is null or qty<0 or qty<>trunc(qty) or qty::text in('NaN','Infinity','-Infinity') then raise exception 'Whole non-negative Count required for % / %.',c->>'colour_code',z->>'size_code'; end if;
   n:=n+1;
  end loop;
 end loop;
 if n<>jsonb_array_length(p_count_rows) then raise exception 'Unexpected colour or size in Count.'; end if;
 if jsonb_typeof(p_material_rows) is distinct from 'array' then raise exception 'Material rows array required.'; end if;
 for x in select value from jsonb_array_elements(p_material_rows) loop
  if ((x->>'assignment_id')::uuid=any(q.assignment_ids)) is distinct from true then raise exception 'Material assignment must belong to this handover.'; end if;
  qty:=nullif(x->>'consumed_qty','')::numeric;
  if qty is null or qty<=0 or qty::text in('NaN','Infinity','-Infinity') then raise exception 'Consumed material quantity required.'; end if;
 end loop;
 perform rr_chat_notifications_test71.accept_queue_handover(p_request_id);
 result:=public.rr_upm_lm_count_submit_v328(p_request_id,p_count_rows);
 -- Preserve the existing Short/Excess decision authority. A disputed count is
 -- explicitly NOT an Accepted/completed handover and does not advance stock.
 if result->>'status'='COMPLETED' then
  for x in select value from jsonb_array_elements(p_material_rows) loop
   perform public.rr_material_direct_confirm_v658((x->>'assignment_id')::uuid,(x->>'mapping_id')::uuid,(x->>'consumed_qty')::numeric,'TEST');
  end loop;
 elsif result->>'status' is distinct from 'DISPUTED' then raise exception 'Accept & Count did not reach a valid final state.';
 end if;
 return result||jsonb_build_object('accept_count_complete',result->>'status'='COMPLETED',
  'acceptance_status',case when result->>'status'='COMPLETED' then 'ACCEPTED' else 'NOT_ACCEPTED' end);
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_accept_count_test71(uuid,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_accept_count_test71(uuid,jsonb,jsonb) TO authenticated;

