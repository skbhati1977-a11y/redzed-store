-- TEST71 only: opening the count form never claims or accepts a handover.
CREATE OR REPLACE FUNCTION public.rr_chat_prepare_accept_count_test71(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare q public.rr_upm_submit_requests_v794%rowtype;
 ctx jsonb:=public.rr_upm_effective_identity_v200();
 worker uuid:=public.rr_upm_current_worker_id_v9112();
 actor uuid:=nullif(ctx->>'effective_auth_user_id','')::uuid;
begin
 perform public.rr_assert_active_user_v1();
 if auth.uid() is null or worker is null then raise exception 'Login and effective worker identity required.'; end if;
 select * into q from public.rr_upm_submit_requests_v794 where id=p_request_id;
 if not found then raise exception 'Submit handover not found.'; end if;
 if public.rr_upm_core_department_v9077(coalesce(q.target_department_code,'FABRICATION'))='FABRICATION' then
  if not public.rr_upm_fabrication_receiver_allowed_v770() then raise exception 'Fabrication receive/count requires staff authority.'; end if;
 else
  if q.selected_receiver_worker_id is distinct from worker and q.selected_receiver_auth_id is distinct from actor
     and not exists(select 1 from public.rr_upm_submit_lm_candidates_v794 c where c.request_id=q.id and c.response_status='PENDING' and c.line_man_id in(worker,actor))
  then raise exception 'Only an eligible receiver can Accept & Count this handover.'; end if;
 end if;
 if q.accepted_lm_id is not null and q.accepted_lm_id is distinct from worker and q.accepted_lm_id is distinct from actor then
  raise exception 'This handover belongs to another receiver.';
 end if;
 if q.status not in('WAITING_LM','ESCALATED','LM_ACCEPTED','COMPLETED') then raise exception 'This handover requires its pending final decision.'; end if;
 return jsonb_build_object('ok',true,'request_id',q.id,'lot_no',q.lot_no,'colour_rows',q.colour_rows,
  'assignment_ids',q.assignment_ids,'worker_ready_total',q.worker_ready_total,
  'status',case when q.status='COMPLETED' then 'COMPLETED' else 'NOT_ACCEPTED' end,
  'accept_count_complete',q.status='COMPLETED');
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_prepare_accept_count_test71(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_prepare_accept_count_test71(uuid) TO authenticated;

-- Claim, full size-wise count, canonical next-stage transition and optional
-- material consumption share one transaction. Any error rolls back all steps.
CREATE OR REPLACE FUNCTION public.rr_chat_accept_count_test71(p_request_id uuid,p_count_rows jsonb,p_material_rows jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare q public.rr_upm_submit_requests_v794%rowtype; prepared jsonb; result jsonb;
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
 perform public.rr_upm_accept_submit_authorized_v770(p_request_id);
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

-- Fix only the TEST71 projection. Legacy incomplete claims stay actionable,
-- but never appear as Accepted; completed requests cannot return as pending.
CREATE OR REPLACE FUNCTION public.rr_chat_department_projection_test71(p_department_code text,p_status text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare payload jsonb; cards jsonb;
begin
 perform public.rr_assert_active_user_v1();
 payload:=public.rr_real_chat_department_projection_v709(p_department_code,p_status);
 select coalesce(jsonb_agg(x||jsonb_strip_nulls(jsonb_build_object('worker_id',a.worker_id,'worker_name',a.worker_name_snapshot,'source_type',a.source_type))||
  case when upper(p_status)='WORKING' and q.id is not null and upper(q.status) in('WAITING_LM','ESCALATED','LM_ACCEPTED')
   and exists(select 1 from jsonb_array_elements(coalesce(x->'actions','[]')) action where coalesce(action->>'code',action#>>'{}')='ACCEPT_AND_COUNT') then
   jsonb_build_object('submit_status','NOT_ACCEPTED','resolved_work_state','NOT_ACCEPTED','accept_count_complete',false,
    'message',coalesce(q.worker_name,'Worker')||' ने काम जमा किया · Accept & Count पूरा करना बाकी',
    'actions',jsonb_build_array(jsonb_build_object('code','ACCEPT_AND_COUNT','label','ACCEPT & COUNT','request_id',q.id)))
  when upper(p_status)='WORKING' and q.id is not null and upper(q.status)='DISPUTED' and x->>'assignment_id' is null then
   jsonb_build_object('accept_count_complete',false,'resolved_work_state','DECISION_PENDING','message','Short / Excess final decision बाकी · Not Accepted')
  else '{}'::jsonb end),'[]') into cards
 from jsonb_array_elements(coalesce(payload->'cards','[]')) x
 left join public.rr_upm_work_assignments_v8 a on a.id::text=x->>'assignment_id'
 left join public.rr_upm_submit_requests_v794 q on q.id::text=x->>'submit_request_id'
 where upper(p_status)='CLOSE' or q.id is null or upper(q.status) not in('COMPLETED','CANCELLED','CANCELED','REJECTED','VOID');
 return payload||jsonb_build_object('cards',cards,'count',jsonb_array_length(cards));
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_department_projection_test71(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_department_projection_test71(text,text) TO authenticated;
