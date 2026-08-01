begin;

-- REDZED UPM V754
-- QC canonical department + canonical C1/C2... colour identity + complete board open status.

-- ---------------------------------------------------------------------------
-- 1. Canonical department resolver
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_norm_department_v754(p_code text)
returns text
language sql
immutable
as $$
  select case upper(trim(coalesce(p_code,'')))
    when 'CHECKING' then 'QC'
    when 'CHECK' then 'QC'
    when 'QUALITY CHECK' then 'QC'
    when 'QUALITY_CHECK' then 'QC'
    when 'QA' then 'QC'
    when 'KR' then 'STITCHING'
    when 'KAJ' then 'STITCHING'
    when 'KARIGAR' then 'STITCHING'
    when 'KARIGAR / STITCHING' then 'STITCHING'
    when 'KARIGAR/STITCHING' then 'STITCHING'
    when 'STITCH' then 'STITCHING'
    when 'STITCHING' then 'STITCHING'
    else upper(trim(coalesce(p_code,'')))
  end
$$;

-- QC must already exist in one of the two canonical department sources.
-- rr_departments is intentionally NOT used because its schema has no department_code.
do $$
declare
  v_qc_active boolean := false;
begin
  if to_regclass('public.rr_departments_v1') is not null then
    select exists(
      select 1
      from public.rr_departments_v1 d
      where upper(trim(coalesce(d.department_code,'')))='QC'
        and coalesce(d.is_active,false)
    )
    into v_qc_active;
  end if;

  if not v_qc_active
     and to_regclass('public.rr_upm_departments') is not null then
    select exists(
      select 1
      from public.rr_upm_departments d
      where upper(trim(coalesce(d.department_code,'')))='QC'
        and coalesce(d.is_active,false)
    )
    into v_qc_active;
  end if;

  if not v_qc_active then
    raise exception
      'QC department is not active in rr_departments_v1 or rr_upm_departments.';
  end if;
end
$$;

-- STITCHING is the canonical department for KR/KAJ/KARIGAR aliases.
do $$
declare
  v_stitching_active boolean := false;
begin
  if to_regclass('public.rr_departments_v1') is not null then
    select exists(
      select 1
      from public.rr_departments_v1 d
      where upper(trim(coalesce(d.department_code,'')))='STITCHING'
        and coalesce(d.is_active,false)
    )
    into v_stitching_active;
  end if;

  if not v_stitching_active
     and to_regclass('public.rr_upm_departments') is not null then
    select exists(
      select 1
      from public.rr_upm_departments d
      where upper(trim(coalesce(d.department_code,'')))='STITCHING'
        and coalesce(d.is_active,false)
    )
    into v_stitching_active;
  end if;

  if not v_stitching_active then
    raise exception
      'Canonical STITCHING department is not active in rr_departments_v1 or rr_upm_departments.';
  end if;
end
$$;

-- If an alias and STITCHING active assignment somehow exist for the same Colour,
-- keep the canonical STITCHING assignment and close only the duplicate alias row.
update public.rr_upm_work_assignments_v8 a
set status='COMPLETED',
    completed_at=coalesce(a.completed_at,now()),
    updated_at=now(),
    remarks=concat_ws(' · ',nullif(a.remarks,''),'Alias department merged into STITCHING')
where upper(a.department_code) in(
    'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
  )
  and upper(a.status) in('ASSIGNED','IN_PROGRESS')
  and exists(
    select 1
    from public.rr_upm_work_assignments_v8 s
    where s.canonical_lot_id=a.canonical_lot_id
      and upper(s.colour_code)=upper(a.colour_code)
      and upper(s.department_code)='STITCHING'
      and upper(s.status) in('ASSIGNED','IN_PROGRESS')
  );

update public.rr_upm_work_assignments_v8
set department_code='STITCHING',updated_at=now()
where upper(department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_colour_state
set current_department_code='STITCHING',updated_at=now()
where upper(current_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_department_handoffs_v727
set from_department_code='STITCHING'
where upper(from_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_department_handoffs_v727
set to_department_code='STITCHING'
where upper(to_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_dynamic_submit_history_v741
set department_code='STITCHING'
where upper(department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_route_lock_v740
set from_department_code='STITCHING'
where upper(from_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_route_lock_v740
set to_department_code='STITCHING'
where upper(to_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_alter_journey_v740
set origin_department_code='STITCHING'
where upper(origin_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

update public.rr_upm_alter_journey_v740
set responsible_department_code='STITCHING'
where upper(responsible_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

-- Colour-level mandatory department locks also use STITCHING.
update public.rr_upm_colour_department_lock_v754
set locked_department_code='STITCHING'
where upper(locked_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
)
  and upper(status)='ACTIVE';

update public.rr_upm_colour_department_lock_v754
set from_department_code='STITCHING'
where upper(from_department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

-- Retire aliases from selection lists; permanent canonical STITCHING remains active.
update public.rr_upm_departments
set is_active=false,
    department_name=coalesce(nullif(department_name,''),department_code)
      || ' · RETIRED → Karigar / Stitching'
where upper(department_code) in(
  'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
);

-- Move stale CHECKING references to canonical QC.
update public.rr_upm_work_assignments_v8
set department_code='QC', updated_at=now()
where upper(department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_colour_state
set current_department_code='QC', updated_at=now()
where upper(current_department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_department_handoffs_v727
set from_department_code='QC'
where upper(from_department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_department_handoffs_v727
set to_department_code='QC'
where upper(to_department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_dynamic_submit_history_v741
set department_code='QC'
where upper(department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_route_lock_v740
set from_department_code='QC'
where upper(from_department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_route_lock_v740
set to_department_code='QC'
where upper(to_department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_alter_journey_v740
set origin_department_code='QC'
where upper(origin_department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

update public.rr_upm_alter_journey_v740
set responsible_department_code='QC'
where upper(responsible_department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

-- Retire stale alias from normal assignment lists.
update public.rr_upm_departments
set is_active=false,
    department_name=coalesce(nullif(department_name,''),'Checking') || ' · RETIRED → QC'
where upper(department_code) in('CHECKING','CHECK','QUALITY CHECK','QUALITY_CHECK','QA');

-- ---------------------------------------------------------------------------
-- 2. Colour identity is always its canonical code C1, C2, C3...
-- ---------------------------------------------------------------------------

-- CB Purchase / Colour Master existing values.
update public.rr_cb_colours
set colour_name='C' || col_no::text
where col_no is not null
  and colour_name is distinct from ('C' || col_no::text);

-- Cutting snapshots.
update public.rr_cutting_breakup_v3 b
set colour_name_snapshot='C' || c.col_no::text
from public.rr_cb_colours c
where c.id=b.cb_colour_id
  and c.col_no is not null
  and b.colour_name_snapshot is distinct from ('C' || c.col_no::text);

-- Production tables use colour_code as the only display identity.
update public.rr_upm_work_assignments_v8
set colour_name=upper(colour_code)
where nullif(trim(colour_code),'') is not null
  and colour_name is distinct from upper(colour_code);

update public.rr_upm_colour_state
set colour_name=upper(colour_code)
where nullif(trim(colour_code),'') is not null
  and colour_name is distinct from upper(colour_code);

update public.rr_upm_department_handoffs_v727
set colour_name=upper(colour_code)
where nullif(trim(colour_code),'') is not null
  and colour_name is distinct from upper(colour_code);

update public.rr_upm_dynamic_submit_history_v741
set colour_name=upper(colour_code)
where nullif(trim(colour_code),'') is not null
  and colour_name is distinct from upper(colour_code);

update public.rr_upm_alter_journey_v740
set colour_name=upper(colour_code)
where nullif(trim(colour_code),'') is not null
  and colour_name is distinct from upper(colour_code);

-- Lock CB colour names at purchase/master level.
create or replace function public.rr_cb_colour_code_lock_v754()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.col_no is null then
    raise exception 'Colour sequence number is required.';
  end if;

  if new.col_no < 1 then
    raise exception 'Colour sequence must start from 1.';
  end if;

  new.colour_name := 'C' || new.col_no::text;
  return new;
end;
$$;

drop trigger if exists rr_cb_colour_code_lock_v754 on public.rr_cb_colours;
create trigger rr_cb_colour_code_lock_v754
before insert or update of col_no,colour_name
on public.rr_cb_colours
for each row
execute function public.rr_cb_colour_code_lock_v754();

-- ---------------------------------------------------------------------------
-- 3. Canonical worker list: stale alias can never return workers.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_worker_list_v754(p_department_code text)
returns table(
  worker_id uuid,
  worker_code text,
  worker_name text,
  role_code text,
  department_code text,
  mobile text
)
language sql
stable
security definer
set search_path=public
as $$
  select
    w.worker_id,
    w.worker_code,
    w.worker_name,
    w.role_code,
    public.rr_upm_norm_department_v754(w.department_code) department_code,
    public.rr_upm_phone_v740(to_jsonb(w)) mobile
  from public.rr_worker_directory_unified_v1 w
  where coalesce(w.is_active,true)
    and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
    and public.rr_upm_norm_department_v754(w.department_code)
        =public.rr_upm_norm_department_v754(p_department_code)
  order by lower(w.worker_name),w.worker_code
$$;

grant execute on function public.rr_upm_worker_list_v754(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Complete board status:
--    active/submitted departments + every eligible department for open colours.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_board_lot_status_v754(p_canonical_lot_id text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_identity jsonb;
  v_statuses jsonb;
begin
  select jsonb_build_object(
    'canonical_lot_id',b.canonical_lot_id,
    'lot_no',b.lot_no,
    'cb_no',b.cb_no,
    'art_no',b.art_no
  )
  into v_identity
  from public.rr_upm_lot_board_v1 b
  where b.canonical_lot_id=p_canonical_lot_id
  limit 1;

  with all_colours as (
    select distinct upper(q.colour_code) colour_code
    from public.rr_upm_colour_queue_v741 q
    where q.canonical_lot_id=p_canonical_lot_id
  ),
  departments as (
    select
      public.rr_upm_norm_department_v754(d.department_code) department_code,
      case
        when public.rr_upm_norm_department_v754(d.department_code)='QC' then 'QC'
        else d.department_name
      end department_name
    from public.rr_upm_departments d
    where d.is_active
      and coalesce(d.colour_assignment_enabled,true)
      and coalesce(d.worker_assignment_enabled,true)
      and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION'
      and not coalesce(d.is_start_department,false)
      and public.rr_upm_norm_department_v754(d.department_code)<>'CHECKING'
      and not exists(
        select 1
        from public.rr_upm_departments ch
        where ch.is_active
          and upper(coalesce(ch.parent_department_code,''))
              =upper(d.department_code)
      )
  ),
  active as (
    select
      public.rr_upm_norm_department_v754(a.department_code) department_code,
      upper(a.colour_code) colour_code,
      case
        when bool_or(upper(a.status)='IN_PROGRESS') then 'IN_PROGRESS'
        else 'ASSIGNED'
      end assignment_status
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.status) in('ASSIGNED','IN_PROGRESS')
    group by
      public.rr_upm_norm_department_v754(a.department_code),
      upper(a.colour_code)
  ),
  submitted as (
    select distinct
      public.rr_upm_norm_department_v754(x.department_code) department_code,
      upper(x.colour_code) colour_code
    from (
      select department_code,colour_code
      from public.rr_upm_work_assignments_v8
      where canonical_lot_id=p_canonical_lot_id
        and upper(status)='COMPLETED'
      union all
      select department_code,colour_code
      from public.rr_upm_dynamic_submit_history_v741
      where canonical_lot_id=p_canonical_lot_id
    ) x
  ),
  open_colours as (
    select c.colour_code
    from all_colours c
    where not exists(
      select 1 from active a where a.colour_code=c.colour_code
    )
  ),
  active_rows as (
    select
      d.department_code,
      d.department_name,
      coalesce(array_agg(a.colour_code order by a.colour_code)
        filter(where a.assignment_status='ASSIGNED'),array[]::text[]) assigned_codes,
      coalesce(array_agg(a.colour_code order by a.colour_code)
        filter(where a.assignment_status='IN_PROGRESS'),array[]::text[]) running_codes,
      array[]::text[] submitted_codes,
      array[]::text[] open_codes,
      'ACTIVE' row_type
    from departments d
    join active a on a.department_code=d.department_code
    group by d.department_code,d.department_name
  ),
  submitted_rows as (
    select
      d.department_code,
      d.department_name,
      array[]::text[] assigned_codes,
      array[]::text[] running_codes,
      array_agg(s.colour_code order by s.colour_code) submitted_codes,
      array[]::text[] open_codes,
      'SUBMITTED' row_type
    from departments d
    join submitted s on s.department_code=d.department_code
    where not exists(
      select 1 from active a
      where a.department_code=s.department_code
        and a.colour_code=s.colour_code
    )
    group by d.department_code,d.department_name
  ),
  open_rows as (
    select
      d.department_code,
      d.department_name,
      array[]::text[] assigned_codes,
      array[]::text[] running_codes,
      array[]::text[] submitted_codes,
      array_agg(o.colour_code order by o.colour_code) open_codes,
      'OPEN' row_type
    from departments d
    cross join open_colours o
    group by d.department_code,d.department_name
  ),
  combined as (
    select * from active_rows
    union all
    select * from submitted_rows
    union all
    select * from open_rows
  ),
  packed as (
    select
      c.department_code,
      c.department_name,
      coalesce(array_agg(distinct x order by x)
        filter(where x is not null and c.row_type='ACTIVE'
          and x=any(c.assigned_codes)),array[]::text[]) assigned_codes,
      coalesce(array_agg(distinct x order by x)
        filter(where x is not null and c.row_type='ACTIVE'
          and x=any(c.running_codes)),array[]::text[]) running_codes,
      coalesce(array_agg(distinct x order by x)
        filter(where x is not null and c.row_type='SUBMITTED'
          and x=any(c.submitted_codes)),array[]::text[]) submitted_codes,
      coalesce(array_agg(distinct x order by x)
        filter(where x is not null and c.row_type='OPEN'
          and x=any(c.open_codes)),array[]::text[]) open_codes
    from combined c
    left join lateral unnest(
      c.assigned_codes||c.running_codes||c.submitted_codes||c.open_codes
    ) x on true
    group by c.department_code,c.department_name
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'department_code',p.department_code,
      'department_name',p.department_name,
      'status_colour',
        case
          when cardinality(p.running_codes)+cardinality(p.assigned_codes)>0 then 'ORANGE'
          when cardinality(p.open_codes)>0 then 'BASE'
          else 'RED'
        end,
      'assigned_codes',p.assigned_codes,
      'running_codes',p.running_codes,
      'submitted_codes',p.submitted_codes,
      'open_codes',p.open_codes,
      'board_detail',
        trim(concat(
          case when cardinality(p.running_codes)>0
            then 'RUNNING '||array_to_string(p.running_codes,' ') end,
          case when cardinality(p.assigned_codes)>0
            then case when cardinality(p.running_codes)>0 then ' · ' else '' end
              ||'ASSIGNED '||array_to_string(p.assigned_codes,' ') end,
          case when cardinality(p.submitted_codes)>0
            then case when cardinality(p.running_codes)+cardinality(p.assigned_codes)>0
              then ' · ' else '' end
              ||'SUBMITTED '||array_to_string(p.submitted_codes,' ') end,
          case when cardinality(p.open_codes)>0
            then case when cardinality(p.running_codes)+cardinality(p.assigned_codes)
                           +cardinality(p.submitted_codes)>0
              then ' · ' else '' end
              ||'OPEN '||array_to_string(p.open_codes,' ') end
        ))
    )
    order by
      case
        when cardinality(p.running_codes)+cardinality(p.assigned_codes)>0 then 1
        when cardinality(p.open_codes)>0 then 2
        else 3
      end,
      p.department_name
  ),'[]'::jsonb)
  into v_statuses
  from packed p;

  return jsonb_build_object(
    'identity',coalesce(v_identity,'{}'::jsonb),
    'department_statuses',v_statuses,
    'version','V754_QC_COLOUR_OPEN_STATUS_LOCK'
  );
end;
$$;

grant execute on function public.rr_upm_board_lot_status_v754(text) to authenticated;

-- Read-only verification.
create or replace function public.rr_upm_v754_debug(p_canonical_lot_id text)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'ok',true,
    'version','V754_QC_COLOUR_OPEN_STATUS_LOCK',
    'active_stitching_alias_departments',coalesce((
      select jsonb_agg(jsonb_build_object(
        'department_code',d.department_code,
        'department_name',d.department_name,
        'is_active',d.is_active
      ))
      from public.rr_upm_departments d
      where upper(d.department_code) in(
        'KR','KAJ','KARIGAR','KARIGAR / STITCHING','KARIGAR/STITCHING','STITCH'
      )
        and d.is_active
    ),'[]'::jsonb),
    'stale_checking_departments',coalesce((
      select jsonb_agg(to_jsonb(d))
      from public.rr_upm_departments d
      where upper(d.department_code)='CHECKING' and d.is_active
    ),'[]'::jsonb),
    'noncanonical_cb_colours',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'col_no',c.col_no,'colour_name',c.colour_name
      ))
      from public.rr_cb_colours c
      where c.col_no is not null
        and c.colour_name is distinct from ('C'||c.col_no::text)
    ),'[]'::jsonb),
    'board',public.rr_upm_board_lot_status_v754(p_canonical_lot_id)
  )
$$;

grant execute on function public.rr_upm_v754_debug(text) to authenticated;

commit;


begin;

-- V754.2 MERGE: mandatory next-department lock after every Submit.
-- Worker can be assigned later, but department ownership must exist immediately.

create table if not exists public.rr_upm_colour_department_lock_v754(
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text,
  colour_id uuid,
  colour_code text not null,
  from_department_code text,
  locked_department_code text not null,
  lock_source text not null default 'SUBMIT_NEXT_DEPARTMENT',
  locked_at timestamptz not null default now(),
  locked_by uuid default auth.uid(),
  released_at timestamptz,
  released_by uuid,
  status text not null default 'ACTIVE',
  unique(canonical_lot_id,colour_code,status)
);

create index if not exists rr_upm_colour_department_lock_v754_lookup
on public.rr_upm_colour_department_lock_v754(
  canonical_lot_id,upper(colour_code),status
);

alter table public.rr_upm_colour_department_lock_v754 enable row level security;

drop policy if exists rr_upm_colour_department_lock_v754_read on public.rr_upm_colour_department_lock_v754;
create policy rr_upm_colour_department_lock_v754_read
on public.rr_upm_colour_department_lock_v754
for select
to authenticated
using (true);

-- Current canonical department for a Colour:
-- active assignment wins; otherwise mandatory submit lock; otherwise colour state;
-- only old legacy records may return null.
create or replace function public.rr_upm_colour_active_department_v754(
  p_canonical_lot_id text,
  p_colour_id uuid,
  p_colour_code text
)
returns table(
  department_code text,
  ownership_status text,
  assignment_id uuid,
  worker_id uuid,
  worker_name text
)
language sql
stable
security definer
set search_path=public
as $$
  with a as (
    select
      public.rr_upm_norm_department_v754(x.department_code) department_code,
      case
        when upper(x.status)='IN_PROGRESS' then 'RUNNING'
        else 'ASSIGNED'
      end ownership_status,
      x.id assignment_id,
      x.worker_id,
      x.worker_name_snapshot worker_name,
      1 priority
    from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id
      and upper(x.status) in('ASSIGNED','IN_PROGRESS')
      and (
        (p_colour_id is not null and x.colour_id=p_colour_id)
        or upper(x.colour_code)=upper(p_colour_code)
      )
    order by x.assigned_at desc
    limit 1
  ),
  l as (
    select
      public.rr_upm_norm_department_v754(x.locked_department_code) department_code,
      'WAITING_WORKER'::text ownership_status,
      null::uuid assignment_id,
      null::uuid worker_id,
      null::text worker_name,
      2 priority
    from public.rr_upm_colour_department_lock_v754 x
    where x.canonical_lot_id=p_canonical_lot_id
      and upper(x.colour_code)=upper(p_colour_code)
      and upper(x.status)='ACTIVE'
    order by x.locked_at desc
    limit 1
  ),
  s as (
    select
      public.rr_upm_norm_department_v754(x.current_department_code) department_code,
      case
        when nullif(trim(x.current_department_code),'') is not null
          then 'WAITING_WORKER'
        else 'LEGACY_UNLOCKED'
      end ownership_status,
      null::uuid assignment_id,
      null::uuid worker_id,
      null::text worker_name,
      3 priority
    from public.rr_upm_colour_state x
    where x.canonical_lot_id=p_canonical_lot_id
      and (
        (p_colour_id is not null and x.colour_id=p_colour_id)
        or upper(x.colour_code)=upper(p_colour_code)
      )
    order by x.updated_at desc
    limit 1
  )
  select q.department_code,q.ownership_status,q.assignment_id,q.worker_id,q.worker_name
  from (
    select * from a
    union all
    select * from l
    union all
    select * from s
  ) q
  where nullif(trim(q.department_code),'') is not null
  order by q.priority
  limit 1
$$;

grant execute on function public.rr_upm_colour_active_department_v754(text,uuid,text)
to authenticated;

-- Lock/upsert a Colour immediately when Submit chooses Next Department.
create or replace function public.rr_upm_lock_colour_department_v754(
  p_canonical_lot_id text,
  p_lot_no text,
  p_colour_id uuid,
  p_colour_code text,
  p_from_department_code text,
  p_next_department_code text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_next text:=public.rr_upm_norm_department_v754(p_next_department_code);
begin
  if nullif(trim(v_next),'') is null then
    raise exception 'NEXT_DEPARTMENT_REQUIRED';
  end if;

  if not exists(
    select 1
    from public.rr_upm_departments d
    where d.is_active
      and public.rr_upm_norm_department_v754(d.department_code)=v_next
  ) then
    raise exception 'Selected Next Department % is inactive or unmapped.',v_next;
  end if;

  update public.rr_upm_colour_department_lock_v754
  set status='RELEASED',
      released_at=now(),
      released_by=auth.uid()
  where canonical_lot_id=p_canonical_lot_id
    and upper(colour_code)=upper(p_colour_code)
    and upper(status)='ACTIVE';

  insert into public.rr_upm_colour_department_lock_v754(
    canonical_lot_id,lot_no,colour_id,colour_code,
    from_department_code,locked_department_code,
    lock_source,locked_by,status
  )
  values(
    p_canonical_lot_id,p_lot_no,p_colour_id,upper(p_colour_code),
    public.rr_upm_norm_department_v754(p_from_department_code),
    v_next,'SUBMIT_NEXT_DEPARTMENT',auth.uid(),'ACTIVE'
  );

  update public.rr_upm_colour_state
  set current_department_code=v_next,
      status='PENDING',
      updated_at=now()
  where canonical_lot_id=p_canonical_lot_id
    and (
      (p_colour_id is not null and colour_id=p_colour_id)
      or upper(colour_code)=upper(p_colour_code)
    );

  return jsonb_build_object(
    'ok',true,
    'colour_code',upper(p_colour_code),
    'locked_department_code',v_next,
    'ownership_status','WAITING_WORKER'
  );
end;
$$;

grant execute on function public.rr_upm_lock_colour_department_v754(
  text,text,uuid,text,text,text
) to authenticated;

-- Backfill active lock from existing colour state for legacy rows.
insert into public.rr_upm_colour_department_lock_v754(
  canonical_lot_id,lot_no,colour_id,colour_code,
  from_department_code,locked_department_code,
  lock_source,locked_by,status
)
select
  s.canonical_lot_id,
  b.lot_no,
  s.colour_id,
  upper(s.colour_code),
  null,
  public.rr_upm_norm_department_v754(s.current_department_code),
  'LEGACY_COLOUR_STATE_BACKFILL',
  auth.uid(),
  'ACTIVE'
from public.rr_upm_colour_state s
left join public.rr_upm_lot_board_v1 b
  on b.canonical_lot_id=s.canonical_lot_id
where nullif(trim(s.current_department_code),'') is not null
  and not exists(
    select 1
    from public.rr_upm_colour_department_lock_v754 l
    where l.canonical_lot_id=s.canonical_lot_id
      and upper(l.colour_code)=upper(s.colour_code)
      and upper(l.status)='ACTIVE'
  );

commit;
