
begin;

create or replace function public.rr_business_date_v777_2(p_event_at timestamptz)
returns date language sql immutable as $$
  select (p_event_at at time zone 'Asia/Kolkata')::date
$$;

create table if not exists public.rr_shift_master_v777_2 (
  shift_id uuid primary key default gen_random_uuid(),
  shift_code text not null unique,
  shift_name text not null,
  duty_start time not null,
  duty_end time not null,
  normal_payable_minutes integer not null check(normal_payable_minutes>0),
  lunch_start time,
  lunch_end time,
  lunch_is_paid boolean not null default true,
  grace_in_minutes integer not null default 10 check(grace_in_minutes>=0),
  minimum_presence_minutes integer not null default 240 check(minimum_presence_minutes>=0),
  overtime_multiplier numeric(8,4) not null default 1 check(overtime_multiplier>=0),
  holiday_multiplier numeric(8,4) not null default 1.5 check(holiday_multiplier>=0),
  is_active boolean not null default true,
  effective_from date not null default current_date,
  effective_to date,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  check(effective_to is null or effective_to>=effective_from)
);

insert into public.rr_shift_master_v777_2(
  shift_code,shift_name,duty_start,duty_end,normal_payable_minutes,
  lunch_start,lunch_end,lunch_is_paid,grace_in_minutes,
  minimum_presence_minutes,overtime_multiplier,holiday_multiplier
)
values(
  'GENERAL_10_TO_8','General 10 AM to 8 PM',
  '10:00'::time,'20:00'::time,600,
  '13:30'::time,'14:15'::time,true,10,240,1,1.5
)
on conflict(shift_code) do update set
  shift_name=excluded.shift_name,
  duty_start=excluded.duty_start,
  duty_end=excluded.duty_end,
  normal_payable_minutes=excluded.normal_payable_minutes,
  lunch_start=excluded.lunch_start,
  lunch_end=excluded.lunch_end,
  lunch_is_paid=excluded.lunch_is_paid,
  grace_in_minutes=excluded.grace_in_minutes,
  minimum_presence_minutes=excluded.minimum_presence_minutes,
  overtime_multiplier=excluded.overtime_multiplier,
  holiday_multiplier=excluded.holiday_multiplier,
  updated_at=now();

create table if not exists public.rr_holiday_calendar_v777_2 (
  holiday_id uuid primary key default gen_random_uuid(),
  holiday_date date not null,
  holiday_name text not null check(holiday_name in(
    'REPUBLIC_DAY','HOLI','EID_UL_FITR','EID_UL_ADHA',
    'RAKSHA_BANDHAN','INDEPENDENCE_DAY','VISHWAKARMA_DAY','DIWALI'
  )),
  applies_to text not null default 'SALARIED_ONLY' check(applies_to in(
    'ALL','SALARIED_ONLY','PIECE_RATE_ONLY','SELECTED_DEPARTMENTS'
  )),
  selected_departments jsonb not null default '[]'::jsonb,
  is_paid_holiday boolean not null default true,
  holiday_multiplier numeric(8,4) not null default 1.5 check(holiday_multiplier>=0),
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  is_active boolean not null default true,
  payroll_locked boolean not null default false,
  lock_reason text,
  locked_at timestamptz,
  locked_by uuid,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  check(applies_to='SELECTED_DEPARTMENTS' or selected_departments='[]'::jsonb)
);

create unique index if not exists rr_holiday_calendar_v777_2_uq
on public.rr_holiday_calendar_v777_2(holiday_date,holiday_name,data_mode);

create table if not exists public.rr_worker_payroll_profile_v777_2 (
  profile_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  worker_category text not null check(worker_category in('PIECE_RATE','SALARIED')),
  shift_id uuid references public.rr_shift_master_v777_2(shift_id),
  monthly_salary numeric(14,2) not null default 0 check(monthly_salary>=0),
  weekly_holiday_isodow integer not null default 1 check(weekly_holiday_isodow=1),
  attendance_required boolean not null default false,
  late_deduction_applicable boolean not null default true,
  overtime_applicable boolean not null default true,
  holiday_extra_applicable boolean not null default true,
  grace_offset_against_ot boolean not null default true,
  exception_reason text,
  piece_advance_percent numeric(8,4) not null default 40 check(piece_advance_percent>=0),
  piece_advance_floor numeric(14,2) not null default 2000 check(piece_advance_floor>=0),
  salaried_advance_limit_type text check(
    salaried_advance_limit_type is null or salaried_advance_limit_type in('PERCENT','FIXED')
  ),
  salaried_advance_limit_value numeric(14,2) check(
    salaried_advance_limit_value is null or salaried_advance_limit_value>=0
  ),
  advance_cycle text not null,
  settlement_cycle text not null,
  salary_advance_day integer,
  salary_due_day integer,
  claim_debit_timing text not null default 'SETTLEMENT_ONLY' check(
    claim_debit_timing in('SETTLEMENT_ONLY','FULL_AND_FINAL_ONLY')
  ),
  effective_from date not null,
  effective_to date,
  status text not null default 'ACTIVE' check(status in('ACTIVE','INACTIVE')),
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  configured_at timestamptz not null default now(),
  configured_by uuid default auth.uid(),
  reason text,
  check(effective_to is null or effective_to>=effective_from),
  check(
    (
      worker_category='PIECE_RATE'
      and attendance_required=false
      and monthly_salary=0
      and shift_id is null
      and advance_cycle='WEEKLY'
      and settlement_cycle='FORTNIGHTLY'
      and salary_advance_day is null
      and salary_due_day is null
      and salaried_advance_limit_type is null
      and salaried_advance_limit_value is null
    )
    or
    (
      worker_category='SALARIED'
      and attendance_required=true
      and monthly_salary>0
      and shift_id is not null
      and advance_cycle='MONTHLY_DAY_20'
      and settlement_cycle='MONTHLY'
      and salary_advance_day=20
      and salary_due_day=7
    )
  )
);

create index if not exists rr_worker_payroll_profile_v777_2_worker_idx
on public.rr_worker_payroll_profile_v777_2(
  worker_id,effective_from,effective_to,status,data_mode
);

create or replace function public.rr_guard_payroll_profile_overlap_v777_2()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if exists(
    select 1
    from public.rr_worker_payroll_profile_v777_2 p
    where p.worker_id=new.worker_id
      and p.data_mode=new.data_mode
      and p.profile_id<>new.profile_id
      and daterange(p.effective_from,coalesce(p.effective_to,'infinity'::date),'[]')
          && daterange(new.effective_from,coalesce(new.effective_to,'infinity'::date),'[]')
  ) then
    raise exception 'Worker Payroll Profile effective dates overlap kar rahe hain.';
  end if;
  return new;
end $$;

drop trigger if exists rr_guard_payroll_profile_overlap_v777_2
on public.rr_worker_payroll_profile_v777_2;

create trigger rr_guard_payroll_profile_overlap_v777_2
before insert or update on public.rr_worker_payroll_profile_v777_2
for each row execute function public.rr_guard_payroll_profile_overlap_v777_2();

create table if not exists public.rr_worker_payroll_profile_events_v777_2 (
  event_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  profile_id uuid,
  event_type text not null,
  old_snapshot jsonb,
  new_snapshot jsonb,
  actor_auth_user_id uuid default auth.uid(),
  actor_name text,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.rr_attendance_events_v777_2 (
  attendance_event_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  event_type text not null check(event_type in('CHECK_IN','CHECK_OUT')),
  event_at timestamptz not null,
  business_date date generated always as (public.rr_business_date_v777_2(event_at)) stored,
  attendance_source text not null check(attendance_source in('GPS','QR','MANUAL','ADMIN_OVERRIDE')),
  latitude numeric(10,7),
  longitude numeric(10,7),
  gps_accuracy_meters numeric(10,2),
  factory_radius_meters numeric(10,2) not null default 100 check(factory_radius_meters>0),
  inside_factory_radius boolean,
  source_event_id text,
  metadata jsonb not null default '{}'::jsonb,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  is_void boolean not null default false,
  void_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create unique index if not exists rr_attendance_events_v777_2_source_uq
on public.rr_attendance_events_v777_2(source_event_id,data_mode)
where source_event_id is not null;

create index if not exists rr_attendance_events_v777_2_worker_date_idx
on public.rr_attendance_events_v777_2(worker_id,business_date,event_at);

create table if not exists public.rr_attendance_day_v777_2 (
  attendance_day_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  profile_id uuid not null references public.rr_worker_payroll_profile_v777_2(profile_id),
  attendance_date date not null,
  first_check_in timestamptz,
  last_check_out timestamptz,
  gross_presence_minutes integer not null default 0 check(gross_presence_minutes>=0),
  grace_used_minutes integer not null default 0 check(grace_used_minutes>=0),
  late_deduction_minutes integer not null default 0 check(late_deduction_minutes>=0),
  early_exit_deduction_minutes integer not null default 0 check(early_exit_deduction_minutes>=0),
  normal_payable_minutes integer not null default 0 check(normal_payable_minutes>=0),
  gross_overtime_minutes integer not null default 0 check(gross_overtime_minutes>=0),
  payable_overtime_minutes integer not null default 0 check(payable_overtime_minutes>=0),
  holiday_work_minutes integer not null default 0 check(holiday_work_minutes>=0),
  attendance_status text not null check(attendance_status in(
    'PENDING','PRESENT','ABSENT','HOLIDAY','HOLIDAY_WORKED','REVIEW_REQUIRED'
  )),
  is_holiday boolean not null default false,
  calculation_snapshot jsonb not null default '{}'::jsonb,
  approval_status text not null default 'PENDING' check(
    approval_status in('PENDING','APPROVED','REJECTED')
  ),
  approved_by uuid,
  approved_at timestamptz,
  approval_reason text,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(worker_id,attendance_date,data_mode)
);

create table if not exists public.rr_piece_job_presence_v777_2 (
  presence_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  presence_date date not null,
  presence_source text not null check(presence_source in(
    'ASSIGNED_JOB','IN_PROGRESS_JOB','SUBMIT_ACTIVITY','ALTER_ACTIVITY','REMAKE_ACTIVITY'
  )),
  canonical_lot_id text,
  lot_no text,
  department_code text,
  assignment_id text,
  source_event_id text not null,
  activity_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  created_at timestamptz not null default now(),
  unique(worker_id,presence_source,source_event_id,data_mode)
);

create table if not exists public.rr_worker_operational_status_v777_2 (
  worker_id uuid primary key,
  operational_status text not null default 'AVAILABLE' check(operational_status in(
    'AVAILABLE','ASSIGNED','ON_LEAVE','HOLIDAY','OFF_DUTY',
    'INACTIVE','BLOCKED','FULL_AND_FINAL','LEFT_JOB'
  )),
  last_activity_at timestamptz,
  last_assignment_at timestamptz,
  auto_inactive_after_days integer not null default 6 check(auto_inactive_after_days=6),
  auto_inactivated_at timestamptz,
  status_reason text,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table if not exists public.rr_worker_advances_v777_2 (
  advance_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  worker_category text not null check(worker_category in('PIECE_RATE','SALARIED')),
  advance_date date not null,
  earned_amount_snapshot numeric(16,2) not null default 0 check(earned_amount_snapshot>=0),
  allowed_limit_snapshot numeric(16,2) not null default 0 check(allowed_limit_snapshot>=0),
  advance_amount numeric(16,2) not null check(advance_amount>0),
  advance_type text not null check(advance_type in(
    'WEEKLY_ADVANCE','SALARY_ADVANCE_DAY_20','SPECIAL_ADVANCE'
  )),
  payment_mode text not null check(payment_mode in('CASH','UPI','BANK')),
  reference_no text,
  notes text,
  claim_debit_applied boolean not null default false check(claim_debit_applied=false),
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  is_reversed boolean not null default false,
  reversal_reason text,
  reversed_at timestamptz,
  reversed_by uuid
);

create table if not exists public.rr_worker_settlements_v777_2 (
  settlement_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  worker_category text not null check(worker_category in('PIECE_RATE','SALARIED')),
  cycle_type text not null check(cycle_type in('FORTNIGHTLY','MONTHLY','FULL_AND_FINAL')),
  period_start date not null,
  period_end date not null,
  opening_balance numeric(16,2) not null default 0,
  earnings_amount numeric(16,2) not null default 0,
  incentive_amount numeric(16,2) not null default 0,
  overtime_amount numeric(16,2) not null default 0,
  holiday_amount numeric(16,2) not null default 0,
  advance_recovery_amount numeric(16,2) not null default 0,
  approved_claim_debit_amount numeric(16,2) not null default 0,
  payment_amount numeric(16,2) not null default 0,
  closing_balance numeric(16,2) not null default 0,
  claim_debit_applied boolean not null default false,
  full_and_final boolean not null default false,
  settlement_status text not null default 'OPEN' check(settlement_status in(
    'OPEN','CALCULATED','APPROVED','PAID','CLOSED','REVERSED','CANCELLED'
  )),
  calculation_snapshot jsonb not null default '{}'::jsonb,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  approved_at timestamptz,
  approved_by uuid,
  closed_at timestamptz,
  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,
  unique(worker_id,cycle_type,period_start,period_end,data_mode),
  check(period_end>=period_start)
);

create table if not exists public.rr_worker_claims_v777_2 (
  claim_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  claim_code text not null,
  claim_type text not null,
  claimed_amount numeric(16,2) not null check(claimed_amount>=0),
  approved_amount numeric(16,2) not null default 0 check(approved_amount>=0),
  claim_status text not null default 'RAISED' check(claim_status in(
    'RAISED','REVIEW_PENDING','APPROVED_PENDING_SETTLEMENT',
    'REJECTED','DEBIT_POSTED','REVERSED'
  )),
  source_type text,
  source_id text,
  evidence jsonb not null default '{}'::jsonb,
  raised_at timestamptz not null default now(),
  raised_by uuid default auth.uid(),
  approved_at timestamptz,
  approved_by uuid,
  approval_reason text,
  debit_settlement_id uuid references public.rr_worker_settlements_v777_2(settlement_id),
  debit_posted_at timestamptz,
  reversed_at timestamptz,
  reversed_by uuid,
  reversal_reason text,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  unique(claim_code,data_mode),
  check(approved_amount<=claimed_amount),
  check(claim_status<>'DEBIT_POSTED' or debit_settlement_id is not null)
);

create table if not exists public.rr_work_analytics_events_v777_2 (
  analytics_event_id uuid primary key default gen_random_uuid(),
  source_name text not null,
  source_event_id text not null,
  assignment_id text not null,
  source_sequence_no bigint not null,
  canonical_lot_id text,
  lot_no text,
  colour_code text,
  department_code text not null,
  worker_id uuid not null,
  event_type text not null check(event_type in(
    'ASSIGNED','STARTED','PAUSED','RESUMED','SUBMITTED','COMPLETED',
    'CANCELLED','REOPENED','ALTER_STARTED','ALTER_COMPLETED',
    'REMAKE_STARTED','REMAKE_COMPLETED'
  )),
  assigned_qty numeric(16,2) not null default 0 check(assigned_qty>=0),
  good_qty numeric(16,2) not null default 0 check(good_qty>=0),
  alter_qty numeric(16,2) not null default 0 check(alter_qty>=0),
  remake_qty numeric(16,2) not null default 0 check(remake_qty>=0),
  rejected_qty numeric(16,2) not null default 0 check(rejected_qty>=0),
  occurred_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  created_at timestamptz not null default now(),
  unique(source_name,source_event_id,data_mode),
  unique(assignment_id,source_sequence_no,data_mode)
);

create or replace function public.rr_piece_advance_limit_v777_2(p_earned_amount numeric)
returns numeric language sql immutable as $$
  select greatest(coalesce(p_earned_amount,0)*0.40,2000)
$$;

create or replace function public.rr_mark_worker_activity_v777_2(
  p_worker_id uuid,p_activity_at timestamptz,p_activity_type text,p_data_mode text default 'TEST'
)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_status text;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
begin
  if not exists(
    select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=p_worker_id
  ) then raise exception 'Worker nahi mila.'; end if;

  v_status:=case when upper(trim(coalesce(p_activity_type,'')))='ASSIGNMENT'
    then 'ASSIGNED' else 'AVAILABLE' end;

  insert into public.rr_worker_operational_status_v777_2(
    worker_id,operational_status,last_activity_at,last_assignment_at,
    auto_inactive_after_days,auto_inactivated_at,status_reason,data_mode,updated_at,updated_by
  )
  values(
    p_worker_id,v_status,p_activity_at,
    case when upper(trim(coalesce(p_activity_type,'')))='ASSIGNMENT' then p_activity_at else null end,
    6,null,'Activity received',v_mode,now(),auth.uid()
  )
  on conflict(worker_id) do update set
    operational_status=case
      when public.rr_worker_operational_status_v777_2.operational_status
        in('BLOCKED','FULL_AND_FINAL','LEFT_JOB')
      then public.rr_worker_operational_status_v777_2.operational_status
      else excluded.operational_status
    end,
    last_activity_at=greatest(
      coalesce(public.rr_worker_operational_status_v777_2.last_activity_at,excluded.last_activity_at),
      excluded.last_activity_at
    ),
    last_assignment_at=coalesce(excluded.last_assignment_at,
      public.rr_worker_operational_status_v777_2.last_assignment_at),
    auto_inactivated_at=null,
    status_reason='Activity received',
    data_mode=excluded.data_mode,
    updated_at=now(),
    updated_by=auth.uid();

  return jsonb_build_object(
    'ok',true,'worker_id',p_worker_id,'operational_status',v_status,'auto_reactivated',true
  );
end $$;

create or replace function public.rr_worker_auto_inactive_scan_v777_2(
  p_scan_at timestamptz default now(),p_data_mode text default 'TEST'
)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_count integer:=0;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
begin
  update public.rr_worker_operational_status_v777_2 s
  set operational_status='INACTIVE',
      auto_inactivated_at=p_scan_at,
      status_reason='6 days without recorded activity',
      updated_at=now(),
      updated_by=auth.uid()
  where s.data_mode=v_mode
    and s.operational_status not in('BLOCKED','FULL_AND_FINAL','LEFT_JOB','INACTIVE')
    and coalesce(s.last_activity_at,s.updated_at)<p_scan_at-interval '6 days';

  get diagnostics v_count=row_count;

  return jsonb_build_object(
    'ok',true,'version','V777_2_FINAL_CONSOLIDATED_FOUNDATION',
    'scan_at',p_scan_at,'data_mode',v_mode,
    'workers_auto_inactivated',v_count,
    'assignment_history_removed',false,
    'worker_directory_removed',false,
    'auto_reactivate_on_new_activity',true
  );
end $$;

create or replace view public.rr_work_assignment_summary_v777_2 as
with ordered as (
  select e.*,
    lead(e.event_type) over(
      partition by e.assignment_id,e.data_mode order by e.source_sequence_no
    ) as next_event_type,
    lead(e.occurred_at) over(
      partition by e.assignment_id,e.data_mode order by e.source_sequence_no
    ) as next_occurred_at
  from public.rr_work_analytics_events_v777_2 e
),
agg as (
  select
    assignment_id,data_mode,
    (array_agg(canonical_lot_id order by source_sequence_no desc)
      filter(where canonical_lot_id is not null))[1] as canonical_lot_id,
    (array_agg(lot_no order by source_sequence_no desc)
      filter(where lot_no is not null))[1] as lot_no,
    (array_agg(colour_code order by source_sequence_no desc)
      filter(where colour_code is not null))[1] as colour_code,
    (array_agg(department_code order by source_sequence_no desc))[1] as department_code,
    (array_agg(worker_id order by source_sequence_no desc))[1] as worker_id,
    (array_agg(event_type order by source_sequence_no desc))[1] as latest_status,
    min(occurred_at) filter(where event_type='ASSIGNED') as assigned_at,
    min(occurred_at) filter(where event_type='STARTED') as started_at,
    max(occurred_at) filter(where event_type='COMPLETED') as completed_at,
    coalesce((array_agg(assigned_qty order by source_sequence_no desc))[1],0) as assigned_qty,
    coalesce((array_agg(good_qty order by source_sequence_no desc))[1],0) as good_qty,
    coalesce((array_agg(alter_qty order by source_sequence_no desc))[1],0) as alter_qty,
    coalesce((array_agg(remake_qty order by source_sequence_no desc))[1],0) as remake_qty,
    coalesce((array_agg(rejected_qty order by source_sequence_no desc))[1],0) as rejected_qty,
    coalesce(sum(
      case when event_type='PAUSED'
        and next_event_type in('RESUMED','COMPLETED','CANCELLED')
        and next_occurred_at>=occurred_at
      then extract(epoch from(next_occurred_at-occurred_at))/60.0 else 0 end
    ),0) as paused_minutes
  from ordered
  group by assignment_id,data_mode
)
select a.*,
  case when a.latest_status='COMPLETED'
    and a.completed_at is not null and a.started_at is not null
    and a.completed_at>=a.started_at
  then extract(epoch from(a.completed_at-a.started_at))/60.0 else null end
    as elapsed_minutes,
  case when a.latest_status='COMPLETED'
    and a.completed_at is not null and a.started_at is not null
    and a.completed_at>=a.started_at
  then greatest(extract(epoch from(a.completed_at-a.started_at))/60.0-a.paused_minutes,0)
  else null end as active_work_minutes
from agg a;

create or replace view public.rr_worker_daily_productivity_v777_2 as
select
  worker_id,department_code,completed_at::date as work_date,data_mode,
  count(*) as completed_jobs,
  count(distinct canonical_lot_id) as completed_lots,
  sum(good_qty) as good_qty,
  sum(alter_qty) as alter_qty,
  sum(remake_qty) as remake_qty,
  sum(rejected_qty) as rejected_qty,
  sum(active_work_minutes) as active_work_minutes,
  case when sum(active_work_minutes)>0
    then sum(good_qty)/(sum(active_work_minutes)/60.0) else null end
    as pcs_per_active_hour
from public.rr_work_assignment_summary_v777_2
where latest_status='COMPLETED' and good_qty>0
group by worker_id,department_code,completed_at::date,data_mode;

create or replace view public.rr_department_daily_productivity_v777_2 as
select
  department_code,work_date,data_mode,
  count(distinct worker_id) as active_workers,
  sum(completed_jobs) as completed_jobs,
  sum(completed_lots) as completed_lots,
  sum(good_qty) as good_qty,
  sum(alter_qty) as alter_qty,
  sum(remake_qty) as remake_qty,
  sum(rejected_qty) as rejected_qty,
  sum(active_work_minutes) as active_work_minutes,
  case when sum(active_work_minutes)>0
    then sum(good_qty)/(sum(active_work_minutes)/60.0) else null end
    as pcs_per_active_hour
from public.rr_worker_daily_productivity_v777_2
group by department_code,work_date,data_mode;

revoke all
on public.rr_shift_master_v777_2,
   public.rr_holiday_calendar_v777_2,
   public.rr_worker_payroll_profile_v777_2,
   public.rr_worker_payroll_profile_events_v777_2,
   public.rr_attendance_events_v777_2,
   public.rr_attendance_day_v777_2,
   public.rr_piece_job_presence_v777_2,
   public.rr_worker_operational_status_v777_2,
   public.rr_worker_advances_v777_2,
   public.rr_worker_settlements_v777_2,
   public.rr_worker_claims_v777_2,
   public.rr_work_analytics_events_v777_2
from anon,authenticated;

grant execute on function public.rr_business_date_v777_2(timestamptz) to authenticated;
grant execute on function public.rr_piece_advance_limit_v777_2(numeric) to authenticated;
grant execute on function public.rr_mark_worker_activity_v777_2(uuid,timestamptz,text,text)
to authenticated;
grant execute on function public.rr_worker_auto_inactive_scan_v777_2(timestamptz,text)
to authenticated;

grant select on public.rr_work_assignment_summary_v777_2 to authenticated;
grant select on public.rr_worker_daily_productivity_v777_2 to authenticated;
grant select on public.rr_department_daily_productivity_v777_2 to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V777_2_FINAL_CONSOLIDATED_FOUNDATION',
  'run_earlier_v777_packages',false,
  'worker_categories',jsonb_build_array('PIECE_RATE','SALARIED'),
  'normal_duty_start','10:00',
  'normal_duty_end','20:00',
  'normal_payable_minutes',600,
  'lunch_paid',true,
  'grace_minutes',10,
  'minimum_presence_minutes',240,
  'late_deduction','MINUTE_TO_MINUTE_AFTER_GRACE',
  'early_exit_deduction','MINUTE_TO_MINUTE',
  'overtime','MINUTE_TO_MINUTE_AFTER_20_00',
  'grace_offset_against_ot',true,
  'holiday_work_multiplier',1.5,
  'piece_rate_attendance',false,
  'piece_rate_presence','UPM_JOB_ACTIVITY',
  'piece_rate_advance','MAX_OF_40_PERCENT_OR_2000',
  'piece_rate_settlement','FORTNIGHTLY',
  'salaried_advance_day',20,
  'salaried_due_day',7,
  'claim_debit_on_advance',false,
  'claim_debit_timing','SETTLEMENT_OR_FULL_AND_FINAL',
  'weekly_holiday','MONDAY',
  'holiday_calendar','MANUAL',
  'factory_radius_meters',100,
  'auto_inactive_days',6,
  'auto_reactivate_on_new_activity',true,
  'performance_weights',jsonb_build_object(
    'completion_time',40,'pcs',40,'alter_percent',20
  ),
  'analytics_quantity_semantics','CUMULATIVE_SNAPSHOT',
  'test_real_data_isolated',true,
  'existing_worker_ledger_modified',false,
  'ledger_posting_included',false,
  'whatsapp_sms_included',false
) as rr_upm_v777_2_result;
