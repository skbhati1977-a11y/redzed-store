with printing as (
  select * from public.rr_upm_worker_list_v8_3('PRINTING')
), wrong_primary as (
  select p.*
  from printing p
  where public.rr_upm_canonical_department_v762(p.department_code)<>'PRINTING'
), function_check as (
  select lower(pg_get_functiondef('public.rr_upm_worker_list_v8_3(text)'::regprocedure)) body
)
select jsonb_build_object(
  'result',case
    when exists(select 1 from wrong_primary) then 'FAIL'
    when (select body like '%rr_worker_department_map_v1%' from function_check) then 'FAIL'
    else 'PASS'
  end,
  'version','V797.3',
  'primary_department_only',not (select body like '%rr_worker_department_map_v1%' from function_check),
  'wrong_department_workers',coalesce((select jsonb_agg(to_jsonb(w)) from wrong_primary w),'[]'::jsonb),
  'printing_workers',coalesce((select jsonb_agg(jsonb_build_object(
    'worker_id',p.worker_id,
    'worker_code',p.worker_code,
    'worker_name',p.worker_name,
    'department_code',p.department_code
  ) order by p.worker_name) from printing p),'[]'::jsonb),
  'expected_printing_names','Sanju and Chotu'
) as verification;
