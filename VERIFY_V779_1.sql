
select jsonb_build_object(
  'incentive_table',
    to_regclass('public.rr_payroll_incentives_v779_1') is not null,

  'monthly_payroll_table',
    to_regclass('public.rr_monthly_payroll_v779_1') is not null,

  'source_application_table',
    to_regclass('public.rr_payroll_source_applications_v779_1') is not null,

  'event_audit_table',
    to_regclass('public.rr_payroll_events_v779_1') is not null,

  'calculator_rpc',
    to_regprocedure(
      'public.rr_calculate_monthly_salary_v779_1(numeric,integer,integer,numeric,numeric)'
    ) is not null,

  'save_incentive_rpc',
    to_regprocedure(
      'public.rr_save_payroll_incentive_v779_1(uuid,date,text,numeric,text,text,text,text)'
    ) is not null,

  'approve_incentive_rpc',
    to_regprocedure(
      'public.rr_decide_payroll_incentive_v779_1(uuid,text,text)'
    ) is not null,

  'generate_payroll_rpc',
    to_regprocedure(
      'public.rr_generate_worker_monthly_payroll_v779_1(uuid,date,text,text)'
    ) is not null,

  'self_service_rpc',
    to_regprocedure(
      'public.rr_get_monthly_payroll_v779_1(uuid,date,text)'
    ) is not null,

  'details_rpc',
    to_regprocedure(
      'public.rr_get_payroll_details_v779_1(uuid)'
    ) is not null,

  'board_view',
    to_regclass('public.rr_monthly_payroll_board_v779_1') is not null

) as rr_upm_v779_1_verify;

select public.rr_calculate_monthly_salary_v779_1(
  18000,
  255,
  2415,
  2500,
  750
) as calculator_test;
