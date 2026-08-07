begin;

-- REAL FACTORY V797.3
-- Assignment selectors must use the worker's canonical PRIMARY department only.
-- Additional skill mappings remain stored for directory/history purposes, but
-- they must not place an FLD worker in the PRINTING assignment dropdown.
create or replace function public.rr_upm_worker_list_v8_3(
  p_department_code text default null
)
returns table(
  worker_id uuid,
  worker_code text,
  worker_name text,
  department_code text,
  role_code text,
  is_active boolean,
  access_status text,
  source text,
  linked_auth_user_id uuid
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with requested as (
    select public.rr_upm_canonical_department_v762(p_department_code) as department_code
  )
  select
    u.worker_id,
    u.worker_code,
    u.worker_name,
    public.rr_upm_canonical_department_v762(u.department_code) as department_code,
    u.role_code,
    u.is_active,
    u.access_status,
    u.source,
    u.linked_auth_user_id
  from public.rr_worker_directory_unified_v1 u
  cross join requested r
  where coalesce(u.is_active,false)
    and upper(coalesce(u.access_status,'ACTIVE'))='ACTIVE'
    and (
      r.department_code is null
      or public.rr_upm_canonical_department_v762(u.department_code)=r.department_code
    )
  order by u.worker_name,u.worker_code
$function$;

grant execute on function public.rr_upm_worker_list_v8_3(text) to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V797.3',
  'worker_filter','PRIMARY_DEPARTMENT_ONLY',
  'printing_workers',coalesce((
    select jsonb_agg(jsonb_build_object(
      'worker_id',w.worker_id,
      'worker_code',w.worker_code,
      'worker_name',w.worker_name,
      'department_code',w.department_code
    ) order by w.worker_name)
    from public.rr_upm_worker_list_v8_3('PRINTING') w
  ),'[]'::jsonb),
  'additional_skills_ignored_for_assignment',true,
  'salary_category_not_used',true
) as result;
