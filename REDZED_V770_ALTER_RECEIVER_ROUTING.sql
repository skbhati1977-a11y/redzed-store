-- REDZED Universal Production V770
-- Per-journey Alter Receiver Line Man routing + logged-in LM self assignment
--
-- FINAL RULES:
-- 1) Every ALTER_FILL Save remains a separate Alter journey (existing V765/core behaviour).
-- 2) A non-Line-Man actor must explicitly select an active Line Man for every new journey.
-- 3) An authenticated active LINE_MAN actor is automatically assigned to their own Alter journey.
-- 4) The selected/self Line Man becomes the holder for THIS ALTER JOURNEY only.
--    This does not silently change the permanent Lot Line Man enrolment.
-- 5) Existing responsibility-stage engine and completed-assignment compatibility remain unchanged.

begin;

-- Preserve the originally installed V740 responsibility engine as the core.
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

-- Frontend context: active LM candidates + authenticated actor/self-LM mapping.
create or replace function public.rr_upm_alter_receiver_context_v770(
  p_canonical_lot_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_profile public.rr_user_profiles%rowtype;
  v_profile_json jsonb := '{}'::jsonb;
  v_actor_role text := '';
  v_actor_lm jsonb := null;
  v_candidates jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Login required.';
  end if;

  select p.*
    into v_profile
  from public.rr_user_profiles p
  where p.auth_user_id = auth.uid()
    and coalesce(p.is_active,false)
    and upper(coalesce(p.access_status,'ACTIVE')) = 'ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active User Directory profile required.';
  end if;

  v_profile_json := to_jsonb(v_profile);
  v_actor_role := upper(
    regexp_replace(
      coalesce(v_profile_json->>'role_code',v_profile_json->>'role',''),
      '[^A-Za-z0-9]+','_','g'
    )
  );

  select coalesce(jsonb_agg(candidate_json order by
           coalesce(candidate_json->>'worker_name',candidate_json->>'person_name_snapshot',candidate_json->>'name','')
         ),'[]'::jsonb)
    into v_candidates
  from (
    select to_jsonb(c) as candidate_json
    from public.rr_upm_worker_candidates_v740('LINE_MAN',null) c
  ) q;

  if v_actor_role = 'LINE_MAN' then
    select candidate_json
      into v_actor_lm
    from (
      select to_jsonb(c) as candidate_json
      from public.rr_upm_worker_candidates_v740('LINE_MAN',null) c
    ) q
    where
      nullif(candidate_json->>'auth_user_id','') = auth.uid()::text
      or nullif(candidate_json->>'user_id','') = auth.uid()::text
      or nullif(candidate_json->>'worker_id','') = nullif(v_profile_json->>'worker_id','')
      or nullif(candidate_json->>'worker_id','') = nullif(v_profile_json->>'person_id','')
      or nullif(candidate_json->>'person_id','') = nullif(v_profile_json->>'worker_id','')
      or nullif(candidate_json->>'person_id','') = nullif(v_profile_json->>'person_id','')
      or (
        nullif(candidate_json->>'worker_code','') is not null
        and nullif(candidate_json->>'worker_code','') = nullif(v_profile_json->>'worker_code','')
      )
    order by
      case when nullif(candidate_json->>'auth_user_id','') = auth.uid()::text then 0 else 1 end,
      case when nullif(candidate_json->>'user_id','') = auth.uid()::text then 0 else 1 end
    limit 1;

    if v_actor_lm is null then
      raise exception 'Your login role is LINE_MAN, but your active Line Man worker mapping is missing.';
    end if;
  end if;

  return jsonb_build_object(
    'version','V770_ALTER_RECEIVER_ROUTING',
    'canonical_lot_id',p_canonical_lot_id,
    'actor_role',v_actor_role,
    'actor_profile',v_profile_json,
    'actor_line_man',v_actor_lm,
    'auto_assign_self',v_actor_role = 'LINE_MAN',
    'selection_required',v_actor_role <> 'LINE_MAN',
    'assignment_scope','ALTER_JOURNEY_ONLY',
    'line_man_candidates',v_candidates
  );
end
$function$;

-- Replace only the compatibility/routing wrapper. Core responsibility logic is untouched.
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
  v_result jsonb;

  v_profile public.rr_user_profiles%rowtype;
  v_profile_json jsonb := '{}'::jsonb;
  v_actor_role text := '';
  v_actor_lm_id uuid := null;
  v_effective_lm_id uuid := p_line_man_id;
  v_receiver_json jsonb := null;
  v_receiver_name text := null;
  v_actor_self_assigned boolean := false;
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

  if v_stage = 'ALTER_FILL' then
    select p.*
      into v_profile
    from public.rr_user_profiles p
    where p.auth_user_id = auth.uid()
      and coalesce(p.is_active,false)
      and upper(coalesce(p.access_status,'ACTIVE')) = 'ACTIVE'
    limit 1;

    if not found then
      raise exception 'Active User Directory profile required.';
    end if;

    v_profile_json := to_jsonb(v_profile);
    v_actor_role := upper(
      regexp_replace(
        coalesce(v_profile_json->>'role_code',v_profile_json->>'role',''),
        '[^A-Za-z0-9]+','_','g'
      )
    );

    -- A logged-in active Line Man always receives their own Alter Fill.
    if v_actor_role = 'LINE_MAN' then
      select nullif(coalesce(candidate_json->>'worker_id',candidate_json->>'person_id',''),'')::uuid,
             candidate_json
        into v_actor_lm_id, v_receiver_json
      from (
        select to_jsonb(c) as candidate_json
        from public.rr_upm_worker_candidates_v740('LINE_MAN',null) c
      ) q
      where
        nullif(candidate_json->>'auth_user_id','') = auth.uid()::text
        or nullif(candidate_json->>'user_id','') = auth.uid()::text
        or nullif(candidate_json->>'worker_id','') = nullif(v_profile_json->>'worker_id','')
        or nullif(candidate_json->>'worker_id','') = nullif(v_profile_json->>'person_id','')
        or nullif(candidate_json->>'person_id','') = nullif(v_profile_json->>'worker_id','')
        or nullif(candidate_json->>'person_id','') = nullif(v_profile_json->>'person_id','')
        or (
          nullif(candidate_json->>'worker_code','') is not null
          and nullif(candidate_json->>'worker_code','') = nullif(v_profile_json->>'worker_code','')
        )
      order by
        case when nullif(candidate_json->>'auth_user_id','') = auth.uid()::text then 0 else 1 end,
        case when nullif(candidate_json->>'user_id','') = auth.uid()::text then 0 else 1 end
      limit 1;

      if v_actor_lm_id is null then
        raise exception 'Your login role is LINE_MAN, but your active Line Man worker mapping is missing.';
      end if;

      v_effective_lm_id := v_actor_lm_id;
      v_actor_self_assigned := true;
    else
      if v_effective_lm_id is null then
        raise exception 'Select the active Line Man who will receive this Alter journey.';
      end if;
    end if;

    -- Final server-side candidate validation.
    if v_receiver_json is null then
      select to_jsonb(c)
        into v_receiver_json
      from public.rr_upm_worker_candidates_v740('LINE_MAN',null) c
      where c.worker_id = v_effective_lm_id
      limit 1;
    end if;

    if v_receiver_json is null then
      raise exception 'Selected person is not an active Line Man.';
    end if;

    v_receiver_name := coalesce(
      v_receiver_json->>'worker_name',
      v_receiver_json->>'person_name_snapshot',
      v_receiver_json->>'name',
      'Selected Line Man'
    );
  end if;

  -- Preserve V766 support for an already submitted/completed source department.
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

      update public.rr_upm_work_assignments_v8
      set status = 'IN_PROGRESS'
      where id = v_history_assignment.id;

      if not (v_history_assignment.id = any(v_reopened_ids)) then
        v_reopened_ids := array_append(v_reopened_ids,v_history_assignment.id);
      end if;
    end if;
  end loop;

  v_result := public.rr_upm_alter_stage_v740_core(
    p_stage,
    p_canonical_lot_id,
    p_department_code,
    p_rows,
    coalesce(p_evidence_urls,'[]'::jsonb),
    coalesce(p_physical_confirmed,false),
    v_effective_lm_id,
    concat_ws(
      ' | ',
      nullif(trim(coalesce(p_remarks,'')),''),
      case when v_stage = 'ALTER_FILL' then
        'ALTER RECEIVER LM: ' || coalesce(v_receiver_name,'') ||
        ' · JOURNEY ONLY' ||
        case when v_actor_self_assigned then ' · SELF AUTO-ASSIGNED' else ' · SELECTED BY SENDER' end
      else null end
    )
  );

  if cardinality(v_reopened_ids) > 0 then
    update public.rr_upm_work_assignments_v8
    set status = 'COMPLETED'
    where id = any(v_reopened_ids)
      and status = 'IN_PROGRESS';
  end if;

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'compatibility_version','V770_ALTER_RECEIVER_ROUTING',
    'historical_assignments_used',cardinality(v_reopened_ids),
    'alter_receiver_line_man_id',v_effective_lm_id,
    'alter_receiver_line_man_name',v_receiver_name,
    'actor_self_assigned',v_actor_self_assigned,
    'assignment_scope','ALTER_JOURNEY_ONLY',
    'alert_target_line_man_id',v_effective_lm_id
  );
exception
  when others then
    raise;
end
$function$;

revoke all on function public.rr_upm_alter_receiver_context_v770(text) from public;
grant execute on function public.rr_upm_alter_receiver_context_v770(text) to authenticated;

revoke all on function public.rr_upm_alter_stage_v740(
  text,text,text,jsonb,jsonb,boolean,uuid,text
) from public;
grant execute on function public.rr_upm_alter_stage_v740(
  text,text,text,jsonb,jsonb,boolean,uuid,text
) to authenticated;

commit;
