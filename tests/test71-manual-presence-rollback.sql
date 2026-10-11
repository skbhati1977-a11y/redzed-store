BEGIN;
DO $test$
DECLARE admin_uid uuid;worker_uid uuid;w uuid;rid uuid;runid uuid:=gen_random_uuid();j jsonb;g record;before_days integer;before_pay integer;
BEGIN
 SELECT auth_user_id INTO admin_uid FROM public.rr_user_profiles WHERE is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND upper(role_code) IN('SUPER_ADMIN','ADMIN','OWNER') AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT wd.worker_id,wd.linked_auth_user_id INTO w,worker_uid FROM public.rr_worker_directory_compat_v264 wd JOIN public.rr_user_profiles u ON u.auth_user_id=wd.linked_auth_user_id AND u.is_active AND upper(coalesce(u.access_status,'ACTIVE'))='ACTIVE'
 WHERE wd.is_active AND upper(u.role_code) NOT IN('OWNER','SUPER_ADMIN','ADMIN') AND EXISTS(SELECT 1 FROM public.rr_active_payroll_profile_v778_2(wd.worker_id,(now() AT TIME ZONE 'Asia/Kolkata')::date,'TEST') p WHERE p.worker_category='SALARIED') LIMIT 1;
 IF admin_uid IS NULL OR worker_uid IS NULL THEN RAISE EXCEPTION 'Required test identities missing';END IF;
 SELECT count(*) INTO before_days FROM public.rr_attendance_day_v777_2;SELECT count(*) INTO before_pay FROM public.rr_payroll_runs_v778;
 INSERT INTO public.rr_regular_attendance_sessions_v778_2(worker_id,business_date,checkin_at,checkin_latitude,checkin_longitude,checkin_inside_geofence,source_checkin_id,data_mode)
 VALUES(w,(now() AT TIME ZONE 'Asia/Kolkata')::date,now(),0,0,true,gen_random_uuid(),'TEST');
 PERFORM set_config('request.jwt.claim.sub',worker_uid::text,true);
 BEGIN PERFORM public.rr_attendance_presence_run_test71(runid,w,false);RAISE EXCEPTION 'Worker run should fail';EXCEPTION WHEN OTHERS THEN IF SQLERRM='Worker run should fail' THEN RAISE;END IF;END;
 PERFORM set_config('request.jwt.claim.sub',admin_uid::text,true);
 j:=public.rr_attendance_presence_run_test71(runid,w,false);IF (j->>'requests')::integer<>1 THEN RAISE EXCEPTION 'Individual Admin run failed %',j;END IF;
 j:=public.rr_attendance_presence_run_test71(runid,w,false);IF (j->>'requests')::integer<>0 THEN RAISE EXCEPTION 'Duplicate run';END IF;
 SELECT id INTO rid FROM public.rr_attendance_presence_checks_test71 WHERE worker_id=w AND run_id=runid;
 IF NOT public.rr_presence_push_pending_test71(rid,w,false) OR public.rr_presence_push_pending_test71(rid,gen_random_uuid(),false) THEN RAISE EXCEPTION 'Push recipient guard failed';END IF;
 PERFORM set_config('request.jwt.claim.sub',worker_uid::text,true);
 j:=public.rr_attendance_presence_respond_test71(rid,NULL,NULL,NULL,'PERMISSION_DENIED');IF j->>'status'<>'REVIEW_REQUIRED' THEN RAISE EXCEPTION 'GPS off not review';END IF;
 SELECT p.* INTO g FROM public.rr_attendance_premises_v778_1 p JOIN public.rr_worker_attendance_premises_v778_1 wp ON wp.premise_id=p.premise_id WHERE wp.worker_id=w AND wp.is_active AND p.data_mode='TEST' AND p.is_active LIMIT 1;
 IF g.premise_id IS NULL THEN RAISE EXCEPTION 'No allowed premise';END IF;
 j:=public.rr_attendance_presence_respond_test71(rid,g.latitude,g.longitude,10,NULL);IF NOT (j->>'verified')::boolean THEN RAISE EXCEPTION 'Inside GPS failed';END IF;
 IF public.rr_presence_push_pending_test71(rid,w,false) THEN RAISE EXCEPTION 'Verified push should stop';END IF;
 PERFORM set_config('request.jwt.claim.sub',admin_uid::text,true);
 j:=public.rr_attendance_presence_run_test71(gen_random_uuid(),w,false);
 SELECT id INTO rid FROM public.rr_attendance_presence_checks_test71 WHERE worker_id=w AND status='PENDING' ORDER BY created_at DESC LIMIT 1;
 PERFORM public.rr_presence_worker_switch_test71(w,false);
 IF EXISTS(SELECT 1 FROM public.rr_attendance_presence_checks_test71 WHERE id=rid AND status='PENDING') THEN RAISE EXCEPTION 'OFF did not cancel';END IF;
 j:=public.rr_attendance_presence_run_test71(gen_random_uuid(),w,false);IF (j->>'requests')::integer<>0 THEN RAISE EXCEPTION 'OFF worker run';END IF;
 PERFORM public.rr_presence_worker_switch_test71(w,true);
 j:=public.rr_attendance_presence_run_test71(gen_random_uuid(),w,false);IF (j->>'requests')::integer<>1 THEN RAISE EXCEPTION 'ON worker run failed';END IF;
 SELECT id INTO rid FROM public.rr_attendance_presence_checks_test71 WHERE worker_id=w AND status='PENDING' LIMIT 1;
 UPDATE public.rr_attendance_presence_checks_test71 SET scheduled_at=now()-interval '20 minutes',deadline_at=now()-interval '10 minutes' WHERE id=rid;
 j:=public.rr_attendance_presence_run_test71(gen_random_uuid(),w,true);IF (j->>'requests')::integer<>1 THEN RAISE EXCEPTION 'Manual review push failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_targeted_push_outbox_v708 WHERE payload->>'source'='PRESENCE_REVIEW_TEST71' AND payload->>'request_id'=rid::text) THEN RAISE EXCEPTION 'Review outbox absent';END IF;
 j:=public.rr_attendance_presence_review_test71(rid,'Supervisor presence checked in person');IF (j->>'salary_deduction_applied')::boolean THEN RAISE EXCEPTION 'Unexpected deduction';END IF;
 IF (SELECT count(*) FROM public.rr_attendance_day_v777_2)<>before_days OR (SELECT count(*) FROM public.rr_payroll_runs_v778)<>before_pay THEN RAISE EXCEPTION 'Presence changed payroll';END IF;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname ILIKE '%presence%') THEN RAISE EXCEPTION 'Automatic presence job exists';END IF;
END $test$;
SELECT '{"admin_manual_run":"PASS","worker_run_denied":"PASS","individual_switch":"PASS","gps_permission_review":"PASS","inside_verify":"PASS","manual_staff_review":"PASS","no_payroll_changes":"PASS","no_auto_presence_cron":"PASS","business_and_push_rows":"ROLLBACK"}'::jsonb result;
ROLLBACK;