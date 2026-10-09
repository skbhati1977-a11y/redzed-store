-- Run with both TEST71 migrations inside BEGIN/ROLLBACK.
create temp table queue_checks(name text,passed boolean);
DO $$
declare d text;s text;p jsonb;x jsonb;n int;q public.rr_upm_submit_requests_v794%rowtype;ctx jsonb;counts jsonb;original jsonb;result jsonb;a public.rr_upm_work_assignments_v8%rowtype;uid uuid;
begin
 select selected_receiver_auth_id into uid from public.rr_upm_submit_requests_v794 where status='LM_ACCEPTED' and selected_receiver_auth_id is not null limit 1;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 perform set_config('request.headers','{"origin":"https://test71-workspace.app.github.dev","x-client-info":"redzed-test71"}',true);
 perform set_config('rr_chat_notifications_test71.test_run','on',true);
 foreach d in array array['FABRICATION','PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING'] loop
  p:=public.rr_chat_department_projection_test71(d,'OPEN');
  if exists(select 1 from jsonb_array_elements(p->'cards') c where not exists(select 1 from jsonb_array_elements(c->'actions')z where coalesce(z->>'code',z#>>'{}')='ASSIGN_WORKER') or c->>'resolved_work_state'<>'READY_TO_ASSIGN') then raise exception 'OPEN includes assigned count %',d;end if;
  p:=public.rr_chat_department_projection_test71(d,'WORKING');
  if exists(select 1 from jsonb_array_elements(p->'cards')c where exists(select 1 from jsonb_array_elements(c->'actions')z where coalesce(z->>'code',z#>>'{}')='SUBMIT') and exists(select 1 from public.rr_upm_submit_requests_v794 z where (c->>'assignment_id')::uuid=any(z.assignment_ids) and z.status not in('CANCELLED','CANCELED','REJECTED','VOID'))) then raise exception 'Submitted assignment remains Submit %',d;end if;
 end loop;
 insert into queue_checks values('all_departments_open_assignment_only_and_submit_supersession',true);
 p:=public.rr_chat_department_projection_test71('FABRICATION','WORKING');
 select count(*) into n from public.rr_upm_submit_requests_v794 where status in('WAITING_LM','ESCALATED','LM_ACCEPTED');
 if (select count(*) from jsonb_array_elements(p->'cards')c where c->>'submit_request_id' is not null and c->>'submit_status'='NOT_ACCEPTED')<>n then raise exception 'Missing handover from shared staff queue';end if;
 if exists(select 1 from jsonb_array_elements(p->'cards')c where c->>'receipt_kind'='ASSIGNED_GOODS' and c->>'queue_lane'<>'WORKER') then raise exception 'Initial receipt mixed into staff handover queue';end if;
 insert into queue_checks values('every_pending_handover_including_null_target_visible',true);
 ctx:=public.rr_chat_source_card_receipts_test71('FABRICATION','WORKING');
 if exists(select 1 from jsonb_array_elements(ctx)c where c->>'submit_request_id' is not null and c->>'actor_action_label'<>'Submit') then raise exception 'Incomplete handover shows Accepted last action';end if;
 if exists(select 1 from jsonb_array_elements(ctx)c where c->>'event_key' like 'UPM_WORKER_LOT:%' and c->>'actor_action_label'<>'Assign Work') then raise exception 'Worker last action is not assignment';end if;
 insert into queue_checks values('stage_last_actions_are_submit_and_assign_not_partial_accept',true);
 select * into q from public.rr_upm_submit_requests_v794 where status='WAITING_LM' and target_department_code is null limit 1;
 if q.id is not null then
  original:=to_jsonb(q);ctx:=public.rr_chat_prepare_accept_count_test71(q.id);
  if (select to_jsonb(z) from public.rr_upm_submit_requests_v794 z where id=q.id)<>original then raise exception 'Opening legacy handover mutated it';end if;
  select jsonb_agg(jsonb_build_object('colour_code',c->>'colour_code','size_code',z->>'size_code','qty',coalesce(z->'ready_qty',z->'assigned_qty'))) into counts from jsonb_array_elements(q.colour_rows)c cross join lateral jsonb_array_elements(c->'sizes')z;
  -- Actual Rate remains a gate; fixture rates exist only in this rolled-back test.
  begin perform public.rr_chat_accept_count_test71(q.id,counts);exception when others then
   if sqlerrm not like '%Actual Rate%' then raise;end if;
   if (select to_jsonb(z) from public.rr_upm_submit_requests_v794 z where id=q.id)<>original then raise exception 'Rate failure left a partial acceptance';end if;
  end;
  update public.rr_upm_work_assignments_v8 set actual_rate=1 where canonical_lot_id=q.canonical_lot_id and public.rr_upm_core_department_v9077(department_code)=q.department_code and status not in('CANCELLED','CANCELED','VOID','REJECTED');
  result:=public.rr_chat_accept_count_test71(q.id,counts);
  if result->>'status'<>'COMPLETED' then raise exception 'Legacy null target cannot complete';end if;
  p:=public.rr_chat_department_projection_test71('FABRICATION','WORKING');
  if exists(select 1 from jsonb_array_elements(p->'cards')c where c->>'submit_request_id'=q.id::text) then raise exception 'Completed still working';end if;
  p:=public.rr_chat_department_projection_test71('FABRICATION','OPEN');
  if not exists(select 1 from jsonb_array_elements(p->'cards')c where c->>'canonical_lot_id'=q.canonical_lot_id) then raise exception 'Next assignment missing';end if;
 end if;
 insert into queue_checks values('null_target_save_atomic_and_next_assignment_open',true);
 select a0.* into a from public.rr_upm_work_assignments_v8 a0 join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=a0.id where a0.status in('ASSIGNED','IN_PROGRESS') and r.status='PENDING' and not exists(select 1 from public.rr_upm_submit_requests_v794 q0 where a0.id=any(q0.assignment_ids) and q0.status not in('CANCELLED','CANCELED','REJECTED','VOID')) limit 1;
 if a.id is null then raise exception 'Receipt fixture missing';end if;
 ctx:=public.rr_chat_assignment_count_context_test71(a.id);
 select jsonb_agg(jsonb_build_object('assignment_id',z->>'assignment_id','confirmed_qty',z->'expected_qty')) into counts from jsonb_array_elements(ctx->'rows')z;
 begin perform public.rr_chat_assignment_count_save_test71(a.id,'[]');raise exception 'BAD_COUNT_ACCEPTED';exception when others then if sqlerrm='BAD_COUNT_ACCEPTED' then raise;end if;end;
 begin perform public.rr_chat_assignment_count_save_test71(a.id,jsonb_set(counts,'{0,confirmed_qty}','1.5'));raise exception 'BAD_COUNT_ACCEPTED';exception when others then if sqlerrm='BAD_COUNT_ACCEPTED' then raise;end if;end;
 result:=public.rr_chat_assignment_count_save_test71(a.id,counts);
 if result->>'status'<>'COMPLETED' then raise exception 'Assigned receipt incomplete';end if;
 if exists(select 1 from jsonb_array_elements(counts)z join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id::text=z->>'assignment_id' where r.status<>'CONFIRMED' or r.confirmed_by is distinct from uid) then raise exception 'Count or actual actor lost';end if;
 p:=public.rr_chat_department_projection_test71(a.department_code,'WORKING');
 if not exists(select 1 from jsonb_array_elements(p->'cards')c where c->>'assignment_id'=a.id::text and exists(select 1 from jsonb_array_elements(c->'actions')z where coalesce(z->>'code',z#>>'{}')='SUBMIT')) then raise exception 'Receipt did not become Worker Submit';end if;
 insert into queue_checks values('staff_full_assigned_receipt_count_real_actor_and_worker_submit',true);
 -- Ordinary unrelated workers cannot read or save somebody else's counts.
 select auth_user_id into uid from public.rr_user_profiles where is_active and upper(role_code)='WORKER' and public.rr_canonical_worker_id_v264(auth_user_id)<>public.rr_canonical_worker_id_v264(a.worker_id) limit 1;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 begin perform public.rr_chat_assignment_count_context_test71(a.id);raise exception 'UNRELATED_WORKER_ALLOWED';exception when others then if sqlerrm='UNRELATED_WORKER_ALLOWED' then raise;end if;end;
 begin perform public.rr_chat_assignment_count_save_test71(a.id,counts);raise exception 'UNRELATED_WORKER_ALLOWED';exception when others then if sqlerrm='UNRELATED_WORKER_ALLOWED' then raise;end if;end;
 insert into queue_checks values('unrelated_worker_denied_context_and_save',true);
end $$;
select * from queue_checks;
