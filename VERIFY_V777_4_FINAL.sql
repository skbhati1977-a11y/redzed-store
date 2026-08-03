
select jsonb_build_object(
  'final_setter_rpc',
    to_regprocedure(
      'public.rr_set_worker_leadership_v777_4_final(uuid,text,jsonb,text,text,numeric,text,numeric,text,numeric,date,date,text,text)'
    ) is not null,
  'final_board_view',
    to_regclass('public.rr_worker_leadership_board_v777_4') is not null,
  'sale_basis_column',
    exists(
      select 1 from information_schema.columns
      where table_schema='public'
        and table_name='rr_worker_leadership_profile_v776'
        and column_name='sale_incentive_basis'
    ),
  'sale_rate_column',
    exists(
      select 1 from information_schema.columns
      where table_schema='public'
        and table_name='rr_worker_leadership_profile_v776'
        and column_name='sale_incentive_rate'
    )
) as rr_upm_v777_4_final_verify;
