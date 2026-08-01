begin;

-- REDZED UPM V755
-- HARD RULE: one Colour = one current department ownership row.
-- Board and Check-in consume this same RPC. Submitted history is not current ownership.

create or replace function public.rr_upm_v755_valid_department(p_code text)
returns text
language sql
immutable
as $$
  select case
    when public.rr_upm_norm_department_v754(p_code) in (
      '', 'OPEN', 'OPEN_NEXT', 'OPEN NEXT',
      'OPEN FOR NEXT PROCESS', 'OPEN_NEXT_PROCESS',
      'OPEN FOR ASSIGNMENT', 'PENDING'
    ) then null
    else public.rr_upm_norm_department_v754(p_code)
  end
$$;

create or replace function public.rr_upm_colour_owner_v755(
  p_canonical_lot_id text,
  p_colour_id uuid,
  p_colour_code text
)
returns table(
  department_code text,
  department_name text,
  ownership_status text,
  assignment_id uuid,
  worker_id uuid,
  worker_name text,
  source_name text
)
language sql
stable
security definer
set search_path=public
as $$
with active_assignment as (
  select
    public.rr_upm_v755_valid_department(a.department_code) department_code,
    case when upper(a.status)='IN_PROGRESS' then 'RUNNING' else 'ASSIGNED' end ownership_status,
    a.id assignment_id,
    a.worker_id,
    coalesce(nullif(a.worker_name_snapshot,''),w.worker_name) worker_name,
    'ACTIVE_ASSIGNMENT'::text source_name,
    1 priority
  from public.rr_upm_work_assignments_v8 a
  left join public.rr_worker_directory_unified_v1 w on w.worker_id=a.worker_id
  where a.canonical_lot_id=p_canonical_lot_id
    and upper(a.status) in('ASSIGNED','IN_PROGRESS')
    and (
      (p_colour_id is not null and a.colour_id=p_colour_id)
      or upper(a.colour_code)=upper(p_colour_code)
    )
    and public.rr_upm_v755_valid_department(a.department_code) is not null
  order by a.assigned_at desc
  limit 1
),
colour_lock as (
  select
    public.rr_upm_v755_valid_department(l.locked_department_code) department_code,
    'OPEN'::text ownership_status,
    null::uuid assignment_id,
    null::uuid worker_id,
    null::text worker_name,
    'COLOUR_DEPARTMENT_LOCK'::text source_name,
    2 priority
  from public.rr_upm_colour_department_lock_v754 l
  where l.canonical_lot_id=p_canonical_lot_id
    and upper(l.colour_code)=upper(p_colour_code)
    and upper(l.status)='ACTIVE'
    and public.rr_upm_v755_valid_department(l.locked_department_code) is not null
  order by l.locked_at desc
  limit 1
),
completed_route as (
  select
    public.rr_upm_v755_valid_department(r.to_department_code) department_code,
    'OPEN'::text ownership_status,
    null::uuid assignment_id,
    null::uuid worker_id,
    null::text worker_name,
    'LAST_SUBMIT_ROUTE'::text source_name,
    3 priority
  from public.rr_upm_work_assignments_v8 a
  join public.rr_upm_route_lock_v740 r
    on r.canonical_lot_id=a.canonical_lot_id
   and public.rr_upm_norm_department_v754(r.from_department_code)
       =public.rr_upm_norm_department_v754(a.department_code)
  where a.canonical_lot_id=p_canonical_lot_id
    and upper(a.status)='COMPLETED'
    and (
      (p_colour_id is not null and a.colour_id=p_colour_id)
      or upper(a.colour_code)=upper(p_colour_code)
    )
    and public.rr_upm_v755_valid_department(r.to_department_code) is not null
  order by a.completed_at desc nulls last,a.updated_at desc
  limit 1
),
colour_state as (
  select
    public.rr_upm_v755_valid_department(s.current_department_code) department_code,
    'OPEN'::text ownership_status,
    null::uuid assignment_id,
    null::uuid worker_id,
    null::text worker_name,
    'COLOUR_STATE'::text source_name,
    4 priority
  from public.rr_upm_colour_state s
  where s.canonical_lot_id=p_canonical_lot_id
    and (
      (p_colour_id is not null and s.colour_id=p_colour_id)
      or upper(s.colour_code)=upper(p_colour_code)
    )
    and public.rr_upm_v755_valid_department(s.current_department_code) is not null
  order by s.updated_at desc
  limit 1
),
picked as (
  select * from active_assignment
  union all select * from colour_lock
  union all select * from completed_route
  union all select * from colour_state
),
one_row as (
  select *
  from picked
  order by priority
  limit 1
)
select
  o.department_code,
  case
    when o.department_code='STITCHING' then 'Karigar / Stitching'
    when o.department_code='QC' then 'QC'
    else coalesce(
      (select d.department_name
       from public.rr_departments_v1 d
       where upper(d.department_code)=upper(o.department_code)
         and coalesce(d.is_active,false)
       limit 1),
      (select d.department_name
       from public.rr_upm_departments d
       where upper(d.department_code)=upper(o.department_code)
         and coalesce(d.is_active,false)
       limit 1),
      o.department_code
    )
  end department_name,
  o.ownership_status,
  o.assignment_id,
  o.worker_id,
  o.worker_name,
  o.source_name
from one_row o
$$;

grant execute on function public.rr_upm_colour_owner_v755(text,uuid,text)
to authenticated;

create or replace function public.rr_upm_lot_colour_matrix_v755(
  p_canonical_lot_id text default null,
  p_lot_no text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_canonical text:=nullif(trim(p_canonical_lot_id),'');
  v_lot_no text:=upper(trim(coalesce(p_lot_no,'')));
  v_rows jsonb;
begin
  if v_canonical is null then
    select b.canonical_lot_id,b.lot_no
    into v_canonical,v_lot_no
    from public.rr_upm_lot_board_v1 b
    where upper(b.lot_no)=v_lot_no
    order by b.board_updated_at desc nulls last
    limit 1;
  else
    select b.lot_no
    into v_lot_no
    from public.rr_upm_lot_board_v1 b
    where b.canonical_lot_id=v_canonical
    limit 1;
  end if;

  if v_canonical is null then
    raise exception 'Lot not found.';
  end if;

  with colours as (
    select distinct
      q.colour_id,
      upper(q.colour_code) colour_code
    from public.rr_upm_colour_queue_v741 q
    where q.canonical_lot_id=v_canonical
  ),
  matrix as (
    select
      c.colour_id,
      c.colour_code,
      coalesce(o.department_code,'') department_code,
      coalesce(o.department_name,'DEPARTMENT NOT LOCKED') department_name,
      coalesce(o.ownership_status,'LEGACY') ownership_status,
      o.assignment_id,
      o.worker_id,
      o.worker_name,
      coalesce(o.source_name,'NO_CURRENT_OWNER') source_name
    from colours c
    left join lateral public.rr_upm_colour_owner_v755(
      v_canonical,c.colour_id,c.colour_code
    ) o on true
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'colour_id',m.colour_id,
      'colour_code',m.colour_code,
      'colour_name',m.colour_code,
      'department_code',m.department_code,
      'department_name',m.department_name,
      'ownership_status',m.ownership_status,
      'assignment_id',m.assignment_id,
      'worker_id',m.worker_id,
      'worker_name',m.worker_name,
      'source_name',m.source_name
    )
    order by
      coalesce(nullif(regexp_replace(m.colour_code,'\D','','g'),''),'0')::int,
      m.colour_code
  ),'[]'::jsonb)
  into v_rows
  from matrix m;

  return jsonb_build_object(
    'ok',true,
    'version','V755_HARD_COLOUR_OWNERSHIP_MATRIX',
    'canonical_lot_id',v_canonical,
    'lot_no',v_lot_no,
    'colours',v_rows
  );
end;
$$;

grant execute on function public.rr_upm_lot_colour_matrix_v755(text,text)
to authenticated;

-- Repair active locks only where ownership can be resolved from a real route/state.
do $$
declare
  r record;
begin
  for r in
    select
      b.canonical_lot_id,
      b.lot_no,
      q.colour_id,
      upper(q.colour_code) colour_code,
      o.department_code
    from public.rr_upm_lot_board_v1 b
    join public.rr_upm_colour_queue_v741 q
      on q.canonical_lot_id=b.canonical_lot_id
    cross join lateral public.rr_upm_colour_owner_v755(
      b.canonical_lot_id,q.colour_id,q.colour_code
    ) o
    where o.department_code is not null
      and o.ownership_status='OPEN'
      and not exists(
        select 1
        from public.rr_upm_colour_department_lock_v754 l
        where l.canonical_lot_id=b.canonical_lot_id
          and upper(l.colour_code)=upper(q.colour_code)
          and upper(l.status)='ACTIVE'
          and public.rr_upm_v755_valid_department(l.locked_department_code)
              =o.department_code
      )
  loop
    update public.rr_upm_colour_department_lock_v754
    set status='RELEASED',released_at=now(),released_by=auth.uid()
    where canonical_lot_id=r.canonical_lot_id
      and upper(colour_code)=r.colour_code
      and upper(status)='ACTIVE';

    insert into public.rr_upm_colour_department_lock_v754(
      canonical_lot_id,lot_no,colour_id,colour_code,
      locked_department_code,lock_source,locked_by,status
    )
    values(
      r.canonical_lot_id,r.lot_no,r.colour_id,r.colour_code,
      r.department_code,'V755_OWNERSHIP_REPAIR',auth.uid(),'ACTIVE'
    );
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- MERGED V755.1 ALTER JOURNEY MATRIX
-- ---------------------------------------------------------------------------

-- REDZED UPM V755.1
-- Add live Alter Journey data to the same Colour Ownership Matrix RPC.

create or replace function public.rr_upm_lot_colour_matrix_v755(
  p_canonical_lot_id text default null,
  p_lot_no text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_canonical text:=nullif(trim(p_canonical_lot_id),'');
  v_lot_no text:=upper(trim(coalesce(p_lot_no,'')));
  v_rows jsonb;
begin
  if v_canonical is null then
    select b.canonical_lot_id,b.lot_no
    into v_canonical,v_lot_no
    from public.rr_upm_lot_board_v1 b
    where upper(b.lot_no)=v_lot_no
    order by b.board_updated_at desc nulls last
    limit 1;
  else
    select b.lot_no
    into v_lot_no
    from public.rr_upm_lot_board_v1 b
    where b.canonical_lot_id=v_canonical
    limit 1;
  end if;

  if v_canonical is null then
    raise exception 'Lot not found.';
  end if;

  with colours as (
    select distinct
      q.colour_id,
      upper(q.colour_code) colour_code
    from public.rr_upm_colour_queue_v741 q
    where q.canonical_lot_id=v_canonical
  ),
  matrix as (
    select
      c.colour_id,
      c.colour_code,
      coalesce(o.department_code,'') department_code,
      coalesce(o.department_name,'DEPARTMENT NOT LOCKED') department_name,
      coalesce(o.ownership_status,'LEGACY') ownership_status,
      o.assignment_id,
      o.worker_id,
      o.worker_name,
      coalesce(o.source_name,'NO_CURRENT_OWNER') source_name,
      aj.journey_id,
      aj.alter_qty,
      aj.alter_stage,
      aj.stage_label,
      aj.responsible_name,
      aj.responsible_role_short,
      aj.responsible_department_code,
      aj.size_details
    from colours c
    left join lateral public.rr_upm_colour_owner_v755(
      v_canonical,c.colour_id,c.colour_code
    ) o on true
    left join lateral (
      select
        max(j.id) journey_id,
        sum(j.open_qty)::numeric alter_qty,
        max(j.stage) alter_stage,
        case max(j.stage)
          when 'LM_ALTER_PENDING' then 'ALTER PENDING'
          when 'CM_REMAKE_READY' then 'REMAKE READY'
          when 'LM_DELIVERY_PENDING' then 'LINE MAN DELIVERY'
          when 'KARIGAR_REMAKE_PENDING' then 'KARIGAR PENDING'
          else max(j.stage)
        end stage_label,
        max(j.responsible_name) responsible_name,
        max(case
          when upper(j.responsible_role_code)='LINE_MAN' then 'LM'
          when upper(j.responsible_role_code)='CUTTING_MASTER' then 'CM'
          when upper(j.responsible_role_code)='WORKER' then 'WORKER'
          else upper(coalesce(j.responsible_role_code,''))
        end) responsible_role_short,
        max(j.responsible_department_code) responsible_department_code,
        string_agg(
          upper(j.size_code)||' '||trim(to_char(j.open_qty,'FM999999990.##'))||' PCS',
          ' · '
          order by upper(j.size_code)
        ) size_details
      from public.rr_upm_alter_journey_v740 j
      where j.canonical_lot_id=v_canonical
        and upper(j.colour_code)=c.colour_code
        and upper(j.stage) not like 'CLOSED%'
        and coalesce(j.open_qty,0)>0
    ) aj on true
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'colour_id',m.colour_id,
      'colour_code',m.colour_code,
      'colour_name',m.colour_code,
      'department_code',m.department_code,
      'department_name',m.department_name,
      'ownership_status',m.ownership_status,
      'assignment_id',m.assignment_id,
      'worker_id',m.worker_id,
      'worker_name',m.worker_name,
      'source_name',m.source_name,
      'alter_journey',
        case
          when coalesce(m.alter_qty,0)>0 then
            jsonb_build_object(
              'journey_id',m.journey_id,
              'qty',m.alter_qty,
              'stage',m.alter_stage,
              'stage_label',m.stage_label,
              'responsible_name',m.responsible_name,
              'responsible_role_short',m.responsible_role_short,
              'responsible_department_code',m.responsible_department_code,
              'size_details',m.size_details
            )
          else null
        end
    )
    order by
      coalesce(nullif(regexp_replace(m.colour_code,'\D','','g'),''),'0')::int,
      m.colour_code
  ),'[]'::jsonb)
  into v_rows
  from matrix m;

  return jsonb_build_object(
    'ok',true,
    'version','V755_1_ALTER_JOURNEY_MATRIX',
    'canonical_lot_id',v_canonical,
    'lot_no',v_lot_no,
    'colours',v_rows
  );
end;
$$;

grant execute on function public.rr_upm_lot_colour_matrix_v755(text,text)
to authenticated;

commit;
