-- REDZED UPM V742
-- Department colour aggregation + partial submitted visibility.
-- Run AFTER successful V741 installation.

begin;

create or replace function public.rr_upm_department_status_v741(p_canonical_lot_id text)
returns table(
  department_code text,department_name text,status_colour text,
  active_colour_codes text[],completed_colour_codes text[],display_colour_codes text[],
  active_count integer,completed_count integer,total_colours integer,display_label text
) language sql stable security definer set search_path=public as $$
with allc as (
  select
    coalesce(array_agg(distinct upper(q.colour_code) order by upper(q.colour_code)),array[]::text[]) as all_codes,
    count(distinct upper(q.colour_code))::int as total
  from public.rr_upm_colour_queue_v741 q
  where q.canonical_lot_id=p_canonical_lot_id
), openq as (
  select exists(
    select 1 from public.rr_upm_colour_queue_v741 q
    where q.canonical_lot_id=p_canonical_lot_id and q.queue_state='OPEN'
  ) as has_open
), deps as (
  select d.department_code,d.department_name
  from public.rr_upm_departments d
  where d.is_active
    and coalesce(d.colour_assignment_enabled,true)
    and coalesce(d.worker_assignment_enabled,true)
    and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION'
    and not coalesce(d.is_start_department,false)
    and not exists(
      select 1 from public.rr_upm_departments ch
      where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code)
    )
), active_src as (
  select upper(a.department_code) as department_code,upper(a.colour_code) as colour_code
  from public.rr_upm_work_assignments_v8 a
  where a.canonical_lot_id=p_canonical_lot_id
    and a.status in ('ASSIGNED','IN_PROGRESS')
  group by upper(a.department_code),upper(a.colour_code)
), completed_src as (
  select upper(a.department_code) as department_code,upper(a.colour_code) as colour_code
  from public.rr_upm_work_assignments_v8 a
  where a.canonical_lot_id=p_canonical_lot_id and a.status='COMPLETED'
  union
  select upper(h.department_code),upper(h.colour_code)
  from public.rr_upm_dynamic_submit_history_v741 h
  where h.canonical_lot_id=p_canonical_lot_id
), x as (
  select d.department_code,d.department_name,
    coalesce((
      select array_agg(a.colour_code order by a.colour_code)
      from active_src a where a.department_code=upper(d.department_code)
    ),array[]::text[]) as active_codes,
    coalesce((
      select array_agg(c.colour_code order by c.colour_code)
      from completed_src c where c.department_code=upper(d.department_code)
    ),array[]::text[]) as completed_codes
  from deps d
), s as (
  select x.*,
    array(
      select distinct z
      from unnest(x.active_codes||x.completed_codes) z
      order by z
    ) as display_codes,
    cardinality(x.active_codes)::int as ac,
    cardinality(x.completed_codes)::int as cc,
    (select total from allc) as tc,
    (select has_open from openq) as has_open
  from x
)
select
  s.department_code,
  s.department_name,
  case
    when s.cc=s.tc and s.tc>0 and s.ac=0 then 'RED'
    when s.ac=s.tc and s.tc>0 then 'GREEN'
    when cardinality(s.display_codes)>0 then 'ORANGE'
    else 'BASE'
  end as status_colour,
  s.active_codes,
  s.completed_codes,
  s.display_codes,
  s.ac,
  s.cc,
  s.tc,
  case
    when s.cc=s.tc and s.tc>0 and s.ac=0
      then s.department_name||' · '||s.cc||'/'||s.tc||' SUBMITTED'
    when s.ac=s.tc and s.tc>0
      then s.department_name||' · ALL RUNNING '||s.ac||'/'||s.tc
    when cardinality(s.display_codes)>0
      then s.department_name||' · '||array_to_string(s.display_codes,' ')
    else s.department_name
  end as display_label
from s
where cardinality(s.display_codes)>0 or s.has_open
order by s.department_name;
$$;

grant execute on function public.rr_upm_department_status_v741(text) to authenticated;

create or replace function public.rr_upm_universal_form_v741(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  base jsonb;
  outrows jsonb:='[]'::jsonb;
  r jsonb;
  a record;
  c record;
  q record;
  eligible boolean;
  completed_here boolean;
  statuses jsonb;
begin
  perform public.rr_upm_sync_colour_queue_v741(p_canonical_lot_id);
  base:=public.rr_upm_universal_form_v740(p_canonical_lot_id,p_department_code);

  select exists(
    select 1 from public.rr_upm_departments d
    where upper(d.department_code)=upper(p_department_code)
      and d.is_active
      and coalesce(d.colour_assignment_enabled,true)
      and coalesce(d.worker_assignment_enabled,true)
      and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION'
      and not coalesce(d.is_start_department,false)
      and not exists(
        select 1 from public.rr_upm_departments ch
        where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code)
      )
  ) into eligible;

  for r in select value from jsonb_array_elements(coalesce(base->'rows','[]'::jsonb)) loop
    q:=null;
    a:=null;
    c:=null;

    select * into q
    from public.rr_upm_colour_queue_v741
    where canonical_lot_id=p_canonical_lot_id
      and upper(colour_code)=upper(r->>'colour_code');

    select * into a
    from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id
      and upper(x.colour_code)=upper(r->>'colour_code')
      and x.status in('ASSIGNED','IN_PROGRESS')
    order by x.assigned_at desc limit 1;

    select * into c
    from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id
      and upper(x.department_code)=upper(p_department_code)
      and upper(x.colour_code)=upper(r->>'colour_code')
      and x.status='COMPLETED'
    order by coalesce(x.completed_at,x.updated_at,x.assigned_at) desc limit 1;

    select (
      c.id is not null or exists(
        select 1 from public.rr_upm_dynamic_submit_history_v741 h
        where h.canonical_lot_id=p_canonical_lot_id
          and upper(h.department_code)=upper(p_department_code)
          and upper(h.colour_code)=upper(r->>'colour_code')
      )
    ) into completed_here;

    if coalesce(q.queue_state,'OPEN')='OPEN'
       or (a.id is not null and upper(a.department_code)=upper(p_department_code))
       or completed_here then
      r:=r||jsonb_build_object(
        'is_locked',(a.id is not null and upper(a.department_code)=upper(p_department_code)),
        'is_completed_here',completed_here and not (a.id is not null and upper(a.department_code)=upper(p_department_code)),
        'can_assign',(coalesce(q.queue_state,'OPEN')='OPEN' and eligible and not completed_here),
        'assignment_id',case
          when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.id
          when c.id is not null then c.id else null end,
        'worker_id',case
          when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_id
          when c.id is not null then c.worker_id else null end,
        'worker_name',case
          when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_name_snapshot
          when c.id is not null then c.worker_name_snapshot else null end,
        'worker_code',case
          when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_code
          when c.id is not null then c.worker_code else null end,
        'assigned_qty',case
          when a.id is not null and upper(a.department_code)=upper(p_department_code) then (r->>'main_qty')::numeric
          when completed_here then (r->>'main_qty')::numeric else 0 end,
        'assignment_status',case
          when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.status
          when completed_here then 'COMPLETED' else null end,
        'status',case
          when a.id is not null and upper(a.department_code)=upper(p_department_code) then 'ASSIGNED / IN PROGRESS'
          when completed_here then 'SUBMITTED HERE'
          else 'OPEN FOR ASSIGNMENT' end,
        'queue_state',coalesce(q.queue_state,'OPEN'),
        'owner_department_code',q.owner_department_code
      );
      outrows:=outrows||jsonb_build_array(r);
    end if;
  end loop;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.department_name),'[]'::jsonb)
  into statuses
  from public.rr_upm_department_status_v741(p_canonical_lot_id) s;

  base:=jsonb_set(base,'{rows}',outrows,true);
  base:=base||jsonb_build_object(
    'department_statuses',statuses,
    'dynamic_queue','FIRST_ASSIGNMENT_WINS',
    'route_locked_to',null,
    'next_department_code',null,
    'versions',coalesce(base->'versions','{}'::jsonb)||jsonb_build_object('dynamic_queue','V742_COLOUR_STATUS')
  );
  return base;
end;$$;

grant execute on function public.rr_upm_universal_form_v741(text,text) to authenticated;


-- V743: First-window immutable identity + live department/colour status.
create or replace function public.rr_upm_board_lot_status_v743(p_canonical_lot_id text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  ident public.rr_upm_lot_identity_lock_v740;
  statuses jsonb;
begin
  ident := public.rr_upm_resolve_identity_v740(p_canonical_lot_id,false,null);

  with allc as (
    select count(distinct upper(q.colour_code))::int as total
    from public.rr_upm_colour_queue_v741 q
    where q.canonical_lot_id=p_canonical_lot_id
  ), deps as (
    select d.department_code,d.department_name
    from public.rr_upm_departments d
    where d.is_active
      and coalesce(d.colour_assignment_enabled,true)
      and coalesce(d.worker_assignment_enabled,true)
      and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION'
      and not coalesce(d.is_start_department,false)
      and not exists(
        select 1 from public.rr_upm_departments ch
        where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code)
      )
  ), raw_active as (
    select upper(a.department_code) department_code,
           upper(a.colour_code) colour_code,
           upper(a.status) assignment_status
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.status) in ('ASSIGNED','IN_PROGRESS')
  ), active as (
    select department_code,colour_code,
           case when bool_or(assignment_status='IN_PROGRESS') then 'IN_PROGRESS' else 'ASSIGNED' end assignment_status
    from raw_active group by department_code,colour_code
  ), completed_raw as (
    select upper(a.department_code) department_code,upper(a.colour_code) colour_code
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id and upper(a.status)='COMPLETED'
    union
    select upper(h.department_code),upper(h.colour_code)
    from public.rr_upm_dynamic_submit_history_v741 h
    where h.canonical_lot_id=p_canonical_lot_id
  ), x as (
    select d.department_code,d.department_name,
      coalesce((select array_agg(a.colour_code order by a.colour_code) from active a where a.department_code=upper(d.department_code) and a.assignment_status='ASSIGNED'),array[]::text[]) assigned_codes,
      coalesce((select array_agg(a.colour_code order by a.colour_code) from active a where a.department_code=upper(d.department_code) and a.assignment_status='IN_PROGRESS'),array[]::text[]) running_codes,
      coalesce((select array_agg(c.colour_code order by c.colour_code) from completed_raw c where c.department_code=upper(d.department_code) and not exists(select 1 from active a where a.department_code=c.department_code and a.colour_code=c.colour_code)),array[]::text[]) submitted_codes,
      (select total from allc) total_colours
    from deps d
  ), y as (
    select x.*,
      cardinality(x.assigned_codes) assigned_count,
      cardinality(x.running_codes) running_count,
      cardinality(x.submitted_codes) submitted_count,
      cardinality(x.assigned_codes||x.running_codes) active_count
    from x
  ), visible as (
    select y.*,
      case
        when submitted_count=total_colours and total_colours>0 and active_count=0 then 'RED'
        when active_count=total_colours and total_colours>0 then 'GREEN'
        when active_count+submitted_count>0 then 'ORANGE'
        else 'BASE'
      end status_colour,
      case
        when submitted_count=total_colours and total_colours>0 and active_count=0 then 'ALL COLOURS SUBMITTED'
        when running_count=total_colours and total_colours>0 then 'ALL COLOURS RUNNING'
        when assigned_count=total_colours and total_colours>0 then 'ALL COLOURS ASSIGNED'
        when active_count=total_colours and total_colours>0 then
          trim(concat(
            case when cardinality(running_codes)>0 then 'RUNNING '||array_to_string(running_codes,' ') end,
            case when cardinality(assigned_codes)>0 then ' · ASSIGNED '||array_to_string(assigned_codes,' ') end
          ))
        else trim(concat(
          case when cardinality(running_codes)>0 then 'RUNNING '||array_to_string(running_codes,' ') end,
          case when cardinality(assigned_codes)>0 then case when cardinality(running_codes)>0 then ' · ' else '' end||'ASSIGNED '||array_to_string(assigned_codes,' ') end,
          case when cardinality(submitted_codes)>0 then case when cardinality(running_codes)+cardinality(assigned_codes)>0 then ' · ' else '' end||'SUBMITTED '||array_to_string(submitted_codes,' ') end
        ))
      end board_detail
    from y
    where active_count+submitted_count>0
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'department_code',v.department_code,
    'department_name',v.department_name,
    'status_colour',v.status_colour,
    'assigned_codes',v.assigned_codes,
    'running_codes',v.running_codes,
    'submitted_codes',v.submitted_codes,
    'total_colours',v.total_colours,
    'board_detail',v.board_detail
  ) order by case v.status_colour when 'GREEN' then 1 when 'ORANGE' then 2 when 'RED' then 3 else 4 end,v.department_name),'[]'::jsonb)
  into statuses
  from visible v;

  return jsonb_build_object(
    'identity',to_jsonb(ident),
    'department_statuses',statuses,
    'version','V743_BOARD_LIVE_LOCKED_IDENTITY'
  );
end;
$$;

grant execute on function public.rr_upm_board_lot_status_v743(text) to authenticated;

commit;
