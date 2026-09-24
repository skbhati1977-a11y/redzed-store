-- TEST71 V628: Cutting OPEN/WORKING + Fabrication OPEN mirror.
-- One canonical Lot/assignment; no named Lot mutation and no parallel queue.
begin;

create or replace function public.rr_cutting_child_lifecycle_v628(p_cb_unit_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='public'
as $function$
declare
  v_unit public.rr_cb_units%rowtype;
  v_decisions_complete boolean:=false;
  v_due_count integer:=0;
  v_lots jsonb:='[]'::jsonb;
  v_state text;
  v_production_assigned boolean:=false;
begin
  select * into v_unit from public.rr_cb_units where id=p_cb_unit_id;
  if not found or not coalesce(v_unit.is_final,true) or not coalesce(v_unit.is_cutting_enabled,true) then
    return jsonb_build_object('cb_unit_id',p_cb_unit_id,'state','NOT_AVAILABLE',
      'canonical_state','CLOSE','all_decisions_complete',false,'material_due_count',0,
      'production_assigned',false,'lots','[]'::jsonb);
  end if;

  select coalesce(d.all_decisions_complete,false) into v_decisions_complete
  from public.rr_pm_decision_status_v802 d where d.cb_unit_id=p_cb_unit_id;

  select count(*)::integer into v_due_count
  from public.rr_cb_purchase_entries e
  where e.cb_id=v_unit.purchase_id and upper(coalesce(e.requirement_state,''))='DUE';

  select coalesce(jsonb_agg(jsonb_build_object('lot_no',x.lot_no,'cutting_pieces',x.pcs,'source',x.source)
    order by x.lot_no),'[]'::jsonb) into v_lots
  from (
    select distinct on (lot_no) lot_no,pcs,source
    from (
      select upper(btrim(l.lot_no)) lot_no,
        coalesce(nullif(l.actual_pcs,0),nullif(l.planned_pcs,0),0)::numeric pcs,
        'rr_cutting_lots_v3'::text source,1 priority
      from public.rr_cutting_lots_v3 l
      where l.cb_unit_id=p_cb_unit_id
        and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')
      union all
      select upper(btrim(l.lot_no)),
        coalesce(nullif(l.actual_pcs,0),nullif(l.planned_pcs,0),0)::numeric,
        'rr_production_lots'::text,2
      from public.rr_production_lots l
      where l.cb_unit_id=p_cb_unit_id
        and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')
      union all
      select upper(btrim(l.lot_no)),
        coalesce(nullif(l.verified_cut_qty,0),nullif(l.original_cut_qty,0),nullif(l.total_qty,0),0)::numeric,
        'rr_upm_lot_registry'::text,3
      from public.rr_upm_lot_registry l
      where upper(coalesce(l.cb_no,''))=upper(v_unit.cb_code)
         or l.metadata->>'cb_unit_id'=p_cb_unit_id::text
    ) s
    order by lot_no,priority
  ) x;

  v_state:=case
    when jsonb_array_length(v_lots)>0 then 'RELEASED'
    when not v_decisions_complete then 'ART_DUE'
    when v_due_count>0 then 'CUTTING_HOLD'
    else 'READY_FOR_CUTTING'
  end;

  select exists(
    select 1
    from public.rr_upm_work_assignments_v8 a
    join public.rr_upm_lot_registry r on r.canonical_lot_id=a.canonical_lot_id
    where (upper(coalesce(r.cb_no,''))=upper(v_unit.cb_code)
       or r.metadata->>'cb_unit_id'=p_cb_unit_id::text)
      and upper(public.rr_upm_core_department_v9077(a.department_code))<>'CUTTING'
      and upper(coalesce(a.status,'')) not in('CANCELLED','CANCELED','VOID')
  ) into v_production_assigned;

  return jsonb_build_object(
    'cb_unit_id',v_unit.id,'purchase_id',v_unit.purchase_id,'cb_code',v_unit.cb_code,
    'state',v_state,
    'canonical_state',case
      when v_state='RELEASED' and not v_production_assigned then 'WORKING'
      when v_state='RELEASED' then 'CLOSE'
      when v_state='READY_FOR_CUTTING' then 'WORKING'
      else 'OPEN' end,
    'all_decisions_complete',v_decisions_complete,
    'material_due_count',v_due_count,
    'production_assigned',v_production_assigned,
    'lots',v_lots);
end
$function$;

revoke all on function public.rr_cutting_child_lifecycle_v628(uuid) from public,anon;
grant execute on function public.rr_cutting_child_lifecycle_v628(uuid) to authenticated,service_role;

create or replace function public.rr_cutting_child_lifecycle_v615(p_cb_unit_id uuid)
returns jsonb language sql stable security definer
set search_path='public'
as $function$
  select public.rr_cutting_child_lifecycle_v628(p_cb_unit_id)
$function$;

revoke all on function public.rr_cutting_child_lifecycle_v615(uuid) from public,anon;
grant execute on function public.rr_cutting_child_lifecycle_v615(uuid) to authenticated,service_role;

create or replace function public.rr_real_chat_reconcile_cutting_v628()
returns jsonb language plpgsql security definer
set search_path='public','pg_temp'
as $function$
declare v_inserted integer:=0; v_archived integer:=0; v_open integer:=0;
begin
  with released as (
    select distinct on (r.canonical_lot_id)
      r.id registry_id,r.canonical_lot_id,upper(trim(r.lot_no)) lot_no,
      coalesce(r.cb_no,'') cb_no,coalesce(r.art_no,'') art_no,
      coalesce(r.print_no,'N/A') print_no,
      coalesce(r.total_qty,r.original_cut_qty,r.verified_cut_qty,0)::numeric quantity
    from public.rr_upm_lot_registry r
    where upper(coalesce(r.source_table,'')) in('RR_CUTTING_LOTS_V3','RR_PRODUCTION_LOTS')
      and (
        exists(select 1 from public.rr_cutting_lots_v3 l
          where upper(trim(l.lot_no))=upper(trim(r.lot_no))
            and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'))
        or exists(select 1 from public.rr_production_lots l
          where upper(trim(l.lot_no))=upper(trim(r.lot_no))
            and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'))
      )
    order by r.canonical_lot_id,r.updated_at desc nulls last
  ), pending as (
    select d.*,exists(
      select 1 from public.rr_upm_work_assignments_v8 a
      where a.canonical_lot_id=d.canonical_lot_id
        and upper(public.rr_upm_core_department_v9077(a.department_code))<>'CUTTING'
        and upper(coalesce(a.status,'')) not in('CANCELLED','CANCELED','VOID')
    ) assigned
    from released d
  )
  insert into public.rr_real_chat_message_bridge_v70(
    canonical_key,source_module,source_record_id,source_event_type,department_code,
    action_code,action_label,personal_payload,group_payload,deep_link,
    projection_type,archived_at,archive_reason
  )
  select
    'CUTTING_RELEASED_PENDING:'||p.registry_id::text,'CUTTING',p.registry_id::text,
    'CUTTING_RELEASED_PENDING_ASSIGNMENT','CUTTING','ASSIGN_WORKER','ASSIGN WORK',
    jsonb_build_object(
      'card_type','CUTTING_RELEASED','canonical_lot_id',p.canonical_lot_id,
      'lot_no',p.lot_no,'cb_no',p.cb_no,'art_no',p.art_no,'print_no',p.print_no,
      'quantity',p.quantity,'status','WORKING','canonical_state','WORKING',
      'chat_status','WORKING','work_category','READY_TO_ASSIGN',
      'message','Lot released · production assignment pending',
      'sender_name','Cutting Master','sender_department_code','CUTTING',
      'source_department_code','CUTTING','target_department_code','FABRICATION',
      'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER'),
      'next_actions',jsonb_build_array(jsonb_build_object(
        'code','ASSIGN_WORKER','label','ASSIGN WORK',
        'href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST71_CUTTING_MIRROR&rrMode=ASSIGN&lot='||p.lot_no,
        'engine','rr_upm_ready_to_assign_v9107'))),
    jsonb_build_object(
      'card_type','CUTTING_RELEASED','canonical_lot_id',p.canonical_lot_id,
      'lot_no',p.lot_no,'cb_no',p.cb_no,'art_no',p.art_no,'print_no',p.print_no,
      'quantity',p.quantity,'status','WORKING','canonical_state','WORKING',
      'chat_status','WORKING','work_category','READY_TO_ASSIGN',
      'message','Lot released · production assignment pending',
      'sender_name','Cutting Master','sender_department_code','CUTTING',
      'source_department_code','CUTTING','target_department_code','FABRICATION',
      'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER'),
      'next_actions',jsonb_build_array(jsonb_build_object(
        'code','ASSIGN_WORKER','label','ASSIGN WORK',
        'href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST71_CUTTING_MIRROR&rrMode=ASSIGN&lot='||p.lot_no,
        'engine','rr_upm_ready_to_assign_v9107'))),
    'real-universal-production-v770-v9059.html?mode=TEST&from=TEST71_CUTTING_MIRROR&rrMode=ASSIGN&lot='||p.lot_no,
    'TARGET',null,null
  from pending p
  where not p.assigned
    and not exists(
      select 1 from public.rr_real_chat_message_bridge_v70 b
      where b.source_module='CUTTING'
        and b.source_record_id=p.registry_id::text
        and b.source_event_type in('CUTTING_RELEASE_SUCCEEDED','CUTTING_RELEASED_PENDING_ASSIGNMENT')
        and b.archived_at is null)
  on conflict(canonical_key) do update set
    personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
    action_code=excluded.action_code,action_label=excluded.action_label,
    deep_link=excluded.deep_link,archived_at=null,archive_reason=null;
  get diagnostics v_inserted=row_count;

  update public.rr_real_chat_message_bridge_v70 b
  set archived_at=coalesce(b.archived_at,now()),
      archive_reason='CUTTING_HANDOFF_ASSIGNED',
      action_code=null,action_label=null
  where b.archived_at is null and b.source_module='CUTTING'
    and b.source_event_type in('CUTTING_RELEASE_SUCCEEDED','CUTTING_RELEASED_PENDING_ASSIGNMENT')
    and exists(
      select 1 from public.rr_upm_lot_registry r
      join public.rr_upm_work_assignments_v8 a on a.canonical_lot_id=r.canonical_lot_id
      where r.id::text=b.source_record_id
        and upper(public.rr_upm_core_department_v9077(a.department_code))<>'CUTTING'
        and upper(coalesce(a.status,'')) not in('CANCELLED','CANCELED','VOID'));
  get diagnostics v_archived=row_count;

  update public.rr_real_chat_message_bridge_v70 b
  set personal_payload=jsonb_set(jsonb_set(coalesce(b.personal_payload,'{}'::jsonb),'{canonical_state}','"OPEN"'::jsonb,true),'{status}','"OPEN"'::jsonb,true),
      group_payload=jsonb_set(jsonb_set(coalesce(b.group_payload,'{}'::jsonb),'{canonical_state}','"OPEN"'::jsonb,true),'{status}','"OPEN"'::jsonb,true)
  where b.archived_at is null and b.source_module='CUTTING'
    and b.source_event_type='READY_FOR_CUTTING'
    and not exists(
      select 1 from public.rr_cutting_lots_v3 l
      where l.cb_unit_id::text=b.source_record_id
        and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'))
    and not exists(
      select 1 from public.rr_production_lots l
      where l.cb_unit_id::text=b.source_record_id
        and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'));
  get diagnostics v_open=row_count;

  return jsonb_build_object('released_pending_inserted',v_inserted,
    'released_archived',v_archived,'ready_open_normalized',v_open);
end
$function$;

revoke all on function public.rr_real_chat_reconcile_cutting_v628() from public,anon;
grant execute on function public.rr_real_chat_reconcile_cutting_v628() to authenticated,service_role;

create or replace function public.rr_real_chat_cutting_trigger_v113()
returns trigger language plpgsql security definer
set search_path='public','pg_temp'
as $function$
begin
  if pg_trigger_depth()>1 then return null; end if;
  perform public.rr_real_chat_reconcile_cutting_v113();
  perform public.rr_real_chat_reconcile_cutting_v628();
  return null;
exception when others then
  raise warning 'V628 Cutting projection reconciliation deferred: %',sqlerrm;
  return null;
end
$function$;

select public.rr_real_chat_reconcile_cutting_v113();
select public.rr_real_chat_reconcile_cutting_v628();

commit;