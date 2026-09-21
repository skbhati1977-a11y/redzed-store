-- TEST71 Checkpoint 4 recovery hardening.
-- Keeps the V400 salary/Printing/costing and V760 rate engines canonical while
-- enforcing Super Admin-only private costing at every client boundary.

begin;

create or replace function public.rr_costing_redact_payload_v401(
  p_value jsonb,
  p_allow_private boolean,
  p_allow_rate boolean
) returns jsonb
language plpgsql
immutable
set search_path=public
as $function$
declare
  v_kind text:=jsonb_typeof(p_value);
  v_key text;
  v_item jsonb;
  v_out jsonb;
begin
  if p_value is null then return null; end if;
  if v_kind='array' then
    select coalesce(jsonb_agg(public.rr_costing_redact_payload_v401(x,p_allow_private,p_allow_rate)),'[]'::jsonb)
      into v_out from jsonb_array_elements(p_value) x;
    return v_out;
  elsif v_kind<>'object' then
    return p_value;
  end if;

  v_out:='{}'::jsonb;
  for v_key,v_item in select key,value from jsonb_each(p_value)
  loop
    if not p_allow_private and (
      lower(v_key) ~ '(^|_)(cost|costs|salary|salaries|wage|wages|payroll|margin|reserve|quota|rrq|material|materials|chemical|cloth|box|recovery|price|value|profit|loss|pnl|amount)($|_)'
      or lower(v_key) in (
        'cloth','box','printing','materials_resolved','material_breakdown',
        'department_breakdown','company_loss','team_salary','weighted_rate',
        'weighted_rate_per_kg','standard_rate','standard_source','rate_per_colour',
        'can_view_standard','can_change_standard','can_change_margin'
      )
      or lower(v_key) like '%weighted_rate%'
    ) then
      continue;
    end if;
    if not p_allow_rate and (
      lower(v_key) in (
        'rate','rates','actual_rate','department_rates','filled_rate','source_rate',
        'final_rate','sale_rate','suggested_rate','admin_suggested_rate',
        'sales_suggested_rate','approved_rate','request_token','rate_filled_by',
        'rate_filled_by_name','rate_filled_at'
      )
      or lower(v_key) ~ '(^|_)rate($|_)'
      or lower(v_key) like '%_rate_%'
    ) then
      continue;
    end if;
    v_out:=v_out||jsonb_build_object(
      v_key,
      public.rr_costing_redact_payload_v401(v_item,p_allow_private,p_allow_rate)
    );
  end loop;
  return v_out;
end
$function$;

-- Legacy UPM form versions are still transitively used by the current form.
-- Keep their engines intact, but sanitize every direct and downstream response.
create or replace function public.rr_upm_redact_form_v401(
  p_payload jsonb,
  p_department_code text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(p_department_code);
  v_private boolean;
  v_rate boolean;
  v_out jsonb;
begin
  v_private:=coalesce((v_scope->>'can_view_private_cost')::boolean,false);
  v_rate:=coalesce((v_scope->>'can_edit_rate')::boolean,false);
  v_out:=public.rr_costing_redact_payload_v401(
    coalesce(p_payload,'{}'::jsonb),v_private,v_rate
  );
  return v_out||jsonb_build_object(
    'is_owner',v_private,
    'is_super_admin',v_private,
    'can_view_private_cost',v_private,
    'can_view_standard',v_private,
    'can_change_standard',v_private,
    'can_change_margin',v_private,
    'can_edit_rate',v_rate,
    'security',case when v_private then 'SUPER_ADMIN_PRIVATE_COST'
      else 'PRIVATE_COST_OMITTED' end
  );
end
$function$;

revoke all on function public.rr_upm_redact_form_v401(jsonb,text)
  from public,anon,authenticated;
grant execute on function public.rr_upm_redact_form_v401(jsonb,text)
  to service_role;

alter function public.rr_upm_universal_form_v723(text,text)
  rename to rr_upm_universal_form_v723_core_v401;
create function public.rr_upm_universal_form_v723(
  p_canonical_lot_id text,
  p_department_code text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
begin
  return public.rr_upm_redact_form_v401(
    public.rr_upm_universal_form_v723_core_v401(
      p_canonical_lot_id,p_department_code
    ),p_department_code
  );
end
$function$;

alter function public.rr_upm_universal_form_v724(text,text)
  rename to rr_upm_universal_form_v724_core_v401;
create function public.rr_upm_universal_form_v724(
  p_canonical_lot_id text,
  p_department_code text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
begin
  return public.rr_upm_redact_form_v401(
    public.rr_upm_universal_form_v724_core_v401(
      p_canonical_lot_id,p_department_code
    ),p_department_code
  );
end
$function$;

alter function public.rr_upm_universal_form_v725(text,text)
  rename to rr_upm_universal_form_v725_core_v401;
create function public.rr_upm_universal_form_v725(
  p_canonical_lot_id text,
  p_department_code text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
begin
  return public.rr_upm_redact_form_v401(
    public.rr_upm_universal_form_v725_core_v401(
      p_canonical_lot_id,p_department_code
    ),p_department_code
  );
end
$function$;

alter function public.rr_upm_universal_form_v726(text,text)
  rename to rr_upm_universal_form_v726_core_v401;
create function public.rr_upm_universal_form_v726(
  p_canonical_lot_id text,
  p_department_code text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
begin
  return public.rr_upm_redact_form_v401(
    public.rr_upm_universal_form_v726_core_v401(
      p_canonical_lot_id,p_department_code
    ),p_department_code
  );
end
$function$;

alter function public.rr_upm_get_universal_lot_context_v721(text,text)
  rename to rr_upm_get_universal_lot_context_v721_core_v401;
create function public.rr_upm_get_universal_lot_context_v721(
  p_canonical_lot_id text default null,
  p_lot_no text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
begin
  return public.rr_upm_redact_form_v401(
    public.rr_upm_get_universal_lot_context_v721_core_v401(
      p_canonical_lot_id,p_lot_no
    ),null
  );
end
$function$;

alter function public.rr_upm_submit_summary_v2(text,text,text,text)
  rename to rr_upm_submit_summary_v2_core_v401;
create function public.rr_upm_submit_summary_v2(
  p_canonical_lot_id text,
  p_department_code text,
  p_colour_code text,
  p_size_code text default 'ALL'
) returns table(
  lot_no text,art_no text,item_name text,cutting_qty numeric,
  alter_qty numeric,repair_assigned_qty numeric,
  repair_submitted_qty numeric,repair_accepted_qty numeric,
  re_repair_pending_qty numeric,remake_qty numeric,
  remake_completed_qty numeric,damage_qty numeric,pending_alter_qty numeric,
  already_submitted_qty numeric,submit_ready_qty numeric,actual_rate numeric,
  rate_filled_by text,image_required boolean
)
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(p_department_code);
  v_rate boolean;
begin
  v_rate:=coalesce((v_scope->>'can_edit_rate')::boolean,false);
  return query
  select s.lot_no,s.art_no,s.item_name,s.cutting_qty,s.alter_qty,
    s.repair_assigned_qty,s.repair_submitted_qty,s.repair_accepted_qty,
    s.re_repair_pending_qty,s.remake_qty,s.remake_completed_qty,s.damage_qty,
    s.pending_alter_qty,s.already_submitted_qty,s.submit_ready_qty,
    case when v_rate then s.actual_rate else null::numeric end,
    case when v_rate then s.rate_filled_by else null::text end,
    s.image_required
  from public.rr_upm_submit_summary_v2_core_v401(
    p_canonical_lot_id,p_department_code,p_colour_code,p_size_code
  ) s;
end
$function$;

revoke all on function public.rr_costing_redact_payload_v401(jsonb,boolean,boolean)
  from public,anon,authenticated;
grant execute on function public.rr_costing_redact_payload_v401(jsonb,boolean,boolean)
  to service_role;

create or replace function public.rr_costing_user_scope_v760(
  p_department_code text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_identity jsonb;
  v_role text;
  v_code text;
  v_departments text[];
  v_private boolean;
  v_rate_editor boolean;
  v_own_department boolean:=false;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  v_identity:=public.rr_upm_effective_identity_v200();
  v_role:=upper(coalesce(v_identity->>'resolved_role',v_identity->>'role_code','WORKER'));
  v_code:=public.rr_costing_canonical_department_v760(p_department_code);
  select coalesce(array_agg(upper(value)),'{}'::text[])
    into v_departments
  from jsonb_array_elements_text(coalesce(v_identity->'department_codes','[]'::jsonb));
  if coalesce(array_length(v_departments,1),0)=0
     and nullif(v_identity->>'department_code','') is not null then
    v_departments:=array[upper(v_identity->>'department_code')];
  end if;
  v_private:=v_role='SUPER_ADMIN';
  v_rate_editor:=v_role in ('OWNER','SUPER_ADMIN','ADMIN','MANAGER');
  if p_department_code is not null then
    v_own_department:=v_code=any(v_departments);
  end if;
  return jsonb_build_object(
    'role',lower(v_role),
    'effective_role',v_role,
    'is_owner',v_private,
    'is_super_admin',v_private,
    'can_view_private_cost',v_private,
    'full_rate_access',v_rate_editor,
    'own_department_access',v_own_department,
    'can_view_material',v_private,
    'can_edit_material',v_private,
    'can_edit_owner_margin',v_private,
    'can_edit_rate',v_rate_editor,
    'on_behalf',coalesce((v_identity->>'on_behalf')::boolean,false)
  );
end
$function$;

create or replace function public.rr_printing_actor_scope_v400(p_assignment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  a record;
  i jsonb;
  r text;
  worker_ok boolean;
  privileged boolean;
begin
  select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment_id;
  if not found
     or public.rr_costing_canonical_department_v760(a.department_code)<>'PRINTING' then
    raise exception 'Printing assignment not found.';
  end if;
  i:=public.rr_upm_effective_identity_v200();
  r:=upper(coalesce(i->>'resolved_role',i->>'role_code','WORKER'));
  privileged:=r in('OWNER','SUPER_ADMIN','ADMIN','MANAGER');
  worker_ok:=public.rr_canonical_worker_id_v264((i->>'worker_id')::uuid)
             =public.rr_canonical_worker_id_v264(a.worker_id);
  if not privileged and not worker_ok then
    raise exception 'Printing assignment permission denied.';
  end if;
  return jsonb_build_object(
    'role',r,
    'private_cost',r='SUPER_ADMIN',
    'worker_match',worker_ok,
    'identity',i,
    'canonical_lot_id',a.canonical_lot_id,
    'worker_id',a.worker_id
  );
end
$function$;

-- One writer, one event. An identical retry completes any pending request but
-- does not update the rate row or append another rate log entry.
create or replace function public.rr_upm_set_department_rate_v760(
  p_canonical_lot_id text,
  p_department_code text,
  p_actual_rate numeric,
  p_request_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  l record;
  code text;
  scope jsonb;
  identity jsonb;
  actor_name text;
  old_rate numeric;
  target_rate numeric:=round(p_actual_rate,4);
  row_rate public.rr_upm_department_rates_v2%rowtype;
  request_row public.rr_upm_rate_requests_v760%rowtype;
begin
  if p_actual_rate is null or p_actual_rate<0 then
    raise exception 'Actual Rate zero ya usse zyada honi chahiye.';
  end if;
  select * into l from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Production Lot nahi mila.'; end if;

  code:=public.rr_costing_canonical_department_v760(p_department_code);
  scope:=public.rr_costing_user_scope_v760(code);
  if not coalesce((scope->>'can_edit_rate')::boolean,false) then
    raise exception 'Only eligible Manager/Admin/Owner/Super Admin can fill Actual Rate.';
  end if;

  if p_request_id is not null then
    select * into request_row from public.rr_upm_rate_requests_v760
    where id=p_request_id
      and canonical_lot_id=p_canonical_lot_id
      and department_code=code
      and request_status in('PENDING','OPENED','RATE_FILLED')
      and expires_at>now()
    for update;
    if not found then raise exception 'Active canonical rate request not found.'; end if;
  end if;

  identity:=public.rr_upm_effective_identity_v200();
  actor_name:=coalesce(identity->>'display_name',auth.uid()::text);
  select * into row_rate
  from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=code
  order by updated_at desc
  limit 1
  for update;
  old_rate:=row_rate.actual_rate;

  if found and old_rate=target_rate then
    perform set_config('app.rr_lot_department_rate_group_sync','1',true);
    update public.rr_upm_work_assignments_v8
    set actual_rate=target_rate,rate_filled_by=auth.uid(),
        rate_filled_by_name=actor_name,rate_filled_at=coalesce(rate_filled_at,now()),
        updated_at=now()
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(department_code)=code
      and status not in('CANCELLED','CANCELED','VOID','REJECTED')
      and actual_rate is distinct from target_rate;
    perform set_config('app.rr_lot_department_rate_group_sync','',true);
    update public.rr_upm_rate_requests_v760
    set request_status='COMPLETED',filled_rate=target_rate,filled_at=now(),
        filled_by=auth.uid(),filled_by_name=actor_name,completed_at=now(),archived_at=now()
    where canonical_lot_id=p_canonical_lot_id and department_code=code
      and request_status in('PENDING','OPENED','RATE_FILLED');
    return jsonb_build_object(
      'ok',true,'version','V401_CANONICAL_RATE_IDEMPOTENT',
      'canonical_lot_id',p_canonical_lot_id,'lot_no',l.lot_no,
      'department_code',code,
      'department_name',public.rr_costing_department_display_v760(code),
      'actual_rate',old_rate,'rate_id',row_rate.id,
      'filled_by_name',actor_name,'duplicate_blocked',true
    );
  end if;

  delete from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=code
    and department_code<>code;
  insert into public.rr_upm_department_rates_v2(
    canonical_lot_id,lot_no,department_code,actual_rate,
    filled_by,filled_by_name,updated_by,updated_by_name,updated_at
  ) values(
    p_canonical_lot_id,l.lot_no,code,target_rate,
    auth.uid(),actor_name,auth.uid(),actor_name,now()
  )
  on conflict(canonical_lot_id,department_code) do update set
    actual_rate=excluded.actual_rate,
    updated_by=auth.uid(),updated_by_name=actor_name,updated_at=now()
  returning * into row_rate;
  insert into public.rr_upm_department_rate_log_v2(
    rate_id,old_rate,new_rate,changed_by_name
  ) values(row_rate.id,old_rate,target_rate,actor_name);
  perform set_config('app.rr_lot_department_rate_group_sync','1',true);
  update public.rr_upm_work_assignments_v8
  set actual_rate=target_rate,rate_filled_by=auth.uid(),
      rate_filled_by_name=actor_name,rate_filled_at=now(),updated_at=now()
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=code
    and status not in('CANCELLED','CANCELED','VOID','REJECTED')
    and actual_rate is distinct from target_rate;
  perform set_config('app.rr_lot_department_rate_group_sync','',true);
  update public.rr_upm_rate_requests_v760
  set request_status='COMPLETED',filled_rate=target_rate,filled_at=now(),
      filled_by=auth.uid(),filled_by_name=actor_name,completed_at=now(),archived_at=now()
  where canonical_lot_id=p_canonical_lot_id and department_code=code
    and request_status in('PENDING','OPENED','RATE_FILLED');
  return jsonb_build_object(
    'ok',true,'version','V401_CANONICAL_RATE_IDEMPOTENT',
    'canonical_lot_id',p_canonical_lot_id,'lot_no',l.lot_no,
    'department_code',code,
    'department_name',public.rr_costing_department_display_v760(code),
    'actual_rate',row_rate.actual_rate,'rate_id',row_rate.id,
    'filled_by_name',actor_name,'duplicate_blocked',false
  );
end
$function$;

create or replace function public.rr_upm_set_department_rate_v2(
  p_canonical_lot_id text,
  p_department_code text,
  p_actual_rate numeric
) returns public.rr_upm_department_rates_v2
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_code text:=public.rr_costing_canonical_department_v760(p_department_code);
  v_row public.rr_upm_department_rates_v2%rowtype;
begin
  perform public.rr_upm_set_department_rate_v760(
    p_canonical_lot_id,v_code,p_actual_rate,null
  );
  select * into strict v_row from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id and department_code=v_code;
  return v_row;
end
$function$;

create or replace function public.rr_upm_bulk_set_department_rates_v189(
  p_canonical_lot_id text,
  p_rates jsonb,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(null);
  v_item jsonb;
  v_dept text;
  v_rate numeric;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
  v_saved jsonb:='[]'::jsonb;
  v_skipped jsonb:='[]'::jsonb;
  v_result jsonb;
  v_salaried numeric;
  v_allowed constant text[]:=array[
    'CUTTING','PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK',
    'FOLDING','KAAJ_BUTTON','KAJ_BUTTON','TEAK_TANKI','TANKI_TACK',
    'THREAD_CUT','QC','PRESS','PACKING','DISPATCH','DESPATCH'
  ];
begin
  if not coalesce((v_scope->>'can_edit_rate')::boolean,false) then
    raise exception 'Canonical rate editor permission denied.';
  end if;
  if coalesce(jsonb_typeof(p_rates),'')<>'array' or jsonb_array_length(p_rates)=0 then
    raise exception 'At least one Department rate required.';
  end if;
  if v_reason is null or length(v_reason)<5 then
    raise exception 'Rate save reason minimum 5 characters required.';
  end if;

  for v_item in select value from jsonb_array_elements(p_rates)
  loop
    v_dept:=public.rr_costing_canonical_department_v760(v_item->>'department_code');
    v_rate:=nullif(v_item->>'actual_rate','')::numeric;
    if not (v_dept=any(v_allowed)) then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'department_code',v_dept,'reason','OUTSIDE_CUT_TO_DESPATCH_SCOPE'));
      continue;
    end if;
    if coalesce(v_rate,0)<=0 then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'department_code',v_dept,'reason','RATE_REQUIRED'));
      continue;
    end if;
    select coalesce(max(salaried_labor_cost),0) into v_salaried
    from public.rr_upm_department_labor_cost_v9160
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(department_code)=v_dept;
    if coalesce(v_salaried,0)>0 then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'department_code',v_dept,'reason','SALARIED_TEAM_COST_AUTO'));
      continue;
    end if;
    v_result:=public.rr_upm_set_department_rate_v760(
      p_canonical_lot_id,v_dept,v_rate,null
    );
    v_saved:=v_saved||jsonb_build_array(v_result);
  end loop;
  return jsonb_build_object(
    'ok',true,'version','V401_ONE_CANONICAL_RATE_EVENT',
    'canonical_lot_id',p_canonical_lot_id,'saved',v_saved,'skipped',v_skipped,
    'saved_count',jsonb_array_length(v_saved),
    'skipped_count',jsonb_array_length(v_skipped)
  );
end
$function$;

create or replace function public.rr_upm_first_submit_rate_gate_v760(
  p_canonical_lot_id text,
  p_department_code text,
  p_colour_code text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;
  v_code text;
  v_rate numeric;
  v_standard jsonb;
  v_request public.rr_upm_rate_requests_v760%rowtype;
  v_name text;
  v_first_submit boolean;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  select * into v_lot from public.rr_upm_lot_registry
  where canonical_lot_id=p_canonical_lot_id limit 1;
  if not found then raise exception 'Lot nahi mila.'; end if;
  v_code:=public.rr_costing_canonical_department_v760(p_department_code);
  select actual_rate into v_rate from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=v_code
  order by updated_at desc limit 1;
  select not exists(
    select 1 from public.rr_upm_work_assignments_v8
    where canonical_lot_id=p_canonical_lot_id
      and public.rr_costing_canonical_department_v760(department_code)=v_code
      and status='COMPLETED'
  ) into v_first_submit;
  if coalesce(v_rate,0)>0 or not v_first_submit then
    return jsonb_build_object(
      'ok',true,'allowed',true,'first_submit',v_first_submit,
      'department_code',v_code,
      'rate_status',case when coalesce(v_rate,0)>0 then 'RESOLVED' else 'NOT_REQUIRED_AFTER_FIRST_SUBMIT' end
    );
  end if;
  v_standard:=public.rr_costing_standard_rate_v760(v_lot.art_no,v_code);
  v_name:=coalesce(public.rr_up_user_context_v2()->>'display_name',auth.uid()::text);
  insert into public.rr_upm_rate_requests_v760(
    canonical_lot_id,lot_no,department_code,colour_code,
    requested_by,requested_by_name,metadata
  ) values(
    p_canonical_lot_id,v_lot.lot_no,v_code,upper(p_colour_code),
    auth.uid(),v_name,
    jsonb_build_object(
      'art_no',v_lot.art_no,'item_name',v_lot.item_name,
      'standard_rate',v_standard->'standard_rate',
      'standard_source',v_standard->>'source',
      'request_purpose','FIRST_SUBMIT_RATE_GATE'
    )
  )
  on conflict(canonical_lot_id,department_code)
    where request_status in ('PENDING','OPENED','RATE_FILLED')
  do update set
    colour_code=excluded.colour_code,
    requested_by=auth.uid(),requested_by_name=v_name,requested_at=now(),
    expires_at=now()+interval '24 hours',
    metadata=public.rr_upm_rate_requests_v760.metadata||excluded.metadata
  returning * into v_request;
  return jsonb_build_object(
    'ok',true,'allowed',false,'first_submit',true,
    'reason','ACTUAL_RATE_REQUIRED',
    'message','First Submit se pehle Actual Rate fill karna mandatory hai.',
    'canonical_lot_id',p_canonical_lot_id,'lot_no',v_lot.lot_no,
    'colour_code',upper(p_colour_code),'department_code',v_code,
    'department_name',public.rr_costing_department_display_v760(v_code),
    'request_id',v_request.id,'expires_at',v_request.expires_at,
    'rate_status','PENDING'
  );
end
$function$;

create or replace function public.rr_upm_submit_gate_v277(
  p_canonical_lot_id text,
  p_department_code text,
  p_colour_code text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  g jsonb;
  d text:=public.rr_costing_canonical_department_v760(p_department_code);
begin
  g:=public.rr_upm_first_submit_rate_gate_v760(
    p_canonical_lot_id,d,p_colour_code
  );
  if not coalesce((g->>'allowed')::boolean,false) then
    return g||jsonb_build_object(
      'version','V401_CANONICAL_SUBMIT_GATE',
      'next_action','FULFIL_RATE_ALERT'
    );
  end if;
  return jsonb_build_object(
    'ok',true,'allowed',true,'version','V401_CANONICAL_SUBMIT_GATE',
    'department_code',d,'rate_status',g->>'rate_status',
    'next_action','SELECT_RECEIVER','receivers',
    case when d='PRESS' then
      (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
       from public.rr_upm_worker_list_v8_4('PACKING') x)
    else
      (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
       from public.rr_upm_worker_candidates_v740('LINE_MAN',d) x)
    end
  );
end
$function$;

create or replace function public.rr_upm_submit_with_actual_cost_gate_v9300(
  p_canonical_lot_id text,
  p_department_code text,
  p_rows jsonb,
  p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_code text:=public.rr_costing_canonical_department_v760(p_department_code);
  v_core text:=public.rr_upm_core_department_v9077(p_department_code);
  v_rate numeric;
  v_result jsonb;
  v_bridge jsonb;
  v_row jsonb;
  v_actor_worker uuid:=public.rr_upm_current_worker_id_v9112();
  v_a public.rr_upm_work_assignments_v8%rowtype;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_core<>'PACKING' then
    raise exception 'Upstream departments must use selected Receiver Submit/Count.';
  end if;
  if v_actor_worker is null then
    raise exception 'Effective Packing worker identity is required.';
  end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then
    raise exception 'Select at least one Packing colour.';
  end if;
  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    select * into v_a from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and public.rr_upm_core_department_v9077(a.department_code)='PACKING'
      and upper(a.colour_code)=upper(v_row->>'colour_code')
      and a.status='IN_PROGRESS'
    order by a.assigned_at desc limit 1 for update;
    if not found or v_a.worker_id is distinct from v_actor_worker then
      raise exception 'Only the assigned Packer can complete Colour %.',v_row->>'colour_code';
    end if;
    if not exists(
      select 1 from public.rr_upm_assignment_receipts_v9112 r
      where r.assignment_id=v_a.id and r.status='CONFIRMED'
    ) then
      raise exception 'Press handover Accept & Count is required before Packing completion.';
    end if;
  end loop;
  select actual_rate into v_rate from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code)=v_code
  order by updated_at desc limit 1;
  if coalesce(v_rate,0)<=0 then
    raise exception 'Actual Cost / PCS is mandatory before Packing submit.';
  end if;
  v_result:=public.rr_upm_submit_colours_v9111(
    p_canonical_lot_id,'PACKING',p_rows,
    concat_ws(' · ',p_remarks,'V204 PACKING WORKER COMPLETE')
  );
  v_bridge:=public.rr_fg_sync_packing_actuals_from_upm_v9311(p_canonical_lot_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'version','V401_PACKING_ONLY_COMPLETE',
    'actual_cost_gate','PASSED','rate_status','RESOLVED',
    'costing_department_code',v_code,'fg_packing_bridge',v_bridge,
    'workflow_terminal',false,'terminal_stage','FINAL_DESPATCH_PENDING'
  );
end
$function$;

create or replace function public.rr_upm_rate_assignment_list_v401(
  p_limit integer default 5000
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(null);
  v_rows jsonb;
begin
  if not coalesce((v_scope->>'can_edit_rate')::boolean,false) then
    raise exception 'Canonical rate editor permission required.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.assigned_at desc),'[]'::jsonb)
    into v_rows
  from (
    select id,canonical_lot_id,lot_no,department_code,worker_id,worker_code,
      worker_name_snapshot,colour_code,colour_name,assigned_qty,status,actual_rate,
      rate_filled_by_name,rate_filled_at,assigned_at
    from public.rr_upm_work_assignments_v8
    order by assigned_at desc
    limit least(greatest(coalesce(p_limit,5000),1),5000)
  ) x;
  return v_rows;
end
$function$;

create or replace function public.rr_test_checkpoint4_rate_authority_v401()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $function$
declare
  v_profile record;
  v_identity jsonb:=public.rr_upm_effective_identity_v200();
  v_role text;
  v_rate_row public.rr_upm_department_rates_v2%rowtype;
  v_old numeric;
  v_new numeric;
  v_first jsonb;
  v_second jsonb;
  v_log_before integer;
  v_log_during integer;
  v_log_after integer;
  v_rate_after numeric;
begin
  select role_code,full_name into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if lower(coalesce(v_profile.role_code,''))<>'super_admin'
     or lower(coalesce(v_profile.full_name,'')) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required';
  end if;
  v_role:=upper(coalesce(v_identity->>'resolved_role',v_identity->>'role_code',''));
  if v_role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER') then
    raise exception 'Act As an eligible canonical rate editor before running fixture';
  end if;
  select * into v_rate_row from public.rr_upm_department_rates_v2
  where actual_rate>0 order by updated_at desc limit 1;
  if not found then raise exception 'Positive canonical rate fixture required'; end if;
  v_old:=v_rate_row.actual_rate;
  v_new:=round(v_old+0.1379,4);
  select count(*) into v_log_before from public.rr_upm_department_rate_log_v2
  where rate_id=v_rate_row.id;
  begin
    v_first:=public.rr_upm_set_department_rate_v760(
      v_rate_row.canonical_lot_id,v_rate_row.department_code,v_new,null
    );
    v_second:=public.rr_upm_set_department_rate_v760(
      v_rate_row.canonical_lot_id,v_rate_row.department_code,v_new,null
    );
    select count(*) into v_log_during from public.rr_upm_department_rate_log_v2
    where rate_id=v_rate_row.id;
    raise exception '__TEST71_CP4_RATE_ROLLBACK__';
  exception when raise_exception then
    if sqlerrm<>'__TEST71_CP4_RATE_ROLLBACK__' then raise; end if;
  end;
  select count(*) into v_log_after from public.rr_upm_department_rate_log_v2
  where rate_id=v_rate_row.id;
  select actual_rate into v_rate_after from public.rr_upm_department_rates_v2
  where id=v_rate_row.id;
  return jsonb_build_object(
    'effective_role',v_role,'first',v_first,'second',v_second,
    'single_event_during',v_log_during-v_log_before=1,
    'log_delta_during',v_log_during-v_log_before,
    'rolled_back',v_log_after=v_log_before and v_rate_after=v_old,
    'persisted',not(v_log_after=v_log_before and v_rate_after=v_old)
  );
end
$function$;

-- Actual-rate editors may read the canonical process rate. Only Super Admin
-- may read or write the material-cost inputs behind that rate.
alter function public.rr_costing_department_input_context_v290(text,text,text)
  rename to rr_costing_department_input_context_v290_core_v401;
create function public.rr_costing_department_input_context_v290(
  p_canonical_lot_id text,
  p_department_code text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(p_department_code);
  v_private boolean;
  v_rate boolean;
  v_payload jsonb;
begin
  v_private:=coalesce((v_scope->>'can_view_private_cost')::boolean,false);
  v_rate:=coalesce((v_scope->>'can_edit_rate')::boolean,false);
  if not v_rate then
    raise exception 'Canonical rate editor permission required.';
  end if;
  v_payload:=public.rr_costing_department_input_context_v290_core_v401(
    p_canonical_lot_id,p_department_code,p_data_mode
  );
  return public.rr_costing_redact_payload_v401(v_payload,v_private,true)
    ||jsonb_build_object(
      'can_edit_rate',true,
      'can_edit_material',v_private,
      'security',case when v_private then 'SUPER_ADMIN_PRIVATE_COST'
        else 'PRIVATE_COST_OMITTED' end
    );
end
$function$;

alter function public.rr_upm_save_cost_input_v9300(
  text,text,text,numeric,text,numeric,numeric,numeric,text,text
) rename to rr_upm_save_cost_input_v9300_core_v401;
create function public.rr_upm_save_cost_input_v9300(
  p_canonical_lot_id text,
  p_department_code text,
  p_input_type text,
  p_qty numeric,
  p_unit text default 'PCS',
  p_weighted_rate numeric default 0,
  p_gsm numeric default null,
  p_roll_width_m numeric default null,
  p_source_note text default null,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(p_department_code);
begin
  if not coalesce((v_scope->>'can_edit_material')::boolean,false) then
    raise exception 'Only Super Admin may change private material costing.';
  end if;
  return public.rr_upm_save_cost_input_v9300_core_v401(
    p_canonical_lot_id,p_department_code,p_input_type,p_qty,p_unit,
    p_weighted_rate,p_gsm,p_roll_width_m,p_source_note,p_data_mode
  );
end
$function$;

alter function public.rr_costing_rate_alert_detail_v284(uuid)
  rename to rr_costing_rate_alert_detail_v284_core_v401;
create function public.rr_costing_rate_alert_detail_v284(
  p_request_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(null);
begin
  if not coalesce((v_scope->>'can_edit_rate')::boolean,false) then
    raise exception 'Canonical rate editor permission required.';
  end if;
  return public.rr_costing_redact_payload_v401(
    public.rr_costing_rate_alert_detail_v284_core_v401(p_request_id),
    coalesce((v_scope->>'can_view_private_cost')::boolean,false),true
  );
end
$function$;

alter function public.rr_costing_rate_alerts_current_v286(text)
  rename to rr_costing_rate_alerts_current_v286_core_v401;
create function public.rr_costing_rate_alerts_current_v286(
  p_canonical_lot_id text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(null);
begin
  if not coalesce((v_scope->>'can_edit_rate')::boolean,false) then
    raise exception 'Canonical rate editor permission required.';
  end if;
  return public.rr_costing_redact_payload_v401(
    public.rr_costing_rate_alerts_current_v286_core_v401(p_canonical_lot_id),
    coalesce((v_scope->>'can_view_private_cost')::boolean,false),true
  );
end
$function$;

alter function public.rr_costing_rate_lot_open_v284(text)
  rename to rr_costing_rate_lot_open_v284_core_v401;
create function public.rr_costing_rate_lot_open_v284(
  p_canonical_lot_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(null);
begin
  if not coalesce((v_scope->>'can_edit_rate')::boolean,false) then
    raise exception 'Canonical rate editor permission required.';
  end if;
  return public.rr_costing_redact_payload_v401(
    public.rr_costing_rate_lot_open_v284_core_v401(p_canonical_lot_id),
    coalesce((v_scope->>'can_view_private_cost')::boolean,false),true
  );
end
$function$;

-- Margin and standard-rate maintenance are private-cost operations.
alter function public.rr_upm_set_owner_margin_v723(numeric,text)
  rename to rr_upm_set_owner_margin_v723_core_v401;
create function public.rr_upm_set_owner_margin_v723(
  p_amount numeric,
  p_reason text
) returns public.rr_upm_owner_margin_v723
language plpgsql
security definer
set search_path=public
as $function$
begin
  if not coalesce((public.rr_costing_user_scope_v760(null)
      ->>'can_edit_owner_margin')::boolean,false) then
    raise exception 'Only Super Admin may change private margin.';
  end if;
  return public.rr_upm_set_owner_margin_v723_core_v401(p_amount,p_reason);
end
$function$;

alter function public.rr_upm_set_owner_margin_v726(numeric,text)
  rename to rr_upm_set_owner_margin_v726_core_v401;
create function public.rr_upm_set_owner_margin_v726(
  p_amount numeric,
  p_reason text default null
) returns public.rr_upm_owner_margin_v726
language plpgsql
security definer
set search_path=public
as $function$
begin
  if not coalesce((public.rr_costing_user_scope_v760(null)
      ->>'can_edit_owner_margin')::boolean,false) then
    raise exception 'Only Super Admin may change private margin.';
  end if;
  return public.rr_upm_set_owner_margin_v726_core_v401(p_amount,p_reason);
end
$function$;

alter function public.rr_upm_set_standard_rate_v723(text,text,numeric,text)
  rename to rr_upm_set_standard_rate_v723_core_v401;
create function public.rr_upm_set_standard_rate_v723(
  p_canonical_lot_id text,
  p_department_code text,
  p_standard_rate numeric,
  p_reason text default null
) returns public.rr_upm_standard_rates_v723
language plpgsql
security definer
set search_path=public
as $function$
begin
  if not coalesce((public.rr_costing_user_scope_v760(p_department_code)
      ->>'can_view_private_cost')::boolean,false) then
    raise exception 'Only Super Admin may change private standard costing.';
  end if;
  return public.rr_upm_set_standard_rate_v723_core_v401(
    p_canonical_lot_id,p_department_code,p_standard_rate,p_reason
  );
end
$function$;

alter function public.rr_upm_set_standard_rate_v726(text,text,numeric,text)
  rename to rr_upm_set_standard_rate_v726_core_v401;
create function public.rr_upm_set_standard_rate_v726(
  p_canonical_lot_id text,
  p_department_code text,
  p_standard_rate numeric,
  p_reason text default null
) returns public.rr_upm_standard_rates_v726
language plpgsql
security definer
set search_path=public
as $function$
begin
  if not coalesce((public.rr_costing_user_scope_v760(p_department_code)
      ->>'can_view_private_cost')::boolean,false) then
    raise exception 'Only Super Admin may change private standard costing.';
  end if;
  return public.rr_upm_set_standard_rate_v726_core_v401(
    p_canonical_lot_id,p_department_code,p_standard_rate,p_reason
  );
end
$function$;

-- Checkpoint 6 rate approval remains canonical; these wrappers only correct
-- the legacy OWNER/SUPER_ADMIN private-data equivalence in its responses.
alter function public.rr_pack_rate_context_public_v333(text,text)
  rename to rr_pack_rate_context_public_v333_core_v401;
create function public.rr_pack_rate_context_public_v333(
  p_lot_no text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760('PACKING');
  v_role text:=upper(coalesce(v_scope->>'effective_role','WORKER'));
  v_rate_view boolean;
begin
  v_rate_view:=coalesce((v_scope->>'can_edit_rate')::boolean,false)
    or v_role in('SALES','SALESMAN');
  return public.rr_costing_redact_payload_v401(
    public.rr_pack_rate_context_public_v333_core_v401(p_lot_no,p_data_mode),
    coalesce((v_scope->>'can_view_private_cost')::boolean,false),
    v_rate_view
  )||jsonb_build_object(
    'visibility',case
      when coalesce((v_scope->>'can_view_private_cost')::boolean,false)
        then 'SUPER_ADMIN_PRIVATE'
      when v_role in('SALES','SALESMAN') then 'SALES_RATE'
      when coalesce((v_scope->>'can_edit_rate')::boolean,false)
        then 'ADMIN_RATE'
      else 'PACKING_STATUS_ONLY' end
  );
end
$function$;

alter function public.rr_pack_rate_status_v9340(text,text)
  rename to rr_pack_rate_status_v9340_core_v401;
create function public.rr_pack_rate_status_v9340(
  p_lot_no text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760('PACKING');
  v_role text:=upper(coalesce(v_scope->>'effective_role','WORKER'));
  v_rate_view boolean;
begin
  v_rate_view:=coalesce((v_scope->>'can_edit_rate')::boolean,false)
    or v_role in('SALES','SALESMAN');
  return public.rr_costing_redact_payload_v401(
    public.rr_pack_rate_status_v9340_core_v401(p_lot_no,p_data_mode),
    coalesce((v_scope->>'can_view_private_cost')::boolean,false),
    v_rate_view
  )||jsonb_build_object(
    'visibility',case
      when coalesce((v_scope->>'can_view_private_cost')::boolean,false)
        then 'SUPER_ADMIN_PRIVATE'
      when v_role in('SALES','SALESMAN') then 'SALES_RATE'
      when coalesce((v_scope->>'can_edit_rate')::boolean,false)
        then 'ADMIN_RATE'
      else 'PACKING_STATUS_ONLY' end
  );
end
$function$;

alter function public.rr_pack_rate_approve_v9340(text,numeric,text)
  rename to rr_pack_rate_approve_v9340_core_v401;
create function public.rr_pack_rate_approve_v9340(
  p_lot_no text,
  p_final_rate numeric,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760('PACKING');
begin
  return public.rr_costing_redact_payload_v401(
    public.rr_pack_rate_approve_v9340_core_v401(
      p_lot_no,p_final_rate,p_data_mode
    ),
    coalesce((v_scope->>'can_view_private_cost')::boolean,false),
    true
  );
end
$function$;

-- Real Chat receives the same role-aware payload as the source RPC. It never
-- becomes an alternate salary, costing, margin, or rate API.
create or replace function public.rr_real_chat_redact_v401(
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
declare
  v_scope jsonb:=public.rr_costing_user_scope_v760(null);
begin
  return public.rr_costing_redact_payload_v401(
    coalesce(p_payload,'{}'::jsonb),
    coalesce((v_scope->>'can_view_private_cost')::boolean,false),
    coalesce((v_scope->>'can_edit_rate')::boolean,false)
  );
end
$function$;

revoke all on function public.rr_real_chat_redact_v401(jsonb)
  from public,anon,authenticated;
grant execute on function public.rr_real_chat_redact_v401(jsonb)
  to service_role;

alter function public.rr_real_chat_conversation_history_v83(integer)
  rename to rr_real_chat_conversation_history_v83_core_v401;
create function public.rr_real_chat_conversation_history_v83(
  p_limit integer default 2000
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
begin
  return public.rr_real_chat_redact_v401(
    public.rr_real_chat_conversation_history_v83_core_v401(p_limit)
  );
end
$function$;

alter function public.rr_real_chat_work_search_v10(text,text,text,integer)
  rename to rr_real_chat_work_search_v10_core_v401;
create function public.rr_real_chat_work_search_v10(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
begin
  return public.rr_real_chat_redact_v401(
    public.rr_real_chat_work_search_v10_core_v401(
      p_status,p_search,p_department_code,p_limit
    )
  );
end
$function$;

alter function public.rr_real_chat_work_search_v317(text,text,text,integer)
  rename to rr_real_chat_work_search_v317_core_v401;
create function public.rr_real_chat_work_search_v317(
  p_status text default 'WORKING',
  p_search text default null,
  p_department_code text default null,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $function$
begin
  return public.rr_real_chat_redact_v401(
    public.rr_real_chat_work_search_v317_core_v401(
      p_status,p_search,p_department_code,p_limit
    )
  );
end
$function$;

-- Retire the old assignment-rate event path. Assignment rows remain derived
-- snapshots, synchronized by rr_upm_set_department_rate_v760 above.
drop trigger if exists rr_upm_freeze_owner_default_actual_rate_v9112
  on public.rr_upm_work_assignments_v8;
drop trigger if exists rr_upm_lot_department_rate_after_insert_v7726
  on public.rr_upm_work_assignments_v8;
drop trigger if exists rr_upm_lot_department_rate_after_update_v7726
  on public.rr_upm_work_assignments_v8;

create or replace function public.rr_upm_canonical_actual_rate_v401(
  p_canonical_lot_id text,
  p_department_code text
) returns numeric
language sql
stable
security definer
set search_path=public
as $function$
  select r.actual_rate
  from public.rr_upm_department_rates_v2 r
  where r.canonical_lot_id=p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(r.department_code)
      =public.rr_costing_canonical_department_v760(p_department_code)
  order by r.updated_at desc
  limit 1
$function$;

revoke all on function public.rr_upm_canonical_actual_rate_v401(text,text)
  from public,anon,authenticated;
grant execute on function public.rr_upm_canonical_actual_rate_v401(text,text)
  to service_role;

alter function public.rr_upm_claim_colours_v741(text,text,text,jsonb,text)
  rename to rr_upm_claim_colours_v741_core_v401;
create function public.rr_upm_claim_colours_v741(
  p_canonical_lot_id text,
  p_lot_no text,
  p_department_code text,
  p_rows jsonb,
  p_remarks text default null
) returns setof public.rr_upm_work_assignments_v8
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_rate numeric:=public.rr_upm_canonical_actual_rate_v401(
    p_canonical_lot_id,p_department_code
  );
  v_rows jsonb;
  v_row public.rr_upm_work_assignments_v8%rowtype;
  v_allow_rate boolean:=coalesce((public.rr_costing_user_scope_v760(
    p_department_code)->>'can_edit_rate')::boolean,false);
begin
  select coalesce(jsonb_agg(
    (x-'actual_rate'-'rate_filled_by'-'rate_filled_by_name'-'rate_filled_at')
      ||jsonb_build_object('actual_rate',coalesce(v_rate,0)) order by ord
  ),'[]'::jsonb) into v_rows
  from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb))
    with ordinality q(x,ord);
  for v_row in
    select * from public.rr_upm_claim_colours_v741_core_v401(
      p_canonical_lot_id,p_lot_no,p_department_code,v_rows,p_remarks
    )
  loop
    if not v_allow_rate then
      v_row.actual_rate:=null;
      v_row.rate_filled_by:=null;
      v_row.rate_filled_by_name:=null;
      v_row.rate_filled_at:=null;
    end if;
    return next v_row;
  end loop;
  return;
end
$function$;

alter function public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text)
  rename to rr_upm_assign_colours_v8_3_core_v401;
create function public.rr_upm_assign_colours_v8_3(
  p_canonical_lot_id text,
  p_lot_no text,
  p_department_code text,
  p_rows jsonb,
  p_remarks text default null
) returns setof public.rr_upm_work_assignments_v8
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_rate numeric:=public.rr_upm_canonical_actual_rate_v401(
    p_canonical_lot_id,p_department_code
  );
  v_rows jsonb;
  v_row public.rr_upm_work_assignments_v8%rowtype;
  v_allow_rate boolean:=coalesce((public.rr_costing_user_scope_v760(
    p_department_code)->>'can_edit_rate')::boolean,false);
begin
  select coalesce(jsonb_agg(
    (x-'actual_rate'-'rate_filled_by'-'rate_filled_by_name'-'rate_filled_at')
      ||jsonb_build_object('actual_rate',coalesce(v_rate,0)) order by ord
  ),'[]'::jsonb) into v_rows
  from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb))
    with ordinality q(x,ord);
  for v_row in
    select * from public.rr_upm_assign_colours_v8_3_core_v401(
      p_canonical_lot_id,p_lot_no,p_department_code,v_rows,p_remarks
    )
  loop
    if not v_allow_rate then
      v_row.actual_rate:=null;
      v_row.rate_filled_by:=null;
      v_row.rate_filled_by_name:=null;
      v_row.rate_filled_at:=null;
    end if;
    return next v_row;
  end loop;
  return;
end
$function$;

alter function public.rr_upm_apply_actions_batch_v726(text,text,jsonb,numeric,text)
  rename to rr_upm_apply_actions_batch_v726_core_v401;
create function public.rr_upm_apply_actions_batch_v726(
  p_canonical_lot_id text,
  p_department_code text,
  p_actions jsonb,
  p_rate numeric default 0,
  p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
begin
  return public.rr_upm_apply_actions_batch_v726_core_v401(
    p_canonical_lot_id,p_department_code,p_actions,
    coalesce(public.rr_upm_canonical_actual_rate_v401(
      p_canonical_lot_id,p_department_code
    ),0),p_remarks
  );
end
$function$;

alter function public.rr_upm_save_damage_v731(text,text,jsonb,numeric,text)
  rename to rr_upm_save_damage_v731_core_v401;
create function public.rr_upm_save_damage_v731(
  p_canonical_lot_id text,
  p_department_code text,
  p_rows jsonb,
  p_rate numeric default 0,
  p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
begin
  return public.rr_upm_save_damage_v731_core_v401(
    p_canonical_lot_id,p_department_code,p_rows,
    coalesce(public.rr_upm_canonical_actual_rate_v401(
      p_canonical_lot_id,p_department_code
    ),0),p_remarks
  );
end
$function$;

alter function public.rr_upm_set_actual_rate_v8_4(uuid,numeric)
  rename to rr_upm_set_actual_rate_v8_4_core_v401;
create function public.rr_upm_set_actual_rate_v8_4(
  p_assignment_id uuid,
  p_actual_rate numeric
) returns setof public.rr_upm_work_assignments_v8
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_assignment public.rr_upm_work_assignments_v8%rowtype;
begin
  select * into v_assignment from public.rr_upm_work_assignments_v8
  where id=p_assignment_id;
  if not found then raise exception 'Assignment not found.'; end if;
  perform public.rr_upm_set_department_rate_v760(
    v_assignment.canonical_lot_id,v_assignment.department_code,
    p_actual_rate,null
  );
  return query select * from public.rr_upm_work_assignments_v8
    where id=p_assignment_id;
end
$function$;

alter function public.rr_upm_set_assignment_actual_rate_v772(uuid,numeric,text)
  rename to rr_upm_set_assignment_actual_rate_v772_core_v401;
create function public.rr_upm_set_assignment_actual_rate_v772(
  p_assignment_id uuid,
  p_actual_rate numeric,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_result jsonb;
begin
  select * into v_assignment from public.rr_upm_work_assignments_v8
  where id=p_assignment_id;
  if not found then raise exception 'Assignment not found.'; end if;
  v_result:=public.rr_upm_set_department_rate_v760(
    v_assignment.canonical_lot_id,v_assignment.department_code,
    p_actual_rate,null
  );
  return v_result||jsonb_build_object(
    'assignment_id',p_assignment_id,
    'reason',nullif(trim(coalesce(p_reason,'')),'')
  );
end
$function$;

-- Raw tables are not authorization APIs. Service functions retain full access;
-- authenticated clients receive only columns that contain no private costing.
revoke all on table public.rr_upm_costing_inputs_v9300
  from public,anon,authenticated;
revoke all on table public.rr_upm_department_rates_v2
  from public,anon,authenticated;
revoke all on table public.rr_upm_department_rate_log_v2
  from public,anon,authenticated;
revoke all on table public.rr_upm_assignment_rate_log_v772
  from public,anon,authenticated;
revoke all on table public.rr_upm_rate_requests_v760
  from public,anon,authenticated;
revoke all on table public.rr_upm_lot_costing_v760
  from public,anon,authenticated;
revoke all on table public.rr_upm_owner_margin_v723
  from public,anon,authenticated;
revoke all on table public.rr_upm_owner_margin_v726
  from public,anon,authenticated;
revoke all on table public.rr_upm_standard_rates_v723
  from public,anon,authenticated;
revoke all on table public.rr_upm_standard_rates_v726
  from public,anon,authenticated;
revoke all on table public.rr_costing_universal_settings_v760
  from public,anon,authenticated;
revoke all on table public.rr_costing_component_rule_v289
  from public,anon,authenticated;
revoke all on table public.rr_costing_effective_boundary_v308
  from public,anon,authenticated;
revoke all on table public.rr_upm_dispatch_cost_snapshot_v723
  from public,anon,authenticated;
revoke all on table public.rr_upm_actions_v726
  from public,anon,authenticated;
revoke all on table public.rr_print_frame_asset_v298
  from public,anon,authenticated;
revoke all on table public.rr_print_frame_recovery_event_v298
  from public,anon,authenticated;

grant all on table public.rr_upm_costing_inputs_v9300,
  public.rr_upm_department_rates_v2,
  public.rr_upm_department_rate_log_v2,
  public.rr_upm_assignment_rate_log_v772,
  public.rr_upm_rate_requests_v760,
  public.rr_upm_lot_costing_v760,
  public.rr_upm_owner_margin_v723,
  public.rr_upm_owner_margin_v726,
  public.rr_upm_standard_rates_v723,
  public.rr_upm_standard_rates_v726,
  public.rr_costing_universal_settings_v760,
  public.rr_costing_component_rule_v289,
  public.rr_costing_effective_boundary_v308,
  public.rr_upm_dispatch_cost_snapshot_v723,
  public.rr_upm_actions_v726,
  public.rr_print_frame_asset_v298,
  public.rr_print_frame_recovery_event_v298
  to service_role;

revoke all on table public.rr_print_master from public,anon,authenticated;
grant select(
  id,print_no,print_name,artwork_url,garment_preview_url,frame_base,colours,
  frame_labels,placement,print_type,notes,is_active,created_by,created_at,
  updated_at,caption_text,caption_items,design_colours,short_note
) on public.rr_print_master to authenticated;
grant insert(
  id,print_no,print_name,artwork_url,garment_preview_url,frame_base,colours,
  frame_labels,placement,print_type,notes,is_active,created_by,created_at,
  updated_at,caption_text,caption_items,design_colours,short_note
) on public.rr_print_master to authenticated;
grant update(
  print_no,print_name,artwork_url,garment_preview_url,frame_base,colours,
  frame_labels,placement,print_type,notes,is_active,updated_at,caption_text,
  caption_items,design_colours,short_note
) on public.rr_print_master to authenticated;
grant delete on public.rr_print_master to authenticated;
grant all on table public.rr_print_master to service_role;

revoke all on table public.rr_upm_work_assignments_v8
  from public,anon,authenticated;
grant select(
  id,canonical_lot_id,lot_no,department_code,colour_code,colour_name,
  worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,status,
  assigned_by,assigned_by_name,assigned_at,completed_at,cancelled_at,
  cancel_reason,remarks,created_at,updated_at,colour_id,source_type,
  source_lot_id,inbound_qty,inbound_breakup,assignment_batch_id,
  assigner_worker_id,assigner_role
) on public.rr_upm_work_assignments_v8 to authenticated;
grant all on table public.rr_upm_work_assignments_v8 to service_role;

revoke all on table public.rr_upm_submit_ledger_v2
  from public,anon,authenticated;
grant select(
  id,canonical_lot_id,lot_no,department_code,colour_code,size_code,
  cutting_qty,alter_qty,remake_qty,damage_qty,pending_alter_qty,
  already_submitted_qty,submitted_qty,remarks,submitted_by,
  submitted_by_name,submitted_by_category,created_at,submit_status,
  reversed_at,reversed_by,reversed_by_name,reverse_reason,work_assignment_id,
  assigned_worker_id,assigned_worker_code,assigned_worker_name
) on public.rr_upm_submit_ledger_v2 to authenticated;
grant all on table public.rr_upm_submit_ledger_v2 to service_role;

revoke all on table public.rr_upm_entries from public,anon,authenticated;
grant select(
  id,canonical_lot_id,lot_no,department_code,colour_code,size_code,
  entry_type,qty,remarks,reference_entry_id,operator_user_id,operator_name,
  created_at
) on public.rr_upm_entries to authenticated;
grant all on table public.rr_upm_entries to service_role;

-- Disable direct execution of private calculators and legacy response paths.
-- Their canonical security-definer callers still execute them as function owner.
do $do$
declare
  v_proc record;
begin
  for v_proc in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and (
      p.proname=any(array[
        'rr_cost_lot_report_v852','rr_cost_monthly_pnl_v852',
        'rr_report_base_rate_lookup_v852','rr_report_cost_ai_context_v852',
        'rr_report_cost_run_v852','rr_costing_box_context_v296',
        'rr_costing_box_cost_per_pc_v259','rr_costing_component_value_v289',
        'rr_costing_lot_department_context_v291','rr_costing_material_source_v292',
        'rr_costing_materials_resolved_v292',
        'rr_costing_salary_allocation_guard_v264',
        'rr_costing_salary_allocation_v400',
        'rr_costing_salary_department_drilldown_v297',
        'rr_costing_salary_department_v260','rr_costing_salary_department_v273',
        'rr_costing_salary_pool_v294','rr_costing_standard_rate_v760',
        'rr_pack_rate_context_legacy_v9405','rr_upm_cloth_cost_context_v9300',
        'rr_upm_costing_e2e_v275','rr_upm_costing_e2e_v276',
        'rr_upm_costing_panel_safe_v258','rr_upm_costing_panel_safe_v260',
        'rr_upm_costing_panel_safe_v273','rr_upm_damage_rate_snapshot_v759',
        'rr_upm_final_costing_private_v400','rr_upm_final_costing_v293',
        'rr_upm_final_costing_v295','rr_upm_final_costing_v296',
        'rr_upm_final_costing_v297','rr_upm_refresh_lot_costing_v760',
        'rr_upm_weighted_costing_projection_v261',
        'rr_upm_weighted_product_cost_v9082',
        'rr_sale_live_cloth_cost_v849_2c','rr_sale_live_material_cost_v849_2c',
        'rr_sale_live_actual_labour_cost_v849_2c',
        'rr_print_apply_frame_recovery_v299',
        'rr_print_apply_frame_recovery_v302',
        'rr_print_ensure_frame_assets_v302',
        'rr_print_frame_recovery_context_v299',
        'rr_print_frame_recovery_preview_v302',
        'rr_print_frame_recovery_preview_v303',
        'rr_print_frame_reframe_v298','rr_print_unused_frame_library_v298',
        'rr_printing_chemical_context_v304','rr_printing_chemical_context_v306',
        'rr_printing_design_context_v400','rr_printing_final_cost_resolver_v308',
        'rr_printing_save_chemical_qty_v304',
        'rr_printing_save_chemical_qty_v306',
        'rr_printing_finalize_costing_v305',
        'rr_printing_submit_costing_context_v305',
        'rr_upm_lot_department_rate_before_v7726',
        'rr_upm_lot_department_rate_after_v7726'
      ])
      or p.proname like '%\_core\_v401' escape '\'
      or p.proname like 'rr_real_chat_work_inbox_v%'
      or (p.proname like 'rr_real_chat_work_search_v%'
          and p.proname not in(
            'rr_real_chat_work_search_v10','rr_real_chat_work_search_v317'
          ))
      or (p.proname like 'rr_real_chat_conversation_history_v%'
          and p.proname<>'rr_real_chat_conversation_history_v83')
    )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_proc.oid::regprocedure
    );
    execute format(
      'grant execute on function %s to service_role',
      v_proc.oid::regprocedure
    );
  end loop;
end
$do$;

-- Publish only role-aware boundaries. Anonymous clients receive none of them.
do $do$
declare
  v_proc record;
begin
  for v_proc in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(array[
      'rr_costing_user_scope_v760',
      'rr_upm_universal_form_v723','rr_upm_universal_form_v724',
      'rr_upm_universal_form_v725','rr_upm_universal_form_v726',
      'rr_upm_get_universal_lot_context_v721','rr_upm_submit_summary_v2',
      'rr_costing_department_input_context_v290','rr_upm_save_cost_input_v9300',
      'rr_costing_rate_alert_detail_v284','rr_costing_rate_alerts_current_v286',
      'rr_costing_rate_lot_open_v284','rr_upm_set_owner_margin_v723',
      'rr_upm_set_owner_margin_v726','rr_upm_set_standard_rate_v723',
      'rr_upm_set_standard_rate_v726','rr_pack_rate_context_public_v333',
      'rr_pack_rate_status_v9340','rr_pack_rate_approve_v9340',
      'rr_real_chat_conversation_history_v83','rr_real_chat_work_search_v10',
      'rr_real_chat_work_search_v317','rr_upm_claim_colours_v741',
      'rr_upm_assign_colours_v8_3','rr_upm_apply_actions_batch_v726',
      'rr_upm_save_damage_v731','rr_upm_set_actual_rate_v8_4',
      'rr_upm_set_assignment_actual_rate_v772',
      'rr_upm_set_department_rate_v760','rr_upm_set_department_rate_v2',
      'rr_upm_bulk_set_department_rates_v189',
      'rr_upm_first_submit_rate_gate_v760','rr_upm_submit_gate_v277',
      'rr_upm_submit_with_actual_cost_gate_v9300',
      'rr_upm_rate_assignment_list_v401',
      'rr_test_checkpoint4_rate_authority_v401',
      'rr_printing_submit_costing_context_v307',
      'rr_printing_finalize_costing_v307','rr_upm_final_costing_v308',
      'rr_upm_costing_context_v9300','rr_upm_costing_panel_v760',
      'rr_upm_update_lot_costing_v760','rr_upm_lock_store_price_v760',
      'rr_upm_set_universal_owner_margin_v760'
    ])
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_proc.oid::regprocedure
    );
    execute format(
      'grant execute on function %s to authenticated, service_role',
      v_proc.oid::regprocedure
    );
  end loop;
end
$do$;

comment on function public.rr_costing_user_scope_v760(text) is
  'V401: only effective SUPER_ADMIN receives private costing; canonical rate editors are OWNER/SUPER_ADMIN/ADMIN/MANAGER.';
comment on function public.rr_upm_set_department_rate_v760(text,text,numeric,uuid) is
  'V401 canonical idempotent lot/department rate event; assignment rates are derived snapshots only.';
comment on function public.rr_upm_costing_panel_v760(text) is
  'V401 role-aware costing boundary: private cost only for effective SUPER_ADMIN.';
comment on function public.rr_real_chat_conversation_history_v83(integer) is
  'V401 Real Chat boundary strips salary, costing, margin and unauthorized rate fields recursively.';

commit;
