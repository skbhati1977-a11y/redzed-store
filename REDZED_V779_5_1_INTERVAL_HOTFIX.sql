-- ============================================================
-- REDZED V779.5.1 — INTERVAL HOTFIX
-- Fixes PostgreSQL error 22007:
-- invalid input syntax for type interval: "1 month-1 day"
--
-- Safe hotfix:
-- * No table/data deletion
-- * No HTML/JS change
-- * Replaces only the six affected payroll functions
-- ============================================================

begin;

create or replace function public.rr_generate_worker_monthly_payroll_safe_v779_4(
  p_worker_id uuid,
  p_payroll_month date,
  p_data_mode text default 'REAL',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'REAL')));
  v_month_start date:=date_trunc('month',p_payroll_month)::date;
  v_month_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  v_attendance_days integer:=0;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll generation permission denied.';
  end if;

  if p_payroll_month<>v_month_start then
    raise exception 'Payroll Month first date honi chahiye.';
  end if;

  if v_month_start>=date_trunc('month',current_date)::date then
    raise exception 'Sirf completed month ka payroll generate ho sakta hai.';
  end if;

  select count(*)
  into v_attendance_days
  from public.rr_attendance_day_v777_2 d
  where d.worker_id=p_worker_id
    and d.attendance_date between v_month_start and v_month_end
    and d.data_mode=v_mode
    and d.approval_status='APPROVED';

  if v_attendance_days=0 then
    raise exception 'Approved attendance records nahi hain; payroll generate nahi kiya gaya.';
  end if;

  return public.rr_generate_worker_monthly_payroll_v779_1(
    p_worker_id,
    v_month_start,
    v_mode,
    coalesce(nullif(trim(p_reason),''),'V779.4 safe payroll generation')
  );
end $$;

create or replace function public.rr_generate_monthly_payroll_batch_v779_4(
  p_payroll_month date,
  p_data_mode text default 'REAL',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'REAL')));
  v_month_start date:=date_trunc('month',p_payroll_month)::date;
  v_month_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  v_row record;
  v_generated integer:=0;
  v_existing integer:=0;
  v_skipped integer:=0;
  v_failed integer:=0;
  v_results jsonb:='[]'::jsonb;
  v_result jsonb;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll batch generation permission denied.';
  end if;

  if p_payroll_month<>v_month_start then
    raise exception 'Payroll Month first date honi chahiye.';
  end if;

  if v_month_start>=date_trunc('month',current_date)::date then
    raise exception 'Sirf completed month ka payroll generate ho sakta hai.';
  end if;

  for v_row in
    select distinct p.worker_id
    from public.rr_worker_payroll_profile_v777_2 p
    where upper(p.worker_category)='SALARIED'
      and p.data_mode=v_mode
      and p.status='ACTIVE'
      and p.effective_from<=v_month_end
      and (p.effective_to is null or p.effective_to>=v_month_start)
    order by p.worker_id
  loop
    begin
      if exists(
        select 1
        from public.rr_monthly_payroll_v779_1 m
        where m.worker_id=v_row.worker_id
          and m.payroll_month=v_month_start
          and m.data_mode=v_mode
      ) then
        v_existing:=v_existing+1;
        v_results:=v_results||jsonb_build_array(jsonb_build_object(
          'worker_id',v_row.worker_id,
          'status','ALREADY_EXISTS'
        ));
      elsif not exists(
        select 1
        from public.rr_attendance_day_v777_2 d
        where d.worker_id=v_row.worker_id
          and d.attendance_date between v_month_start and v_month_end
          and d.data_mode=v_mode
          and d.approval_status='APPROVED'
      ) then
        v_skipped:=v_skipped+1;
        v_results:=v_results||jsonb_build_array(jsonb_build_object(
          'worker_id',v_row.worker_id,
          'status','SKIPPED_NO_APPROVED_ATTENDANCE'
        ));
      else
        v_result:=public.rr_generate_worker_monthly_payroll_v779_1(
          v_row.worker_id,
          v_month_start,
          v_mode,
          coalesce(nullif(trim(p_reason),''),'V779.4 batch payroll generation')
        );
        v_generated:=v_generated+1;
        v_results:=v_results||jsonb_build_array(jsonb_build_object(
          'worker_id',v_row.worker_id,
          'status','GENERATED',
          'payroll_id',v_result->>'payroll_id'
        ));
      end if;
    exception when others then
      v_failed:=v_failed+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'worker_id',v_row.worker_id,
        'status','FAILED',
        'error',sqlerrm
      ));
    end;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'version','V779_4_FINAL_GENERATION_FIX',
    'payroll_month',v_month_start,
    'generated',v_generated,
    'already_existing',v_existing,
    'skipped_no_attendance',v_skipped,
    'failed',v_failed,
    'results',v_results
  );
end $$;

create or replace function public.rr_get_payroll_management_board_v779_4(
  p_payroll_month date,
  p_data_mode text default 'REAL'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'REAL')));
  v_month_start date:=date_trunc('month',p_payroll_month)::date;
  v_month_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  v_rows jsonb;
  v_summary jsonb;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll management permission denied.';
  end if;

  with eligible as (
    select distinct on (p.worker_id)
      p.worker_id,
      p.profile_id,
      p.monthly_salary,
      p.shift_id
    from public.rr_worker_payroll_profile_v777_2 p
    where upper(p.worker_category)='SALARIED'
      and p.data_mode=v_mode
      and p.status='ACTIVE'
      and p.effective_from<=v_month_end
      and (p.effective_to is null or p.effective_to>=v_month_start)
    order by p.worker_id,p.effective_from desc,p.configured_at desc
  ), rows as (
    select
      e.worker_id,
      w.worker_code,
      w.worker_name,
      w.department_code,
      e.monthly_salary as contract_monthly_salary,
      m.payroll_id,
      m.monthly_salary_amount,
      m.net_extra_work_minutes,
      public.rr_minutes_dhm_v778_2(coalesce(m.net_extra_work_minutes,0)) as net_extra_work_dhm,
      m.net_extra_work_amount,
      m.incentive_amount,
      m.claims_recovery_amount,
      m.net_payable_salary,
      m.payroll_status,
      m.settlement_id,
      s.settlement_status,
      coalesce(s.payment_amount,0) as payment_amount,
      coalesce(s.closing_balance,0) as closing_balance,
      (
        select count(*)
        from public.rr_attendance_day_v777_2 d
        where d.worker_id=e.worker_id
          and d.attendance_date between v_month_start and v_month_end
          and d.data_mode=v_mode
          and d.approval_status='APPROVED'
      ) as approved_attendance_days,
      case
        when m.payroll_id is not null then 'GENERATED'
        when exists(
          select 1
          from public.rr_attendance_day_v777_2 d
          where d.worker_id=e.worker_id
            and d.attendance_date between v_month_start and v_month_end
            and d.data_mode=v_mode
            and d.approval_status='APPROVED'
        ) then 'READY_TO_GENERATE'
        else 'WAITING_FOR_ATTENDANCE'
      end as generation_status
    from eligible e
    join public.rr_worker_directory_unified_v1 w
      on w.worker_id=e.worker_id
    left join public.rr_monthly_payroll_v779_1 m
      on m.worker_id=e.worker_id
     and m.payroll_month=v_month_start
     and m.data_mode=v_mode
    left join public.rr_worker_settlements_v777_2 s
      on s.settlement_id=m.settlement_id
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'worker_id',r.worker_id,
      'worker_code',r.worker_code,
      'worker_name',r.worker_name,
      'department_code',r.department_code,
      'contract_monthly_salary',r.contract_monthly_salary,
      'payroll_id',r.payroll_id,
      'monthly_salary',coalesce(r.monthly_salary_amount,0),
      'net_extra_work_amount',coalesce(r.net_extra_work_amount,0),
      'net_extra_work_time',coalesce(r.net_extra_work_dhm,'0 M'),
      'monthly_incentive',coalesce(r.incentive_amount,0),
      'claims_recovery',coalesce(r.claims_recovery_amount,0),
      'net_payable_salary',coalesce(r.net_payable_salary,0),
      'payroll_status',coalesce(r.payroll_status,'NOT_GENERATED'),
      'settlement_status',r.settlement_status,
      'payment_amount',r.payment_amount,
      'closing_balance',r.closing_balance,
      'approved_attendance_days',r.approved_attendance_days,
      'generation_status',r.generation_status,
      'open_disputes',case when r.payroll_id is null then 0 else (
        select count(*)
        from public.rr_payroll_disputes_v779_3 d
        where d.payroll_id=r.payroll_id
          and d.dispute_status in('OPEN','UNDER_REVIEW')
      ) end
    ) order by r.department_code,r.worker_name
  ),'[]'::jsonb)
  into v_rows
  from rows r;

  with eligible as (
    select distinct p.worker_id
    from public.rr_worker_payroll_profile_v777_2 p
    where upper(p.worker_category)='SALARIED'
      and p.data_mode=v_mode
      and p.status='ACTIVE'
      and p.effective_from<=v_month_end
      and (p.effective_to is null or p.effective_to>=v_month_start)
  )
  select jsonb_build_object(
    'eligible_workers',(select count(*) from eligible),
    'generated_workers',count(m.payroll_id),
    'not_generated_workers',(select count(*) from eligible)-count(m.payroll_id),
    'monthly_salary_total',coalesce(sum(m.monthly_salary_amount),0),
    'net_extra_work_total',coalesce(sum(m.net_extra_work_amount),0),
    'incentive_total',coalesce(sum(m.incentive_amount),0),
    'claims_recovery_total',coalesce(sum(m.claims_recovery_amount),0),
    'net_payable_total',coalesce(sum(m.net_payable_salary),0),
    'paid_total',coalesce(sum(s.payment_amount),0),
    'closing_balance_total',coalesce(sum(s.closing_balance),0)
  )
  into v_summary
  from eligible e
  left join public.rr_monthly_payroll_v779_1 m
    on m.worker_id=e.worker_id
   and m.payroll_month=v_month_start
   and m.data_mode=v_mode
  left join public.rr_worker_settlements_v777_2 s
    on s.settlement_id=m.settlement_id;

  return jsonb_build_object(
    'ok',true,
    'version','V779_4_FINAL_GENERATION_FIX',
    'payroll_month',v_month_start,
    'salary_month',to_char(v_month_start,'FMMonth YYYY'),
    'month_completed',v_month_start<date_trunc('month',current_date)::date,
    'summary',v_summary,
    'workers',v_rows
  );
end $$;

create or replace function public.rr_generate_worker_monthly_payroll_safe_v779_5(
  p_worker_id uuid,
  p_payroll_month date,
  p_data_mode text default 'REAL',
  p_reason text default null
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
declare
  v_result jsonb;
  v_id uuid;
  v_month_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  v_days integer;
begin
  perform public.rr_assert_worker_earning_type_v779_5(
    p_worker_id,'MONTHLY_SALARY',v_month_end,p_data_mode
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
end $$;

create or replace function public.rr_generate_worker_monthly_payroll_legacy_v779_5(
  p_worker_id uuid,
  p_payroll_month date,
  p_reason text,
  p_data_mode text default 'REAL'
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'REAL')));
  v_start date:=date_trunc('month',p_payroll_month)::date;
  v_end date:=(date_trunc('month',p_payroll_month) + interval '1 month' - interval '1 day')::date;
  v_result jsonb;
  v_id uuid;
begin
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
end $$;

create or replace function public.rr_generate_monthly_payroll_legacy_batch_v779_5(
  p_payroll_month date,
  p_reason text,
  p_data_mode text default 'REAL'
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
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
end $$;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V779_5_1_INTERVAL_HOTFIX',
  'affected_functions_replaced',6,
  'valid_month_end_expression',
    'date_trunc(month) + interval 1 month - interval 1 day'
) as rr_upm_v779_5_1_result;
