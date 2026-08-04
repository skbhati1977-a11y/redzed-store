-- REDZED Universal Production V766
-- ALTER FILL: mandatory Lot Line Man + submitted/COMPLETED department history support
--
-- IMPORTANT:
-- 1) Existing rr_upm_alter_stage_v740 responsibility journey is preserved unchanged.
-- 2) This wrapper only makes the latest COMPLETED assignment temporarily visible
--    to the existing V740 core while the RPC runs, then restores it to COMPLETED.
-- 3) Current holder responsibility remains controlled by the existing journey stages.
-- 4) Run this complete file once in Supabase SQL Editor.

begin;

-- Keep the installed V740 implementation as the untouched core.
do $install$
begin
  if to_regprocedure(
       'public.rr_upm_alter_stage_v740_core(text,text,text,jsonb,jsonb,boolean,uuid,text)'
     ) is null then
    if to_regprocedure(
         'public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text)'
       ) is null then
      raise exception 'Required function rr_upm_alter_stage_v740 is not installed.';
    end if;

    execute 'alter function public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text) rename to rr_upm_alter_stage_v740_core';
  end if;
end
$install$;

create or replace function public.rr_upm_alter_stage_v740(
  p_stage text,
  p_canonical_lot_id text,
  p_department_code text,
  p_rows jsonb,
  p_evidence_urls jsonb default '[]'::jsonb,
  p_physical_confirmed boolean default false,
  p_line_man_id uuid default null,
  p_remarks text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_stage text := upper(trim(coalesce(p_stage,'')));
  v_row jsonb;
  v_colour_id uuid;
  v_colour_code text;
  v_active_assignment_id uuid;
  v_history_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_reopened_ids uuid[] := array[]::uuid[];
  v_current_lm_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Login required.';
  end if;

  if nullif(trim(coalesce(p_canonical_lot_id,'')),'') is null then
    raise exception 'Lot reference is required.';
  end if;

  if nullif(trim(coalesce(p_department_code,'')),'') is null then
    raise exception 'Department is required.';
  end if;

  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'No selected Alter rows.';
  end if;

  -- ALTER FILL must come from an explicitly selected, active Line Man.
  if v_stage = 'ALTER_FILL' then
    if p_line_man_id is null then
      raise exception 'Lot Line Man selection is mandatory before Save Alter Fill.';
    end if;

    if not exists (
      select 1
      from public.rr_upm_worker_candidates_v740('LINE_MAN', null) c
      where c.worker_id = p_line_man_id
    ) then
      raise exception 'Selected person is not an active Line Man.';
    end if;

    -- A running Lot LM cannot be silently replaced from the Alter modal.
    -- Use the installed CHANGE LOT LM handover flow for a real transfer.
    select e.person_id
      into v_current_lm_id
    from public.rr_upm_lot_role_enrolment_v740 e
    where e.canonical_lot_id = p_canonical_lot_id
      and upper(e.role_code) = 'LINE_MAN'
      and upper(e.status) = 'ACTIVE'
    order by e.enrolled_at desc
    limit 1;

    if v_current_lm_id is not null and v_current_lm_id <> p_line_man_id then
      raise exception 'This Lot is enrolled to another Line Man. Use CHANGE LOT LM with handover first.';
    end if;
  end if;

  /*
    Existing V740 requires ASSIGNED/IN_PROGRESS even when the department has
    already submitted and the assignment has correctly become COMPLETED.

    For each requested Colour, reopen only the latest matching COMPLETED row
    inside this same database transaction. The installed V740 core reads the
    original worker snapshot, creates/advances the Alter journey, and this
    wrapper immediately restores the row to COMPLETED before returning.
  */
  for v_row in
    select value from jsonb_array_elements(p_rows)
  loop
    v_colour_code := upper(trim(coalesce(v_row->>'colour_code','')));
    v_colour_id := nullif(trim(coalesce(v_row->>'colour_id','')),'')::uuid;
    v_active_assignment_id := null;
    v_history_assignment := null;

    if nullif(v_colour_code,'') is null and v_colour_id is null then
      raise exception 'Colour reference is required in every Alter row.';
    end if;

    select a.id
      into v_active_assignment_id
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id = p_canonical_lot_id
      and upper(a.department_code) = upper(p_department_code)
      and a.status in ('ASSIGNED','IN_PROGRESS')
      and (
        (v_colour_id is not null and a.colour_id = v_colour_id)
        or
        (v_colour_id is null and upper(a.colour_code) = v_colour_code)
      )
    order by a.assigned_at desc
    limit 1;

    if v_active_assignment_id is null then
      select a.*
        into v_history_assignment
      from public.rr_upm_work_assignments_v8 a
      where a.canonical_lot_id = p_canonical_lot_id
        and upper(a.department_code) = upper(p_department_code)
        and a.status = 'COMPLETED'
        and (
          (v_colour_id is not null and a.colour_id = v_colour_id)
          or
          (v_colour_id is null and upper(a.colour_code) = v_colour_code)
        )
      order by coalesce(a.completed_at,a.updated_at,a.assigned_at) desc,
               a.assigned_at desc
      limit 1
      for update;

      if v_history_assignment.id is null then
        raise exception
          'Production assignment history missing for new Alter Fill: % in %.',
          coalesce(nullif(v_colour_code,''),v_colour_id::text),
          upper(p_department_code);
      end if;

      -- Do not change completed_at or ownership history; this is transaction-local compatibility.
      update public.rr_upm_work_assignments_v8
      set status = 'IN_PROGRESS'
      where id = v_history_assignment.id;

      if not (v_history_assignment.id = any(v_reopened_ids)) then
        v_reopened_ids := array_append(v_reopened_ids,v_history_assignment.id);
      end if;
    end if;
  end loop;

  -- Existing responsibility engine runs unchanged here.
  v_result := public.rr_upm_alter_stage_v740_core(
    p_stage,
    p_canonical_lot_id,
    p_department_code,
    p_rows,
    coalesce(p_evidence_urls,'[]'::jsonb),
    coalesce(p_physical_confirmed,false),
    p_line_man_id,
    p_remarks
  );

  if cardinality(v_reopened_ids) > 0 then
    update public.rr_upm_work_assignments_v8
    set status = 'COMPLETED'
    where id = any(v_reopened_ids)
      and status = 'IN_PROGRESS';
  end if;

  return v_result || jsonb_build_object(
    'compatibility_version','V766_COMPLETED_ASSIGNMENT_HISTORY',
    'historical_assignments_used',cardinality(v_reopened_ids)
  );
exception
  when others then
    -- Re-raising rolls back temporary status changes and all core writes atomically.
    raise;
end
$function$;

revoke all on function public.rr_upm_alter_stage_v740(
  text,text,text,jsonb,jsonb,boolean,uuid,text
) from public;

grant execute on function public.rr_upm_alter_stage_v740(
  text,text,text,jsonb,jsonb,boolean,uuid,text
) to authenticated;

commit;

-- Expected verification:
-- select
--   to_regprocedure('public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text)') as wrapper,
--   to_regprocedure('public.rr_upm_alter_stage_v740_core(text,text,text,jsonb,jsonb,boolean,uuid,text)') as preserved_core;
