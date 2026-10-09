-- Uses the existing claimed-but-uncounted handover only inside a transaction.
-- No real quantity, assignment, receipt, alert or stock change is committed.
begin;
create temp table accept_count_result(check_name text primary key,passed boolean);
do $$
declare q public.rr_upm_submit_requests_v794%rowtype; original jsonb; prepared jsonb; result jsonb; rows jsonb; bad jsonb; c jsonb; z jsonb; uid uuid; n int; before_n int;
begin
 select x.* into q from public.rr_upm_submit_requests_v794 x
 where x.status='LM_ACCEPTED' and x.counted_at is null and jsonb_array_length(coalesce(x.lm_count_rows,'[]'))=0
 and x.department_code not in('PRESS','PACKING') and x.target_department_code='FABRICATION'
 and exists(select 1 from public.rr_user_profiles p where p.auth_user_id=x.selected_receiver_auth_id and p.is_active)
 and not exists(select 1 from public.rr_upm_work_assignments_v8 a where a.id=any(x.assignment_ids) and a.status<>'IN_PROGRESS')
 order by (x.lot_no='2634') desc,x.created_at limit 1;
 if q.id is null then raise exception 'Claimed-but-uncounted rollback fixture required'; end if;
 uid:=q.selected_receiver_auth_id;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 perform set_config('request.headers','{"origin":"https://test71-workspace.app.github.dev","x-client-info":"redzed-test71"}',true);
 perform set_config('rr_chat_notifications_test71.test_run','on',true);
 original:=to_jsonb(q);
 prepared:=public.rr_chat_prepare_accept_count_test71(q.id);
 if prepared->>'status'<>'NOT_ACCEPTED' or prepared->>'accept_count_complete'<>'false' then raise exception 'Opening form falsely accepted'; end if;
 if (select to_jsonb(x) from public.rr_upm_submit_requests_v794 x where id=q.id)<>original then raise exception 'Read/open changed business state'; end if;
 insert into accept_count_result values('open_cancel_no_mutation',true);
 rows:='[]';
 for c in select value from jsonb_array_elements(q.colour_rows) loop
  for z in select value from jsonb_array_elements(c->'sizes') loop
   rows:=rows||jsonb_build_array(jsonb_build_object('colour_code',c->>'colour_code','size_code',z->>'size_code','qty',coalesce(z->'ready_qty',z->'assigned_qty')));
  end loop;
 end loop;
 foreach bad in array array['[]'::jsonb,rows-0,jsonb_set(rows,'{0,qty}','null'),jsonb_set(rows,'{0,qty}','-1'),jsonb_set(rows,'{0,qty}','1.5'),rows||jsonb_build_array(rows->0)] loop
  begin
   perform public.rr_chat_accept_count_test71(q.id,bad);
   raise exception 'INVALID_COUNT_ACCEPTED';
  exception when others then
   if sqlerrm='INVALID_COUNT_ACCEPTED' then raise; end if;
  end;
  if (select to_jsonb(x) from public.rr_upm_submit_requests_v794 x where id=q.id)<>original then raise exception 'Invalid count left a partial accept'; end if;
 end loop;
 insert into accept_count_result values('invalid_partial_blank_negative_fractional_duplicate_counts',true);
 -- Even a later material failure must undo count completion and the next stage.
 begin
  perform public.rr_chat_accept_count_test71(q.id,rows,jsonb_build_array(jsonb_build_object('assignment_id',q.assignment_ids[1],'mapping_id',gen_random_uuid(),'consumed_qty',1)));
  raise exception 'INVALID_MATERIAL_ACCEPTED';
 exception when others then if sqlerrm='INVALID_MATERIAL_ACCEPTED' then raise; end if; end;
 if (select to_jsonb(x) from public.rr_upm_submit_requests_v794 x where id=q.id)<>original then raise exception 'Material failure left partial acceptance'; end if;
 insert into accept_count_result values('late_failure_rolls_back_whole_save',true);
 result:=public.rr_chat_department_projection_test71('FABRICATION','WORKING');
 if not exists(select 1 from jsonb_array_elements(result->'cards') x where x->>'submit_request_id'=q.id::text and x->>'submit_status'='NOT_ACCEPTED' and x->>'resolved_work_state'='WORKING') then raise exception 'Legacy incomplete card still labeled Accepted'; end if;
 insert into accept_count_result values('legacy_incomplete_projection_not_accepted',true);
 result:=public.rr_chat_department_projection_test71(q.department_code,'CLOSE');
 if exists(select 1 from jsonb_array_elements(result->'cards') x where x->>'submit_request_id'=q.id::text and (x->>'resolved_work_state'='WORKING' or exists(select 1 from jsonb_array_elements(coalesce(x->'actions','[]')) a where a->>'code'='ACCEPT_AND_COUNT'))) then raise exception 'Source worker CLOSE card was reopened as a receiver action'; end if;
 insert into accept_count_result values('source_worker_close_preserved',true);
 -- A fresh request must never persist an intermediate LM_ACCEPTED state.
 begin
  update public.rr_upm_submit_requests_v794 set status='WAITING_LM',accepted_lm_id=null,accepted_lm_name=null,accepted_at=null where id=q.id;
  prepared:=public.rr_chat_prepare_accept_count_test71(q.id);
  if prepared->>'status'<>'NOT_ACCEPTED' or (select status from public.rr_upm_submit_requests_v794 where id=q.id)<>'WAITING_LM' then raise exception 'Fresh open claimed a handover'; end if;
  result:=public.rr_chat_accept_count_test71(q.id,rows);
  if result->>'status'<>'COMPLETED' or result->>'accept_count_complete'<>'true' then raise exception 'Fresh atomic Save failed'; end if;
  raise exception 'RESTORE_FRESH_CASE';
 exception when others then if sqlerrm<>'RESTORE_FRESH_CASE' then raise; end if; end;
 insert into accept_count_result values('fresh_request_claim_count_complete_in_one_save',true);
 begin
  update public.rr_upm_submit_requests_v794 set status='WAITING_LM',accepted_lm_id=null,accepted_lm_name=null,accepted_at=null where id=q.id;
  result:=public.rr_chat_accept_count_test71(q.id,jsonb_set(rows,'{0,qty}',to_jsonb((rows->0->>'qty')::numeric-1)));
  if result->>'status'<>'DISPUTED' or result->>'accept_count_complete'<>'false' or result->>'acceptance_status'<>'NOT_ACCEPTED' then raise exception 'Mismatch falsely completed'; end if;
  prepared:=public.rr_chat_department_projection_test71('FABRICATION','WORKING');
  if not exists(select 1 from jsonb_array_elements(prepared->'cards') x where x->>'submit_request_id'=q.id::text and x->>'resolved_work_state'='DECISION_PENDING' and x->>'accept_count_complete'='false') then raise exception 'Mismatch displayed Accepted'; end if;
  raise exception 'RESTORE_MISMATCH_CASE';
 exception when others then if sqlerrm<>'RESTORE_MISMATCH_CASE' then raise; end if; end;
 insert into accept_count_result values('mismatch_stays_not_accepted_until_final_decision',true);
 begin
  select auth_user_id into uid from public.rr_user_profiles where is_active and upper(role_code)='WORKER' and auth_user_id<>q.selected_receiver_auth_id limit 1;
  if uid is null then raise exception 'Unauthorized worker test identity required'; end if;
  perform set_config('request.jwt.claim.sub',uid::text,true);
  begin perform public.rr_chat_prepare_accept_count_test71(q.id);raise exception 'UNAUTHORIZED_READ_ACCEPTED';
  exception when others then if sqlerrm='UNAUTHORIZED_READ_ACCEPTED' then raise; end if;end;
  begin perform public.rr_chat_accept_count_test71(q.id,rows);raise exception 'UNAUTHORIZED_SAVE_ACCEPTED';
  exception when others then if sqlerrm='UNAUTHORIZED_SAVE_ACCEPTED' then raise; end if;end;
  raise exception 'RESTORE_AUTH_CASE';
 exception when others then if sqlerrm<>'RESTORE_AUTH_CASE' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',q.selected_receiver_auth_id::text,true);
 insert into accept_count_result values('unrelated_worker_cannot_read_or_accept',true);

 result:=public.rr_chat_accept_count_test71(q.id,rows);
 if result->>'status'<>'COMPLETED' or result->>'accept_count_complete'<>'true' then raise exception 'Full Save not complete'; end if;
 if not exists(select 1 from public.rr_upm_submit_requests_v794 x where x.id=q.id and x.status='COMPLETED' and x.counted_at is not null and x.completed_at is not null and x.lm_counted_total=q.worker_ready_total) then raise exception 'Count and completion not persisted together'; end if;
 if exists(select 1 from public.rr_upm_work_assignments_v8 a where a.id=any(q.assignment_ids) and a.status<>'COMPLETED') then raise exception 'Source work remains working'; end if;
 insert into accept_count_result values('full_save_completes_source_and_count',true);
 result:=public.rr_chat_department_projection_test71('FABRICATION','WORKING');
 if exists(select 1 from jsonb_array_elements(result->'cards') x where x->>'submit_request_id'=q.id::text) then raise exception 'Completed handover remains pending'; end if;
 insert into accept_count_result values('completed_card_removed_from_working',true);
 result:=public.rr_chat_department_projection_test71('FABRICATION','OPEN');
 if not exists(select 1 from jsonb_array_elements(result->'cards') x where x->>'canonical_lot_id'=q.canonical_lot_id and x->>'source_department_code'<>q.department_code and exists(select 1 from jsonb_array_elements(x->'actions') a where a->>'code'='ASSIGN_WORKER')) then raise exception 'Next-stage OPEN assign card missing after %',q.department_code; end if;
 insert into accept_count_result values('next_stage_open_assignment_visible',true);
 select count(*) into before_n from public.rr_upm_submit_audit_v794 where request_id=q.id;
 result:=public.rr_chat_accept_count_test71(q.id,rows);
 select count(*) into n from public.rr_upm_submit_audit_v794 where request_id=q.id;
 if result->>'duplicate_blocked'<>'true' or n<>before_n then raise exception 'Repeat Save duplicated acceptance'; end if;
 insert into accept_count_result values('retry_idempotent',true);
end $$;
select * from accept_count_result order by check_name;
rollback;
