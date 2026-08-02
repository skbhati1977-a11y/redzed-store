
select jsonb_build_object(
  'shift_view',
    to_regclass('public.rr_shift_options_v777_3') is not null,
  'payroll_board',
    to_regclass('public.rr_worker_payroll_board_v777_3') is not null,
  'save_rpc',
    to_regprocedure(
      'public.rr_set_worker_payroll_profile_v777_3(uuid,text,numeric,uuid,boolean,boolean,boolean,boolean,text,text,numeric,date,date,text,text)'
    ) is not null
) as rr_upm_v777_3_verify;

select *
from public.rr_shift_options_v777_3
order by shift_name;

select
  worker_name,
  worker_category,
  monthly_salary,
  shift_name,
  late_deduction_applicable,
  overtime_applicable,
  holiday_extra_applicable,
  grace_offset_against_ot,
  salaried_advance_limit_type,
  salaried_advance_limit_value,
  effective_from,
  effective_to,
  data_mode
from public.rr_worker_payroll_board_v777_3
order by worker_name,data_mode;
