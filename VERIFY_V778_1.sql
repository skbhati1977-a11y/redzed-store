
select jsonb_build_object(
  'premises_table',
    to_regclass('public.rr_attendance_premises_v778_1') is not null,
  'policy_table',
    to_regclass('public.rr_worker_attendance_policy_v778_1') is not null,
  'worker_premises_table',
    to_regclass('public.rr_worker_attendance_premises_v778_1') is not null,
  'field_sessions_table',
    to_regclass('public.rr_field_attendance_sessions_v778_1') is not null,
  'field_events_table',
    to_regclass('public.rr_field_business_events_v778_1') is not null,
  'geofence_audit_table',
    to_regclass('public.rr_attendance_geofence_audit_v778_1') is not null,
  'distance_rpc',
    to_regprocedure(
      'public.rr_distance_meters_v778_1(numeric,numeric,numeric,numeric)'
    ) is not null,
  'match_rpc',
    to_regprocedure(
      'public.rr_match_attendance_premise_v778_1(uuid,numeric,numeric,date,text)'
    ) is not null,
  'policy_rpc',
    to_regprocedure(
      'public.rr_set_worker_attendance_policy_v778_1(uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,integer,numeric,date,date,text,text)'
    ) is not null,
  'premises_board',
    to_regclass('public.rr_attendance_premises_board_v778_1') is not null,
  'policy_board',
    to_regclass('public.rr_worker_attendance_policy_board_v778_1') is not null
) as rr_upm_v778_1_verify;

select
  premise_code,
  premise_name,
  latitude,
  longitude,
  radius_meters,
  data_mode
from public.rr_attendance_premises_board_v778_1
order by premise_code;

select round(
  public.rr_distance_meters_v778_1(
    28.6628890,
    77.2590560,
    28.6660260,
    77.2566850
  ),
  2
) as location_1_to_2_distance_meters;
