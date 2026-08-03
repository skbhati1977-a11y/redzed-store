
-- V779.5.1 verification
with target_functions(signature) as (
  values
    ('public.rr_generate_worker_monthly_payroll_safe_v779_4(uuid,date,text,text)'),
    ('public.rr_generate_monthly_payroll_batch_v779_4(date,text,text)'),
    ('public.rr_get_payroll_management_board_v779_4(date,text)'),
    ('public.rr_generate_worker_monthly_payroll_safe_v779_5(uuid,date,text,text)'),
    ('public.rr_generate_worker_monthly_payroll_legacy_v779_5(uuid,date,text,text)'),
    ('public.rr_generate_monthly_payroll_legacy_batch_v779_5(date,text,text)')
),
defs as (
  select
    signature,
    to_regprocedure(signature) as function_oid,
    case
      when to_regprocedure(signature) is null then null
      else pg_get_functiondef(to_regprocedure(signature))
    end as definition
  from target_functions
)
select jsonb_build_object(
  'all_functions_exist',
    bool_and(function_oid is not null),

  'invalid_interval_removed',
    bool_and(
      function_oid is not null
      and position('1 month-1 day' in definition)=0
    ),

  'valid_interval_present',
    bool_and(
      function_oid is not null
      and position('interval ''1 month'' - interval ''1 day''' in definition)>0
    ),

  'functions_checked',
    count(*)
) as rr_upm_v779_5_1_verify
from defs;
