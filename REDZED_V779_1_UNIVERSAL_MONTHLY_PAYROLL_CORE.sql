
-- ============================================================
-- REDZED V779.1 — UNIVERSAL MONTHLY PAYROLL CORE
--
-- Dependencies:
--   V777.2 / V777.3 Payroll Profile
--   V778.2 Revised Net-Minute Attendance Engine
--
-- This phase:
--   * 30-day / 18,000-minute monthly salary basis
--   * Monthly salary after hidden minute deduction
--   * Net Extra Work amount
--   * Monthly incentives
--   * Claims + advances as Claims / Recovery
--   * Immutable monthly calculation snapshot
--   * Worker self-service: own payroll only
--
-- Existing rr_worker_settlements_v777_2 and worker ledger are NOT
-- written in this phase because their CHECK constraints/status values
-- have not yet been verified. No guessing.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Monthly incentive source
-- ------------------------------------------------------------
create table if not exists public.rr_payroll_incentives_v779_1(
  incentive_id uuid primary key default gen_random_uuid(),

  worker_id uuid not null,
  payroll_month date not null,

  incentive_type text not null
    check(incentive_type in(
      'MONTHLY_FLAT',
      'LEADERSHIP',
      'PERFORMANCE',
      'SALE_PCS',
      'MANUAL_APPROVED',
      'OTHER'
    )),

  incentive_amount numeric(14,2) not null
    check(incentive_amount>=0),

  source_type text,
  source_id text,
  description text,

  incentive_status text not null default 'PENDING'
    check(incentive_status in(
      'PENDING','APPROVED','REJECTED','REVERSED'
    )),

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),

  approved_at timestamptz,
  approved_by uuid,
  approval_reason text,

  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,

  unique(worker_id,payroll_month,incentive_type,source_type,source_id,data_mode),

  check(date_trunc('month',payroll_month)::date=payroll_month)
);

-- ------------------------------------------------------------
-- 2. Monthly payroll snapshot
-- ------------------------------------------------------------
create table if not exists public.rr_monthly_payroll_v779_1(
  payroll_id uuid primary key default gen_random_uuid(),

  worker_id uuid not null,
  payroll_month date not null,

  worker_category text not null
    check(worker_category='SALARIED'),

  profile_id uuid not null,

  monthly_salary_contract numeric(14,2) not null
    check(monthly_salary_contract>=0),

  salary_basis_days integer not null default 30
    check(salary_basis_days=30),

  minutes_per_day integer not null default 600
    check(minutes_per_day=600),

  monthly_base_minutes integer not null default 18000
    check(monthly_base_minutes=18000),

  scheduled_minutes_snapshot integer not null default 0
    check(scheduled_minutes_snapshot>=0),

  net_deduction_minutes integer not null default 0
    check(net_deduction_minutes>=0),

  net_extra_work_minutes integer not null default 0
    check(net_extra_work_minutes>=0),

  net_working_minutes integer not null default 0
    check(net_working_minutes>=0),

  per_minute_rate numeric(18,8) not null default 0
    check(per_minute_rate>=0),

  deduction_amount numeric(14,2) not null default 0
    check(deduction_amount>=0),

  monthly_salary_amount numeric(14,2) not null default 0
    check(monthly_salary_amount>=0),

  net_extra_work_amount numeric(14,2) not null default 0
    check(net_extra_work_amount>=0),

  incentive_amount numeric(14,2) not null default 0
    check(incentive_amount>=0),

  approved_claim_amount numeric(14,2) not null default 0
    check(approved_claim_amount>=0),

  advance_recovery_amount numeric(14,2) not null default 0
    check(advance_recovery_amount>=0),

  claims_recovery_amount numeric(14,2) not null default 0
    check(claims_recovery_amount>=0),

  net_payable_salary numeric(14,2) not null default 0,

  payroll_status text not null default 'DRAFT'
    check(payroll_status in(
      'DRAFT',
      'POSTED',
      'UNDER_REVIEW',
      'FINAL',
      'PAID',
      'REVERSED'
    )),

  posting_date date,
  review_from date,
  review_until date,
  finalized_at timestamptz,
  finalized_by uuid,

  calculation_snapshot jsonb not null default '{}'::jsonb,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),

  unique(worker_id,payroll_month,data_mode),

  check(date_trunc('month',payroll_month)::date=payroll_month)
);

create index if not exists rr_monthly_payroll_v779_1_month_idx
on public.rr_monthly_payroll_v779_1(payroll_month,data_mode,payroll_status);

create index if not exists rr_monthly_payroll_v779_1_worker_idx
on public.rr_monthly_payroll_v779_1(worker_id,payroll_month desc,data_mode);

-- ------------------------------------------------------------
-- 3. Frozen source applications
--
-- Prevents the same claim/advance/incentive from being recovered or
-- credited in two different payroll months.
-- ------------------------------------------------------------
create table if not exists public.rr_payroll_source_applications_v779_1(
  application_id uuid primary key default gen_random_uuid(),

  payroll_id uuid not null
    references public.rr_monthly_payroll_v779_1(payroll_id)
    on delete restrict,

  worker_id uuid not null,

  source_type text not null
    check(source_type in('CLAIM','ADVANCE','INCENTIVE')),

  source_id uuid not null,
  applied_amount numeric(14,2) not null
    check(applied_amount>=0),

  data_mode text not null
    check(data_mode in('TEST','REAL')),

  applied_at timestamptz not null default now(),
  applied_by uuid default auth.uid(),

  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,

  unique(source_type,source_id,data_mode)
);

-- ------------------------------------------------------------
-- 4. Payroll event audit
-- ------------------------------------------------------------
create table if not exists public.rr_payroll_events_v779_1(
  payroll_event_id uuid primary key default gen_random_uuid(),
  payroll_id uuid,
  worker_id uuid not null,
  payroll_month date not null,

  event_type text not null,
  old_snapshot jsonb,
  new_snapshot jsonb,
  reason text,

  data_mode text not null
    check(data_mode in('TEST','REAL')),

  actor_auth_user_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 5. Universal calculator
--
-- Worker-facing slip:
--   Monthly Salary
--   Net Extra Work
--   Monthly Incentive
--   Claims / Recovery
--   Net Payable Salary
--
-- Minute deduction remains inside Monthly Salary amount and details.
-- ------------------------------------------------------------
create or replace function public.rr_calculate_monthly_salary_v779_1(
  p_monthly_salary numeric,
  p_net_deduction_minutes integer,
  p_net_extra_work_minutes integer,
  p_incentive_amount numeric default 0,
  p_claims_recovery_amount numeric default 0
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_rate numeric;
  v_deduction numeric;
  v_salary_amount numeric;
  v_extra numeric;
  v_net numeric;
begin
  if coalesce(p_monthly_salary,0)<0 then
    raise exception 'Monthly Salary negative nahi ho sakti.';
  end if;

  if coalesce(p_net_deduction_minutes,0)<0
     or coalesce(p_net_extra_work_minutes,0)<0
  then
    raise exception 'Payroll minutes negative nahi ho sakte.';
  end if;

  if coalesce(p_incentive_amount,0)<0
     or coalesce(p_claims_recovery_amount,0)<0
  then
    raise exception 'Incentive/Claims amount negative nahi ho sakta.';
  end if;

  v_rate:=coalesce(p_monthly_salary,0)/18000.0;

  v_deduction:=
    coalesce(p_net_deduction_minutes,0)*v_rate;

  v_salary_amount:=greatest(
    coalesce(p_monthly_salary,0)-v_deduction,
    0
  );

  v_extra:=
    coalesce(p_net_extra_work_minutes,0)*v_rate;

  v_net:=
      v_salary_amount
    + v_extra
    + coalesce(p_incentive_amount,0)
    - coalesce(p_claims_recovery_amount,0);

  return jsonb_build_object(
    'salary_basis_days',30,
    'minutes_per_day',600,
    'monthly_base_minutes',18000,

    'monthly_salary_contract',
      round(coalesce(p_monthly_salary,0),2),

    'per_minute_rate',
      round(v_rate,8),

    'net_deduction_minutes',
      coalesce(p_net_deduction_minutes,0),

    'deduction_amount',
      round(v_deduction,2),

    'monthly_salary_amount',
      round(v_salary_amount,2),

    'net_extra_work_minutes',
      coalesce(p_net_extra_work_minutes,0),

    'net_extra_work_amount',
      round(v_extra,2),

    'monthly_incentive',
      round(coalesce(p_incentive_amount,0),2),

    'claims_recovery',
      round(coalesce(p_claims_recovery_amount,0),2),

    'net_payable_salary',
      round(v_net,2),

    'holiday_multiplier',1,
    'overtime_multiplier',1
  );
end $$;

-- ------------------------------------------------------------
-- 6. Payroll actor helpers
-- ------------------------------------------------------------
create or replace function public.rr_payroll_actor_role_v779_1()
returns text
language sql
stable
security definer
set search_path='public'
as $$
  select lower(coalesce(p.role_code,''))
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid()
    and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  limit 1
$$;

create or replace function public.rr_payroll_worker_is_self_v779_1(
  p_worker_id uuid
)
returns boolean
language sql
stable
security definer
set search_path='public'
as $$
  select exists(
    select 1
    from public.rr_worker_directory_unified_v1 w
    where w.worker_id=p_worker_id
      and w.linked_auth_user_id=auth.uid()
  )
$$;

create or replace function public.rr_payroll_can_manage_v779_1()
returns boolean
language sql
stable
security definer
set search_path='public'
as $$
  select public.rr_payroll_actor_role_v779_1()
    in('owner','admin','manager','production')
$$;

-- ------------------------------------------------------------
-- 7. Incentive save/approve
-- ------------------------------------------------------------
create or replace function public.rr_save_payroll_incentive_v779_1(
  p_worker_id uuid,
  p_payroll_month date,
  p_incentive_type text,
  p_amount numeric,
  p_source_type text default null,
  p_source_id text default null,
  p_description text default null,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_type text:=upper(trim(coalesce(p_incentive_type,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_id uuid;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll incentive permission denied.';
  end if;

  if date_trunc('month',p_payroll_month)::date<>p_payroll_month then
    raise exception 'Payroll Month first date honi chahiye.';
  end if;

  insert into public.rr_payroll_incentives_v779_1(
    worker_id,payroll_month,incentive_type,incentive_amount,
    source_type,source_id,description,incentive_status,
    data_mode,created_by
  )
  values(
    p_worker_id,p_payroll_month,v_type,p_amount,
    nullif(trim(p_source_type),''),
    nullif(trim(p_source_id),''),
    p_description,'PENDING',v_mode,auth.uid()
  )
  returning incentive_id into v_id;

  return jsonb_build_object(
    'ok',true,
    'version','V779_1_UNIVERSAL_MONTHLY_PAYROLL_CORE',
    'incentive_id',v_id,
    'status','PENDING'
  );
end $$;

create or replace function public.rr_decide_payroll_incentive_v779_1(
  p_incentive_id uuid,
  p_decision text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_decision text:=upper(trim(coalesce(p_decision,'')));
begin
  if public.rr_payroll_actor_role_v779_1() not in('owner','admin') then
    raise exception 'Incentive approval Owner/Admin only.';
  end if;

  if v_decision not in('APPROVED','REJECTED') then
    raise exception 'Decision APPROVED ya REJECTED hona chahiye.';
  end if;

  update public.rr_payroll_incentives_v779_1
  set incentive_status=v_decision,
      approved_at=now(),
      approved_by=auth.uid(),
      approval_reason=p_reason
  where incentive_id=p_incentive_id
    and incentive_status='PENDING';

  if not found then
    raise exception 'Pending incentive record nahi mila.';
  end if;

  return jsonb_build_object(
    'ok',true,
    'incentive_id',p_incentive_id,
    'decision',v_decision
  );
end $$;

-- ------------------------------------------------------------
-- 8. Generate / refresh one worker's monthly payroll
--
-- Payroll month means the month being paid.
-- Example: payroll_month = 2026-07-01, posting date = 2026-08-01.
-- ------------------------------------------------------------
create or replace function public.rr_generate_worker_monthly_payroll_v779_1(
  p_worker_id uuid,
  p_payroll_month date,
  p_data_mode text default 'TEST',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
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
  v_period_end:=(p_payroll_month+interval '1 month-1 day')::date;
  v_posting_date:=(p_payroll_month+interval '1 month')::date;
  v_review_from:=v_posting_date+1;
  v_review_until:=v_posting_date+6;

  select *
  into v_profile
  from public.rr_active_payroll_profile_v778_2(
    p_worker_id,v_period_end,v_mode
  );

  if v_profile.profile_id is null then
    raise exception 'Active Payroll Profile required hai.';
  end if;

  if upper(v_profile.worker_category)<>'SALARIED' then
    raise exception 'V779.1 monthly payroll SALARIED Worker ke liye hai.';
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
    and approval_status='APPROVED';

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
    and c.claim_status='APPROVED'
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
    v_incentive,
    v_claim,
    v_advance,
    v_recovery,
    (v_calc->>'net_payable_salary')::numeric,
    'DRAFT',
    v_posting_date,v_review_from,v_review_until,
    jsonb_build_object(
      'engine_version','V779_1_UNIVERSAL_MONTHLY_PAYROLL_CORE',
      'period_start',v_period_start,
      'period_end',v_period_end,
      'profile_snapshot',to_jsonb(v_profile),
      'attendance',jsonb_build_object(
        'scheduled_minutes',v_scheduled,
        'net_deduction_minutes',v_deduction,
        'net_extra_work_minutes',v_extra,
        'net_working_minutes',v_working,
        'net_deduction_dhm',
          public.rr_minutes_dhm_v778_2(v_deduction),
        'net_extra_work_dhm',
          public.rr_minutes_dhm_v778_2(v_extra)
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
    raise exception 'FINAL/PAID payroll refresh nahi ho sakta.';
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
    'version','V779_1_UNIVERSAL_MONTHLY_PAYROLL_CORE',
    'payroll_id',v_payroll_id,
    'worker_id',p_worker_id,
    'payroll_month',p_payroll_month,

    'monthly_salary',
      (v_calc->>'monthly_salary_amount')::numeric,

    'net_extra_work_amount',
      (v_calc->>'net_extra_work_amount')::numeric,

    'net_extra_work_dhm',
      public.rr_minutes_dhm_v778_2(v_extra),

    'monthly_incentive',v_incentive,
    'claims_recovery',v_recovery,

    'net_payable_salary',
      (v_calc->>'net_payable_salary')::numeric,

    'status','DRAFT'
  );
end $$;

-- ------------------------------------------------------------
-- 9. Worker self-service RPC
--
-- A worker can request only their own payroll.
-- Owner/Admin/Manager/Production may request any worker.
-- ------------------------------------------------------------
create or replace function public.rr_get_monthly_payroll_v779_1(
  p_worker_id uuid,
  p_payroll_month date,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_payroll public.rr_monthly_payroll_v779_1%rowtype;
  v_worker record;
begin
  if not public.rr_payroll_worker_is_self_v779_1(p_worker_id)
     and not public.rr_payroll_can_manage_v779_1()
  then
    raise exception 'Aap sirf apna Payroll dekh sakte hain.';
  end if;

  select *
  into v_payroll
  from public.rr_monthly_payroll_v779_1
  where worker_id=p_worker_id
    and payroll_month=p_payroll_month
    and data_mode=v_mode
  limit 1;

  if not found then
    raise exception 'Payroll record nahi mila.';
  end if;

  select worker_code,worker_name,department_code
  into v_worker
  from public.rr_worker_directory_unified_v1
  where worker_id=p_worker_id
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'payroll_id',v_payroll.payroll_id,
    'worker_id',p_worker_id,
    'worker_code',v_worker.worker_code,
    'worker_name',v_worker.worker_name,
    'department_code',v_worker.department_code,
    'salary_month',to_char(v_payroll.payroll_month,'FMMonth YYYY'),

    'summary',jsonb_build_object(
      'monthly_salary',v_payroll.monthly_salary_amount,

      'net_extra_work',jsonb_build_object(
        'amount',v_payroll.net_extra_work_amount,
        'time',public.rr_minutes_dhm_v778_2(
          v_payroll.net_extra_work_minutes
        ),
        'details_available',true
      ),

      'monthly_incentive',v_payroll.incentive_amount,
      'claims_recovery',v_payroll.claims_recovery_amount,
      'net_payable_salary',v_payroll.net_payable_salary
    ),

    'status',v_payroll.payroll_status,
    'posting_date',v_payroll.posting_date,
    'review_from',v_payroll.review_from,
    'review_until',v_payroll.review_until
  );
end $$;

-- ------------------------------------------------------------
-- 10. Own detail RPC
-- ------------------------------------------------------------
create or replace function public.rr_get_payroll_details_v779_1(
  p_payroll_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_payroll public.rr_monthly_payroll_v779_1%rowtype;
begin
  select *
  into v_payroll
  from public.rr_monthly_payroll_v779_1
  where payroll_id=p_payroll_id;

  if not found then raise exception 'Payroll record nahi mila.'; end if;

  if not public.rr_payroll_worker_is_self_v779_1(v_payroll.worker_id)
     and not public.rr_payroll_can_manage_v779_1()
  then
    raise exception 'Aap kisi dusre Worker ka Payroll nahi dekh sakte.';
  end if;

  return jsonb_build_object(
    'ok',true,
    'payroll_id',v_payroll.payroll_id,

    'monthly_salary_details',jsonb_build_object(
      'contract_monthly_salary',v_payroll.monthly_salary_contract,
      'monthly_salary_amount',v_payroll.monthly_salary_amount,
      'net_deduction_minutes',v_payroll.net_deduction_minutes,
      'net_deduction_dhm',
        public.rr_minutes_dhm_v778_2(
          v_payroll.net_deduction_minutes
        ),
      'deduction_amount',v_payroll.deduction_amount,
      'per_minute_rate',v_payroll.per_minute_rate,
      'basis_days',30,
      'base_minutes',18000
    ),

    'net_extra_work_details',jsonb_build_object(
      'minutes',v_payroll.net_extra_work_minutes,
      'time',
        public.rr_minutes_dhm_v778_2(
          v_payroll.net_extra_work_minutes
        ),
      'amount',v_payroll.net_extra_work_amount
    ),

    'incentive_details',jsonb_build_object(
      'amount',v_payroll.incentive_amount
    ),

    'claims_recovery_details',jsonb_build_object(
      'approved_claims',v_payroll.approved_claim_amount,
      'advance_recovery',v_payroll.advance_recovery_amount,
      'total',v_payroll.claims_recovery_amount
    ),

    'net_payable_salary',v_payroll.net_payable_salary,
    'calculation_snapshot',v_payroll.calculation_snapshot
  );
end $$;

-- ------------------------------------------------------------
-- 11. Read model for management boards
-- ------------------------------------------------------------
create or replace view public.rr_monthly_payroll_board_v779_1 as
select
  p.payroll_id,
  p.worker_id,
  w.worker_code,
  w.worker_name,
  w.department_code,

  p.payroll_month,
  p.monthly_salary_contract,
  p.monthly_salary_amount,

  p.net_extra_work_minutes,
  public.rr_minutes_dhm_v778_2(
    p.net_extra_work_minutes
  ) as net_extra_work_dhm,
  p.net_extra_work_amount,

  p.incentive_amount,
  p.claims_recovery_amount,
  p.net_payable_salary,

  p.payroll_status,
  p.posting_date,
  p.review_from,
  p.review_until,
  p.data_mode,
  p.updated_at
from public.rr_monthly_payroll_v779_1 p
join public.rr_worker_directory_unified_v1 w
  on w.worker_id=p.worker_id;

-- ------------------------------------------------------------
-- 12. Security
-- ------------------------------------------------------------
revoke all
on public.rr_payroll_incentives_v779_1,
   public.rr_monthly_payroll_v779_1,
   public.rr_payroll_source_applications_v779_1,
   public.rr_payroll_events_v779_1
from anon,authenticated;

revoke all
on public.rr_monthly_payroll_board_v779_1
from anon,authenticated;

grant execute on function public.rr_calculate_monthly_salary_v779_1(
  numeric,integer,integer,numeric,numeric
) to authenticated;

grant execute on function public.rr_payroll_actor_role_v779_1()
to authenticated;

grant execute on function public.rr_payroll_worker_is_self_v779_1(uuid)
to authenticated;

grant execute on function public.rr_payroll_can_manage_v779_1()
to authenticated;

grant execute on function public.rr_save_payroll_incentive_v779_1(
  uuid,date,text,numeric,text,text,text,text
) to authenticated;

grant execute on function public.rr_decide_payroll_incentive_v779_1(
  uuid,text,text
) to authenticated;

grant execute on function public.rr_generate_worker_monthly_payroll_v779_1(
  uuid,date,text,text
) to authenticated;

grant execute on function public.rr_get_monthly_payroll_v779_1(
  uuid,date,text
) to authenticated;

grant execute on function public.rr_get_payroll_details_v779_1(uuid)
to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V779_1_UNIVERSAL_MONTHLY_PAYROLL_CORE',

  'salary_basis_days',30,
  'minutes_per_day',600,
  'monthly_base_minutes',18000,

  'payslip_heads',jsonb_build_array(
    'MONTHLY_SALARY',
    'NET_EXTRA_WORK',
    'MONTHLY_INCENTIVE',
    'CLAIMS_RECOVERY',
    'NET_PAYABLE_SALARY'
  ),

  'net_extra_work_details_button',true,
  'worker_own_data_only',true,

  'existing_advances_reused',true,
  'existing_claims_reused',true,
  'existing_settlement_written',false,
  'existing_worker_ledger_written',false,

  'reason_settlement_not_written',
    'CHECK_CONSTRAINT_VALUES_NOT_YET_VERIFIED',

  'special_multiplier_used',false
) as rr_upm_v779_1_result;
