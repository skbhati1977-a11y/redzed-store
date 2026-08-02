-- V776.7 VERIFY

select jsonb_build_object(
  'normalizer_rpc',
    to_regprocedure(
      'public.rr_normalize_worker_name_v776_7(text)'
    ) is not null,
  'guard_trigger',
    exists(
      select 1
      from pg_trigger
      where tgname='rr_worker_duplicate_name_guard_v776_7'
        and not tgisinternal
    ),
  'worker_table',
    to_regclass('public.rr_worker_directory_v1') is not null,
  'unified_view',
    to_regclass('public.rr_worker_directory_unified_v1') is not null
) as rr_upm_v776_7_verify;

-- Existing duplicates audit only; this query changes nothing.
select
  lower(trim(department_code)) as department_code,
  public.rr_normalize_worker_name_v776_7(worker_name) as normalized_name,
  count(*) as worker_count,
  string_agg(
    worker_name||' · '||coalesce(worker_code,worker_id::text),
    ' | '
    order by worker_name
  ) as existing_workers
from public.rr_worker_directory_unified_v1
group by
  lower(trim(department_code)),
  public.rr_normalize_worker_name_v776_7(worker_name)
having count(*)>1
order by department_code,normalized_name;
