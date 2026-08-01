begin;

create or replace function public.rr_upm_completed_departments_v764(
  p_canonical_lot_id text
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with completed as (
    select
      upper(a.colour_code) as colour_code,
      public.rr_upm_canonical_department_v762(a.department_code)
        as department_code,
      max(a.completed_at) as completed_at
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.status)='COMPLETED'
    group by
      upper(a.colour_code),
      public.rr_upm_canonical_department_v762(a.department_code)
  ),
  colour_totals as (
    select count(distinct upper(q.colour_code))::int as total_colours
    from public.rr_upm_colour_queue_v741 q
    where q.canonical_lot_id=p_canonical_lot_id
  ),
  department_totals as (
    select
      c.department_code,
      count(distinct c.colour_code)::int as completed_colours
    from completed c
    group by c.department_code
  )
  select jsonb_build_object(
    'ok',true,
    'version','V764_COMPLETED_DEPARTMENT_HIDE',
    'canonical_lot_id',p_canonical_lot_id,
    'total_colours',coalesce(
      (select total_colours from colour_totals),
      0
    ),
    'completed_pairs',coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'colour_code',c.colour_code,
            'department_code',c.department_code,
            'completed_at',c.completed_at
          )
          order by c.colour_code,c.department_code
        )
        from completed c
      ),
      '[]'::jsonb
    ),
    'fully_completed_departments',coalesce(
      (
        select jsonb_agg(
          d.department_code
          order by d.department_code
        )
        from department_totals d
        cross join colour_totals t
        where t.total_colours>0
          and d.completed_colours>=t.total_colours
      ),
      '[]'::jsonb
    )
  )
$$;

grant execute on function public.rr_upm_completed_departments_v764(text)
to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V764_COMPLETED_DEPARTMENT_HIDE',
  'single_rule',
    'Hide departments already completed by selected Colour.',
  'bulk_rule',
    'Hide departments completed by every Colour in the Lot.'
) as rr_upm_v764_result;
