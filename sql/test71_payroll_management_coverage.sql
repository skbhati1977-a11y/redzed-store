CREATE OR REPLACE FUNCTION public.rr_get_payroll_management_board_v779_5(p_payroll_month date, p_data_mode text DEFAULT 'REAL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base jsonb;
  v_workers jsonb;
  v_summary jsonb;
begin
  v_base:=public.rr_get_payroll_management_board_v779_4(
    p_payroll_month,p_data_mode
  );

  select coalesce(jsonb_agg(
    w.item
    || jsonb_build_object(
      'worker_category','SALARIED',
      'pcs_earning_allowed',false,
      'department_actual_rate_treatment',
        'LOT_PROCESS_COST_ONLY_NOT_WORKER_PCS_PAY',
      'generation_mode',coalesce(m.generation_mode,'NOT_GENERATED'),
      'legacy_reason',m.legacy_reason,
      'generation_status',
        case
          when m.payroll_id is not null and m.generation_mode='LEGACY'
            then 'LEGACY_GENERATED'
          when m.payroll_id is not null
            then 'GENERATED'
          when (w.item->>'generation_status')='WAITING_FOR_ATTENDANCE'
            and date_trunc('month',p_payroll_month)::date
              < date_trunc('month',current_date)::date
            then 'READY_FOR_LEGACY_GENERATION'
          else w.item->>'generation_status'
        end
    )
    order by w.ord
  ),'[]'::jsonb)
  into v_workers
  from jsonb_array_elements(v_base->'workers') with ordinality w(item,ord)
  left join public.rr_monthly_payroll_v779_1 m
    on m.payroll_id=nullif(w.item->>'payroll_id','')::uuid;

  select (v_base->'summary')||jsonb_build_object(
    'legacy_generated_workers',count(*) filter(where generation_mode='LEGACY'),
    'attendance_generated_workers',count(*) filter(where generation_mode='ATTENDANCE')
  )
  into v_summary
  from public.rr_monthly_payroll_v779_1
  where payroll_month=date_trunc('month',p_payroll_month)::date
    and data_mode=upper(trim(coalesce(p_data_mode,'REAL')));


  IF upper(trim(p_data_mode))='TEST' THEN
   SELECT coalesce(jsonb_agg(w.item||jsonb_build_object(
    'required_attendance_days',c.required_days,'resolved_attendance_days',c.required_days-c.missing_days,
    'unresolved_attendance_days',c.missing_days,'legacy_generation_allowed',false,
    'generation_status',CASE WHEN nullif(w.item->>'payroll_id','') IS NOT NULL THEN w.item->>'generation_status'
      WHEN c.required_days=0 THEN 'NO_ACTIVE_SALARIED_DAYS'
      WHEN c.contracts<>1 THEN 'CONTRACT_REVIEW_REQUIRED'
      WHEN c.missing_days>0 THEN 'WAITING_FOR_ATTENDANCE'
      WHEN date_trunc('month',p_payroll_month)::date>=date_trunc('month',(now() AT TIME ZONE 'Asia/Kolkata'))::date THEN 'WAITING_FOR_MONTH_CLOSE'
      ELSE 'READY_TO_GENERATE' END
   ) ORDER BY w.ord),'[]'::jsonb) INTO v_workers
   FROM jsonb_array_elements(v_workers) WITH ORDINALITY w(item,ord)
   CROSS JOIN LATERAL(
    SELECT count(*) required_days,count(*) FILTER(WHERE d.attendance_day_id IS NULL OR d.approval_status<>'APPROVED' OR d.attendance_status IN('PENDING','REVIEW_REQUIRED') OR d.profile_id IS DISTINCT FROM a.profile_id) missing_days,count(DISTINCT a.monthly_salary) contracts
    FROM generate_series(date_trunc('month',p_payroll_month)::timestamp,(date_trunc('month',p_payroll_month)+interval '1 month'-interval '1 day')::timestamp,interval '1 day') g(dt)
    CROSS JOIN LATERAL public.rr_active_payroll_profile_v778_2((w.item->>'worker_id')::uuid,g.dt::date,'TEST') a
    LEFT JOIN public.rr_attendance_day_v777_2 d ON d.worker_id=(w.item->>'worker_id')::uuid AND d.attendance_date=g.dt::date AND d.data_mode='TEST'
    WHERE a.profile_id IS NOT NULL AND a.worker_category='SALARIED'
   ) c;
  END IF;

  return v_base
    || jsonb_build_object(
      'version','V779_5_MONTHLY_SALARY_FINAL_LOCK',
      'summary',v_summary,
      'workers',v_workers
    );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_generate_monthly_payroll_legacy_batch_v779_5(p_payroll_month date, p_reason text, p_data_mode text DEFAULT 'REAL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'REAL')));
  v_start date:=date_trunc('month',p_payroll_month)::date;
  v_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  r record;
  v_generated integer:=0;
  v_existing integer:=0;
  v_attendance integer:=0;
  v_failed integer:=0;
  v_items jsonb:='[]'::jsonb;
  v_res jsonb;
begin
 IF upper(trim(p_data_mode))='TEST' THEN RAISE EXCEPTION 'TEST requires approved canonical attendance or an approved opening settlement; missing history cannot generate full salary.';END IF;

  if public.rr_payroll_actor_role_v779_1() not in('owner','admin') then
    raise exception 'Legacy batch Owner/Admin only.';
  end if;
  if nullif(trim(p_reason),'') is null then
    raise exception 'Legacy batch reason mandatory hai.';
  end if;
  if p_payroll_month<>v_start or v_start>=date_trunc('month',current_date)::date then
    raise exception 'Completed historical month required hai.';
  end if;

  for r in
    select distinct p.worker_id
    from public.rr_worker_payroll_profile_v777_2 p
    where upper(p.worker_category)='SALARIED'
      and p.data_mode=v_mode and p.status='ACTIVE'
      and p.effective_from<=v_end
      and (p.effective_to is null or p.effective_to>=v_start)
  loop
    begin
      if exists(
        select 1 from public.rr_monthly_payroll_v779_1
        where worker_id=r.worker_id and payroll_month=v_start and data_mode=v_mode
      ) then
        v_existing:=v_existing+1;
      elsif exists(
        select 1 from public.rr_attendance_day_v777_2
        where worker_id=r.worker_id
          and attendance_date between v_start and v_end
          and data_mode=v_mode and approval_status='APPROVED'
      ) then
        v_attendance:=v_attendance+1;
      else
        v_res:=public.rr_generate_worker_monthly_payroll_legacy_v779_5(
          r.worker_id,v_start,trim(p_reason),v_mode
        );
        v_generated:=v_generated+1;
        v_items:=v_items||jsonb_build_array(jsonb_build_object(
          'worker_id',r.worker_id,'status','LEGACY_GENERATED',
          'payroll_id',v_res->>'payroll_id'
        ));
      end if;
    exception when others then
      v_failed:=v_failed+1;
      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'worker_id',r.worker_id,'status','FAILED','error',sqlerrm
      ));
    end;
  end loop;

  return jsonb_build_object(
    'ok',true,'version','V779_5_MONTHLY_SALARY_FINAL_LOCK',
    'legacy_generated',v_generated,'already_existing',v_existing,
    'skipped_attendance_available',v_attendance,'failed',v_failed,
    'results',v_items
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_generate_worker_monthly_payroll_legacy_v779_5(p_worker_id uuid, p_payroll_month date, p_reason text, p_data_mode text DEFAULT 'REAL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'REAL')));
  v_start date:=date_trunc('month',p_payroll_month)::date;
  v_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  v_result jsonb;
  v_id uuid;
begin
 IF upper(trim(p_data_mode))='TEST' THEN RAISE EXCEPTION 'TEST requires approved canonical attendance or an approved opening settlement; missing history cannot generate full salary.';END IF;

  if public.rr_payroll_actor_role_v779_1() not in('owner','admin') then
    raise exception 'Legacy Payroll Owner/Admin only.';
  end if;
  if nullif(trim(p_reason),'') is null then
    raise exception 'Legacy generation reason mandatory hai.';
  end if;
  if p_payroll_month<>v_start or v_start>=date_trunc('month',current_date)::date then
    raise exception 'Legacy generation sirf completed historical month ke liye hai.';
  end if;
  perform public.rr_assert_worker_earning_type_v779_5(
    p_worker_id,'MONTHLY_SALARY',v_end,v_mode
  );
  if exists(
    select 1 from public.rr_attendance_day_v777_2
    where worker_id=p_worker_id
      and attendance_date between v_start and v_end
      and data_mode=v_mode and approval_status='APPROVED'
  ) then
    raise exception 'Approved attendance available hai; normal Generate use karein.';
  end if;
  if exists(
    select 1 from public.rr_monthly_payroll_v779_1
    where worker_id=p_worker_id and payroll_month=v_start and data_mode=v_mode
  ) then
    raise exception 'Payroll pehle se generated hai.';
  end if;

  v_result:=public.rr_generate_worker_monthly_payroll_v779_1(
    p_worker_id,v_start,v_mode,'LEGACY: '||trim(p_reason)
  );
  v_id:=(v_result->>'payroll_id')::uuid;

  update public.rr_monthly_payroll_v779_1
  set generation_mode='LEGACY',
      legacy_reason=trim(p_reason),
      legacy_approved_at=now(),
      legacy_approved_by=auth.uid(),
      calculation_snapshot=calculation_snapshot||jsonb_build_object(
        'generation_mode','LEGACY',
        'legacy_reason',trim(p_reason),
        'approved_attendance_days',0,
        'legacy_full_contract_salary',true,
        'worker_payment_classification','SALARIED_MONTHLY_ONLY',
        'pcs_earning_allowed',false
      ),
      updated_at=now()
  where payroll_id=v_id;

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,new_snapshot,reason,data_mode
  ) values(
    v_id,p_worker_id,v_start,'LEGACY_PAYROLL_GENERATED',
    jsonb_build_object('generation_mode','LEGACY','monthly_salary_only',true),
    trim(p_reason),v_mode
  );

  return v_result||jsonb_build_object(
    'version','V779_5_MONTHLY_SALARY_FINAL_LOCK',
    'generation_mode','LEGACY',
    'legacy_generated',true
  );
end $function$
;
