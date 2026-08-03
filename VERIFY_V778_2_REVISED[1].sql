
select jsonb_build_object(
  'leave_table',to_regclass('public.rr_worker_leave_v778_2') is not null,
  'correction_audit',to_regclass('public.rr_attendance_corrections_v778_2') is not null,
  'policy_rpc',to_regprocedure(
    'public.rr_active_attendance_policy_v778_2(uuid,date,text)'
  ) is not null,
  'payroll_profile_rpc',to_regprocedure(
    'public.rr_active_payroll_profile_v778_2(uuid,date,text)'
  ) is not null,
  'premise_assignment_rpc',to_regprocedure(
    'public.rr_set_worker_attendance_premises_v778_2(uuid,jsonb,date,date,text)'
  ) is not null,
  'factory_event_rpc',to_regprocedure(
    'public.rr_factory_attendance_event_v778_2(uuid,text,timestamptz,numeric,numeric,numeric,text,text,jsonb)'
  ) is not null,
  'leave_request_rpc',to_regprocedure(
    'public.rr_save_worker_leave_v778_2(uuid,date,text,text,integer,text,text)'
  ) is not null,
  'leave_decision_rpc',to_regprocedure(
    'public.rr_decide_worker_leave_v778_2(uuid,text,text)'
  ) is not null,
  'daily_net_minute_rpc',to_regprocedure(
    'public.rr_recalculate_attendance_day_v778_2(uuid,date,text)'
  ) is not null,
  'dhm_formatter_rpc',to_regprocedure(
    'public.rr_minutes_dhm_v778_2(integer)'
  ) is not null,
  'live_board',to_regclass('public.rr_attendance_live_board_v778_2') is not null,
  'net_deduction_column',exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='rr_attendance_day_v777_2'
      and column_name='net_deduction_minutes'
  ),
  'net_extra_column',exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='rr_attendance_day_v777_2'
      and column_name='net_extra_work_minutes'
  ),
  'net_working_column',exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='rr_attendance_day_v777_2'
      and column_name='net_working_minutes'
  )
) as rr_upm_v778_2_revised_verify;

select
  public.rr_minutes_dhm_v778_2(255) as deduction_255_minutes,
  public.rr_minutes_dhm_v778_2(2415) as extra_2415_minutes,
  public.rr_minutes_dhm_v778_2(2535) as extra_2535_minutes;
