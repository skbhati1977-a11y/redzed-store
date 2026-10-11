-- Keep REAL normalization unchanged; skip identical OPEN writes in TEST.
do $patch$ declare d text; old_fragment text; new_fragment text; begin
select pg_get_functiondef('public.rr_real_chat_reconcile_cutting_v628()'::regprocedure) into d;
old_fragment:=$old$where b.archived_at is null and b.source_module='CUTTING' and b.source_event_type='READY_FOR_CUTTING' and not exists$old$;
new_fragment:=$new$where b.archived_at is null and b.source_module='CUTTING' and b.source_event_type='READY_FOR_CUTTING'
 and (b.data_mode is distinct from 'TEST'
   or b.personal_payload->>'canonical_state' is distinct from 'OPEN'
   or b.personal_payload->>'status' is distinct from 'OPEN'
   or b.group_payload->>'canonical_state' is distinct from 'OPEN'
   or b.group_payload->>'status' is distinct from 'OPEN')
 and not exists$new$;
if position(old_fragment in d)=0 then raise exception 'Expected Cutting OPEN normalization missing'; end if;
execute replace(d,old_fragment,new_fragment);
end $patch$;
-- TEST-only reversible fixture follows canonical parent-child identity and handoff.
do $patch$ declare d text; begin
select pg_get_functiondef('public.rr_test_released_dcard_regression_v502()'::regprocedure) into d;
d:=replace(d,$old$  v_unit uuid:=gen_random_uuid();$old$,$new$  v_unit uuid:=gen_random_uuid();
  v_division integer;$new$);
d:=replace(d,$old$  v_code:='TEST71-DCARD-'$old$,$new$  perform 1 from public.rr_fabric_purchases where id=v_purchase for update;
  select coalesce(max(division_index),0)+1 into v_division
  from public.rr_cb_units where purchase_id=v_purchase;
  v_code:='TEST71-DCARD-'$new$);
d:=replace(d,$old$v_unit,v_purchase,v_code,1,1,v_code||'-D1'$old$,$new$v_unit,v_purchase,v_code,v_division,v_division,v_code||'-D1'$new$);
execute d;
end $patch$;
do $patch$ declare d text; begin
select pg_get_functiondef('public.rr_test_released_dcard_regression_v502()'::regprocedure) into d;
d:=replace(d,$old$or v_open_count<>0 or v_history_count<>1 or v_chat_state<>'CLOSE'
       or v_chat_action is not null or coalesce(jsonb_array_length(v_chat_next),0)<>0$old$,$new$or v_open_count<>0 or v_history_count<>1 or v_chat_state<>'WORKING'
       or v_chat_action is distinct from 'ASSIGN_WORKER'
       or coalesce(jsonb_array_length(v_chat_next),0)<>1
       or v_chat_next->0->>'code' is distinct from 'ASSIGN_WORKER'$new$);
if position($expected$v_chat_state<>'WORKING'$expected$ in d)=0 then raise exception 'Expected released-to-assignment guard missing'; end if;
execute d;
end $patch$;
