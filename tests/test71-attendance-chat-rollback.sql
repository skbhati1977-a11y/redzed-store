
BEGIN;
SELECT set_config('request.jwt.claim.sub','c2411a86-84ed-4c36-8789-bd4410f87cdf',true);
CREATE TEMP TABLE att_test_result(label text,result jsonb);
GRANT ALL ON att_test_result TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
DECLARE w uuid:='3cb8f1b4-74ab-4230-b2fb-4ebed6826249';j jsonb;q jsonb;blocked boolean;id text:=gen_random_uuid()::text;
BEGIN
 q:=public.rr_chat_attendance_queue_test71(null,w);
 ASSERT jsonb_array_length(q->'cards')=1,'Worker must see own card only';
 ASSERT q->'cards'->0->>'action'='CHECK_IN','Configured CHECK_IN required';
 blocked:=false;BEGIN q:=public.rr_chat_attendance_queue_test71(null,'3a1ca08c-ffda-49be-a54c-5c6863902596');blocked:=jsonb_array_length(q->'cards')=0;EXCEPTION WHEN others THEN blocked:=true;END;
 ASSERT blocked,'Other-department read must fail or be empty'; INSERT INTO att_test_result VALUES('own_scope',to_jsonb(blocked));
 blocked:=false;BEGIN PERFORM public.rr_chat_attendance_action_test71(w,'CHECK_IN',0,0,10,id);EXCEPTION WHEN others THEN blocked:=true;END;
 ASSERT blocked,'Outside check-in blocked';INSERT INTO att_test_result VALUES('outside_blocked',to_jsonb(blocked));
 blocked:=false;BEGIN PERFORM public.rr_chat_attendance_action_test71(w,'CHECK_IN',28.662889,77.259056,1000,id);EXCEPTION WHEN others THEN blocked:=true;END;
 ASSERT blocked,'Bad accuracy blocked';INSERT INTO att_test_result VALUES('accuracy_blocked',to_jsonb(blocked));
 j:=public.rr_chat_attendance_action_test71(w,'CHECK_IN',28.662889,77.259056,10,id);
 ASSERT (j->>'ok')::boolean,'check-in failed';
 q:=public.rr_chat_attendance_queue_test71(null,w);
 ASSERT q->'cards'->0->>'chat_status'='WORKING' AND q->'cards'->0->>'action'='CHECK_OUT','check-in moves to WORKING';
 INSERT INTO att_test_result VALUES('checked_in_working',to_jsonb(true));
 j:=public.rr_chat_attendance_action_test71(w,'CHECK_IN',28.662889,77.259056,10,id);
 ASSERT (j->>'duplicate')::boolean,'duplicate tap dedupe required';
 INSERT INTO att_test_result VALUES('duplicate_checkin',j);
 j:=public.rr_chat_attendance_action_test71(w,'CHECK_OUT',28.662889,77.259056,10,gen_random_uuid()::text);
 ASSERT (j->>'ok')::boolean,'checkout failed';
 q:=public.rr_chat_attendance_queue_test71(null,w);
 ASSERT jsonb_array_length(q->'cards')=1 AND q->'cards'->0->>'check_out_at' IS NOT NULL AND q->'cards'->0->>'action' IS NULL,'checkout one card no pending action';
 INSERT INTO att_test_result VALUES('checked_out_same_card',to_jsonb(true));
 j:=public.rr_chat_attendance_action_test71(w,'CHECK_OUT',28.662889,77.259056,10,gen_random_uuid()::text);
 ASSERT (j->>'duplicate')::boolean,'duplicate checkout';INSERT INTO att_test_result VALUES('duplicate_checkout',j);
END $$;
RESET ROLE;
SELECT jsonb_build_object('after_checkout_deduction', (SELECT net_deduction_minutes FROM public.rr_attendance_day_v777_2 WHERE worker_id='3cb8f1b4-74ab-4230-b2fb-4ebed6826249' AND data_mode='TEST' LIMIT 1),'canonical_day_count',(SELECT count(*) FROM public.rr_attendance_day_v777_2),'sessions',(SELECT count(*) FROM public.rr_regular_attendance_sessions_v778_2),'results',(SELECT jsonb_agg(jsonb_build_object('test',label,'pass',result)) FROM att_test_result)) results;
ROLLBACK;
