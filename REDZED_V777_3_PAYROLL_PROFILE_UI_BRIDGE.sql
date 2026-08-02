
-- ============================================================
-- REDZED V777.3 — PAYROLL PROFILE UI BRIDGE
-- Dependency: V777.2 successfully installed
-- ============================================================

begin;

-- Read-only shift options for Owner/Admin frontend.
create or replace view public.rr_shift_options_v777_3 as
select
  shift_id,
  shift_code,
  shift_name,
  duty_start,
  duty_end,
  normal_payable_minutes,
  lunch_start,
  lunch_end,
  lunch_is_paid,
  grace_in_minutes,
  minimum_presence_minutes,
  overtime_multiplier,
  holiday_multiplier,
  effective_from,
  effective_to
from public.rr_shift_master_v777_2
where is_active
  and effective_from<=current_date
  and (effective_to is null or effective_to>=current_date);

grant select on public.rr_shift_options_v777_3 to authenticated;

-- Current/latest payroll profile board.
create or replace view public.rr_worker_payroll_board_v777_3 as
with latest as (
  select distinct on(p.worker_id,p.data_mode)
    p.*
  from public.rr_worker_payroll_profile_v777_2 p
  order by
    p.worker_id,
    p.data_mode,
    (p.status='ACTIVE') desc,
    p.effective_from desc,
    p.configured_at desc
)
select
  w.worker_id,
  w.worker_code,
  w.worker_name,
  w.department_code,
  w.role_code,

  p.profile_id,
  p.worker_category,
  p.shift_id,
  s.shift_code,
  s.shift_name,
  s.duty_start,
  s.duty_end,
  s.normal_payable_minutes,
  s.lunch_is_paid,
  s.grace_in_minutes,
  s.minimum_presence_minutes,
  s.overtime_multiplier,
  s.holiday_multiplier,

  p.monthly_salary,
  p.attendance_required,
  p.late_deduction_applicable,
  p.overtime_applicable,
  p.holiday_extra_applicable,
  p.grace_offset_against_ot,
  p.exception_reason,

  p.piece_advance_percent,
  p.piece_advance_floor,

  p.salaried_advance_limit_type,
  p.salaried_advance_limit_value,

  p.advance_cycle,
  p.settlement_cycle,
  p.salary_advance_day,
  p.salary_due_day,
  p.claim_debit_timing,

  p.effective_from,
  p.effective_to,
  p.status as payroll_profile_status,
  p.data_mode,
  p.configured_at,
  p.configured_by,
  p.reason

from public.rr_worker_directory_unified_v1 w
left join latest p
  on p.worker_id=w.worker_id
left join public.rr_shift_master_v777_2 s
  on s.shift_id=p.shift_id;

grant select on public.rr_worker_payroll_board_v777_3 to authenticated;

create or replace function public.rr_set_worker_payroll_profile_v777_3(
  p_worker_id uuid,
  p_worker_category text,
  p_monthly_salary numeric default 0,
  p_shift_id uuid default null,
  p_late_deduction_applicable boolean default true,
  p_overtime_applicable boolean default true,
  p_holiday_extra_applicable boolean default true,
  p_grace_offset_against_ot boolean default true,
  p_exception_reason text default null,
  p_salaried_advance_limit_type text default null,
  p_salaried_advance_limit_value numeric default null,
  p_effective_from date default current_date,
  p_effective_to date default null,
  p_data_mode text default 'TEST',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_worker record;
  v_category text:=upper(trim(coalesce(p_worker_category,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_limit_type text:=nullif(upper(trim(coalesce(p_salaried_advance_limit_type,''))),'');
  v_current public.rr_worker_payroll_profile_v777_2%rowtype;
  v_saved public.rr_worker_payroll_profile_v777_2%rowtype;
  v_old_snapshot jsonb;
begin
  select *
  into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active ERP profile required.';
  end if;

  if lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Payroll Profile permission denied.';
  end if;

  select worker_id,worker_name
  into v_worker
  from public.rr_worker_directory_unified_v1
  where worker_id=p_worker_id
  limit 1;

  if not found then
    raise exception 'Worker nahi mila.';
  end if;

  if v_category not in('PIECE_RATE','SALARIED') then
    raise exception 'Worker Category PIECE_RATE ya SALARIED honi chahiye.';
  end if;

  if v_mode not in('TEST','REAL') then
    raise exception 'Data Mode TEST ya REAL hona chahiye.';
  end if;

  if p_effective_to is not null and p_effective_to<p_effective_from then
    raise exception 'Effective To, Effective From se pehle nahi ho sakta.';
  end if;

  if v_category='SALARIED' then
    if coalesce(p_monthly_salary,0)<=0 then
      raise exception 'SALARIED Worker ke liye Monthly Salary required hai.';
    end if;

    if p_shift_id is null then
      raise exception 'SALARIED Worker ke liye Shift required hai.';
    end if;

    if not exists(
      select 1
      from public.rr_shift_master_v777_2 s
      where s.shift_id=p_shift_id
        and s.is_active
        and s.effective_from<=p_effective_from
        and (s.effective_to is null or s.effective_to>=p_effective_from)
    ) then
      raise exception 'Selected active Shift nahi mila.';
    end if;

    if v_limit_type not in('PERCENT','FIXED') then
      raise exception 'Salaried Advance Limit Type PERCENT ya FIXED required hai.';
    end if;

    if coalesce(p_salaried_advance_limit_value,0)<=0 then
      raise exception 'Salaried Advance Limit Value required hai.';
    end if;

    if v_limit_type='PERCENT'
       and p_salaried_advance_limit_value>100
    then
      raise exception 'Salaried Advance Percent 100 se zyada nahi ho sakta.';
    end if;
  else
    p_monthly_salary:=0;
    p_shift_id:=null;
    v_limit_type:=null;
    p_salaried_advance_limit_value:=null;
  end if;

  select *
  into v_current
  from public.rr_worker_payroll_profile_v777_2
  where worker_id=p_worker_id
    and data_mode=v_mode
    and status='ACTIVE'
    and effective_to is null
  order by effective_from desc,configured_at desc
  limit 1
  for update;

  if found then
    v_old_snapshot:=to_jsonb(v_current);

    if p_effective_from<v_current.effective_from then
      raise exception
        'New Effective From current active Profile se pehle nahi ho sakta.';
    end if;

    if p_effective_from=v_current.effective_from then
      update public.rr_worker_payroll_profile_v777_2
      set
        worker_category=v_category,
        shift_id=p_shift_id,
        monthly_salary=coalesce(p_monthly_salary,0),
        weekly_holiday_isodow=1,
        attendance_required=(v_category='SALARIED'),

        late_deduction_applicable=p_late_deduction_applicable,
        overtime_applicable=p_overtime_applicable,
        holiday_extra_applicable=p_holiday_extra_applicable,
        grace_offset_against_ot=p_grace_offset_against_ot,
        exception_reason=nullif(trim(p_exception_reason),''),

        piece_advance_percent=40,
        piece_advance_floor=2000,

        salaried_advance_limit_type=v_limit_type,
        salaried_advance_limit_value=p_salaried_advance_limit_value,

        advance_cycle=case
          when v_category='PIECE_RATE' then 'WEEKLY'
          else 'MONTHLY_DAY_20'
        end,
        settlement_cycle=case
          when v_category='PIECE_RATE' then 'FORTNIGHTLY'
          else 'MONTHLY'
        end,
        salary_advance_day=case
          when v_category='SALARIED' then 20
          else null
        end,
        salary_due_day=case
          when v_category='SALARIED' then 7
          else null
        end,

        claim_debit_timing='SETTLEMENT_ONLY',
        effective_to=p_effective_to,
        status='ACTIVE',
        configured_at=now(),
        configured_by=auth.uid(),
        reason=p_reason
      where profile_id=v_current.profile_id
      returning * into v_saved;

    else
      update public.rr_worker_payroll_profile_v777_2
      set
        effective_to=p_effective_from-1,
        status='INACTIVE'
      where profile_id=v_current.profile_id;

      insert into public.rr_worker_payroll_profile_v777_2(
        worker_id,
        worker_category,
        shift_id,
        monthly_salary,
        weekly_holiday_isodow,
        attendance_required,

        late_deduction_applicable,
        overtime_applicable,
        holiday_extra_applicable,
        grace_offset_against_ot,
        exception_reason,

        piece_advance_percent,
        piece_advance_floor,

        salaried_advance_limit_type,
        salaried_advance_limit_value,

        advance_cycle,
        settlement_cycle,
        salary_advance_day,
        salary_due_day,
        claim_debit_timing,

        effective_from,
        effective_to,
        status,
        data_mode,
        configured_at,
        configured_by,
        reason
      )
      values(
        p_worker_id,
        v_category,
        p_shift_id,
        coalesce(p_monthly_salary,0),
        1,
        v_category='SALARIED',

        p_late_deduction_applicable,
        p_overtime_applicable,
        p_holiday_extra_applicable,
        p_grace_offset_against_ot,
        nullif(trim(p_exception_reason),''),

        40,
        2000,

        v_limit_type,
        p_salaried_advance_limit_value,

        case when v_category='PIECE_RATE'
          then 'WEEKLY' else 'MONTHLY_DAY_20'
        end,
        case when v_category='PIECE_RATE'
          then 'FORTNIGHTLY' else 'MONTHLY'
        end,
        case when v_category='SALARIED' then 20 else null end,
        case when v_category='SALARIED' then 7 else null end,
        'SETTLEMENT_ONLY',

        p_effective_from,
        p_effective_to,
        'ACTIVE',
        v_mode,
        now(),
        auth.uid(),
        p_reason
      )
      returning * into v_saved;
    end if;

  else
    insert into public.rr_worker_payroll_profile_v777_2(
      worker_id,
      worker_category,
      shift_id,
      monthly_salary,
      weekly_holiday_isodow,
      attendance_required,

      late_deduction_applicable,
      overtime_applicable,
      holiday_extra_applicable,
      grace_offset_against_ot,
      exception_reason,

      piece_advance_percent,
      piece_advance_floor,

      salaried_advance_limit_type,
      salaried_advance_limit_value,

      advance_cycle,
      settlement_cycle,
      salary_advance_day,
      salary_due_day,
      claim_debit_timing,

      effective_from,
      effective_to,
      status,
      data_mode,
      configured_at,
      configured_by,
      reason
    )
    values(
      p_worker_id,
      v_category,
      p_shift_id,
      coalesce(p_monthly_salary,0),
      1,
      v_category='SALARIED',

      p_late_deduction_applicable,
      p_overtime_applicable,
      p_holiday_extra_applicable,
      p_grace_offset_against_ot,
      nullif(trim(p_exception_reason),''),

      40,
      2000,

      v_limit_type,
      p_salaried_advance_limit_value,

      case when v_category='PIECE_RATE'
        then 'WEEKLY' else 'MONTHLY_DAY_20'
      end,
      case when v_category='PIECE_RATE'
        then 'FORTNIGHTLY' else 'MONTHLY'
      end,
      case when v_category='SALARIED' then 20 else null end,
      case when v_category='SALARIED' then 7 else null end,
      'SETTLEMENT_ONLY',

      p_effective_from,
      p_effective_to,
      'ACTIVE',
      v_mode,
      now(),
      auth.uid(),
      p_reason
    )
    returning * into v_saved;
  end if;

  insert into public.rr_worker_payroll_profile_events_v777_2(
    worker_id,
    profile_id,
    event_type,
    old_snapshot,
    new_snapshot,
    actor_auth_user_id,
    actor_name,
    reason
  )
  values(
    p_worker_id,
    v_saved.profile_id,
    'PAYROLL_PROFILE_UI_SAVE',
    v_old_snapshot,
    to_jsonb(v_saved),
    auth.uid(),
    v_actor.full_name,
    p_reason
  );

  return jsonb_build_object(
    'ok',true,
    'version','V777_3_PAYROLL_PROFILE_UI_BRIDGE',
    'worker_id',p_worker_id,
    'worker_name',v_worker.worker_name,
    'profile_id',v_saved.profile_id,
    'worker_category',v_saved.worker_category,
    'attendance_required',v_saved.attendance_required,
    'advance_cycle',v_saved.advance_cycle,
    'settlement_cycle',v_saved.settlement_cycle,
    'effective_from',v_saved.effective_from,
    'effective_to',v_saved.effective_to,
    'data_mode',v_saved.data_mode
  );
end $$;

grant execute on function public.rr_set_worker_payroll_profile_v777_3(
  uuid,text,numeric,uuid,boolean,boolean,boolean,boolean,
  text,text,numeric,date,date,text,text
) to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V777_3_PAYROLL_PROFILE_UI_BRIDGE',
  'shift_view',to_regclass('public.rr_shift_options_v777_3') is not null,
  'payroll_board',to_regclass('public.rr_worker_payroll_board_v777_3') is not null,
  'save_rpc',to_regprocedure(
    'public.rr_set_worker_payroll_profile_v777_3(uuid,text,numeric,uuid,boolean,boolean,boolean,boolean,text,text,numeric,date,date,text,text)'
  ) is not null,
  'worker_categories',jsonb_build_array('PIECE_RATE','SALARIED'),
  'existing_worker_ledger_modified',false
) as rr_upm_v777_3_result;
