BEGIN;
DO $test$
DECLARE w uuid;rid uuid; d date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
 SELECT worker_id INTO w FROM public.rr_worker_attendance_policy_v778_1 WHERE data_mode='TEST' AND status='ACTIVE' ORDER BY worker_id LIMIT 1;
 INSERT INTO public.rr_attendance_reminder_state_v778_2(worker_id,business_date,reminder_type,first_due_at,next_due_at,data_mode)
 VALUES(w,d,'CHECKIN_PENDING',now()-interval '1 minute',now(),'TEST') RETURNING reminder_id INTO rid;
 IF NOT public.rr_attendance_push_pending_test71(rid,w) THEN RAISE EXCEPTION 'Eligible own reminder blocked';END IF;
 IF public.rr_attendance_push_pending_test71(rid,gen_random_uuid()) THEN RAISE EXCEPTION 'Cross worker reminder allowed';END IF;
 INSERT INTO public.rr_regular_attendance_sessions_v778_2(worker_id,business_date,checkin_at,checkin_latitude,checkin_longitude,checkin_inside_geofence,source_checkin_id,data_mode)
 VALUES(w,d,now(),0,0,true,gen_random_uuid(),'TEST');
 IF public.rr_attendance_push_pending_test71(rid,w) THEN RAISE EXCEPTION 'Already checked in push allowed';END IF;
 UPDATE public.rr_attendance_reminder_state_v778_2 SET status='RESOLVED' WHERE reminder_id=rid;
 IF public.rr_attendance_push_pending_test71(rid,w) THEN RAISE EXCEPTION 'Resolved push allowed';END IF;
 IF has_function_privilege('anon','public.rr_attendance_push_pending_test71(uuid,uuid)','EXECUTE') OR has_function_privilege('authenticated','public.rr_attendance_push_pending_test71(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Private delivery guard exposed';END IF;
END $test$;
SELECT '{"own_worker_pending":"PASS","cross_worker_denied":"PASS","punch_resolved_skip":"PASS","private_guard":"PASS","test_rows":"ROLLBACK"}'::jsonb result;
ROLLBACK;