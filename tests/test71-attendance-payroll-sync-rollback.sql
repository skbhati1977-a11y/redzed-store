BEGIN;
SELECT set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
DO $$DECLARE w uuid:='3cb8f1b4-74ab-4230-b2fb-4ebed6826249';j jsonb;d public.rr_attendance_day_v777_2%rowtype;blocked boolean;BEGIN
 j:=public.rr_chat_attendance_action_test71(w,'CHECK_IN',28.662889,77.259056,10,gen_random_uuid()::text);
 SELECT * INTO d FROM public.rr_attendance_day_v777_2 WHERE worker_id=w AND data_mode='TEST';
 ASSERT d.approval_status='PENDING' AND d.net_deduction_minutes=0 AND d.normal_payable_minutes=0,'Incomplete day cannot earn/finalise deduction';
 ASSERT (public.rr_attendance_actor_v778_2(w)->>'owner_admin')::boolean,'Super Admin parity';
 blocked:=false;BEGIN PERFORM public.rr_chat_attendance_action_test71(w,'CHECK_OUT',28.662889,77.259056,10,null);EXCEPTION WHEN others THEN blocked:=true;END;
 ASSERT blocked,'Source ID missing rejected';
 j:=public.rr_chat_attendance_action_test71(w,'CHECK_OUT',28.662889,77.259056,10,gen_random_uuid()::text);
 SELECT * INTO d FROM public.rr_attendance_day_v777_2 WHERE worker_id=w AND data_mode='TEST';
 ASSERT d.approval_status='APPROVED' AND d.last_check_out IS NOT NULL,'Completed day feeds canonical payroll';
 ASSERT (SELECT count(*) FROM public.rr_attendance_day_v777_2 WHERE worker_id=w AND data_mode='TEST')=1,'one payroll day';
END $$;
SELECT jsonb_build_object('incomplete_no_final_deduction',true,'superadmin_parity',true,'checkout_canonical_payroll',true,'one_day',true) tests;
ROLLBACK;