BEGIN;
DO $test$
DECLARE p public.rr_worker_payroll_profile_v777_2%rowtype;
BEGIN
 SELECT * INTO p FROM public.rr_worker_payroll_profile_v777_2 WHERE data_mode='TEST' AND worker_category='SALARIED' AND status='ACTIVE' ORDER BY worker_id LIMIT 1;
 UPDATE public.rr_shift_master_v777_2 SET lunch_end=lunch_start+interval '45 minutes' WHERE shift_id=p.shift_id;
 UPDATE public.rr_worker_payroll_profile_v777_2 SET weekly_holiday_isodow=7 WHERE profile_id=p.profile_id;
 IF NOT EXISTS(SELECT 1 FROM public.rr_worker_payroll_profile_v777_2 WHERE profile_id=p.profile_id AND weekly_holiday_isodow=1) THEN RAISE EXCEPTION 'Monday automatic mapping failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_shift_master_v777_2 WHERE shift_id=p.shift_id AND lunch_is_paid AND lunch_end-lunch_start=interval '30 minutes') THEN RAISE EXCEPTION 'Lunch automatic mapping failed';END IF;
 UPDATE public.rr_worker_payroll_profile_v777_2 SET effective_from='2099-01-01',effective_to=NULL WHERE profile_id=p.profile_id;
 IF NOT EXISTS(SELECT 1 FROM public.rr_worker_attendance_policy_v778_1 WHERE worker_id=public.rr_canonical_worker_id_v264(p.worker_id) AND effective_from<='2099-01-01' AND (effective_to IS NULL OR effective_to>='2099-01-01') AND status='ACTIVE' AND data_mode='TEST') THEN RAISE EXCEPTION 'Future worker attendance policy not mapped';END IF;
 UPDATE public.rr_payroll_holidays_v778 SET is_active=false WHERE holiday_date='2026-11-09';
 IF NOT EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 WHERE data_mode='TEST' AND holiday_date='2026-11-09' AND NOT is_active AND is_paid_holiday) THEN RAISE EXCEPTION 'Payroll to attendance calendar mapping failed';END IF;
 UPDATE public.rr_holiday_calendar_v777_2 SET is_active=true WHERE data_mode='TEST' AND holiday_date='2026-11-09';
 IF NOT EXISTS(SELECT 1 FROM public.rr_payroll_holidays_v778 WHERE holiday_date='2026-11-09' AND is_active) THEN RAISE EXCEPTION 'Attendance calendar to payroll mapping failed';END IF;
END $test$;
SELECT '{"existing_and_future_salaried_mapping":"PASS","monday_paid_lunch":"PASS","two_way_calendar_sync":"PASS","test_changes":"ROLLED_BACK"}'::jsonb result;
ROLLBACK;