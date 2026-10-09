CREATE OR REPLACE FUNCTION public.rr_chat_worker_action_authorize_test71(p_worker_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare role_code text; self_id uuid;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 perform public.rr_assert_active_user_v1();
 select upper(p.role_code) into role_code from public.rr_user_profiles p where p.auth_user_id=auth.uid() limit 1;
 self_id:=public.rr_upm_current_worker_id_v9112();
 if p_worker_id is null or not exists(select 1 from public.rr_worker_directory_unified_v1 where worker_id=p_worker_id and coalesce(is_active,false)) then raise exception 'Active assigned worker required.'; end if;
 if coalesce(role_code,'WORKER') not in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER') and self_id is distinct from p_worker_id then raise exception 'Only the assigned worker, Manager, Admin or Super Admin can take this action.'; end if;
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_worker_action_authorize_test71(uuid) FROM PUBLIC,anon,authenticated;
-- TEST71 delegated submit: preserve assigned worker; record actual signed-in actor.
CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.rr_chat_ready_submit_v794_test71(p_worker_id uuid, p_canonical_lot_id text, p_department_code text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ctx jsonb:=public.rr_upm_effective_identity_v200();actor_worker uuid:=p_worker_id;actor_role text:=public.rr_upm_effective_role_v200();can_assign boolean:=public.rr_upm_assignment_allowed_v200();r jsonb;a public.rr_upm_work_assignments_v8%rowtype;ids uuid[]:='{}';outrows jsonb:='[]';sizes jsonb;assigned numeric:=0;ready numeric:=0;req public.rr_upm_submit_requests_v794%rowtype;lm record;lm_count int:=0;lot text;v_row_team boolean:=false;v_any_team boolean:=false;
begin
 perform public.rr_chat_worker_action_authorize_test71(p_worker_id);
 if auth.uid() is null then raise exception 'Login required.';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one running Colour.';end if;
 select lot_no into lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
 for r in select value from jsonb_array_elements(p_rows) loop
  select * into a from public.rr_upm_work_assignments_v8 x where x.canonical_lot_id=p_canonical_lot_id and public.rr_upm_core_department_v9077(x.department_code)=public.rr_upm_core_department_v9077(p_department_code) and x.worker_id=p_worker_id and x.status in('ASSIGNED','IN_PROGRESS') and upper(x.colour_code)=upper(r->>'colour_code') order by x.assigned_at desc limit 1 for update;
  if not found then raise exception 'Active assignment missing for Colour %.',r->>'colour_code';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(a.id::text,0));
  v_row_team:=public.rr_upm_team_assignment_action_allowed_v774(a.id,actor_worker);v_any_team:=v_any_team or v_row_team;
  if a.worker_id is distinct from actor_worker and not can_assign and not v_row_team then raise exception 'Only the assigned worker or mapped team member can mark this Colour READY TO SUBMIT.';end if;
  if exists(select 1 from public.rr_upm_assignment_receipts_v9112 receipt where receipt.assignment_id=a.id and upper(receipt.status) in('PENDING','DISPUTED')) then raise exception 'ACCEPT WORK and confirm received PCS before READY TO SUBMIT.';end if;
  if exists(select 1 from public.rr_upm_submit_requests_v794 request where a.id=any(request.assignment_ids) and upper(request.status) not in('CANCELLED','REJECTED','VOID')) then raise exception 'This Colour is already submitted to Line Man.';end if;
  if array_length(ids,1)>0 and a.worker_id<>(select worker_id from public.rr_upm_work_assignments_v8 where id=ids[1]) and not v_row_team then raise exception 'Selected Colours belong to different workers. Send one worker request at a time.';end if;
  sizes:=coalesce((select jsonb_agg(jsonb_build_object('size_code',upper(z->>'size_code'),'assigned_qty',coalesce((z->>'qty')::numeric,0),'ready_qty',coalesce((z->>'qty')::numeric,0)) order by upper(z->>'size_code')) from jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb))z),'[]'::jsonb);
  ids:=array_append(ids,a.id);assigned:=assigned+a.assigned_qty;ready:=ready+a.assigned_qty;outrows:=outrows||jsonb_build_array(jsonb_build_object('assignment_id',a.id,'colour_id',a.colour_id,'colour_code',a.colour_code,'colour_name',a.colour_name,'sizes',sizes,'assigned_total',a.assigned_qty));
 end loop;
 insert into public.rr_upm_submit_requests_v794(canonical_lot_id,lot_no,department_code,worker_id,worker_auth_id,worker_name,assignment_ids,colour_rows,assigned_total,worker_ready_total)
 values(p_canonical_lot_id,coalesce(lot,p_canonical_lot_id),public.rr_upm_core_department_v9077(p_department_code),actor_worker,coalesce((select linked_auth_user_id from public.rr_worker_directory_unified_v1 where worker_id=actor_worker limit 1),actor_worker),(select worker_name from public.rr_worker_directory_unified_v1 where worker_id=actor_worker limit 1),ids,outrows,assigned,ready) returning * into req;
 for lm in select coalesce(u.linked_auth_user_id,c.worker_id) worker_id,c.worker_name from public.rr_upm_worker_candidates_v740('LINE_MAN',p_department_code)c left join public.rr_worker_directory_unified_v1 u on u.worker_id=c.worker_id where coalesce(u.linked_auth_user_id,c.worker_id) is not null and not exists(select 1 from public.rr_upm_activity_lease_v794 lease where lease.actor_id=coalesce(u.linked_auth_user_id,c.worker_id) and lease.expires_at>now()) and not exists(select 1 from public.rr_upm_submit_requests_v794 active where active.accepted_lm_id=coalesce(u.linked_auth_user_id,c.worker_id) and active.status='LM_ACCEPTED') loop
  insert into public.rr_upm_submit_lm_candidates_v794(request_id,line_man_id,line_man_name) values(req.id,lm.worker_id,lm.worker_name) on conflict do nothing;
  insert into public.rr_upm_alert_events_v794(recipient_id,recipient_role,request_id,alert_code,message_text) values(lm.worker_id,'LINE_MAN',req.id,'READY_TO_SUBMIT',format('Lot %s · %s · %s PCS ready. ACCEPT & COUNT करें.',req.lot_no,req.worker_name,req.worker_ready_total)) on conflict do nothing;lm_count:=lm_count+1;
 end loop;
 if lm_count=0 then update public.rr_upm_submit_requests_v794 set status='ESCALATED',updated_at=now() where id=req.id;end if;
 insert into public.rr_upm_submit_audit_v794(request_id,action_code,actor_name,details) values(req.id,'WORKER_READY',ctx->>'display_name',jsonb_build_object('assigned_total',assigned,'ready_total',ready,'lm_candidates',lm_count,'effective_worker_id',actor_worker,'effective_role',actor_role,'team_shared_authority',v_any_team));
 return jsonb_build_object('ok',true,'version','V775_TEAM_SHARED_SUBMIT_PER_ROW_AUTH','request_id',req.id,'lot_no',req.lot_no,'colours',jsonb_array_length(outrows),'assigned_total',assigned,'worker_ready_total',ready,'lm_candidates',lm_count,'status',case when lm_count=0 then 'ESCALATED' else 'WAITING_LM' end,'team_shared_authority',v_any_team);
end $function$
;
REVOKE ALL ON FUNCTION rr_chat_notifications_test71.rr_chat_ready_submit_v794_test71 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.rr_chat_append_open_submit_v693_test71(p_worker_id uuid, p_canonical_lot_id text, p_department_code text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_worker uuid:=p_worker_id;v_dept text:=public.rr_upm_core_department_v9077(p_department_code);q public.rr_upm_submit_requests_v794%rowtype;x jsonb;a public.rr_upm_work_assignments_v8%rowtype;new_ids uuid[]:='{}';new_rows jsonb:='[]'::jsonb;add_total numeric:=0;sizes jsonb;
begin
perform public.rr_chat_worker_action_authorize_test71(p_worker_id);
if auth.uid() is null or v_worker is null then raise exception 'Effective worker identity is required.';end if;
select * into q from public.rr_upm_submit_requests_v794 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(v_dept) and worker_id=v_worker and upper(status) not in('CANCELLED','REJECTED','VOID','COMPLETED') order by created_at desc limit 1 for update;
if q.id is null then return jsonb_build_object('found',false);end if;
if upper(coalesce(q.status,'')) not in('WAITING_LM','ESCALATED') or q.accepted_lm_id is not null then raise exception 'Existing handover is already claimed; remaining colours must use the next canonical handover after current custody completes.';end if;
for x in select value from jsonb_array_elements(p_rows) loop
 select * into a from public.rr_upm_work_assignments_v8 z where z.canonical_lot_id=p_canonical_lot_id and public.rr_upm_core_department_v9077(z.department_code)=v_dept and public.rr_canonical_worker_id_v264(z.worker_id)=v_worker and upper(z.colour_code)=upper(x->>'colour_code') and z.status='IN_PROGRESS' order by z.assigned_at desc limit 1 for update;
 if a.id is null then raise exception 'WORKING assignment missing for Colour %.',x->>'colour_code';end if;
 if a.id=any(coalesce(q.assignment_ids,'{}'::uuid[])) or a.id=any(new_ids) then continue;end if;
 if not exists(select 1 from public.rr_upm_assignment_receipts_v9112 r where r.assignment_id=a.id and upper(r.status) in('CONFIRMED','CONFIRMED_SHORT')) then raise exception 'ACCEPT & COUNT must be confirmed before Submit.';end if;
 if exists(select 1 from public.rr_upm_submit_requests_v794 z where a.id=any(z.assignment_ids) and z.id<>q.id and upper(z.status) not in('CANCELLED','REJECTED','VOID')) then raise exception 'Colour % already has an active Submit handover.',a.colour_code;end if;
 select coalesce(jsonb_agg(jsonb_build_object('size_code',upper(j->>'size_code'),'assigned_qty',coalesce((j->>'qty')::numeric,0),'ready_qty',coalesce((j->>'qty')::numeric,0)) order by upper(j->>'size_code')),'[]'::jsonb) into sizes from jsonb_array_elements(case when jsonb_typeof(a.inbound_breakup)='array' and jsonb_array_length(a.inbound_breakup)>0 then a.inbound_breakup else coalesce(a.size_breakup,'[]'::jsonb) end)j;
 new_ids:=array_append(new_ids,a.id);add_total:=add_total+greatest(coalesce(a.inbound_qty,0),coalesce(a.assigned_qty,0));new_rows:=new_rows||jsonb_build_array(jsonb_build_object('assignment_id',a.id,'assignment_batch_id',a.assignment_batch_id,'colour_id',a.colour_id,'colour_code',a.colour_code,'colour_name',a.colour_name,'sizes',sizes,'assigned_total',greatest(coalesce(a.inbound_qty,0),coalesce(a.assigned_qty,0))));
end loop;
if cardinality(new_ids)=0 then return jsonb_build_object('found',true,'ok',true,'idempotent',true,'request_id',q.id,'status',q.status);end if;
update public.rr_upm_submit_requests_v794 set assignment_ids=coalesce(assignment_ids,'{}'::uuid[])||new_ids,colour_rows=coalesce(colour_rows,'[]'::jsonb)||new_rows,assigned_total=coalesce(assigned_total,0)+add_total,worker_ready_total=coalesce(worker_ready_total,0)+add_total,updated_at=now() where id=q.id returning * into q;
for a in select * from public.rr_upm_work_assignments_v8 where id=any(new_ids) loop perform public.rr_upm_set_custody_v204(a.canonical_lot_id,a.colour_code,v_worker,null,a.worker_name_snapshot,'WORKER','SUBMIT_PENDING',q.id,null,'FABRICATION TEAM',a.id,q.id);end loop;
insert into public.rr_upm_submit_audit_v794(request_id,action_code,actor_name,details) values(q.id,'WORKER_READY_APPEND',(select full_name from public.rr_user_profiles where auth_user_id=auth.uid() limit 1),jsonb_build_object('assignment_ids',new_ids,'added_total',add_total,'target_department_code','FABRICATION'));
return jsonb_build_object('found',true,'ok',true,'version','V693_APPEND_OPEN_SUBMIT','request_id',q.id,'status',q.status,'added_colours',cardinality(new_ids),'added_total',add_total,'worker_ready_total',q.worker_ready_total);
end $function$
;
REVOKE ALL ON FUNCTION rr_chat_notifications_test71.rr_chat_append_open_submit_v693_test71 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.rr_chat_ready_submit_to_receiver_v204_test71(p_worker_id uuid, p_canonical_lot_id text, p_department_code text, p_rows jsonb, p_receiver_worker_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_dept text:=public.rr_upm_core_department_v9077(p_department_code);v_ctx jsonb:=public.rr_upm_effective_identity_v200();v_actor_worker uuid:=p_worker_id;v_actor_auth uuid:=(select linked_auth_user_id from public.rr_worker_directory_unified_v1 where worker_id=p_worker_id limit 1);v_receiver_worker uuid;v_receiver_auth uuid;v_receiver_name text;v_receiver_role text;v_row jsonb;v_a public.rr_upm_work_assignments_v8%rowtype;v_ids uuid[]:='{}';v_out jsonb:='[]';v_sizes jsonb;v_total numeric:=0;v_request public.rr_upm_submit_requests_v794%rowtype;
begin
 perform public.rr_chat_worker_action_authorize_test71(p_worker_id);
 if v_dept<>'PRESS' then return rr_chat_notifications_test71.rr_chat_ready_submit_v794_test71(p_worker_id,p_canonical_lot_id,v_dept,p_rows)||jsonb_build_object('delegated_by','V204','target_department_code','FABRICATION');end if;
 if auth.uid() is null then raise exception 'Login required.';end if;if v_actor_worker is null then raise exception 'Effective worker identity is required.';end if;if p_receiver_worker_id is null then raise exception 'Select an active Packing worker.';end if;
 select w.worker_id,w.linked_auth_user_id,w.worker_name,w.role_code into v_receiver_worker,v_receiver_auth,v_receiver_name,v_receiver_role from public.rr_worker_directory_unified_v1 w join public.rr_upm_worker_list_v8_4('PACKING') x on x.worker_id=w.worker_id where w.worker_id=p_receiver_worker_id limit 1;if v_receiver_worker is null then raise exception 'Select an active Packing worker.';end if;v_receiver_auth:=coalesce(v_receiver_auth,v_receiver_worker);
 for v_row in select value from jsonb_array_elements(p_rows) loop
  select * into v_a from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and public.rr_upm_core_department_v9077(a.department_code)=v_dept and upper(a.colour_code)=upper(v_row->>'colour_code') and a.worker_id=p_worker_id and a.status='IN_PROGRESS' order by a.assigned_at desc limit 1 for update;
  if not found then raise exception 'WORKING assignment missing for Colour %.',v_row->>'colour_code';end if;if v_a.worker_id is distinct from v_actor_worker then raise exception 'Only the assigned worker can submit Colour %.',v_a.colour_code;end if;
  if not exists(select 1 from public.rr_upm_assignment_receipts_v9112 r where r.assignment_id=v_a.id and upper(r.status) in('CONFIRMED','CONFIRMED_SHORT')) then raise exception 'ACCEPT & COUNT must be confirmed before Submit.';end if;
  if exists(select 1 from public.rr_upm_submit_requests_v794 q where v_a.id=any(q.assignment_ids) and upper(q.status) not in('CANCELLED','REJECTED','VOID')) then raise exception 'Colour % already has an active Submit handover.',v_a.colour_code;end if;
  select coalesce(jsonb_agg(jsonb_build_object('size_code',upper(z->>'size_code'),'assigned_qty',coalesce((z->>'qty')::numeric,0),'ready_qty',coalesce((z->>'qty')::numeric,0)) order by upper(z->>'size_code')),'[]'::jsonb) into v_sizes from jsonb_array_elements(case when jsonb_typeof(v_a.inbound_breakup)='array' and jsonb_array_length(v_a.inbound_breakup)>0 then v_a.inbound_breakup else coalesce(v_a.size_breakup,'[]'::jsonb) end)z;
  v_ids:=array_append(v_ids,v_a.id);v_total:=v_total+greatest(coalesce(v_a.inbound_qty,0),coalesce(v_a.assigned_qty,0));v_out:=v_out||jsonb_build_array(jsonb_build_object('assignment_id',v_a.id,'colour_code',v_a.colour_code,'sizes',v_sizes,'assigned_total',greatest(coalesce(v_a.inbound_qty,0),coalesce(v_a.assigned_qty,0))));
 end loop;
 insert into public.rr_upm_submit_requests_v794(canonical_lot_id,lot_no,department_code,worker_id,worker_auth_id,worker_name,assignment_ids,colour_rows,assigned_total,worker_ready_total,status,selected_receiver_worker_id,selected_receiver_auth_id,selected_receiver_name,selected_receiver_role,target_department_code)
 select p_canonical_lot_id,a.lot_no,v_dept,a.worker_id,coalesce(w.linked_auth_user_id,a.worker_id),a.worker_name_snapshot,v_ids,v_out,v_total,v_total,'WAITING_LM',v_receiver_worker,v_receiver_auth,v_receiver_name,'PACKER','PACKING' from public.rr_upm_work_assignments_v8 a left join public.rr_worker_directory_unified_v1 w on w.worker_id=a.worker_id where a.id=v_ids[1] returning * into v_request;
 insert into public.rr_upm_submit_lm_candidates_v794(request_id,line_man_id,line_man_name) values(v_request.id,v_receiver_auth,v_receiver_name) on conflict do nothing;
 insert into public.rr_upm_alert_events_v794(recipient_id,recipient_role,request_id,alert_code,message_text) values(v_receiver_auth,'PACKER',v_request.id,'READY_TO_RECEIVE',format('Lot %s · %s · %s PCS receive और count करें.',v_request.lot_no,v_request.worker_name,v_total)) on conflict do nothing;
 for v_a in select * from public.rr_upm_work_assignments_v8 where id=any(v_ids) loop perform public.rr_upm_set_custody_v204(v_a.canonical_lot_id,v_a.colour_code,v_actor_worker,v_actor_auth,v_a.worker_name_snapshot,'WORKER','SUBMIT_PENDING',v_request.id,v_receiver_worker,v_receiver_name,v_a.id,v_request.id);end loop;
 return jsonb_build_object('ok',true,'version','V204_PRESS_PACKING_SPECIAL','request_id',v_request.id,'status','WAITING_LM','selected_receiver_worker_id',v_receiver_worker,'selected_receiver_name',v_receiver_name,'target_department_code','PACKING');
end $function$
;
REVOKE ALL ON FUNCTION rr_chat_notifications_test71.rr_chat_ready_submit_to_receiver_v204_test71 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_chat_submit_worker_test71(p_worker_id uuid,p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_evidence_paths jsonb DEFAULT '[]',p_receiver_worker_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare d text:=public.rr_upm_core_department_v9077(p_department_code); r jsonb; rid uuid; gate jsonb; ev jsonb:=coalesce(p_evidence_paths,'[]'); actor_name text;
begin
 perform public.rr_chat_worker_action_authorize_test71(p_worker_id);
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one colour.'; end if;
 if d in ('STITCHING','OVERLOCK') and (jsonb_typeof(ev)<>'array' or jsonb_array_length(ev)<1) then raise exception 'Worked garment photo required.'; end if;
 if d='PRESS' then r:=rr_chat_notifications_test71.rr_chat_ready_submit_to_receiver_v204_test71(p_worker_id,p_canonical_lot_id,d,p_rows,p_receiver_worker_id);
 else
 r:=rr_chat_notifications_test71.rr_chat_append_open_submit_v693_test71(p_worker_id,p_canonical_lot_id,d,p_rows);
 if not coalesce((r->>'found')::boolean,false) then r:=rr_chat_notifications_test71.rr_chat_ready_submit_v794_test71(p_worker_id,p_canonical_lot_id,d,p_rows); end if;
 end if;
 rid:=(r->>'request_id')::uuid;
 if jsonb_typeof(ev)='array' and jsonb_array_length(ev)>0 then perform public.rr_upm_bind_submit_evidence_v739(rid,ev); end if;
 gate:=public.rr_upm_submit_gate_v277(p_canonical_lot_id,d,null);
 if gate->>'request_id' is not null then update public.rr_upm_rate_requests_v760 set metadata=coalesce(metadata,'{}')||jsonb_build_object('submit_request_id',rid,'rate_alert_source','TEST71_WORKER_ACTION') where id=(gate->>'request_id')::uuid; end if;
 select full_name into actor_name from public.rr_user_profiles where auth_user_id=auth.uid() limit 1;
 insert into public.rr_upm_submit_audit_v794(request_id,action_code,actor_name,details) values(rid,'TEST71_SUBMIT_ACTOR',coalesce(actor_name,auth.uid()::text),jsonb_build_object('actor_user_id',auth.uid(),'assigned_worker_id',p_worker_id,'department_code',d));
 return r||jsonb_build_object('actor_user_id',auth.uid(),'actor_name',actor_name,'assigned_worker_id',p_worker_id);
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_submit_worker_test71(uuid,text,text,jsonb,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_submit_worker_test71(uuid,text,text,jsonb,jsonb,uuid) TO authenticated;
-- Re-emit delegated Submit with the real actor so the assigned worker receives it.
CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.submit_actor_test71() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare q public.rr_upm_submit_requests_v794%rowtype; actor uuid; dep text; key text;
begin
 if new.action_code<>'TEST71_SUBMIT_ACTOR' then return new; end if;
 select * into q from public.rr_upm_submit_requests_v794 where id=new.request_id;
 actor:=nullif(new.details->>'actor_user_id','')::uuid;
 key:='UPM_SUBMIT_TEST71:'||q.id||':'||upper(q.status);
 foreach dep in array array[coalesce(q.target_department_code,'FABRICATION'),q.department_code] loop
 perform rr_chat_notifications_test71.emit_upm(key,dep,'WORKING',q.lot_no,q.assignment_ids[1],q.id,array[q.worker_id,q.selected_receiver_worker_id,q.accepted_lm_id],actor);
 update rr_chat_notifications_test71.inbox set actor_user_id=actor,action_label='Submit',action_detail=coalesce(action_detail,'{}')||new.details where event_key=key||':'||public.rr_real_chat_canonical_department_v83(dep);
 end loop;
 return new;
end $$;
REVOKE ALL ON FUNCTION rr_chat_notifications_test71.submit_actor_test71() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS rr_submit_actual_actor_test71 ON public.rr_upm_submit_audit_v794;
CREATE TRIGGER rr_submit_actual_actor_test71 AFTER INSERT ON public.rr_upm_submit_audit_v794 FOR EACH ROW EXECUTE FUNCTION rr_chat_notifications_test71.submit_actor_test71();

CREATE OR REPLACE FUNCTION public.rr_chat_rectification_cards_test71(p_department_code text,p_worker_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare result jsonb;
begin
 perform public.rr_assert_active_user_v1();
 select coalesce(jsonb_agg(to_jsonb(c)),'[]') into result from public.rr_upm_rectification_cases_v9101 c
 where c.status in ('OPEN','ASSIGNED','IN_PROGRESS')
 and (public.rr_real_chat_canonical_department_v83(c.target_department_code)=public.rr_real_chat_canonical_department_v83(p_department_code) or upper(p_department_code)='FABRICATION')
 and (p_worker_id is null or p_worker_id in (c.assigned_worker_id,c.original_worker_id,c.line_man_id))
 and (exists(select 1 from public.rr_user_profiles p where p.auth_user_id=auth.uid() and upper(p.role_code) in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER'))
 or public.rr_upm_current_worker_id_v9112() in (c.assigned_worker_id,c.original_worker_id,c.line_man_id));
 return result;
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_rectification_cards_test71(text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_rectification_cards_test71(text,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_chat_open_rectification_test71(p_canonical_lot_id text,p_origin_department_code text,p_colour_code text,p_qty numeric,p_reason text,p_line_man_id uuid,p_worker_id uuid,p_remarks text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
begin
 perform public.rr_chat_worker_action_authorize_test71(p_worker_id);
 if not exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_origin_department_code) and upper(a.colour_code)=upper(p_colour_code) and a.worker_id=p_worker_id) then raise exception 'Assigned worker does not match this colour.'; end if;
 return public.rr_upm_open_rectification_v9110(p_canonical_lot_id,p_origin_department_code,p_colour_code,p_qty,p_reason,p_line_man_id,p_worker_id,p_remarks);
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_open_rectification_test71(text,text,text,numeric,text,uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_open_rectification_test71(text,text,text,numeric,text,uuid,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_chat_alter_fill_test71(p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_evidence_urls jsonb,p_physical_confirmed boolean,p_line_man_id uuid,p_remarks text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare row_data jsonb; worker uuid;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 for row_data in select value from jsonb_array_elements(p_rows) loop
 select worker_id into worker from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and public.rr_upm_core_department_v9077(a.department_code)=public.rr_upm_core_department_v9077(p_department_code) and upper(a.colour_code)=upper(row_data->>'colour_code') and a.status in ('ASSIGNED','IN_PROGRESS','COMPLETED') order by (a.status in ('ASSIGNED','IN_PROGRESS')) desc,a.assigned_at desc limit 1;
 perform public.rr_chat_worker_action_authorize_test71(worker);
 end loop;
 return public.rr_upm_alter_fill_request_v9114(p_canonical_lot_id,p_department_code,p_rows,p_evidence_urls,p_physical_confirmed,p_line_man_id,p_remarks);
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_alter_fill_test71(text,text,jsonb,jsonb,boolean,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_alter_fill_test71(text,text,jsonb,jsonb,boolean,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION rr_chat_notifications_test71.alter_transition_test71(p_action text, p_rows jsonb, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_action text := upper(trim(coalesce(p_action,'')));
  v_ctx jsonb := public.rr_up_user_context_v2();
  v_actor_role text;
  v_actor_name text;
  v_actor_worker_id uuid;
  v_req jsonb;
  v_j public.rr_upm_alter_journey_v740%rowtype;
  v_qty numeric;
  v_expected_stage text;
  v_to_stage text;
  v_resp_id uuid;
  v_resp_name text;
  v_resp_code text;
  v_resp_role text;
  v_resp_dept text;
  v_target_id uuid;
  v_saved integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_phone text;
  v_recipient_id uuid;
  v_recipient_name text;
  v_message text;
  v_wa text;
  v_outbox uuid;
  v_privileged boolean;
  v_holder_directory jsonb;
  v_current_department text;
  v_current_worker_id uuid;
  v_current_worker_name text;
  v_current_worker_code text;
  v_current_goods_route boolean := false;
  v_already_current_goods_route boolean := false;
  v_credit_dept text;
  v_credit_worker_id uuid;
  v_credit_worker_name text;
  v_credit_assignment_id uuid;
  v_credit_worker_code text;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select an exact Alter journey.'; end if;

  if v_action='RECEIVE_FROM_KARIGAR' then v_action:='KARIGAR_SUBMIT_GOOD'; end if;
  if v_action not in ('REMAKE_ISSUE','RECEIVE_FROM_MASTER','DELIVER_TO_KARIGAR','KARIGAR_SUBMIT_GOOD') then
    raise exception 'Invalid custody action %.',v_action;
  end if;

  v_actor_role := public.rr_upm_norm_role_v740(v_ctx->>'user_category');
  v_actor_name := coalesce(v_ctx->>'display_name',auth.uid()::text);
  v_actor_worker_id := public.rr_upm_actor_worker_id_v771();
  v_privileged := v_actor_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER');

  for v_req in
    select jsonb_build_object('journey_id',g.journey_id,'qty',g.qty)
    from (
      select (e.value->>'journey_id')::uuid as journey_id,
             sum(coalesce(nullif(e.value->>'qty','')::numeric,0)) as qty
      from jsonb_array_elements(p_rows) e(value)
      where nullif(e.value->>'journey_id','') is not null
      group by (e.value->>'journey_id')::uuid
    ) g
    where g.qty>0
  loop
    select * into v_j
    from public.rr_upm_alter_journey_v740
    where id=(v_req->>'journey_id')::uuid
    for update;
    if not found then raise exception 'Exact Alter journey not found.'; end if;
    if v_j.stage like 'CLOSED%' or v_j.open_qty<=0 then raise exception 'Journey % is already closed.',v_j.id; end if;

    v_qty := (v_req->>'qty')::numeric;
    if v_qty>v_j.open_qty then
      raise exception '% / % / %: Qty % exceeds exact holder balance %.',v_j.colour_code,v_j.size_code,'ALT-'||upper(substr(replace(v_j.id::text,'-',''),1,8)),v_qty,v_j.open_qty;
    end if;

    if v_action='REMAKE_ISSUE' then
      v_expected_stage:='LM_ALTER_PENDING'; v_to_stage:='CM_REMAKE_READY';
      if not v_privileged and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.cutting_master_id and auth.uid() is distinct from v_j.cutting_master_id then
        raise exception 'Only this journey''s Cutting Master can confirm Remake Issue.';
      end if;
      v_resp_id:=v_j.cutting_master_id; v_resp_name:=v_j.cutting_master_name; v_resp_code:=v_j.cutting_master_worker_code;
      v_resp_role:='CUTTING_MASTER'; v_resp_dept:='CUTTING';
    elsif v_action='RECEIVE_FROM_MASTER' then
      v_expected_stage:='CM_REMAKE_READY'; v_to_stage:='LM_DELIVERY_PENDING';
      if not v_privileged and v_actor_role<>'MANAGER'
         and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.enrolled_lm_id and auth.uid() is distinct from v_j.enrolled_lm_id then
        raise exception 'Only % Line Man can receive this exact journey from Cutting Master.',coalesce(v_j.enrolled_lm_name,'assigned');
      end if;
      v_resp_id:=v_j.enrolled_lm_id; v_resp_name:=v_j.enrolled_lm_name; v_resp_code:=v_j.enrolled_lm_worker_code;
      select to_jsonb(w) into v_holder_directory
      from public.rr_worker_directory_unified_v1 w where w.worker_id=v_j.enrolled_lm_id limit 1;
      v_resp_role:='LINE_MAN'; v_resp_dept:=coalesce(v_holder_directory->>'department_code','LINE_MAN');
    elsif v_action='DELIVER_TO_KARIGAR' then
      v_expected_stage:='LM_DELIVERY_PENDING'; v_to_stage:='KARIGAR_REMAKE_PENDING';
      if not v_privileged and v_actor_role<>'MANAGER'
         and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.enrolled_lm_id and auth.uid() is distinct from v_j.enrolled_lm_id then
        raise exception 'Only % Line Man can deliver this exact journey to Karigar.',coalesce(v_j.enrolled_lm_name,'assigned');
      end if;
      v_resp_id:=v_j.karigar_id; v_resp_name:=v_j.karigar_name; v_resp_code:=v_j.karigar_worker_code;
      v_resp_role:='WORKER'; v_resp_dept:=v_j.origin_department_code;
    else
      v_expected_stage:='KARIGAR_REMAKE_PENDING';
      v_to_stage:='CLOSED_GOOD';

      -- Re-evaluate destination on every submit/forward event.
      -- Select the immediate next goods assignment after the current
      -- responsible department. Never jump to the latest assignment.
      select nxt.department_code,nxt.worker_id,nxt.worker_name_snapshot,nxt.worker_code
        into v_current_department,v_current_worker_id,v_current_worker_name,v_current_worker_code
      from public.rr_upm_work_assignments_v8 nxt
      where nxt.canonical_lot_id=v_j.canonical_lot_id
        and (upper(nxt.colour_code)=upper(v_j.colour_code)
          or upper(nxt.colour_name)=upper(v_j.colour_name))
        and exists (
          select 1 from jsonb_array_elements(coalesce(nxt.size_breakup,'[]'::jsonb)) s
          where upper(s->>'size_code')=upper(v_j.size_code)
            and coalesce(nullif(s->>'qty','')::numeric,0)>0
        )
        and nxt.assigned_at > coalesce((
          select max(cur.assigned_at)
          from public.rr_upm_work_assignments_v8 cur
          where cur.canonical_lot_id=v_j.canonical_lot_id
            and (upper(cur.colour_code)=upper(v_j.colour_code)
              or upper(cur.colour_name)=upper(v_j.colour_name))
            and upper(cur.department_code)=upper(coalesce(
              nullif(v_j.responsible_department_code,''),
              v_j.origin_department_code
            ))
            and (v_j.responsible_id is null or cur.worker_id=v_j.responsible_id)
        ),'-infinity'::timestamptz)
        and upper(nxt.department_code)<>upper(coalesce(
          nullif(v_j.responsible_department_code,''),
          v_j.origin_department_code
        ))
      order by nxt.assigned_at asc
      limit 1;

      -- No later department means the current responsible worker is the
      -- final destination worker; allow final Good submit there.
      if v_current_worker_id is null then
        v_current_department:=coalesce(nullif(v_j.responsible_department_code,''),v_j.origin_department_code);
        v_current_worker_id:=v_j.responsible_id;
        v_current_worker_name:=v_j.responsible_name;
        v_current_worker_code:=v_j.responsible_worker_code;
      end if;

      if nullif(trim(v_current_department),'') is not null
         and upper(v_current_department)<>upper(v_j.origin_department_code) then
        if v_current_worker_id is null then
          raise exception 'Current goods department % has no mapped active worker for % / %.',
            upper(v_current_department),v_j.colour_code,v_j.size_code;
        end if;

        if v_current_worker_id is distinct from v_j.responsible_id
           or upper(coalesce(v_current_department,''))<>upper(coalesce(v_j.responsible_department_code,'')) then
          -- Goods moved again: current holder forwards to the new destination owner.
          if not v_privileged and v_actor_role<>'MANAGER'
             and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.responsible_id
             and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.karigar_id
             and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.enrolled_lm_id
             and auth.uid() is distinct from v_j.responsible_id
             and auth.uid() is distinct from v_j.karigar_id
             and auth.uid() is distinct from v_j.enrolled_lm_id then
            raise exception 'Only current Alter holder can forward to destination owner %.',
              coalesce(v_current_worker_name,'mapped worker');
          end if;
          v_current_goods_route:=true;
          v_to_stage:='KARIGAR_REMAKE_PENDING';
          v_resp_id:=v_current_worker_id;
          v_resp_name:=v_current_worker_name;
          v_resp_code:=v_current_worker_code;
          v_resp_role:='WORKER';
          v_resp_dept:=v_current_department;
        else
          -- Destination has not changed: current destination owner can merge Good.
          if not v_privileged and v_actor_role<>'MANAGER'
             and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_current_worker_id
             and auth.uid() is distinct from v_current_worker_id then
            raise exception 'Only current goods department worker % can submit final Good.',
              coalesce(v_current_worker_name,'mapped worker');
          end if;
          v_resp_id:=null; v_resp_name:=null; v_resp_code:=null; v_resp_role:='NONE'; v_resp_dept:=null;
        end if;
      else
        if not v_privileged and v_actor_role<>'MANAGER'
           and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.karigar_id
           and coalesce(v_actor_worker_id,auth.uid()) is distinct from v_j.enrolled_lm_id
           and auth.uid() is distinct from v_j.karigar_id
           and auth.uid() is distinct from v_j.enrolled_lm_id then
          raise exception 'Only the responsible Karigar or this journey''s Line Man can submit/receive Good.';
        end if;
        v_resp_id:=null; v_resp_name:=null; v_resp_code:=null; v_resp_role:='NONE'; v_resp_dept:=null;
      end if;    end if;

    if v_j.stage<>v_expected_stage then
      raise exception 'Journey % is currently %; expected % for action %.',
        'ALT-'||upper(substr(replace(v_j.id::text,'-',''),1,8)),v_j.stage,v_expected_stage,v_action;
    end if;

    if v_qty<v_j.open_qty then
      -- Exact source remainder stays under its existing holder.
      update public.rr_upm_alter_journey_v740
      set open_qty=open_qty-v_qty,updated_at=now(),route_version=case when v_current_goods_route then 'V771_CURRENT_GOODS_OWNER' else 'V771_EXACT_CUSTODY' end
      where id=v_j.id;

      -- Only the moved quantity advances and gets its own traceable child fragment.
      insert into public.rr_upm_alter_journey_v740(
        canonical_lot_id,lot_no,origin_department_code,colour_id,colour_code,colour_name,size_code,
        open_qty,stage,enrolled_lm_id,enrolled_lm_name,enrolled_lm_worker_code,
        cutting_master_id,cutting_master_name,cutting_master_worker_code,
        karigar_id,karigar_name,karigar_worker_code,
        responsible_id,responsible_name,responsible_worker_code,responsible_role_code,responsible_department_code,
        evidence_urls,physical_piece_confirmed,created_by,created_by_name,closed_at,close_reason,
        journey_group_id,parent_journey_id,holder_since,route_version
      ) values (
        v_j.canonical_lot_id,v_j.lot_no,v_j.origin_department_code,v_j.colour_id,v_j.colour_code,v_j.colour_name,v_j.size_code,
        v_qty,v_to_stage,v_j.enrolled_lm_id,v_j.enrolled_lm_name,v_j.enrolled_lm_worker_code,
        v_j.cutting_master_id,v_j.cutting_master_name,v_j.cutting_master_worker_code,
        v_j.karigar_id,v_j.karigar_name,v_j.karigar_worker_code,
        v_resp_id,v_resp_name,v_resp_code,v_resp_role,v_resp_dept,
        v_j.evidence_urls,v_j.physical_piece_confirmed,auth.uid(),v_actor_name,
        case when v_to_stage='CLOSED_GOOD' then now() else null end,
        case when v_to_stage='CLOSED_GOOD' then 'Karigar submitted Good / Line Man received Good' else null end,
        coalesce(v_j.journey_group_id,v_j.id),v_j.id,now(),case when v_current_goods_route then 'V771_CURRENT_GOODS_OWNER' else 'V771_EXACT_CUSTODY' end
      ) returning id into v_target_id;
    else
      update public.rr_upm_alter_journey_v740
      set stage=v_to_stage,
          responsible_id=v_resp_id,responsible_name=v_resp_name,responsible_worker_code=v_resp_code,
          responsible_role_code=v_resp_role,responsible_department_code=v_resp_dept,
          journey_group_id=coalesce(journey_group_id,id),holder_since=now(),route_version=case when v_current_goods_route then 'V771_CURRENT_GOODS_OWNER' else 'V771_EXACT_CUSTODY' end,
          closed_at=case when v_to_stage='CLOSED_GOOD' then now() else null end,
          close_reason=case when v_to_stage='CLOSED_GOOD' then 'Karigar submitted Good / Line Man received Good' else null end,
          updated_at=now()
      where id=v_j.id
      returning id into v_target_id;
    end if;

    insert into public.rr_upm_alter_events_v740(
      journey_id,event_type,qty,from_stage,to_stage,actor_id,actor_name,
      responsible_id,responsible_name,responsible_role_code,remarks
    ) values (
      v_target_id,v_action,v_qty,v_expected_stage,v_to_stage,auth.uid(),v_actor_name,
      v_resp_id,v_resp_name,v_resp_role,
      concat_ws(' Â· ',p_remarks,'V771 exact journey_id custody transfer','source='||v_j.id::text)
    );

    -- A repaired ALTER becomes Good for the worker who repaired it.
    -- The next holder is credited only after their own repair/forward action.
    if v_action='KARIGAR_SUBMIT_GOOD' then
      v_credit_dept:=coalesce(nullif(trim(v_j.responsible_department_code),''),v_j.origin_department_code);
      v_credit_worker_id:=coalesce(v_j.responsible_id,v_j.karigar_id,v_j.enrolled_lm_id);
      v_credit_worker_name:=coalesce(v_j.responsible_name,v_j.karigar_name,v_j.enrolled_lm_name);
      v_credit_worker_code:=coalesce(v_j.responsible_worker_code,v_j.karigar_worker_code,v_j.enrolled_lm_worker_code);

      select a.id into v_credit_assignment_id
      from public.rr_upm_work_assignments_v8 a
      where a.canonical_lot_id=v_j.canonical_lot_id
        and upper(a.department_code)=upper(v_credit_dept)
        and upper(a.colour_code)=upper(v_j.colour_code)
        and (v_credit_worker_id is null or a.worker_id=v_credit_worker_id)
      order by case when a.status in ('ASSIGNED','IN_PROGRESS') then 0 else 1 end,a.assigned_at desc
      limit 1;

      if not exists (
        select 1 from public.rr_upm_actions_v726 x
        where x.reference_id=v_target_id
          and x.action_type='GOOD'
          and upper(x.department_code)=upper(v_credit_dept)
          and (v_credit_worker_id is null or x.worker_id=v_credit_worker_id)
      ) then
        insert into public.rr_upm_actions_v726(
          request_id,canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,
          size_code,assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,
          qty,actual_rate,standard_rate,remarks,reference_id,actor_user_id,actor_name
        ) values (
          gen_random_uuid(),v_j.canonical_lot_id,v_j.lot_no,upper(v_credit_dept),v_j.colour_id,
          v_j.colour_code,v_j.colour_name,upper(v_j.size_code),v_credit_assignment_id,
          v_credit_worker_id,v_credit_worker_name,v_credit_worker_code,'GOOD','PENDING',
          v_qty,0,0,'ALTER REPAIRED AND FORWARDED · V771 STAGE GOOD',
          v_target_id,auth.uid(),v_actor_name
        );

        insert into public.rr_upm_entries(
          canonical_lot_id,lot_no,department_code,colour_code,size_code,entry_type,qty,rate,
          remarks,operator_name
        ) values (
          v_j.canonical_lot_id,v_j.lot_no,upper(v_credit_dept),v_j.colour_code,
          upper(v_j.size_code),'GOOD',v_qty,0,
          'ALTER REPAIRED AND FORWARDED · V771 STAGE GOOD',v_actor_name
        );
      end if;
    end if;

    if v_to_stage='CM_REMAKE_READY' then
      v_recipient_id:=v_j.cutting_master_id; v_recipient_name:=v_j.cutting_master_name;
      v_message:=format('%s Line Man se Lot %s | %s | %s | %s PCS remake aapki custody me aaya.%sJourney: ALT-%s%sAb responsibility Cutting Master ki hai.',v_j.enrolled_lm_name,v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n');
    elsif v_to_stage='LM_DELIVERY_PENDING' then
      v_recipient_id:=v_j.enrolled_lm_id; v_recipient_name:=v_j.enrolled_lm_name;
      v_message:=format('%s Cutting Master ne Lot %s | %s | %s | %s PCS aapko diya.%sJourney: ALT-%s%sAb responsibility Line Man ki hai.',v_j.cutting_master_name,v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n');
    elsif v_to_stage='KARIGAR_REMAKE_PENDING' then
      if v_current_goods_route then
        v_recipient_id:=v_current_worker_id; v_recipient_name:=v_current_worker_name;
        v_message:=format('Alter journey forwarded to current goods department %s.%sLot %s | %s | %s | %s PCS%sJourney: ALT-%s%sCurrent department worker %s ko Good submit karke merge karna hai.',upper(v_current_department),E'\n',v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n',coalesce(v_current_worker_name,'mapped worker'));
      else
        v_recipient_id:=v_j.karigar_id; v_recipient_name:=v_j.karigar_name;
        v_message:=format('%s Line Man ne Lot %s | %s | %s | %s PCS remake aapko diya.%sJourney: ALT-%s%sAb responsibility Karigar ki hai. Complete karke Good submit karein.',v_j.enrolled_lm_name,v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n');
      end if;
    else
      v_recipient_id:=v_j.enrolled_lm_id; v_recipient_name:=v_j.enrolled_lm_name;
      v_message:=format('Lot %s | %s | %s | %s PCS remake Good submit ho gaya.%sJourney: ALT-%s%sResponsibility cleared; Qty current goods department %s ki Good Qty me merge hui.',v_j.lot_no,v_j.colour_name,v_j.size_code,v_qty,E'\n',upper(substr(replace(v_target_id::text,'-',''),1,8)),E'\n',coalesce(nullif(v_current_department,''),v_j.origin_department_code));
    end if;

    select coalesce(to_jsonb(w)->>'mobile',to_jsonb(w)->>'phone',to_jsonb(w)->>'phone_no')
      into v_phone
    from public.rr_worker_directory_unified_v1 w
    where w.worker_id=v_recipient_id
    limit 1;
    v_wa:=public.rr_upm_whatsapp_url_v740(v_phone,v_message);
    insert into public.rr_upm_whatsapp_outbox_v740(
      journey_id,recipient_id,recipient_name,recipient_phone,message_text,evidence_urls,whatsapp_url
    ) values (
      v_target_id,v_recipient_id,v_recipient_name,v_phone,v_message,v_j.evidence_urls,v_wa
    ) returning id into v_outbox;

    v_saved:=v_saved+1;
    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'source_journey_id',v_j.id,'target_journey_id',v_target_id,
      'journey_group_id',coalesce(v_j.journey_group_id,v_j.id),
      'qty',v_qty,'from_stage',v_expected_stage,'to_stage',v_to_stage,
      'responsible_id',v_resp_id,'responsible_name',v_resp_name,'responsible_role_code',v_resp_role
    ));
  end loop;

  if v_saved=0 then raise exception 'Enter a positive quantity against an exact journey.'; end if;
  return jsonb_build_object(
    'ok',true,'version','V771_EXACT_JOURNEY_CUSTODY','rows_saved',v_saved,
    'results',v_results,'whatsapp_url',v_wa,'outbox_id',v_outbox,
    'message',case when v_action='KARIGAR_SUBMIT_GOOD'
      then 'Good submitted; responsibility cleared and quantity returned to Good.'
      else 'Exact journey custody transferred successfully.' end
  );
end
$function$
;
REVOKE ALL ON FUNCTION rr_chat_notifications_test71.alter_transition_test71 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_chat_alter_action_test71(p_action text,p_journey_id uuid,p_qty numeric DEFAULT NULL,p_remarks text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
declare j public.rr_upm_alter_journey_v740%rowtype;
begin
 if auth.uid() is null then raise exception 'Login required.'; end if;
 perform public.rr_assert_active_user_v1();
 select * into j from public.rr_upm_alter_journey_v740 where id=p_journey_id;
 if not found then raise exception 'Alter not found.'; end if;
 if upper(p_action)='LM_ACCEPT' then return public.rr_upm_accept_alter_v9114(p_journey_id,p_remarks); end if;
 return rr_chat_notifications_test71.alter_transition_test71(p_action,jsonb_build_array(jsonb_build_object('journey_id',p_journey_id,'qty',coalesce(p_qty,j.open_qty))),p_remarks);
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_alter_action_test71(text,uuid,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_alter_action_test71(text,uuid,numeric,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_chat_department_projection_test71(p_department_code text,p_status text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
declare payload jsonb; cards jsonb;
begin
 perform public.rr_assert_active_user_v1();
 payload:=public.rr_real_chat_department_projection_v709(p_department_code,p_status);
 select coalesce(jsonb_agg(x||jsonb_strip_nulls(jsonb_build_object('worker_id',a.worker_id,'worker_name',a.worker_name_snapshot,'source_type',a.source_type))),'[]') into cards
 from jsonb_array_elements(coalesce(payload->'cards','[]')) x left join public.rr_upm_work_assignments_v8 a on a.id::text=x->>'assignment_id';
 return payload||jsonb_build_object('cards',cards);
end $$;
REVOKE ALL ON FUNCTION public.rr_chat_department_projection_test71(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_department_projection_test71(text,text) TO authenticated;
