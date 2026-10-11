BEGIN;
DO $test$
DECLARE w uuid; d date; r jsonb; a public.rr_attendance_day_v777_2%rowtype;
BEGIN
 SELECT worker_id INTO w FROM public.rr_worker_payroll_profile_v777_2 WHERE data_mode='TEST' AND worker_category='SALARIED' AND status='ACTIVE' AND effective_from<='2026-08-01' ORDER BY worker_id LIMIT 1;
 FOREACH d IN ARRAY ARRAY['2026-08-15'::date,'2026-08-28'::date,'2026-10-05'::date] LOOP
  r:=public.rr_calculate_attendance_day_v778_2(w,d,'TEST');
  SELECT * INTO a FROM public.rr_attendance_day_v777_2 WHERE worker_id=w AND attendance_date=d AND data_mode='TEST';
  IF a.attendance_status NOT IN ('HOLIDAY','WEEKLY_OFF') OR a.normal_payable_minutes<>600 OR a.net_deduction_minutes<>0 OR a.net_extra_work_minutes<>0 OR a.approval_status<>'APPROVED' THEN RAISE EXCEPTION 'Paid day failed: % %',d,row_to_json(a);END IF;
 END LOOP;
 r:=public.rr_calculate_attendance_day_v778_2(w,'2026-10-04','TEST');
 IF r->>'attendance_status'<>'ABSENT' THEN RAISE EXCEPTION 'Unlisted Sunday incorrectly holiday';END IF;
 IF (SELECT count(*) FROM public.rr_holiday_calendar_v777_2 WHERE data_mode='TEST' AND is_active AND extract(year FROM holiday_date)=2026)<>7 THEN RAISE EXCEPTION 'Expected only seven holidays'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_shift_master_v777_2 WHERE is_active AND lunch_is_paid AND lunch_end-lunch_start=interval '30 minutes' AND normal_payable_minutes=600) THEN RAISE EXCEPTION 'Paid lunch failed'; END IF;
END $test$;
SELECT jsonb_build_object('paid_holidays_and_monday','PASS','no_deduction_no_double_extra','PASS','ordinary_sunday','PASS','paid_lunch_30_minutes','PASS','business_rows','ROLLBACK') result;
ROLLBACK;