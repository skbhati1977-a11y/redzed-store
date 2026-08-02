
select jsonb_build_object(
  'shift_master',to_regclass('public.rr_shift_master_v777_2') is not null,
  'holiday_calendar',to_regclass('public.rr_holiday_calendar_v777_2') is not null,
  'payroll_profile',to_regclass('public.rr_worker_payroll_profile_v777_2') is not null,
  'attendance_events',to_regclass('public.rr_attendance_events_v777_2') is not null,
  'attendance_day',to_regclass('public.rr_attendance_day_v777_2') is not null,
  'piece_presence',to_regclass('public.rr_piece_job_presence_v777_2') is not null,
  'operational_status',to_regclass('public.rr_worker_operational_status_v777_2') is not null,
  'advances',to_regclass('public.rr_worker_advances_v777_2') is not null,
  'settlements',to_regclass('public.rr_worker_settlements_v777_2') is not null,
  'claims',to_regclass('public.rr_worker_claims_v777_2') is not null,
  'analytics_events',to_regclass('public.rr_work_analytics_events_v777_2') is not null,
  'assignment_summary',to_regclass('public.rr_work_assignment_summary_v777_2') is not null,
  'worker_daily_productivity',
    to_regclass('public.rr_worker_daily_productivity_v777_2') is not null,
  'department_daily_productivity',
    to_regclass('public.rr_department_daily_productivity_v777_2') is not null,
  'inactive_scan_rpc',
    to_regprocedure(
      'public.rr_worker_auto_inactive_scan_v777_2(timestamptz,text)'
    ) is not null
) as rr_upm_v777_2_verify;

select
  shift_code,duty_start,duty_end,normal_payable_minutes,
  lunch_start,lunch_end,lunch_is_paid,
  grace_in_minutes,minimum_presence_minutes,
  overtime_multiplier,holiday_multiplier
from public.rr_shift_master_v777_2
where shift_code='GENERAL_10_TO_8';

select public.rr_piece_advance_limit_v777_2(3000)
  as earned_3000_allowed_advance;

select public.rr_piece_advance_limit_v777_2(12000)
  as earned_12000_allowed_advance;
