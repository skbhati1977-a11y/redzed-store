-- User-approved salaried policy: Monday and only seven named paid holidays.
-- 2026 calendar: Vishwakarma Day is the day after Diwali (9 November).
-- Paid lunch is 30 minutes; preserves 600 paid shift minutes.

ALTER TABLE public.rr_holiday_calendar_v777_2 DROP CONSTRAINT rr_holiday_calendar_v777_2_holiday_name_check;
ALTER TABLE public.rr_holiday_calendar_v777_2 ADD CONSTRAINT rr_holiday_calendar_v777_2_holiday_name_check CHECK(holiday_name IN ('REPUBLIC_DAY','HOLI','EID_UL_FITR','EID_UL_ADHA','RAKSHA_BANDHAN','INDEPENDENCE_DAY','VISHWAKARMA_DAY','DIWALI','BHAI_DOOJ'));
ALTER TABLE public.rr_attendance_daily_minutes_v778_2 DROP CONSTRAINT rr_attendance_daily_minutes_v778_2_attendance_status_check;
ALTER TABLE public.rr_attendance_daily_minutes_v778_2 ADD CONSTRAINT rr_attendance_daily_minutes_v778_2_attendance_status_check CHECK(attendance_status IN ('PENDING','PRESENT','ABSENT','ON_LEAVE','HOLIDAY_WORK','REVIEW_REQUIRED','HOLIDAY','WEEKLY_OFF'));
UPDATE public.rr_shift_master_v777_2 SET lunch_end=lunch_start+interval '30 minutes',lunch_is_paid=true,updated_at=now() WHERE is_active AND shift_id IN (SELECT shift_id FROM public.rr_worker_payroll_profile_v777_2 WHERE data_mode='TEST' AND worker_category='SALARIED' AND status='ACTIVE');
UPDATE public.rr_worker_payroll_profile_v777_2 SET weekly_holiday_isodow=1 WHERE data_mode='TEST' AND worker_category='SALARIED' AND status='ACTIVE' AND weekly_holiday_isodow IS DISTINCT FROM 1;
WITH h(d,n) AS (VALUES ('2026-01-26'::date,'REPUBLIC_DAY'),('2026-03-04'::date,'HOLI'),('2026-08-15'::date,'INDEPENDENCE_DAY'),('2026-08-28'::date,'RAKSHA_BANDHAN'),('2026-11-08'::date,'DIWALI'),('2026-11-09'::date,'VISHWAKARMA_DAY'),('2026-11-11'::date,'BHAI_DOOJ'))
INSERT INTO public.rr_holiday_calendar_v777_2(holiday_date,holiday_name,applies_to,is_paid_holiday,holiday_multiplier,data_mode,is_active)
SELECT d,n,'SALARIED_ONLY',true,1,'TEST',true FROM h WHERE NOT EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 c WHERE c.holiday_date=h.d AND c.data_mode='TEST');
UPDATE public.rr_holiday_calendar_v777_2 SET is_paid_holiday=true,holiday_multiplier=1,is_active=true,updated_at=now() WHERE data_mode='TEST' AND holiday_name IN ('REPUBLIC_DAY','HOLI','INDEPENDENCE_DAY','RAKSHA_BANDHAN','DIWALI','VISHWAKARMA_DAY','BHAI_DOOJ') AND extract(year FROM holiday_date)=2026;
INSERT INTO public.rr_payroll_holidays_v778(holiday_date,holiday_name,extra_pay_factor,is_active,remarks)
SELECT holiday_date,holiday_name,0,true,'Paid salaried holiday; no additional holiday-work premium configured.'
FROM public.rr_holiday_calendar_v777_2 WHERE data_mode='TEST' AND is_active AND extract(year FROM holiday_date)=2026
ON CONFLICT(holiday_date) DO UPDATE SET holiday_name=excluded.holiday_name,extra_pay_factor=0,is_active=true,remarks=excluded.remarks,updated_at=now();

CREATE OR REPLACE FUNCTION public.rr_calculate_attendance_day_v778_2(p_worker_id uuid, p_business_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_regular public.rr_regular_attendance_sessions_v778_2%rowtype;
  v_checkin_local timestamp;
  v_checkout_local timestamp;
  v_early_in integer:=0;
  v_late_in integer:=0;
  v_early_out integer:=0;
  v_ot integer:=0;
  v_holiday integer:=0;
  v_net integer:=0;
  v_status text:='PENDING';
begin
  if p_business_date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'Future attendance cannot be marked or calculated.'; end if;
  select * into v_policy
  from public.rr_current_attendance_policy_v778_2(
    p_worker_id,p_business_date,v_mode
  );

  if exists(
    select 1
    from public.rr_worker_leave_requests_v778_2 l
    where l.worker_id=p_worker_id
      and l.status='APPROVED'
      and p_business_date between l.leave_from and l.leave_to
      and l.data_mode=v_mode
  ) then
    v_status:='ON_LEAVE';
  end if;

  select * into v_regular
  from public.rr_regular_attendance_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=p_business_date
    and data_mode=v_mode
  limit 1;

  if found then
    v_checkin_local:=v_regular.checkin_at at time zone 'Asia/Kolkata';
    v_checkout_local:=v_regular.checkout_at at time zone 'Asia/Kolkata';

    if v_policy.early_checkin_payable
       and v_checkin_local::time<time '10:00'
    then
      v_early_in:=floor(extract(epoch from(
        (p_business_date+time '10:00')-v_checkin_local
      ))/60)::integer;
    end if;

    if v_checkin_local::time>time '10:10' then
      v_late_in:=floor(extract(epoch from(
        v_checkin_local-(p_business_date+time '10:10')
      ))/60)::integer;
    end if;

    if v_checkout_local is not null
       and v_checkout_local::time<time '20:00'
    then
      v_early_out:=floor(extract(epoch from(
        (p_business_date+time '20:00')-v_checkout_local
      ))/60)::integer;
    end if;

    v_status:=case
      when v_regular.checkout_at is null then 'REVIEW_REQUIRED'
      else 'PRESENT'
    end;
  elsif v_status<>'ON_LEAVE' then
    v_status:='ABSENT';
    if v_mode='TEST' AND exists(select 1 from public.rr_active_payroll_profile_v778_2(p_worker_id,p_business_date,v_mode) p where p.worker_category='SALARIED') then
      if exists(select 1 from public.rr_holiday_calendar_v777_2 h where h.holiday_date=p_business_date and h.data_mode=v_mode and h.is_active and h.is_paid_holiday and h.applies_to in ('ALL','SALARIED_ONLY')) then
        v_status:='HOLIDAY';
      elsif exists(select 1 from public.rr_active_payroll_profile_v778_2(p_worker_id,p_business_date,v_mode) p where p.worker_category='SALARIED' and extract(isodow from p_business_date)=p.weekly_holiday_isodow) then
        v_status:='WEEKLY_OFF';
      end if;
    end if;
  end if;

  select coalesce(sum(payable_minutes),0)
  into v_ot
  from public.rr_ot_work_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=p_business_date
    and work_type='REGULAR_OT'
    and status='COMPLETED'
    and payable_eligible
    and data_mode=v_mode;

  select coalesce(sum(payable_minutes),0)
  into v_holiday
  from public.rr_ot_work_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=p_business_date
    and work_type='HOLIDAY_WORK'
    and status='COMPLETED'
    and payable_eligible
    and data_mode=v_mode;

  if coalesce(v_regular.ot_hard_zero,false) then v_ot:=0; end if;

  v_net:=v_early_in+v_ot+v_holiday-v_late_in-v_early_out;

  insert into public.rr_attendance_daily_minutes_v778_2(
    worker_id,business_date,
    regular_checkin_at,regular_checkout_at,
    early_checkin_minutes,late_checkin_minutes,early_checkout_minutes,
    verified_ot_minutes,verified_holiday_minutes,
    net_adjustment_minutes,attendance_status,
    forgot_checkout,outside_checkout,data_mode,calculated_at
  )
  values(
    p_worker_id,p_business_date,
    v_regular.checkin_at,v_regular.checkout_at,
    v_early_in,v_late_in,v_early_out,
    v_ot,v_holiday,v_net,v_status,
    coalesce(v_regular.forgot_checkout,false),
    coalesce(v_regular.checkout_inside_geofence=false,false),
    v_mode,now()
  )
  on conflict(worker_id,business_date,data_mode) do update set
    regular_checkin_at=excluded.regular_checkin_at,
    regular_checkout_at=excluded.regular_checkout_at,
    early_checkin_minutes=excluded.early_checkin_minutes,
    late_checkin_minutes=excluded.late_checkin_minutes,
    early_checkout_minutes=excluded.early_checkout_minutes,
    verified_ot_minutes=excluded.verified_ot_minutes,
    verified_holiday_minutes=excluded.verified_holiday_minutes,
    net_adjustment_minutes=excluded.net_adjustment_minutes,
    attendance_status=excluded.attendance_status,
    forgot_checkout=excluded.forgot_checkout,
    outside_checkout=excluded.outside_checkout,
    calculated_at=now();

  return jsonb_build_object(
    'ok',true,
    'worker_id',p_worker_id,
    'business_date',p_business_date,
    'early_checkin_minutes',v_early_in,
    'late_checkin_minutes',v_late_in,
    'early_checkout_minutes',v_early_out,
    'verified_ot_minutes',v_ot,
    'verified_holiday_minutes',v_holiday,
    'net_adjustment_minutes',v_net,
    'attendance_status',v_status
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_attendance_minutes_payroll_sync_test71()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE p public.rr_worker_payroll_profile_v777_2%rowtype;s public.rr_shift_master_v777_2%rowtype;
 n_ded integer:=0;n_extra integer:=0;v_complete boolean;v_status text;v_paid_off boolean;
BEGIN
 IF NEW.data_mode<>'TEST' THEN RETURN NEW;END IF;
 SELECT * INTO p FROM public.rr_active_payroll_profile_v778_2(NEW.worker_id,NEW.business_date,'TEST');
 IF p.profile_id IS NULL OR p.worker_category<>'SALARIED' THEN RETURN NEW;END IF;
 IF NEW.business_date>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Future attendance blocked.';END IF;
 IF EXISTS(SELECT 1 FROM public.rr_payroll_runs_v778 r JOIN public.rr_payroll_run_lines_v778 l ON l.payroll_run_id=r.id
  WHERE l.worker_id=NEW.worker_id AND r.data_mode='TEST' AND NEW.business_date BETWEEN r.period_month AND r.period_end AND r.status IN ('APPROVED','PAID')) THEN RAISE EXCEPTION 'Approved payroll attendance is locked.';END IF;
 SELECT * INTO s FROM public.rr_shift_master_v777_2 WHERE shift_id=p.shift_id;
 v_complete:=NEW.regular_checkin_at IS NOT NULL AND NEW.regular_checkout_at IS NOT NULL AND NOT NEW.forgot_checkout;
 v_paid_off:=NEW.regular_checkin_at IS NULL AND NEW.regular_checkout_at IS NULL AND NOT NEW.forgot_checkout AND (
 extract(isodow FROM NEW.business_date)=p.weekly_holiday_isodow OR EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 h WHERE h.holiday_date=NEW.business_date AND h.data_mode='TEST' AND h.is_active AND h.is_paid_holiday AND h.applies_to IN ('ALL','SALARIED_ONLY')));
 v_status:=CASE WHEN v_paid_off THEN CASE WHEN EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 h WHERE h.holiday_date=NEW.business_date AND h.data_mode='TEST' AND h.is_active AND h.is_paid_holiday) THEN 'HOLIDAY' ELSE 'HOLIDAY' END WHEN NEW.forgot_checkout OR NOT v_complete THEN 'REVIEW_REQUIRED' ELSE NEW.attendance_status END;
 IF v_complete THEN
 n_ded:=(CASE WHEN p.late_deduction_applicable THEN NEW.late_checkin_minutes ELSE 0 END)+NEW.early_checkout_minutes;
 n_extra:=NEW.early_checkin_minutes+(CASE WHEN p.overtime_applicable AND NOT NEW.forgot_checkout AND NOT NEW.outside_checkout THEN NEW.verified_ot_minutes ELSE 0 END)
   +(CASE WHEN p.holiday_extra_applicable THEN NEW.verified_holiday_minutes ELSE 0 END);
 END IF;
 INSERT INTO public.rr_attendance_day_v777_2(worker_id,profile_id,attendance_date,first_check_in,last_check_out,
 gross_presence_minutes,grace_used_minutes,late_deduction_minutes,early_exit_deduction_minutes,normal_payable_minutes,gross_overtime_minutes,
 payable_overtime_minutes,holiday_work_minutes,attendance_status,is_holiday,calculation_snapshot,approval_status,data_mode,
 scheduled_payable_minutes,net_deduction_minutes,net_extra_work_minutes,net_working_minutes,paid_leave_minutes,unpaid_leave_minutes)
 VALUES(NEW.worker_id,p.profile_id,NEW.business_date,NEW.regular_checkin_at,NEW.regular_checkout_at,
 greatest(coalesce(floor(extract(epoch FROM NEW.regular_checkout_at-NEW.regular_checkin_at)/60)::integer,0),0),0,
 CASE WHEN v_complete AND p.late_deduction_applicable THEN NEW.late_checkin_minutes ELSE 0 END,
 CASE WHEN v_complete THEN NEW.early_checkout_minutes ELSE 0 END,
 CASE WHEN v_paid_off OR v_complete THEN greatest(s.normal_payable_minutes-n_ded,0) ELSE 0 END,n_extra,
 CASE WHEN v_complete AND p.overtime_applicable AND NOT NEW.outside_checkout THEN NEW.verified_ot_minutes ELSE 0 END,
 CASE WHEN v_complete AND p.holiday_extra_applicable THEN NEW.verified_holiday_minutes ELSE 0 END,
 v_status,v_paid_off OR extract(isodow FROM NEW.business_date)=p.weekly_holiday_isodow,
 jsonb_build_object('source','V778_2_VERIFIED_DAILY_MINUTES','daily_minutes_id',NEW.daily_minutes_id,'money_calculation_included',false,'review_required',NOT (v_complete OR v_paid_off),'paid_off',v_paid_off),
 CASE WHEN v_complete OR v_paid_off THEN 'APPROVED' ELSE 'PENDING' END,'TEST',s.normal_payable_minutes,n_ded,n_extra,
 CASE WHEN v_complete OR v_paid_off THEN greatest(s.normal_payable_minutes-n_ded+n_extra,0) ELSE 0 END,0,0)
 ON CONFLICT(worker_id,attendance_date,data_mode) DO UPDATE SET
 profile_id=excluded.profile_id,first_check_in=excluded.first_check_in,last_check_out=excluded.last_check_out,gross_presence_minutes=excluded.gross_presence_minutes,
 late_deduction_minutes=excluded.late_deduction_minutes,early_exit_deduction_minutes=excluded.early_exit_deduction_minutes,normal_payable_minutes=excluded.normal_payable_minutes,
 gross_overtime_minutes=excluded.gross_overtime_minutes,payable_overtime_minutes=excluded.payable_overtime_minutes,holiday_work_minutes=excluded.holiday_work_minutes,
 attendance_status=excluded.attendance_status,is_holiday=excluded.is_holiday,calculation_snapshot=excluded.calculation_snapshot,approval_status=excluded.approval_status,
 scheduled_payable_minutes=excluded.scheduled_payable_minutes,net_deduction_minutes=excluded.net_deduction_minutes,net_extra_work_minutes=excluded.net_extra_work_minutes,
 net_working_minutes=excluded.net_working_minutes,updated_at=now();
 RETURN NEW;
END $function$;
