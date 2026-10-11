CREATE OR REPLACE FUNCTION public.rr_monthly_payroll_sources_test71(p_worker uuid,p_month date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('type',s.kind,'id',s.id,'amount',s.amount) ORDER BY s.kind,s.id),'[]'::jsonb) FROM(
 SELECT 'CLAIM'::text kind,c.claim_id id,c.approved_amount amount FROM public.rr_worker_claims_v777_2 c WHERE c.worker_id=p_worker AND c.data_mode='TEST' AND c.claim_status='APPROVED_PENDING_SETTLEMENT' AND c.reversed_at IS NULL AND c.approved_amount>0 AND NOT EXISTS(SELECT 1 FROM public.rr_payroll_source_applications_v779_1 a WHERE a.source_type='CLAIM' AND a.source_id=c.claim_id AND a.data_mode='TEST' AND a.reversed_at IS NULL)
 UNION ALL SELECT 'ADVANCE',v.advance_id,v.advance_amount FROM public.rr_worker_advances_v777_2 v WHERE v.worker_id=p_worker AND v.data_mode='TEST' AND NOT v.is_reversed AND v.advance_date<=(p_month+interval '1 month'-interval '1 day')::date AND NOT EXISTS(SELECT 1 FROM public.rr_payroll_source_applications_v779_1 a WHERE a.source_type='ADVANCE' AND a.source_id=v.advance_id AND a.data_mode='TEST' AND a.reversed_at IS NULL)
 UNION ALL SELECT 'INCENTIVE',i.incentive_id,i.incentive_amount FROM public.rr_payroll_incentives_v779_1 i WHERE i.worker_id=p_worker AND i.data_mode='TEST' AND i.payroll_month=p_month AND i.incentive_status='APPROVED' AND NOT EXISTS(SELECT 1 FROM public.rr_payroll_source_applications_v779_1 a WHERE a.source_type='INCENTIVE' AND a.source_id=i.incentive_id AND a.data_mode='TEST' AND a.reversed_at IS NULL)
 )s;
$$;
REVOKE ALL ON FUNCTION public.rr_monthly_payroll_sources_test71(uuid,date) FROM PUBLIC,anon,authenticated;

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
  v_source_snapshot jsonb;
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
 IF v_mode='TEST' THEN
  v_source_snapshot:=public.rr_monthly_payroll_sources_test71(p_worker_id,p_payroll_month);
  IF coalesce((SELECT sum((x->>'amount')::numeric) FROM jsonb_array_elements(v_source_snapshot) x WHERE x->>'type'='CLAIM'),0)<>v_claim OR coalesce((SELECT sum((x->>'amount')::numeric) FROM jsonb_array_elements(v_source_snapshot) x WHERE x->>'type'='ADVANCE'),0)<>v_advance OR coalesce((SELECT sum((x->>'amount')::numeric) FROM jsonb_array_elements(v_source_snapshot) x WHERE x->>'type'='INCENTIVE'),0)<>v_incentive THEN RAISE EXCEPTION 'Payroll sources changed during generation; retry calculation.';END IF;
 END IF;


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
      'source_snapshot_test71',v_source_snapshot,
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
CREATE OR REPLACE FUNCTION public.rr_post_monthly_payroll_v779_2(p_payroll_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payroll public.rr_monthly_payroll_v779_1%rowtype;
  v_settlement_id uuid;
  v_opening numeric:=0;
  v_closing numeric:=0;
  v_old jsonb;
  v_new jsonb;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll posting permission denied.';
  end if;

  select *
  into v_payroll
  from public.rr_monthly_payroll_v779_1
  where payroll_id=p_payroll_id
  for update;

  if not found then raise exception 'Payroll record nahi mila.'; end if;

  IF v_payroll.data_mode='TEST' AND (v_payroll.calculation_snapshot->'source_snapshot_test71') IS DISTINCT FROM public.rr_monthly_payroll_sources_test71(v_payroll.worker_id,v_payroll.payroll_month) THEN RAISE EXCEPTION 'Payroll sources changed; recalculate draft before posting.';END IF;
  if v_payroll.payroll_status<>'DRAFT' then
    raise exception 'Sirf DRAFT payroll post ho sakta hai.';
  end if;

  if current_date<v_payroll.posting_date then
    raise exception 'Salary posting date % hai.',v_payroll.posting_date;
  end if;

  select coalesce(s.closing_balance,0)
  into v_opening
  from public.rr_worker_settlements_v777_2 s
  where s.worker_id=v_payroll.worker_id
    and s.data_mode=v_payroll.data_mode
    and s.settlement_status not in('REVERSED','CANCELLED')
    and s.period_end<v_payroll.payroll_month
  order by s.period_end desc,s.created_at desc
  limit 1;

  v_opening:=coalesce(v_opening,0);

  -- payment_amount is zero until actual payment.
  v_closing:=
      v_opening
    + v_payroll.monthly_salary_amount
    + v_payroll.incentive_amount
    + v_payroll.net_extra_work_amount
    - v_payroll.advance_recovery_amount
    - v_payroll.approved_claim_amount;

  insert into public.rr_worker_settlements_v777_2(
    worker_id,worker_category,cycle_type,
    period_start,period_end,
    opening_balance,
    earnings_amount,
    incentive_amount,
    overtime_amount,
    holiday_amount,
    advance_recovery_amount,
    approved_claim_debit_amount,
    payment_amount,
    closing_balance,
    claim_debit_applied,
    full_and_final,
    settlement_status,
    calculation_snapshot,
    data_mode,created_by
  )
  values(
    v_payroll.worker_id,'SALARIED','MONTHLY',
    v_payroll.payroll_month,
    (v_payroll.payroll_month+interval '1 month' - interval '1 day')::date,
    v_opening,
    v_payroll.monthly_salary_amount,
    v_payroll.incentive_amount,
    v_payroll.net_extra_work_amount,
    0,
    v_payroll.advance_recovery_amount,
    v_payroll.approved_claim_amount,
    0,
    v_closing,
    false,
    false,
    'CALCULATED',
    jsonb_build_object(
      'engine_version','V779_2_PAYROLL_POSTING_SETTLEMENT_ENGINE',
      'payroll_id',v_payroll.payroll_id,
      'monthly_salary_head',v_payroll.monthly_salary_amount,
      'net_extra_work_head',v_payroll.net_extra_work_amount,
      'monthly_incentive_head',v_payroll.incentive_amount,
      'claims_recovery_head',v_payroll.claims_recovery_amount,
      'net_payable_salary',v_payroll.net_payable_salary,
      'legacy_column_mapping',jsonb_build_object(
        'earnings_amount','MONTHLY_SALARY',
        'overtime_amount','NET_EXTRA_WORK_AT_UNIVERSAL_MINUTE_RATE',
        'holiday_amount','ZERO_NO_MULTIPLIER'
      )
    ),
    v_payroll.data_mode,auth.uid()
  )
  on conflict(worker_id,cycle_type,period_start,period_end,data_mode)
  do update set
    opening_balance=excluded.opening_balance,
    earnings_amount=excluded.earnings_amount,
    incentive_amount=excluded.incentive_amount,
    overtime_amount=excluded.overtime_amount,
    holiday_amount=0,
    advance_recovery_amount=excluded.advance_recovery_amount,
    approved_claim_debit_amount=excluded.approved_claim_debit_amount,
    payment_amount=0,
    closing_balance=excluded.closing_balance,
    claim_debit_applied=false,
    settlement_status='CALCULATED',
    calculation_snapshot=excluded.calculation_snapshot
  where public.rr_worker_settlements_v777_2.settlement_status
    in('OPEN','CALCULATED')
  returning settlement_id into v_settlement_id;

  if v_settlement_id is null then
    raise exception 'Existing settlement already approved/closed hai.';
  end if;

  v_old:=to_jsonb(v_payroll);

  update public.rr_monthly_payroll_v779_1
  set payroll_status='POSTED',
      settlement_id=v_settlement_id,
      updated_at=now()
  where payroll_id=p_payroll_id
  returning to_jsonb(rr_monthly_payroll_v779_1.*) into v_new;

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,
    old_snapshot,new_snapshot,reason,data_mode
  )
  values(
    p_payroll_id,v_payroll.worker_id,v_payroll.payroll_month,
    'PAYROLL_POSTED',v_old,v_new,p_reason,v_payroll.data_mode
  );

  return jsonb_build_object(
    'ok',true,
    'version','V779_2_PAYROLL_POSTING_SETTLEMENT_ENGINE',
    'payroll_id',p_payroll_id,
    'settlement_id',v_settlement_id,
    'payroll_status','POSTED',
    'settlement_status','CALCULATED',
    'opening_balance',v_opening,
    'net_payable_salary',v_payroll.net_payable_salary,
    'closing_balance',v_closing
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_finalize_monthly_payroll_v779_2(p_payroll_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payroll public.rr_monthly_payroll_v779_1%rowtype;
  v_settlement public.rr_worker_settlements_v777_2%rowtype;
  v_claim record;
  v_advance record;
  v_incentive record;
  v_applied jsonb;
begin
  if auth.uid() IS NULL OR (public.rr_payroll_actor_role_v779_1() not in('owner','admin') AND lower(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code',''))<>'super_admin') then
    raise exception 'Final settlement Owner/Admin only.';
  end if;

  select *
  into v_payroll
  from public.rr_monthly_payroll_v779_1
  where payroll_id=p_payroll_id
  for update;

  if not found then raise exception 'Payroll nahi mila.'; end if;

  IF v_payroll.data_mode<>'TEST' AND public.rr_payroll_actor_role_v779_1() not in('owner','admin') THEN RAISE EXCEPTION 'Final settlement Owner/Admin only.';END IF;
  IF v_payroll.data_mode='TEST' AND (v_payroll.calculation_snapshot->'source_snapshot_test71') IS DISTINCT FROM public.rr_monthly_payroll_sources_test71(v_payroll.worker_id,v_payroll.payroll_month) THEN RAISE EXCEPTION 'Payroll sources changed after posting; reviewed recalculation required before finalization.';END IF;
  if v_payroll.payroll_status not in('POSTED','UNDER_REVIEW') then
    raise exception 'Payroll POSTED/UNDER_REVIEW hona chahiye.';
  end if;

  if v_payroll.settlement_id is null then
    raise exception 'Settlement link missing hai.';
  end if;

  select *
  into v_settlement
  from public.rr_worker_settlements_v777_2
  where settlement_id=v_payroll.settlement_id
  for update;

  if not found or v_settlement.settlement_status<>'CALCULATED' then
    raise exception 'CALCULATED settlement required hai.';
  end if;

  -- Claims: exact status and settlement link.
  for v_claim in
    select c.*
    from public.rr_worker_claims_v777_2 c
    where c.worker_id=v_payroll.worker_id
      and c.data_mode=v_payroll.data_mode
      and c.claim_status='APPROVED_PENDING_SETTLEMENT'
      and c.reversed_at is null
      and c.approved_amount>0
      and not exists(
        select 1
        from public.rr_payroll_source_applications_v779_1 a
        where a.source_type='CLAIM'
          and a.source_id=c.claim_id
          and a.data_mode=v_payroll.data_mode
          and a.reversed_at is null
      )
    for update
  loop
    insert into public.rr_payroll_source_applications_v779_1(
      payroll_id,worker_id,source_type,source_id,
      applied_amount,data_mode,applied_by
    )
    values(
      p_payroll_id,v_payroll.worker_id,'CLAIM',v_claim.claim_id,
      v_claim.approved_amount,v_payroll.data_mode,auth.uid()
    );

    update public.rr_worker_claims_v777_2
    set claim_status='DEBIT_POSTED',
        debit_settlement_id=v_payroll.settlement_id,
        debit_posted_at=now()
    where claim_id=v_claim.claim_id;
  end loop;

  -- Advances: source application prevents reuse.
  for v_advance in
    select a.*
    from public.rr_worker_advances_v777_2 a
    where a.worker_id=v_payroll.worker_id
      and a.data_mode=v_payroll.data_mode
      and not a.is_reversed
      and a.advance_date<=(
        v_payroll.payroll_month+interval '1 month' - interval '1 day'
      )::date
      and not exists(
        select 1
        from public.rr_payroll_source_applications_v779_1 x
        where x.source_type='ADVANCE'
          and x.source_id=a.advance_id
          and x.data_mode=v_payroll.data_mode
          and x.reversed_at is null
      )
    for update
  loop
    insert into public.rr_payroll_source_applications_v779_1(
      payroll_id,worker_id,source_type,source_id,
      applied_amount,data_mode,applied_by
    )
    values(
      p_payroll_id,v_payroll.worker_id,'ADVANCE',v_advance.advance_id,
      v_advance.advance_amount,v_payroll.data_mode,auth.uid()
    );
  end loop;

  -- Approved incentives: consume exactly once.
  for v_incentive in
    select i.*
    from public.rr_payroll_incentives_v779_1 i
    where i.worker_id=v_payroll.worker_id
      and i.payroll_month=v_payroll.payroll_month
      and i.data_mode=v_payroll.data_mode
      and i.incentive_status='APPROVED'
      and not exists(
        select 1
        from public.rr_payroll_source_applications_v779_1 x
        where x.source_type='INCENTIVE'
          and x.source_id=i.incentive_id
          and x.data_mode=v_payroll.data_mode
          and x.reversed_at is null
      )
    for update
  loop
    insert into public.rr_payroll_source_applications_v779_1(
      payroll_id,worker_id,source_type,source_id,
      applied_amount,data_mode,applied_by
    )
    values(
      p_payroll_id,v_payroll.worker_id,'INCENTIVE',
      v_incentive.incentive_id,v_incentive.incentive_amount,
      v_payroll.data_mode,auth.uid()
    );
  end loop;

  IF v_payroll.data_mode='TEST' THEN
   SELECT coalesce(jsonb_agg(jsonb_build_object('type',a.source_type,'id',a.source_id,'amount',a.applied_amount) ORDER BY a.source_type,a.source_id),'[]'::jsonb) INTO v_applied FROM public.rr_payroll_source_applications_v779_1 a WHERE a.payroll_id=p_payroll_id AND a.data_mode='TEST' AND a.reversed_at IS NULL;
   IF v_applied IS DISTINCT FROM v_payroll.calculation_snapshot->'source_snapshot_test71' THEN RAISE EXCEPTION 'Payroll source applications differ from approved snapshot; finalization rolled back.';END IF;
  END IF;
  update public.rr_worker_settlements_v777_2
  set settlement_status='APPROVED',
      claim_debit_applied=
        (v_payroll.approved_claim_amount>0),
      approved_at=now(),
      approved_by=auth.uid()
  where settlement_id=v_payroll.settlement_id;

  update public.rr_monthly_payroll_v779_1
  set payroll_status='FINAL',
      finalized_at=now(),
      finalized_by=auth.uid(),
      updated_at=now()
  where payroll_id=p_payroll_id;

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,
    old_snapshot,new_snapshot,reason,data_mode
  )
  values(
    p_payroll_id,v_payroll.worker_id,v_payroll.payroll_month,
    'PAYROLL_FINALIZED',to_jsonb(v_payroll),
    jsonb_build_object(
      'payroll_status','FINAL',
      'settlement_status','APPROVED',
      'settlement_id',v_payroll.settlement_id
    ),
    p_reason,v_payroll.data_mode
  );

  return jsonb_build_object(
    'ok',true,
    'version','V779_2_PAYROLL_POSTING_SETTLEMENT_ENGINE',
    'payroll_id',p_payroll_id,
    'settlement_id',v_payroll.settlement_id,
    'payroll_status','FINAL',
    'settlement_status','APPROVED',
    'net_payable_salary',v_payroll.net_payable_salary
  );
end $function$
;
