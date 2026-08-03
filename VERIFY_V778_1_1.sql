
select jsonb_build_object(
  'premise_save_rpc',
    to_regprocedure(
      'public.rr_save_attendance_premise_v778_1_1(uuid,text,text,text,numeric,numeric,numeric,boolean,boolean,text,date,date)'
    ) is not null,
  'worker_premise_rpc',
    to_regprocedure(
      'public.rr_set_worker_attendance_premises_v778_1_1(uuid,text,jsonb,date,date,text)'
    ) is not null,
  'match_rpc',
    to_regprocedure(
      'public.rr_match_attendance_premise_v778_1(uuid,numeric,numeric,date,text)'
    ) is not null,
  'board_view',
    to_regclass(
      'public.rr_worker_attendance_premises_board_v778_1_1'
    ) is not null,
  'premise_access_mode_column',
    exists(
      select 1
      from information_schema.columns
      where table_schema='public'
        and table_name='rr_worker_attendance_policy_v778_1'
        and column_name='premise_access_mode'
    )
) as rr_upm_v778_1_1_verify;

select *
from public.rr_attendance_premises_board_v778_1
order by premise_name;

select
  worker_name,
  premise_access_mode,
  selected_premises,
  data_mode
from public.rr_worker_attendance_premises_board_v778_1_1
order by worker_name;
