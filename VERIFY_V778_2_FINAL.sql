
select jsonb_build_object(
  'regular_sessions',
    to_regclass('public.rr_regular_attendance_sessions_v778_2') is not null,
  'outside_checkout_violations',
    to_regclass('public.rr_attendance_checkout_violations_v778_2') is not null,
  'ot_sessions',
    to_regclass('public.rr_ot_work_sessions_v778_2') is not null,
  'video_evidence',
    to_regclass('public.rr_attendance_video_evidence_v778_2') is not null,
  'leave_requests',
    to_regclass('public.rr_worker_leave_requests_v778_2') is not null,
  'reactivation_requests',
    to_regclass('public.rr_worker_reactivation_requests_v778_2') is not null,
  'reminder_state',
    to_regclass('public.rr_attendance_reminder_state_v778_2') is not null,
  'daily_minutes',
    to_regclass('public.rr_attendance_daily_minutes_v778_2') is not null,

  'regular_checkin_rpc',
    to_regprocedure(
      'public.rr_regular_checkin_v778_2(uuid,numeric,numeric,numeric,text,text)'
    ) is not null,

  'regular_checkout_rpc',
    to_regprocedure(
      'public.rr_regular_checkout_v778_2(uuid,numeric,numeric,numeric,text,text)'
    ) is not null,

  'video_rpc',
    to_regprocedure(
      'public.rr_register_attendance_video_v778_2(uuid,text,integer,text,text,text,numeric,numeric,numeric,text,text,text)'
    ) is not null,

  'ot_checkin_rpc',
    to_regprocedure(
      'public.rr_ot_checkin_v778_2(uuid,uuid,boolean,text)'
    ) is not null,

  'ot_checkout_rpc',
    to_regprocedure(
      'public.rr_ot_checkout_v778_2(uuid,uuid,text)'
    ) is not null,

  'leave_request_rpc',
    to_regprocedure(
      'public.rr_request_leave_v778_2(uuid,date,date,text,text,text)'
    ) is not null,

  'leave_decision_rpc',
    to_regprocedure(
      'public.rr_decide_leave_v778_2(uuid,text,text)'
    ) is not null,

  'day_calculation_rpc',
    to_regprocedure(
      'public.rr_calculate_attendance_day_v778_2(uuid,date,text)'
    ) is not null,

  'salary_formula_rpc',
    to_regprocedure(
      'public.rr_calculate_monthly_salary_v778_2(numeric,integer,integer,integer,integer,integer,integer,numeric,numeric)'
    ) is not null,

  'live_board',
    to_regclass('public.rr_attendance_live_board_v778_2') is not null,
  'reminder_board',
    to_regclass('public.rr_attendance_reminders_due_v778_2') is not null,
  'leave_board',
    to_regclass('public.rr_leave_approval_board_v778_2') is not null
) as rr_upm_v778_2_final_verify;

select public.rr_calculate_monthly_salary_v778_2(
  30000,
  15600,
  30,
  120,
  180,
  45,
  25,
  700,
  2000
) as salary_formula_example;
