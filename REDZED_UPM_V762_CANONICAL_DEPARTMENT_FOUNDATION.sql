-- ============================================================
-- REDZED UPM V762 — CANONICAL DEPARTMENT FOUNDATION
-- ============================================================
--
-- CANONICAL SOURCE:
--   public.rr_departments_v1 (Role & Permission Department Master)
--
-- COMPATIBILITY LAYER:
--   public.rr_upm_departments
--
-- RULE:
--   Existing history is NOT bulk rewritten.
--   Legacy aliases are canonicalized at read/write boundaries.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Universal canonical Department resolver
-- ------------------------------------------------------------
create or replace function public.rr_upm_canonical_department_v762(
  p_department_code text
)
returns text
language sql
immutable
as $$
  select case
    when nullif(trim(p_department_code),'') is null then null
    else case regexp_replace(
      upper(trim(p_department_code)),
      '[^A-Z0-9]+',
      '',
      'g'
    )
      when 'OV' then 'OVERLOCK'
      when 'OVERLOCK' then 'OVERLOCK'
      when 'OVERLOCKING' then 'OVERLOCK'

      when 'FLD' then 'FOLDING'
      when 'FOLD' then 'FOLDING'
      when 'FOLDING' then 'FOLDING'
      when 'FLATLOCK' then 'FOLDING'

      when 'PRINT' then 'PRINTING'
      when 'PRINTER' then 'PRINTING'
      when 'PRINTING' then 'PRINTING'

      when 'KR' then 'STITCHING'
      when 'KARIGAR' then 'STITCHING'
      when 'STITCH' then 'STITCHING'
      when 'STITCHING' then 'STITCHING'

      when 'THCUT' then 'THREAD_CUT'
      when 'THREADCUT' then 'THREAD_CUT'
      when 'THREADCUTTING' then 'THREAD_CUT'

      when 'CHECK' then 'QC'
      when 'CHECKING' then 'QC'
      when 'QUALITYCHECK' then 'QC'
      when 'QC' then 'QC'

      when 'KAAJ' then 'KAAJ'
      when 'KAJ' then 'KAAJ'

      when 'BTN' then 'BUTTON'
      when 'BUTTON' then 'BUTTON'

      when 'PRESSFINISHING' then 'PRESS'
      when 'FINISHING' then 'PRESS'
      when 'PRESS' then 'PRESS'

      when 'PACK' then 'PACKING'
      when 'PACKING' then 'PACKING'

      when 'STICKER' then 'STICKER'
      when 'CUTTING' then 'CUTTING'
      when 'FABRICATION' then 'FABRICATION'
      when 'ADMIN' then 'ADMIN'
      when 'ACCOUNTS' then 'ACCOUNTS'
      when 'SALES' then 'SALES'
      when 'DISPATCH' then 'DISPATCH'
      when 'DISTRIBUTOR' then 'DISTRIBUTOR'

      when 'OPENNEXT' then 'OPEN_NEXT'
      when 'OPENFORNEXTPROCESS' then 'OPEN_NEXT'
      when 'NEXTPROCESS' then 'OPEN_NEXT'

      else upper(trim(p_department_code))
    end
  end
$$;

-- ------------------------------------------------------------
-- 2. Canonical assignment Department catalog
-- ------------------------------------------------------------
create or replace view public.rr_upm_department_catalog_v762 as
select
  upper(d.department_code) as department_code,
  d.department_name,
  d.display_order as sequence_no,
  upper(nullif(d.parent_department_code,'')) as parent_department_code,
  upper(coalesce(d.department_type,'PRODUCTION')) as department_type,
  coalesce(d.is_active,false) as is_active,
  coalesce(d.production_enabled,true) as production_enabled,
  coalesce(d.worker_assignment_enabled,true) as worker_assignment_enabled,
  coalesce(d.rate_enabled,true) as rate_enabled,
  coalesce(d.colour_assignment_enabled,true) as colour_assignment_enabled,
  coalesce(d.allow_alter,true) as allow_alter
from public.rr_departments_v1 d
where coalesce(d.is_active,false)
  and d.archived_at is null
  and coalesce(d.production_enabled,true)
  and upper(coalesce(d.department_type,'PRODUCTION'))
      in ('PRODUCTION','FABRICATION')
  and public.rr_upm_canonical_department_v762(d.department_code)
      not in (
        'ADMIN',
        'ACCOUNTS',
        'CUTTING',
        'FABRICATION',
        'SALES',
        'DISPATCH',
        'DISTRIBUTOR',
        'OPEN_NEXT'
      );

grant select on public.rr_upm_department_catalog_v762 to authenticated;

-- ------------------------------------------------------------
-- 3. Sync canonical Department Master into UPM compatibility table
-- ------------------------------------------------------------
insert into public.rr_upm_departments(
  department_code,
  department_name,
  sequence_no,
  entry_mode,
  is_start_department,
  is_final_department,
  auto_forward,
  allow_partial,
  allow_alter,
  is_active,
  parent_department_code,
  department_type,
  worker_assignment_enabled,
  rate_enabled,
  colour_assignment_enabled,
  updated_at
)
select
  c.department_code,
  c.department_name,
  c.sequence_no,
  'COLOUR_SIZE',
  false,
  c.department_code='PACKING',
  false,
  true,
  c.allow_alter,
  true,
  lower(c.parent_department_code),
  c.department_type,
  c.worker_assignment_enabled,
  c.rate_enabled,
  c.colour_assignment_enabled,
  now()
from public.rr_upm_department_catalog_v762 c
on conflict(department_code)
do update set
  department_name=excluded.department_name,
  sequence_no=excluded.sequence_no,
  parent_department_code=excluded.parent_department_code,
  department_type=excluded.department_type,
  worker_assignment_enabled=excluded.worker_assignment_enabled,
  rate_enabled=excluded.rate_enabled,
  colour_assignment_enabled=excluded.colour_assignment_enabled,
  allow_alter=excluded.allow_alter,
  is_active=true,
  updated_at=now();

-- Pseudo route and retired alias rows must not appear in new assignment lists.
update public.rr_upm_departments
set
  is_active=false,
  worker_assignment_enabled=false,
  colour_assignment_enabled=false,
  updated_at=now()
where upper(department_code) in (
  'OPEN_NEXT',
  'OV',
  'FLD',
  'KR',
  'CHECKING'
);

-- ------------------------------------------------------------
-- 4. Worker list — canonical primary + additional skill collaboration
-- ------------------------------------------------------------
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
    select public.rr_upm_canonical_department_v762(
      p_department_code
    ) as department_code
  )
  select distinct
    u.worker_id,
    u.worker_code,
    u.worker_name,
    coalesce(
      (select department_code from requested),
      public.rr_upm_canonical_department_v762(u.department_code)
    ) as department_code,
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
      or public.rr_upm_canonical_department_v762(u.department_code)
          =r.department_code
      or exists(
        select 1
        from public.rr_worker_department_map_v1 m
        where m.worker_id=u.worker_id
          and coalesce(m.is_active,false)
          and public.rr_upm_canonical_department_v762(m.department_code)
              =r.department_code
      )
    )
  order by u.worker_name,u.worker_code
$function$;

grant execute on function public.rr_upm_worker_list_v8_3(text)
  to authenticated;

-- ------------------------------------------------------------
-- 5. Assignment RPC — canonical Department identity on all new assignments
-- ------------------------------------------------------------
create or replace function public.rr_upm_claim_colours_v741(
  p_canonical_lot_id text,
  p_lot_no text,
  p_department_code text,
  p_rows jsonb,
  p_remarks text default null
)
returns setof public.rr_upm_work_assignments_v8
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_profile public.rr_user_profiles%rowtype;
  v_row jsonb;
  v_lot_no text;
  v_colour text;
  v_colour_id uuid;
  v_worker uuid;
  v_qty integer;
  v_rate numeric;
  v_expected integer;
  v_sizes jsonb;
  v_cname text;
  v_source text;
  v_source_lot uuid;
  v_wname text;
  v_wcode text;
  v_out public.rr_upm_work_assignments_v8;
  v_department text;
begin
  v_department:=
    public.rr_upm_canonical_department_v762(p_department_code);

  if v_department is null
     or v_department='OPEN_NEXT'
  then
    raise exception 'Valid Department required.';
  end if;

  select *
  into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active User Directory profile required.';
  end if;

  if not public.rr_upm_action_permission_v727(
       'ASSIGN',
       v_department
     )
     and lower(coalesce(v_profile.role_code,'')) not in(
       'owner','admin','manager','line_manager','line_man',
       'department_head','production','cutting_master'
     )
  then
    raise exception 'Assign Work permission denied.';
  end if;

  if not exists(
    select 1
    from public.rr_upm_department_catalog_v762 d
    where d.department_code=v_department
      and d.worker_assignment_enabled
      and d.colour_assignment_enabled
  ) then
    raise exception
      'Department % is not active for Colour/Worker assignment.',
      v_department;
  end if;

  if jsonb_typeof(p_rows)<>'array'
     or jsonb_array_length(p_rows)=0
  then
    raise exception 'Select at least one colour.';
  end if;

  select coalesce(
    (
      select lot_no
      from public.rr_upm_lot_registry
      where canonical_lot_id=p_canonical_lot_id
      limit 1
    ),
    nullif(trim(p_lot_no),'')
  )
  into v_lot_no;

  if v_lot_no is null then
    raise exception 'Lot No is required.';
  end if;

  perform public.rr_upm_sync_colour_queue_v741(
    p_canonical_lot_id
  );

  for v_row in
    select value
    from jsonb_array_elements(p_rows)
  loop
    v_colour:=upper(trim(v_row->>'colour_code'));
    v_colour_id:=nullif(v_row->>'colour_id','')::uuid;
    v_worker:=nullif(v_row->>'worker_id','')::uuid;
    v_qty:=coalesce((v_row->>'assigned_qty')::int,0);
    v_rate:=coalesce((v_row->>'actual_rate')::numeric,0);

    perform pg_advisory_xact_lock(
      hashtextextended(
        p_canonical_lot_id||'|'||v_colour,
        0
      )
    );

    if exists(
      select 1
      from public.rr_upm_work_assignments_v8 a
      where a.canonical_lot_id=p_canonical_lot_id
        and upper(a.colour_code)=v_colour
        and a.status in('ASSIGNED','IN_PROGRESS')
    ) then
      raise exception
        'Colour % is already assigned. Submit it first.',
        v_colour;
    end if;

    if exists(
      select 1
      from public.rr_upm_work_assignments_v8 a
      where a.canonical_lot_id=p_canonical_lot_id
        and public.rr_upm_canonical_department_v762(a.department_code)
            =v_department
        and upper(a.colour_code)=v_colour
        and a.status='COMPLETED'
    ) then
      raise exception
        'Colour % already completed in department %.',
        v_colour,
        v_department;
    end if;

    select
      max(c.colour_name),
      sum(c.cutting_qty)::int,
      jsonb_agg(
        jsonb_build_object(
          'size_code',upper(c.size_code),
          'qty',c.cutting_qty
        )
        order by upper(c.size_code)
      ),
      max(c.source_type),
      (array_agg(c.source_lot_id))[1]
    into
      v_cname,
      v_expected,
      v_sizes,
      v_source,
      v_source_lot
    from public.rr_upm_cut_size_rows_v726(v_lot_no)c
    where
      (v_colour_id is not null and c.colour_id=v_colour_id)
      or
      (v_colour_id is null and upper(c.colour_code)=v_colour);

    if v_expected is null then
      raise exception
        'Cutting mapping missing for Colour %.',
        v_colour;
    end if;

    if v_qty<>v_expected then
      raise exception
        'Colour % must be assigned full mapped Qty %.',
        v_colour,
        v_expected;
    end if;

    select worker_name,worker_code
    into v_wname,v_wcode
    from public.rr_upm_worker_list_v8_3(v_department)
    where worker_id=v_worker
    limit 1;

    if v_wname is null then
      raise exception
        'Selected worker is not actively mapped to department %.',
        v_department;
    end if;

    insert into public.rr_upm_work_assignments_v8(
      canonical_lot_id,
      lot_no,
      department_code,
      colour_id,
      colour_code,
      colour_name,
      source_type,
      source_lot_id,
      worker_id,
      worker_code,
      worker_name_snapshot,
      assigned_qty,
      size_breakup,
      inbound_qty,
      inbound_breakup,
      actual_rate,
      rate_filled_by,
      rate_filled_by_name,
      rate_filled_at,
      assigned_by,
      assigned_by_name,
      remarks,
      status
    )
    values(
      p_canonical_lot_id,
      v_lot_no,
      v_department,
      v_colour_id,
      v_colour,
      coalesce(v_cname,v_colour),
      v_source,
      v_source_lot,
      v_worker,
      v_wcode,
      v_wname,
      v_expected,
      coalesce(v_sizes,'[]'::jsonb),
      v_expected,
      coalesce(v_sizes,'[]'::jsonb),
      round(v_rate,4),
      auth.uid(),
      coalesce(v_profile.full_name,v_profile.email),
      now(),
      auth.uid(),
      coalesce(v_profile.full_name,v_profile.email),
      p_remarks,
      'ASSIGNED'
    )
    returning *
    into v_out;

    return next v_out;
  end loop;
end
$function$;

grant execute on function public.rr_upm_claim_colours_v741(
  text,text,text,jsonb,text
) to authenticated;

commit;

-- ------------------------------------------------------------
-- Verification
-- ------------------------------------------------------------
select jsonb_build_object(
  'ok',true,
  'version','V762_CANONICAL_DEPARTMENT_FOUNDATION',
  'canonical_source','rr_departments_v1',
  'compatibility_source','rr_upm_departments',
  'worker_lookup','PRIMARY_AND_SKILLS_CANONICAL',
  'new_assignment_identity','CANONICAL_DEPARTMENT_CODE',
  'history_bulk_rewritten',false,
  'legacy_aliases',jsonb_build_object(
    'OV','OVERLOCK',
    'FLD','FOLDING',
    'KR','STITCHING',
    'CHECKING','QC',
    'PRINT','PRINTING'
  )
) as rr_upm_v762_result;

select
  department_code,
  department_name,
  department_type,
  sequence_no
from public.rr_upm_department_catalog_v762
order by sequence_no,department_code;

select 'OVERLOCK' requested_department,worker_name,worker_code
from public.rr_upm_worker_list_v8_3('OV')
union all
select 'FOLDING',worker_name,worker_code
from public.rr_upm_worker_list_v8_3('FLD')
union all
select 'STICKER',worker_name,worker_code
from public.rr_upm_worker_list_v8_3('STICKER')
union all
select 'THREAD_CUT',worker_name,worker_code
from public.rr_upm_worker_list_v8_3('TH CUT');
