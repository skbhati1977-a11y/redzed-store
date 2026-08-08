-- REAL FACTORY V798.4
-- Released Cutting Lot → Ready to Assign / Open Queue contract
-- Run once in Supabase SQL Editor, then upload the four matching app files.
-- Safe: does not touch Despatch, Packing stock, challans, or submitted history.

begin;

do $$
begin
  if to_regprocedure('public.rr_upm_sync_cutting_lots_v2()') is null then
    raise exception 'Required Cutting → UPM bridge rr_upm_sync_cutting_lots_v2() is not installed.';
  end if;
  if to_regprocedure('public.rr_upm_universal_form_v740(text,text)') is null then
    raise exception 'Required base Universal Production form rr_upm_universal_form_v740(text,text) is not installed.';
  end if;
  if to_regprocedure('public.rr_upm_sync_colour_queue_v741(text)') is null then
    raise exception 'Required colour queue sync rr_upm_sync_colour_queue_v741(text) is not installed.';
  end if;
  if to_regprocedure('public.rr_upm_claim_colours_v796(text,text,text,jsonb,text,numeric,numeric,numeric,text)') is null then
    raise exception 'Required Ready to Assign save RPC rr_upm_claim_colours_v796(...) is not installed.';
  end if;
end $$;

-- Backfill every already-released Cutting lot through the existing canonical
-- bridge. The bridge is idempotent: it registers missing lots and refreshes
-- their colour/size source without duplicating registry identities.
select public.rr_upm_sync_cutting_lots_v2();

-- Queue form contract, colour by colour:
-- 1. Fresh release / queue OPEN: visible in every production department.
-- 2. Assigned or running: visible only in that exact department.
-- 3. Submitted from this department: hidden from this department's queue.
-- 4. Despatch is deliberately outside this production assignment contract.
create or replace function public.rr_upm_universal_form_v741(
  p_canonical_lot_id text,
  p_department_code text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  base jsonb;
  outrows jsonb := '[]'::jsonb;
  r jsonb;
  active_assignment record;
  queue_row record;
  completed_here boolean;
  eligible boolean;
  statuses jsonb;
  requested text := upper(trim(coalesce(p_department_code,'')));
begin
  if requested in ('','CUTTING','DESPATCH','DISPATCH') then
    raise exception 'Ready to Assign is available only for a production department.';
  end if;

  perform public.rr_upm_sync_colour_queue_v741(p_canonical_lot_id);
  base := public.rr_upm_universal_form_v740(p_canonical_lot_id,p_department_code);

  select exists(
    select 1
    from public.rr_upm_departments d
    where upper(d.department_code)=requested
      and d.is_active
      and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION'
      and upper(d.department_code) not in ('CUTTING','DESPATCH','DISPATCH')
      and coalesce(d.colour_assignment_enabled,true)
      and coalesce(d.worker_assignment_enabled,true)
  ) into eligible;

  for r in select value from jsonb_array_elements(coalesce(base->'rows','[]'::jsonb)) loop
    queue_row := null;
    active_assignment := null;

    select * into queue_row
    from public.rr_upm_colour_queue_v741 q
    where q.canonical_lot_id=p_canonical_lot_id
      and upper(q.colour_code)=upper(r->>'colour_code');

    select * into active_assignment
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.colour_code)=upper(r->>'colour_code')
      and upper(coalesce(a.status,'')) in ('ASSIGNED','IN_PROGRESS','RUNNING','ACTIVE')
    order by a.assigned_at desc
    limit 1;

    select exists(
      select 1 from public.rr_upm_dynamic_submit_history_v741 h
      where h.canonical_lot_id=p_canonical_lot_id
        and upper(h.department_code)=requested
        and upper(h.colour_code)=upper(r->>'colour_code')
    ) into completed_here;

    -- A department never re-opens its own submitted colour. A fresh released
    -- colour is OPEN and therefore intentionally appears in every department.
    if completed_here then
      continue;
    end if;
    if coalesce(queue_row.queue_state,'OPEN') <> 'OPEN'
       and not (active_assignment.id is not null and upper(active_assignment.department_code)=requested) then
      continue;
    end if;

    r := r || jsonb_build_object(
      'is_locked', active_assignment.id is not null and upper(active_assignment.department_code)=requested,
      'is_completed_here', false,
      'can_assign', coalesce(queue_row.queue_state,'OPEN')='OPEN' and eligible,
      'assignment_id', case when active_assignment.id is not null and upper(active_assignment.department_code)=requested then active_assignment.id else null end,
      'worker_id', case when active_assignment.id is not null and upper(active_assignment.department_code)=requested then active_assignment.worker_id else null end,
      'worker_name', case when active_assignment.id is not null and upper(active_assignment.department_code)=requested then active_assignment.worker_name_snapshot else null end,
      'worker_code', case when active_assignment.id is not null and upper(active_assignment.department_code)=requested then active_assignment.worker_code else null end,
      'assigned_qty', case when active_assignment.id is not null and upper(active_assignment.department_code)=requested then coalesce((r->>'main_qty')::numeric,(r->>'cutting_qty')::numeric,0) else 0 end,
      'assignment_status', case when active_assignment.id is not null and upper(active_assignment.department_code)=requested then active_assignment.status else null end,
      'status', case when active_assignment.id is not null and upper(active_assignment.department_code)=requested then 'ASSIGNED / IN PROGRESS' else 'READY TO ASSIGN' end,
      'queue_state', coalesce(queue_row.queue_state,'OPEN'),
      'owner_department_code', case when active_assignment.id is not null then active_assignment.department_code else null end
    );
    outrows := outrows || jsonb_build_array(r);
  end loop;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.department_name),'[]'::jsonb)
  into statuses
  from public.rr_upm_department_status_v741(p_canonical_lot_id) s;

  base := jsonb_set(base,'{rows}',outrows,true)
    || jsonb_build_object(
      'department_statuses',statuses,
      'dynamic_queue','RELEASED_LOT_ALL_DEPARTMENTS__RUNNING_CURRENT_DEPARTMENT_ONLY',
      'versions',coalesce(base->'versions','{}'::jsonb)
        || jsonb_build_object('release_ready_assign','V798_4')
    );
  return base;
end;
$$;

grant execute on function public.rr_upm_universal_form_v741(text,text) to authenticated;

commit;

-- Proof result: every registered lot is now board-visible. `missing_cutting_map`
-- must be empty after the sync for released Cutting lots.
select jsonb_build_object(
  'version','REAL_FACTORY_V798_4_RELEASE_QUEUE_READY_ASSIGN',
  'upm_registry_lots',(select count(*) from public.rr_upm_lot_registry),
  'upm_board_lots',(select count(*) from public.rr_upm_lot_board_v1),
  'missing_cutting_map',coalesce((
    select jsonb_agg(jsonb_build_object('lot_no',x.lot_no,'cutting_qty',x.cutting_qty) order by x.lot_no)
    from (
      select l.lot_no,sum(b.actual_qty) cutting_qty
      from public.rr_cutting_lots_v3 l
      join public.rr_cutting_breakup_v3 b on b.cutting_lot_id=l.id and b.actual_qty>0
      left join public.rr_upm_lot_registry r on upper(trim(r.lot_no))=upper(trim(l.lot_no))
      where r.canonical_lot_id is null
      group by l.lot_no
    ) x
  ),'[]'::jsonb),
  'hard_rules',jsonb_build_object(
    'single_and_multi_release','sync_to_same_upm_registry_and_board',
    'fresh_colour','ready_to_assign_in_all_production_departments',
    'running_colour','visible_only_in_its_current_department',
    'submitted_here','hidden_from_that_departments_open_queue',
    'despatch','separate_untouched_module'
  )
) as real_factory_v798_4_result;
