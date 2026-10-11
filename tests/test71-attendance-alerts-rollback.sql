BEGIN;
DO $test$
DECLARE w uuid;j jsonb;z integer;
BEGIN
 j:=public.rr_attendance_alert_tick_test71('2026-10-11 09:49+05:30');IF (j->>'queued')::integer<>0 THEN RAISE EXCEPTION 'Alert before 9:50';END IF;
 j:=public.rr_attendance_alert_tick_test71('2026-10-11 09:50+05:30');IF (j->>'queued')::integer<>14 THEN RAISE EXCEPTION 'Expected all 14 salaried reminders: %',j;END IF;
 j:=public.rr_attendance_alert_tick_test71('2026-10-11 09:50+05:30');IF (j->>'queued')::integer<>0 THEN RAISE EXCEPTION 'Duplicate alert';END IF;
 SELECT worker_id INTO w FROM public.rr_worker_attendance_policy_v778_1 WHERE data_mode='TEST' AND status='ACTIVE' ORDER BY worker_id LIMIT 1;
 INSERT INTO public.rr_regular_attendance_sessions_v778_2(worker_id,business_date,checkin_at,checkin_latitude,checkin_longitude,checkin_inside_geofence,source_checkin_id,data_mode)
 VALUES(w,'2026-10-11','2026-10-11 10:00+05:30',0,0,true,gen_random_uuid(),'TEST');
 j:=public.rr_attendance_alert_tick_test71('2026-10-11 20:09+05:30');
 IF EXISTS(SELECT 1 FROM public.rr_attendance_reminder_state_v778_2 WHERE worker_id=w AND business_date='2026-10-11' AND reminder_type='CHECKOUT_PENDING') THEN RAISE EXCEPTION 'Checkout alert early';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_attendance_reminder_state_v778_2 WHERE worker_id=w AND business_date='2026-10-11' AND reminder_type='CHECKIN_PENDING' AND status='RESOLVED') THEN RAISE EXCEPTION 'Checkin did not resolve reminder';END IF;
 j:=public.rr_attendance_alert_tick_test71('2026-10-11 20:10+05:30');
 IF NOT EXISTS(SELECT 1 FROM public.rr_attendance_reminder_state_v778_2 WHERE worker_id=w AND business_date='2026-10-11' AND reminder_type='CHECKOUT_PENDING' AND first_due_at='2026-10-11 20:10+05:30' AND delivered_count=1) THEN RAISE EXCEPTION 'Checkout 8:10 alert missing';END IF;
 UPDATE public.rr_regular_attendance_sessions_v778_2 SET checkout_at='2026-10-11 20:11+05:30' WHERE worker_id=w AND business_date='2026-10-11' AND data_mode='TEST';
 j:=public.rr_attendance_alert_tick_test71('2026-10-11 20:11+05:30');
 IF NOT EXISTS(SELECT 1 FROM public.rr_attendance_reminder_state_v778_2 WHERE worker_id=w AND business_date='2026-10-11' AND reminder_type='CHECKOUT_PENDING' AND status='RESOLVED') THEN RAISE EXCEPTION 'Checkout did not stop reminder';END IF;
 j:=public.rr_attendance_alert_tick_test71('2026-10-12 09:50+05:30');IF (j->>'queued')::integer<>0 THEN RAISE EXCEPTION 'Monday alert';END IF;
 j:=public.rr_attendance_alert_tick_test71('2026-11-08 09:50+05:30');IF (j->>'queued')::integer<>0 THEN RAISE EXCEPTION 'Paid holiday alert';END IF;
 UPDATE public.rr_worker_attendance_policy_v778_1 SET checkin_alert_before_minutes=5,checkout_alert_after_minutes=5 WHERE worker_id=w AND data_mode='TEST';
 IF EXISTS(SELECT 1 FROM public.rr_worker_attendance_policy_v778_1 WHERE worker_id=w AND data_mode='TEST' AND (checkin_alert_before_minutes<>10 OR checkout_alert_after_minutes<>10)) THEN RAISE EXCEPTION 'Universal alert mapping failed';END IF;
END $test$;
SELECT '{"9_50_checkin":"PASS","20_10_checkout":"PASS","all_14_workers":"PASS","duplicate_suppression":"PASS","stop_after_punch":"PASS","monday_holiday_skip":"PASS","universal_defaults":"PASS","data_and_push_queue":"ROLLBACK"}'::jsonb result;
ROLLBACK;