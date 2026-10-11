CREATE OR REPLACE FUNCTION public.rr_generate_worker_monthly_payroll_safe_v779_5(p_worker_id uuid, p_payroll_month date, p_data_mode text DEFAULT 'REAL'::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
  v_id uuid;
  v_month_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  v_days integer;
  v_class_date date;
begin
  v_class_date:=v_month_end;
  IF upper(trim(coalesce(p_data_mode,'REAL')))='TEST' THEN
   IF auth.uid() IS NULL OR NOT public.rr_payroll_can_manage_v779_1() THEN RAISE EXCEPTION 'Payroll generation permission denied.' USING ERRCODE='42501';END IF;
   SELECT max(g.dt::date) INTO v_class_date
   FROM generate_series(date_trunc('month',p_payroll_month)::timestamp,v_month_end::timestamp,interval '1 day') g(dt)
   CROSS JOIN LATERAL public.rr_active_payroll_profile_v778_2(p_worker_id,g.dt::date,'TEST') a
   WHERE a.profile_id IS NOT NULL AND a.worker_category='SALARIED';
   IF v_class_date IS NULL THEN RAISE EXCEPTION 'No active salaried days in payroll month.';END IF;
  END IF;
  perform public.rr_assert_worker_earning_type_v779_5(
    p_worker_id,'MONTHLY_SALARY',v_class_date,p_data_mode
  );
  v_result:=public.rr_generate_worker_monthly_payroll_safe_v779_4(
    p_worker_id,p_payroll_month,p_data_mode,p_reason
  );
  v_id:=(v_result->>'payroll_id')::uuid;
  select count(*) into v_days
  from public.rr_attendance_day_v777_2
  where worker_id=p_worker_id
    and attendance_date between date_trunc('month',p_payroll_month)::date and v_month_end
    and data_mode=upper(trim(coalesce(p_data_mode,'REAL')))
    and approval_status='APPROVED';
  update public.rr_monthly_payroll_v779_1
  set generation_mode='ATTENDANCE',
      legacy_reason=null,legacy_approved_at=null,legacy_approved_by=null,
      calculation_snapshot=calculation_snapshot||jsonb_build_object(
        'generation_mode','ATTENDANCE',
        'approved_attendance_days',v_days,
        'worker_payment_classification','SALARIED_MONTHLY_ONLY',
        'pcs_earning_allowed',false
      ),
      updated_at=now()
  where payroll_id=v_id;
  return v_result||jsonb_build_object(
    'version','V779_5_MONTHLY_SALARY_FINAL_LOCK',
    'generation_mode','ATTENDANCE'
  );
end $function$
;
REVOKE ALL ON FUNCTION public.rr_generate_worker_monthly_payroll_safe_v779_5(uuid,date,text,text) FROM PUBLIC,anon;
