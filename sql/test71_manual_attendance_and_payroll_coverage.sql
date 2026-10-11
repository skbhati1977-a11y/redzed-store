CREATE OR REPLACE FUNCTION public.rr_manual_attendance_payroll_sync_test71()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE p public.rr_worker_payroll_profile_v777_2%rowtype;s public.rr_shift_master_v777_2%rowtype;
paid boolean;complete boolean;review boolean;ded integer:=0;extra integer:=0;late integer:=0;early_exit integer:=0;presence integer:=0;st text;
BEGIN
 IF NEW.data_mode<>'TEST' THEN RETURN NEW;END IF;
 IF auth.uid() IS NULL OR NOT public.rr_payroll_can_manage_v778() THEN RAISE EXCEPTION 'Attendance manage permission required.' USING ERRCODE='42501';END IF;
 IF NEW.attendance_date>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Future attendance blocked.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('ATT_PAY_TEST71|'||NEW.worker_id::text||'|'||date_trunc('month',NEW.attendance_date)::date::text,0));
 SELECT * INTO p FROM public.rr_active_payroll_profile_v778_2(NEW.worker_id,NEW.attendance_date,'TEST');
 IF p.profile_id IS NULL OR p.worker_category<>'SALARIED' THEN RAISE EXCEPTION 'Active salaried profile required.';END IF;
 IF EXISTS(SELECT 1 FROM public.rr_monthly_payroll_v779_1 r WHERE r.worker_id=NEW.worker_id AND r.payroll_month=date_trunc('month',NEW.attendance_date)::date AND r.data_mode='TEST' AND r.payroll_status IN('POSTED','FINAL','PAID')) THEN RAISE EXCEPTION 'Final payroll attendance is locked.';END IF;
 IF EXISTS(SELECT 1 FROM public.rr_payroll_runs_v778 r JOIN public.rr_payroll_run_lines_v778 l ON l.payroll_run_id=r.id WHERE l.worker_id=NEW.worker_id AND r.data_mode='TEST' AND NEW.attendance_date BETWEEN r.period_month AND r.period_end AND r.status IN('APPROVED','PAID')) THEN RAISE EXCEPTION 'Approved payroll attendance is locked.';END IF;
 SELECT * INTO s FROM public.rr_shift_master_v777_2 WHERE shift_id=p.shift_id;
 IF s.shift_id IS NULL THEN RAISE EXCEPTION 'Payroll shift required.';END IF;
 paid:=extract(isodow FROM NEW.attendance_date)=p.weekly_holiday_isodow OR EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 h WHERE h.holiday_date=NEW.attendance_date AND h.data_mode='TEST' AND h.is_active AND h.is_paid_holiday AND h.applies_to IN('ALL','SALARIED_ONLY'));
 complete:=NEW.check_in_at IS NOT NULL AND NEW.check_out_at IS NOT NULL;
 -- HALF_DAY uses actual punches under the user-approved policy.
 review:=NEW.status='INCOMPLETE' OR (NEW.status IN('WEEKLY_OFF','HOLIDAY') AND NOT paid);
 IF complete THEN presence:=greatest(floor(extract(epoch FROM NEW.check_out_at-NEW.check_in_at)/60)::integer,0);END IF;
 IF NEW.status IN('PRESENT','HALF_DAY') AND complete THEN
  late:=CASE WHEN p.late_deduction_applicable THEN greatest(floor(extract(epoch FROM NEW.check_in_at-NEW.shift_start_at)/60)::integer,0) ELSE 0 END;
  early_exit:=greatest(floor(extract(epoch FROM NEW.shift_end_at-NEW.check_out_at)/60)::integer,0);
  ded:=least(s.normal_payable_minutes,late+early_exit);
  extra:=greatest(floor(extract(epoch FROM NEW.shift_start_at-NEW.check_in_at)/60)::integer,0)+CASE WHEN p.overtime_applicable THEN greatest(floor(extract(epoch FROM NEW.check_out_at-NEW.shift_end_at)/60)::integer,0) ELSE 0 END;
 ELSIF NEW.status IN('ABSENT','LEAVE_UNPAID') AND NOT paid THEN ded:=s.normal_payable_minutes;
 END IF;
 IF review THEN ded:=0;extra:=0;END IF;
 st:=CASE WHEN review THEN 'REVIEW_REQUIRED' WHEN NEW.status IN('PRESENT','HALF_DAY') THEN 'PRESENT' WHEN paid OR NEW.status='LEAVE_PAID' THEN 'HOLIDAY' ELSE 'ABSENT' END;
 INSERT INTO public.rr_attendance_day_v777_2(worker_id,profile_id,attendance_date,first_check_in,last_check_out,gross_presence_minutes,
 grace_used_minutes,late_deduction_minutes,early_exit_deduction_minutes,normal_payable_minutes,gross_overtime_minutes,payable_overtime_minutes,
 holiday_work_minutes,attendance_status,is_holiday,calculation_snapshot,approval_status,approved_by,approved_at,approval_reason,data_mode,
 scheduled_payable_minutes,net_deduction_minutes,net_extra_work_minutes,net_working_minutes,paid_leave_minutes,unpaid_leave_minutes)
 VALUES(NEW.worker_id,p.profile_id,NEW.attendance_date,NEW.check_in_at,NEW.check_out_at,presence,0,late,early_exit,
 CASE WHEN review THEN 0 ELSE greatest(s.normal_payable_minutes-ded,0) END,extra,extra,0,st,paid,
 jsonb_build_object('source','V778_AUDITED_MANUAL_ATTENDANCE','manual_attendance_id',NEW.id,'manual_revision',NEW.revision_no,'manual_status',NEW.status,'review_required',review,'gps_verified',false,'money_calculation_included',false),
 CASE WHEN review THEN 'PENDING' ELSE 'APPROVED' END,CASE WHEN review THEN NULL ELSE auth.uid() END,CASE WHEN review THEN NULL ELSE now() END,NEW.correction_reason,'TEST',
 s.normal_payable_minutes,ded,extra,CASE WHEN review THEN 0 ELSE greatest(s.normal_payable_minutes-ded+extra,0) END,
 CASE WHEN NEW.status='LEAVE_PAID' AND NOT review THEN s.normal_payable_minutes ELSE 0 END,
 CASE WHEN NEW.status='LEAVE_UNPAID' AND NOT paid THEN s.normal_payable_minutes ELSE 0 END)
 ON CONFLICT(worker_id,attendance_date,data_mode) DO UPDATE SET
 profile_id=excluded.profile_id,first_check_in=excluded.first_check_in,last_check_out=excluded.last_check_out,gross_presence_minutes=excluded.gross_presence_minutes,
 grace_used_minutes=excluded.grace_used_minutes,late_deduction_minutes=excluded.late_deduction_minutes,early_exit_deduction_minutes=excluded.early_exit_deduction_minutes,
 normal_payable_minutes=excluded.normal_payable_minutes,gross_overtime_minutes=excluded.gross_overtime_minutes,payable_overtime_minutes=excluded.payable_overtime_minutes,
 holiday_work_minutes=excluded.holiday_work_minutes,attendance_status=excluded.attendance_status,is_holiday=excluded.is_holiday,calculation_snapshot=excluded.calculation_snapshot,
 approval_status=excluded.approval_status,approved_by=excluded.approved_by,approved_at=excluded.approved_at,approval_reason=excluded.approval_reason,
 scheduled_payable_minutes=excluded.scheduled_payable_minutes,net_deduction_minutes=excluded.net_deduction_minutes,net_extra_work_minutes=excluded.net_extra_work_minutes,
 net_working_minutes=excluded.net_working_minutes,paid_leave_minutes=excluded.paid_leave_minutes,unpaid_leave_minutes=excluded.unpaid_leave_minutes,updated_at=now();
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION public.rr_manual_attendance_payroll_sync_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_manual_attendance_payroll_sync_test71 AFTER INSERT OR UPDATE ON public.rr_attendance_day_v778 FOR EACH ROW EXECUTE FUNCTION public.rr_manual_attendance_payroll_sync_test71();

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
 IF EXISTS(SELECT 1 FROM public.rr_attendance_day_v778 m WHERE m.worker_id=NEW.worker_id AND m.attendance_date=NEW.business_date AND m.data_mode='TEST') THEN RETURN NEW;END IF;
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
END $function$

CREATE OR REPLACE FUNCTION public.rr_generate_worker_monthly_payroll_v779_1(p_worker_id uuid, p_payroll_month date, p_data_mode text DEFAULT 'TEST'::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_period_start date;
  v_period_end date;
  v_posting_date date;
  v_review_from date;
  v_review_until date;

  v_profile public.rr_worker_payroll_profile_v777_2%rowtype;

  v_scheduled integer:=0;
  v_deduction integer:=0;
  v_extra integer:=0;
  v_working integer:=0;

  v_incentive numeric:=0;
  v_claim numeric:=0;
  v_advance numeric:=0;
  v_recovery numeric:=0;

  v_calc jsonb;
  v_active_days int;v_missing_days int;v_contracts int;v_base_pay numeric;v_period_salary numeric;
  v_payroll_id uuid;
  v_old jsonb;
  v_new jsonb;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll generation permission denied.';
  end if;

  if date_trunc('month',p_payroll_month)::date<>p_payroll_month then
    raise exception 'Payroll Month first date honi chahiye.';
  end if;

  v_period_start:=p_payroll_month;
  v_period_end:=(p_payroll_month+interval '1 month' - interval '1 day')::date;
  v_posting_date:=(p_payroll_month+interval '1 month')::date;
  v_review_from:=v_posting_date+1;
  v_review_until:=v_posting_date+6;

  IF v_mode='TEST' THEN
   IF v_period_start>=date_trunc('month',now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Only completed month payroll can be generated.';END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('ATT_PAY_TEST71|'||p_worker_id::text||'|'||v_period_start::text,0));
   SELECT count(*),count(*) FILTER(WHERE d.attendance_day_id IS NULL OR d.approval_status<>'APPROVED' OR d.attendance_status IN('PENDING','REVIEW_REQUIRED') OR d.profile_id<>a.profile_id),count(DISTINCT a.monthly_salary)
   INTO v_active_days,v_missing_days,v_contracts
   FROM generate_series(v_period_start::timestamp,v_period_end::timestamp,interval '1 day') g(dt)
   CROSS JOIN LATERAL public.rr_active_payroll_profile_v778_2(p_worker_id,g.dt::date,'TEST') a
   LEFT JOIN public.rr_attendance_day_v777_2 d ON d.worker_id=p_worker_id AND d.attendance_date=g.dt::date AND d.data_mode='TEST'
   WHERE a.profile_id IS NOT NULL AND a.worker_category='SALARIED';
   IF v_active_days=0 THEN RAISE EXCEPTION 'No active salaried days in payroll month.';END IF;
   IF v_missing_days>0 THEN RAISE EXCEPTION 'Attendance incomplete: % of % active days unresolved.',v_missing_days,v_active_days;END IF;
   IF v_contracts<>1 THEN RAISE EXCEPTION 'Salary contract changes within month require reviewed segmented payroll.';END IF;
   SELECT a.* INTO v_profile FROM generate_series(v_period_start::timestamp,v_period_end::timestamp,interval '1 day') g(dt)
   CROSS JOIN LATERAL public.rr_active_payroll_profile_v778_2(p_worker_id,g.dt::date,'TEST') a
   WHERE a.profile_id IS NOT NULL AND a.worker_category='SALARIED' ORDER BY g.dt DESC LIMIT 1;
  ELSE
   SELECT * INTO v_profile FROM public.rr_active_payroll_profile_v778_2(p_worker_id,v_period_end,v_mode);
  END IF;

  if v_profile.profile_id is null then
    raise exception 'Active Payroll Profile required hai.';
  end if;

  if upper(v_profile.worker_category)<>'SALARIED' then
    raise exception 'Monthly payroll SALARIED Worker ke liye hai.';
  end if;

  select
    coalesce(sum(scheduled_payable_minutes),0)::integer,
    coalesce(sum(net_deduction_minutes),0)::integer,
    coalesce(sum(net_extra_work_minutes),0)::integer,
    coalesce(sum(net_working_minutes),0)::integer
  into v_scheduled,v_deduction,v_extra,v_working
  from public.rr_attendance_day_v777_2
  where worker_id=p_worker_id
    and attendance_date between v_period_start and v_period_end
    and data_mode=v_mode
    and approval_status='APPROVED'
    and (v_mode<>'TEST' OR EXISTS(SELECT 1 FROM public.rr_active_payroll_profile_v778_2(p_worker_id,public.rr_attendance_day_v777_2.attendance_date,'TEST') a WHERE a.profile_id=public.rr_attendance_day_v777_2.profile_id AND a.worker_category='SALARIED'));

  select coalesce(sum(i.incentive_amount),0)
  into v_incentive
  from public.rr_payroll_incentives_v779_1 i
  where i.worker_id=p_worker_id
    and i.payroll_month=p_payroll_month
    and i.data_mode=v_mode
    and i.incentive_status='APPROVED'
    and not exists(
      select 1
      from public.rr_payroll_source_applications_v779_1 a
      where a.source_type='INCENTIVE'
        and a.source_id=i.incentive_id
        and a.data_mode=v_mode
        and a.reversed_at is null
    );

  select coalesce(sum(c.approved_amount),0)
  into v_claim
  from public.rr_worker_claims_v777_2 c
  where c.worker_id=p_worker_id
    and c.data_mode=v_mode
    and c.claim_status='APPROVED_PENDING_SETTLEMENT'
    and c.reversed_at is null
    and c.approved_amount>0
    and not exists(
      select 1
      from public.rr_payroll_source_applications_v779_1 a
      where a.source_type='CLAIM'
        and a.source_id=c.claim_id
        and a.data_mode=v_mode
        and a.reversed_at is null
    );

  select coalesce(sum(a.advance_amount),0)
  into v_advance
  from public.rr_worker_advances_v777_2 a
  where a.worker_id=p_worker_id
    and a.data_mode=v_mode
    and not a.is_reversed
    and a.advance_date<=v_period_end
    and not exists(
      select 1
      from public.rr_payroll_source_applications_v779_1 x
      where x.source_type='ADVANCE'
        and x.source_id=a.advance_id
        and x.data_mode=v_mode
        and x.reversed_at is null
    );

  v_recovery:=v_claim+v_advance;

  v_calc:=public.rr_calculate_monthly_salary_v779_1(
    v_profile.monthly_salary,
    v_deduction,
    v_extra,
    v_incentive,
    v_recovery
  );

  IF v_mode='TEST' THEN
   v_base_pay:=CASE WHEN v_active_days=(v_period_end-v_period_start+1) THEN v_profile.monthly_salary ELSE round(v_profile.monthly_salary*v_active_days/30.0,2) END;
   v_period_salary:=greatest(v_base_pay-coalesce((v_calc->>'deduction_amount')::numeric,0),0);
   v_calc:=v_calc||jsonb_build_object('active_calendar_days',v_active_days,'period_base_salary',v_base_pay,'partial_month_basis','FIXED_30_DAYS',
    'monthly_salary_amount',round(v_period_salary,2),'net_payable_salary',round(v_period_salary+coalesce((v_calc->>'net_extra_work_amount')::numeric,0)+v_incentive-v_recovery,2));
  END IF;
  select to_jsonb(p)
  into v_old
  from public.rr_monthly_payroll_v779_1 p
  where p.worker_id=p_worker_id
    and p.payroll_month=p_payroll_month
    and p.data_mode=v_mode;

  insert into public.rr_monthly_payroll_v779_1(
    worker_id,payroll_month,worker_category,profile_id,
    monthly_salary_contract,
    scheduled_minutes_snapshot,
    net_deduction_minutes,
    net_extra_work_minutes,
    net_working_minutes,
    per_minute_rate,
    deduction_amount,
    monthly_salary_amount,
    net_extra_work_amount,
    incentive_amount,
    approved_claim_amount,
    advance_recovery_amount,
    claims_recovery_amount,
    net_payable_salary,
    payroll_status,
    posting_date,review_from,review_until,
    calculation_snapshot,
    data_mode,created_by,updated_at
  )
  values(
    p_worker_id,p_payroll_month,'SALARIED',v_profile.profile_id,
    v_profile.monthly_salary,
    v_scheduled,v_deduction,v_extra,v_working,
    (v_calc->>'per_minute_rate')::numeric,
    (v_calc->>'deduction_amount')::numeric,
    (v_calc->>'monthly_salary_amount')::numeric,
    (v_calc->>'net_extra_work_amount')::numeric,
    v_incentive,v_claim,v_advance,v_recovery,
    (v_calc->>'net_payable_salary')::numeric,
    'DRAFT',
    v_posting_date,v_review_from,v_review_until,
    jsonb_build_object(
      'engine_version','V779_2_PAYROLL_POSTING_SETTLEMENT_ENGINE',
      'period_start',v_period_start,
      'period_end',v_period_end,
      'profile_snapshot',to_jsonb(v_profile),
      'attendance',jsonb_build_object(
        'scheduled_minutes',v_scheduled,
        'net_deduction_minutes',v_deduction,
        'net_extra_work_minutes',v_extra,
        'net_working_minutes',v_working,
        'net_deduction_dhm',public.rr_minutes_dhm_v778_2(v_deduction),
        'net_extra_work_dhm',public.rr_minutes_dhm_v778_2(v_extra)
      ),
      'calculator',v_calc,
      'claims_amount',v_claim,
      'advance_recovery_amount',v_advance,
      'incentive_amount',v_incentive,
      'reason',p_reason
    ),
    v_mode,auth.uid(),now()
  )
  on conflict(worker_id,payroll_month,data_mode) do update set
    profile_id=excluded.profile_id,
    monthly_salary_contract=excluded.monthly_salary_contract,
    scheduled_minutes_snapshot=excluded.scheduled_minutes_snapshot,
    net_deduction_minutes=excluded.net_deduction_minutes,
    net_extra_work_minutes=excluded.net_extra_work_minutes,
    net_working_minutes=excluded.net_working_minutes,
    per_minute_rate=excluded.per_minute_rate,
    deduction_amount=excluded.deduction_amount,
    monthly_salary_amount=excluded.monthly_salary_amount,
    net_extra_work_amount=excluded.net_extra_work_amount,
    incentive_amount=excluded.incentive_amount,
    approved_claim_amount=excluded.approved_claim_amount,
    advance_recovery_amount=excluded.advance_recovery_amount,
    claims_recovery_amount=excluded.claims_recovery_amount,
    net_payable_salary=excluded.net_payable_salary,
    posting_date=excluded.posting_date,
    review_from=excluded.review_from,
    review_until=excluded.review_until,
    calculation_snapshot=excluded.calculation_snapshot,
    updated_at=now()
  where public.rr_monthly_payroll_v779_1.payroll_status
    in('DRAFT','UNDER_REVIEW')
  returning payroll_id into v_payroll_id;

  if v_payroll_id is null then
    raise exception 'POSTED/FINAL/PAID payroll refresh nahi ho sakta.';
  end if;

  select to_jsonb(p)
  into v_new
  from public.rr_monthly_payroll_v779_1 p
  where p.payroll_id=v_payroll_id;

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,
    old_snapshot,new_snapshot,reason,data_mode
  )
  values(
    v_payroll_id,p_worker_id,p_payroll_month,
    case when v_old is null then 'PAYROLL_GENERATED'
         else 'PAYROLL_RECALCULATED' end,
    v_old,v_new,p_reason,v_mode
  );

  return jsonb_build_object(
    'ok',true,
    'version','V779_2_PAYROLL_POSTING_SETTLEMENT_ENGINE',
    'payroll_id',v_payroll_id,
    'worker_id',p_worker_id,
    'payroll_month',p_payroll_month,
    'monthly_salary',(v_calc->>'monthly_salary_amount')::numeric,
    'net_extra_work_amount',(v_calc->>'net_extra_work_amount')::numeric,
    'net_extra_work_dhm',public.rr_minutes_dhm_v778_2(v_extra),
    'monthly_incentive',v_incentive,
    'claims_recovery',v_recovery,
    'net_payable_salary',(v_calc->>'net_payable_salary')::numeric,
    'status','DRAFT'
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_payroll_can_manage_v779_1() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
 SELECT auth.uid() IS NOT NULL AND (public.rr_payroll_actor_role_v779_1() IN('owner','admin','manager','production') OR lower(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code',''))='super_admin');
$$;