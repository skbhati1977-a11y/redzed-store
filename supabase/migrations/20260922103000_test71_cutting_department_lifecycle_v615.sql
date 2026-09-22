-- TEST71 V615: one canonical Cutting child lifecycle for App + Backend + Real Chat.
-- Named business records are never patched. Reconciliation derives every existing
-- and future child from its canonical Art, Material and physical Lot records.
begin;

create or replace function public.rr_cutting_child_lifecycle_v615(p_cb_unit_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_unit public.rr_cb_units%rowtype;
  v_decisions_complete boolean:=false;
  v_due_count integer:=0;
  v_lots jsonb:='[]'::jsonb;
  v_state text;
begin
  select * into v_unit
  from public.rr_cb_units
  where id=p_cb_unit_id;

  if not found or not coalesce(v_unit.is_final,true) or not coalesce(v_unit.is_cutting_enabled,true) then
    return jsonb_build_object(
      'cb_unit_id',p_cb_unit_id,
      'state','NOT_AVAILABLE',
      'canonical_state','CLOSE',
      'all_decisions_complete',false,
      'material_due_count',0,
      'lots','[]'::jsonb
    );
  end if;

  select coalesce(d.all_decisions_complete,false)
    into v_decisions_complete
  from public.rr_pm_decision_status_v802 d
  where d.cb_unit_id=p_cb_unit_id;

  select count(*)::integer into v_due_count
  from public.rr_cb_purchase_entries e
  where e.cb_id=v_unit.purchase_id
    and upper(coalesce(e.requirement_state,''))='DUE';

  select coalesce(jsonb_agg(
    jsonb_build_object('lot_no',x.lot_no,'cutting_pieces',x.pcs,'source',x.source)
    order by x.lot_no
  ),'[]'::jsonb) into v_lots
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
             'rr_production_lots',2
      from public.rr_production_lots l
      where l.cb_unit_id=p_cb_unit_id
        and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')
      union all
      select upper(btrim(l.lot_no)),
             coalesce(nullif(l.verified_cut_qty,0),nullif(l.original_cut_qty,0),nullif(l.total_qty,0),0)::numeric,
             'rr_upm_lot_registry',3
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

  return jsonb_build_object(
    'cb_unit_id',v_unit.id,
    'purchase_id',v_unit.purchase_id,
    'cb_code',v_unit.cb_code,
    'state',v_state,
    'canonical_state',case
      when v_state='RELEASED' then 'CLOSE'
      when v_state='READY_FOR_CUTTING' then 'WORKING'
      else 'OPEN'
    end,
    'all_decisions_complete',v_decisions_complete,
    'material_due_count',v_due_count,
    'lots',v_lots
  );
end
$function$;

revoke all on function public.rr_cutting_child_lifecycle_v615(uuid) from public,anon;
grant execute on function public.rr_cutting_child_lifecycle_v615(uuid) to authenticated,service_role;

create or replace function public.rr_cutting_assert_authority_v615()
returns void
language plpgsql
stable
security definer
set search_path='public'
as $function$
declare
  v_identity jsonb;
  v_role text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_identity:=public.rr_upm_effective_identity_v200();
  v_role:=upper(coalesce(v_identity->>'resolved_role',v_identity->>'role_code','WORKER'));
  if v_role not in('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER') then
    raise exception 'Cutting release authority required' using errcode='42501';
  end if;
end
$function$;

revoke all on function public.rr_cutting_assert_authority_v615() from public,anon;
grant execute on function public.rr_cutting_assert_authority_v615() to authenticated,service_role;

create or replace function public.rr_cutting_assert_release_gate_v615(p_cb_unit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_state jsonb;
begin
  perform public.rr_cutting_assert_authority_v615();
  if p_cb_unit_id is null then raise exception 'CB Child is required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('RR_CUTTING_RELEASE:'||p_cb_unit_id::text,615));
  v_state:=public.rr_cutting_child_lifecycle_v615(p_cb_unit_id);
  if v_state->>'state'='NOT_AVAILABLE' then
    raise exception 'CB child is not available for cutting';
  end if;
  if not coalesce((v_state->>'all_decisions_complete')::boolean,false) then
    raise exception 'Art / Print / Sticker / Metal ID decision must be completed first';
  end if;
  if coalesce((v_state->>'material_due_count')::integer,0)>0 then
    raise exception '% Material Due — confirm material before Cutting',v_state->>'material_due_count';
  end if;
  return v_state;
end
$function$;

revoke all on function public.rr_cutting_assert_release_gate_v615(uuid) from public,anon;
grant execute on function public.rr_cutting_assert_release_gate_v615(uuid) to authenticated,service_role;

create or replace function public.rr_cutting_release_guard_trigger_v801()
returns trigger
language plpgsql
security definer
set search_path='public'
as $function$
begin
  if lower(btrim(coalesce(new.status,''))) <> 'released' then return new; end if;
  perform public.rr_cutting_assert_release_gate_v615(new.cb_unit_id);
  perform public.rr_cutting_release_assert_v801(new.cb_unit_id,new.art_no,new.print_no);
  return new;
end
$function$;

create or replace function public.rr_cutting_request_multi_art_decision_v1(p_cb_unit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_row public.rr_cutting_multi_art_decisions_v1%rowtype;
  v_lifecycle jsonb;
  v_cb text;
  v_receiver uuid;
begin
  perform public.rr_cutting_assert_authority_v615();
  perform pg_advisory_xact_lock(hashtextextended('RR_CUTTING_MULTI_ART:'||p_cb_unit_id::text,615));
  v_lifecycle:=public.rr_cutting_child_lifecycle_v615(p_cb_unit_id);
  v_cb:=v_lifecycle->>'cb_code';
  if v_lifecycle->>'state'<>'READY_FOR_CUTTING' then
    raise exception 'CB child is not ready for Cutting: %',replace(v_lifecycle->>'state','_',' ');
  end if;

  select * into v_row
  from public.rr_cutting_multi_art_decisions_v1
  where cb_unit_id=p_cb_unit_id and status in('PENDING_SUPERADMIN','DECIDED')
  order by requested_at desc limit 1;
  if found then
    return jsonb_build_object('ok',true,'request_id',v_row.id,'status',v_row.status,
      'cb_code',v_cb,'duplicate_blocked',true,'lifecycle',v_lifecycle);
  end if;

  insert into public.rr_cutting_multi_art_decisions_v1(cb_unit_id,requested_by)
  values(p_cb_unit_id,v_uid) returning * into v_row;

  select auth_user_id into v_receiver
  from public.rr_user_profiles
  where is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
    and upper(role_code) in('SUPER_ADMIN','OWNER')
  order by case when upper(role_code)='SUPER_ADMIN' then 0 else 1 end,updated_at desc limit 1;
  if v_receiver is null then raise exception 'Super Admin receiver is not configured'; end if;

  insert into public.rr_real_chat_message_bridge_v70(
    canonical_key,source_module,source_record_id,source_event_type,department_code,
    sender_user_id,receiver_user_id,action_code,action_label,personal_payload,group_payload,deep_link,projection_type
  ) values(
    'CUTTING_MULTI_ART:'||v_row.id,'PRODUCT_MASTER',v_row.id::text,'MULTI_ART_DECISION_REQUIRED','PRODUCT_MASTER',
    v_uid,v_receiver,'MULTI_ART_DECISION','DECIDE MULTI ART',
    jsonb_build_object('message',v_cb||' Multi Lot Art & All decision required','cb_code',v_cb,
      'cb_unit_id',p_cb_unit_id,'request_id',v_row.id,'status','PENDING_SUPERADMIN',
      'canonical_state','WORKING','cutting_state','READY_FOR_CUTTING',
      'allowed_roles',jsonb_build_array('SUPER_ADMIN','OWNER')),
    jsonb_build_object('message',v_cb||' Multi Lot Art & All decision required','cb_code',v_cb,
      'cb_unit_id',p_cb_unit_id,'request_id',v_row.id,'status','PENDING_SUPERADMIN',
      'canonical_state','WORKING','cutting_state','READY_FOR_CUTTING',
      'allowed_roles',jsonb_build_array('SUPER_ADMIN','OWNER')),
    'test70-real-chat.html?multi_art_request='||v_row.id||'&cb_unit_id='||p_cb_unit_id,
    'MULTI_ART_EXACT_SUPERADMIN'
  ) on conflict(canonical_key) do update set
    receiver_user_id=excluded.receiver_user_id,
    personal_payload=excluded.personal_payload,
    group_payload=excluded.group_payload,
    archived_at=null,archive_reason=null;

  return jsonb_build_object('ok',true,'request_id',v_row.id,'status',v_row.status,
    'cb_code',v_cb,'duplicate_blocked',false,'lifecycle',v_lifecycle);
end
$function$;

create or replace function public.rr_cutting_get_multi_art_decision_v1(p_cb_unit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_row public.rr_cutting_multi_art_decisions_v1%rowtype;
  v_lifecycle jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  v_lifecycle:=public.rr_cutting_child_lifecycle_v615(p_cb_unit_id);
  if v_lifecycle->>'state'<>'READY_FOR_CUTTING' then
    return jsonb_build_object('ok',true,'status',v_lifecycle->>'state','ineligible',true,'lifecycle',v_lifecycle);
  end if;
  select * into v_row
  from public.rr_cutting_multi_art_decisions_v1
  where cb_unit_id=p_cb_unit_id and status in('PENDING_SUPERADMIN','DECIDED')
  order by requested_at desc limit 1;
  if not found then
    return jsonb_build_object('ok',true,'status','NOT_REQUESTED','lifecycle',v_lifecycle);
  end if;
  return jsonb_build_object('ok',true,'request_id',v_row.id,'status',v_row.status,
    'decision_mode',v_row.decision_mode,'set_count',v_row.set_count,
    'set_decisions',v_row.set_decisions,'lifecycle',v_lifecycle);
end
$function$;

create or replace function public.rr_cutting_decide_multi_art_v1(
  p_request_id uuid,p_decision_mode text,p_set_count integer,p_set_decisions jsonb default '[]'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_mode text:=upper(btrim(coalesce(p_decision_mode,'')));
  v_row public.rr_cutting_multi_art_decisions_v1%rowtype;
  v_lifecycle jsonb;
  v_sets jsonb:=case when upper(btrim(coalesce(p_decision_mode,'')))='SAME_EXISTING' then '[]'::jsonb else coalesce(p_set_decisions,'[]'::jsonb) end;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if not public.rr_chat_is_superadmin_v9433() then raise exception 'Only Super Admin can decide Multi Lot Art'; end if;
  if v_mode not in('SAME_EXISTING','SEPARATE') then raise exception 'Invalid decision mode'; end if;
  if coalesce(p_set_count,0)<2 or p_set_count>20 then raise exception 'Set count must be between 2 and 20'; end if;
  if v_mode='SEPARATE' and (jsonb_typeof(v_sets)<>'array' or jsonb_array_length(v_sets)<>p_set_count) then
    raise exception 'Every Set needs its own Art decision';
  end if;

  select * into v_row from public.rr_cutting_multi_art_decisions_v1 where id=p_request_id for update;
  if not found then raise exception 'Multi Lot decision request not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('RR_CUTTING_MULTI_ART:'||v_row.cb_unit_id::text,615));
  v_lifecycle:=public.rr_cutting_child_lifecycle_v615(v_row.cb_unit_id);
  if v_lifecycle->>'state'<>'READY_FOR_CUTTING' then
    raise exception 'CB child is not ready for Cutting: %',replace(v_lifecycle->>'state','_',' ');
  end if;

  if v_row.status='DECIDED' then
    if v_row.decision_mode=v_mode and v_row.set_count=p_set_count and coalesce(v_row.set_decisions,'[]'::jsonb)=v_sets then
      return jsonb_build_object('ok',true,'request_id',v_row.id,'status',v_row.status,
        'decision_mode',v_row.decision_mode,'set_count',v_row.set_count,'duplicate_blocked',true);
    end if;
    raise exception 'Multi Lot decision is already finalized';
  end if;
  if v_row.status<>'PENDING_SUPERADMIN' then raise exception 'Pending Multi Lot decision not found'; end if;

  update public.rr_cutting_multi_art_decisions_v1
  set status='DECIDED',decision_mode=v_mode,set_count=p_set_count,set_decisions=v_sets,
      decided_by=v_uid,decided_at=now(),updated_at=now()
  where id=v_row.id returning * into v_row;
  update public.rr_real_chat_message_bridge_v70
  set archived_at=now(),archive_reason='MULTI_ART_DECIDED'
  where canonical_key='CUTTING_MULTI_ART:'||v_row.id;
  return jsonb_build_object('ok',true,'request_id',v_row.id,'status',v_row.status,
    'decision_mode',v_row.decision_mode,'set_count',v_row.set_count,'duplicate_blocked',false);
end
$function$;

create or replace function public.rr_cutting_multi_art_inbox_v1()
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_super boolean;
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  v_super:=public.rr_chat_is_superadmin_v9433();
  select coalesce(jsonb_agg(jsonb_build_object(
    'request_id',r.id,'cb_unit_id',r.cb_unit_id,'cb_code',u.cb_code,
    'status',r.status,'requested_at',r.requested_at,'requested_by',r.requested_by,
    'decision_mode',r.decision_mode,'set_count',r.set_count,'set_decisions',r.set_decisions,
    'lifecycle',s.lifecycle
  ) order by r.requested_at desc),'[]'::jsonb) into v_rows
  from public.rr_cutting_multi_art_decisions_v1 r
  join public.rr_cb_units u on u.id=r.cb_unit_id
  cross join lateral(select public.rr_cutting_child_lifecycle_v615(r.cb_unit_id) lifecycle) s
  where r.status in('PENDING_SUPERADMIN','DECIDED')
    and s.lifecycle->>'state'='READY_FOR_CUTTING'
    and (v_super or r.requested_by=v_uid);
  return v_rows;
end
$function$;

create or replace function public.rr_real_chat_canonical_state_v83(
  p_source_module text,p_event_type text,p_action_code text,p_payload jsonb default '{}'::jsonb
) returns text
language sql
immutable
set search_path=''
as $function$
with x as (
  select upper(coalesce(p_source_module,'')) m,upper(coalesce(p_event_type,'')) e,
    upper(coalesce(p_action_code,'')) a,
    upper(coalesce(p_payload->>'canonical_state',p_payload->>'chat_status',p_payload->>'message_status',p_payload->>'status','')) s
)
select case
  when s in('OPEN','WORKING','CLOSE','REOPENED') then s
  when e='READY_FOR_CUTTING' then 'WORKING'
  when e='CUTTING_RELEASE_SUCCEEDED' then 'CLOSE'
  when e in('ART_DECIDE_PENDING','READY_TO_ASSIGN','LOT_OPEN','SALE_DRAFT','REQUIREMENT_OPEN','COLLECTION_OPEN') then 'OPEN'
  when e in('WORK_ASSIGNED','ALTER_FILL','LM_ACCEPT_REQUEST','LM_ACCEPT','REMAKE_ISSUE','RECEIVE_FROM_MASTER','DELIVER_TO_KARIGAR',
            'PACKING_ASSIGNED','PACKING_ACCEPTED','DESPATCH_IN_TRANSIT','SALE_CI_FINAL','DIFFERENCE_HOLD') then 'WORKING'
  when e in('ART_DECIDE_SUCCEEDED','ASSIGNMENT_COMPLETED','ASSIGNMENT_CANCELLED','WORK_SUBMITTED','KARIGAR_SUBMIT_GOOD',
            'RECEIVE_FROM_KARIGAR','DAMAGE_POSTED','RECTIFICATION_CLOSED','PACKING_SUBMITTED','DESPATCH_ACCEPTANCE_FINALIZED',
            'DESPATCH_RECEIVED','STOCK_POSTED','SALE_CANCELLED','SALE_QTY_VERIFIED','SALES_RETURN_POSTED','RCI_POSTED',
            'RCI_REVERSED','PAYMENT_POSTED','ORDER_CLOSED','COLLECTION_CLOSED') then 'CLOSE'
  when a in('ASSIGN_WORKER','PACKING_ASSIGN','PACKING_ACCEPT','OPEN_PI','FINALIZE_CI','STORE_RECEIVE','DIFFERENCE_HOLD_RESOLVE') then 'WORKING'
  when a in('SUBMIT','PACKING_SUBMIT','DESPATCH_CREATE','STOCK_POST','VERIFY_CPI_QTY','POST_SALES_RETURN','DAMAGE','RECEIVE_KARIGAR') then 'CLOSE'
  else 'WORKING'
end from x
$function$;

create or replace function public.rr_real_chat_reconcile_cb_children_v105()
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $function$
declare
  v_rows integer:=0;
  v_ready integer:=0;
  v_retired integer:=0;
begin
  create temporary table if not exists pg_temp.rr_cb_child_truth_v615(
    purchase_id uuid,unit_id uuid primary key,cb_code text,created_at timestamptz,
    child_state text,canonical_state text,due_count integer,lots jsonb
  ) on commit drop;
  truncate pg_temp.rr_cb_child_truth_v615;

  insert into pg_temp.rr_cb_child_truth_v615(
    purchase_id,unit_id,cb_code,created_at,child_state,canonical_state,due_count,lots
  )
  select u.purchase_id,u.id,u.cb_code,u.created_at,s.j->>'state',s.j->>'canonical_state',
         coalesce((s.j->>'material_due_count')::integer,0),coalesce(s.j->'lots','[]'::jsonb)
  from public.rr_cb_units u
  cross join lateral(select public.rr_cutting_child_lifecycle_v615(u.id) j) s
  where coalesce(u.is_final,true) and coalesce(u.is_cutting_enabled,true);

  with parent_truth as (
    select purchase_id,
      case when bool_and(child_state='RELEASED') then 'CLOSE'
           when bool_or(child_state in('ART_DUE','CUTTING_HOLD')) then 'OPEN'
           else 'WORKING' end canonical_state,
      jsonb_agg(jsonb_build_object(
        'cb_unit_id',unit_id,'cb_code',cb_code,'state',child_state,
        'canonical_state',canonical_state,'material_due_count',due_count,'lots',lots
      ) order by created_at,cb_code) children,
      coalesce(jsonb_agg(jsonb_build_object(
        'code',case when child_state='ART_DUE' then 'ART_DECIDE_SUBMIT' else 'CUTTING_RELEASE' end,
        'label',case when child_state='ART_DUE' then 'DECIDE ART · '||cb_code else 'READY FOR CUTTING · '||cb_code end,
        'href',case when child_state='ART_DUE' then 'real-art-decide-master.html?cb_unit_id='||unit_id
                    else 'real-cutting-master.html?cb_unit_id='||unit_id end,
        'engine',case when child_state='ART_DUE' then 'rr_pm_save_decision_bundle_v804'
                      else 'EXISTING_CUTTING_RELEASE_CHAIN' end,
        'cb_unit_id',unit_id,
        'allowed_roles',case when child_state='ART_DUE' then jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN')
                             else jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER') end
      ) order by created_at,cb_code) filter(where child_state in('ART_DUE','READY_FOR_CUTTING')),'[]'::jsonb) actions
    from pg_temp.rr_cb_child_truth_v615 group by purchase_id
  ), first_action as (
    select p.*,p.actions->0 a from parent_truth p
  )
  update public.rr_real_chat_message_bridge_v70 b
  set personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions'-'cb_children'-'action_href'-'action_engine')
        ||jsonb_build_object('canonical_state',p.canonical_state,'cb_children',p.children,'next_actions',p.actions,
          'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'))
        ||case when p.a is null then '{}'::jsonb else jsonb_build_object('action_href',p.a->>'href','action_engine',p.a->>'engine') end,
      group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'next_actions'-'cb_children'-'action_href'-'action_engine')
        ||jsonb_build_object('canonical_state',p.canonical_state,'cb_children',p.children,'next_actions',p.actions,
          'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'))
        ||case when p.a is null then '{}'::jsonb else jsonb_build_object('action_href',p.a->>'href','action_engine',p.a->>'engine') end,
      action_code=p.a->>'code',action_label=p.a->>'label',deep_link=coalesce(p.a->>'href',b.deep_link)
  from first_action p
  where b.archived_at is null and b.source_module='CB_PURCHASE'
    and b.source_event_type='CREATE_CB_SUCCEEDED' and b.source_record_id=p.purchase_id::text;
  get diagnostics v_rows=row_count;

  insert into public.rr_real_chat_message_bridge_v70(
    canonical_key,source_module,source_record_id,source_event_type,department_code,sender_user_id,
    action_code,action_label,personal_payload,group_payload,deep_link,sent_at,canonical_event_id,
    projection_type,archived_at,archive_reason
  )
  select 'ACE:'||e.id||':TARGET','CUTTING',c.unit_id::text,'READY_FOR_CUTTING','CUTTING',e.performer_user_id,
    'CUTTING_RELEASE','READY FOR CUTTING · '||c.cb_code,payload.j,payload.j,
    'real-cutting-master.html?cb_unit_id='||c.unit_id,e.source_event_at,e.id,'TARGET',null,null
  from pg_temp.rr_cb_child_truth_v615 c
  join public.rr_cb_art_assignments a on a.cb_id=c.unit_id
  join public.rr_real_chat_canonical_events_v96 e
    on e.action_code='ART_DECIDE_SUBMIT' and e.source_record_id=a.id::text and e.archived_at is null
  cross join lateral(select jsonb_build_object(
    'card_type','READY_FOR_CUTTING','conversation_parent','CB:'||c.purchase_id,
    'cb_no',split_part(c.cb_code,'-S',1),'cb_code',c.cb_code,'cb_unit_id',c.unit_id,
    'status','WORKING','canonical_state','WORKING','cutting_state','READY_FOR_CUTTING',
    'material_due_count',0,'message','Art decided · Material Due 0 · Ready for Cutting',
    'sender_name','Product Master','receiver_name','Cutting Master Queue',
    'source_department_code','CUTTING','target_department_code','CUTTING',
    'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'),
    'action_href','real-cutting-master.html?cb_unit_id='||c.unit_id,
    'action_engine','EXISTING_CUTTING_RELEASE_CHAIN'
  ) j) payload
  where c.child_state='READY_FOR_CUTTING'
  on conflict(canonical_key) do update set
    action_code=excluded.action_code,action_label=excluded.action_label,
    personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
    deep_link=excluded.deep_link,archived_at=null,archive_reason=null;
  get diagnostics v_ready=row_count;

  update public.rr_real_chat_message_bridge_v70 q
  set archived_at=coalesce(q.archived_at,now()),archive_reason='CHILD_NOT_READY_V615'
  where q.archived_at is null and q.source_module='CUTTING' and q.source_event_type='READY_FOR_CUTTING'
    and exists(select 1 from pg_temp.rr_cb_child_truth_v615 c
      where c.unit_id::text=q.source_record_id and c.child_state<>'READY_FOR_CUTTING');

  update public.rr_cutting_multi_art_decisions_v1 r
  set status=case when r.status='DECIDED' then 'CONSUMED' else 'CANCELLED' end,
      consumed_at=case when r.status='DECIDED' then coalesce(r.consumed_at,now()) else r.consumed_at end,
      updated_at=now()
  where r.status in('PENDING_SUPERADMIN','DECIDED')
    and exists(select 1 from pg_temp.rr_cb_child_truth_v615 c
      where c.unit_id=r.cb_unit_id and c.child_state<>'READY_FOR_CUTTING');
  get diagnostics v_retired=row_count;

  update public.rr_real_chat_message_bridge_v70 b
  set archived_at=coalesce(b.archived_at,now()),archive_reason='CUTTING_CHILD_NOT_READY_V615'
  where b.archived_at is null and b.canonical_key like 'CUTTING_MULTI_ART:%'
    and exists(select 1 from public.rr_cutting_multi_art_decisions_v1 r
      where b.canonical_key='CUTTING_MULTI_ART:'||r.id
        and r.status in('CANCELLED','CONSUMED'));

  return jsonb_build_object(
    'purchase_parents',v_rows,'ready_projections_upserted',v_ready,
    'multi_art_requests_retired',v_retired,
    'missing_ready_projection',(select count(*) from pg_temp.rr_cb_child_truth_v615 c
      where c.child_state='READY_FOR_CUTTING' and not exists(
        select 1 from public.rr_real_chat_message_bridge_v70 q
        where q.archived_at is null and q.source_module='CUTTING'
          and q.source_event_type='READY_FOR_CUTTING' and q.source_record_id=c.unit_id::text
      )),
    'stale_ready_projection',(select count(*) from public.rr_real_chat_message_bridge_v70 q
      where q.archived_at is null and q.source_module='CUTTING' and q.source_event_type='READY_FOR_CUTTING'
        and exists(select 1 from pg_temp.rr_cb_child_truth_v615 c
          where c.unit_id::text=q.source_record_id and c.child_state<>'READY_FOR_CUTTING')),
    'stale_multi_art_projection',(select count(*) from public.rr_real_chat_message_bridge_v70 b
      join public.rr_cutting_multi_art_decisions_v1 r on b.canonical_key='CUTTING_MULTI_ART:'||r.id
      where b.archived_at is null and r.status in('CANCELLED','CONSUMED'))
  );
end
$function$;

create or replace function public.rr_real_chat_cb_children_trigger_v105()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $function$
begin
  if pg_trigger_depth()>1 then return null; end if;
  perform public.rr_real_chat_reconcile_cb_children_v105();
  return null;
exception when others then
  raise warning 'V615 CB child reconciliation deferred: %',sqlerrm;
  return null;
end
$function$;

do $triggers$
declare t text;
begin
  foreach t in array array[
    'rr_cb_units','rr_cb_art_assignments','rr_cb_purchase_entries',
    'rr_cutting_lots_v3','rr_production_lots','rr_upm_lot_registry'
  ] loop
    execute format('drop trigger if exists zzzzzzzzz_rr_cb_children_v105 on public.%I',t);
    execute format('create trigger zzzzzzzzz_rr_cb_children_v105 after insert or update or delete on public.%I for each statement execute function public.rr_real_chat_cb_children_trigger_v105()',t);
  end loop;
end
$triggers$;

revoke all on function public.rr_cutting_request_multi_art_decision_v1(uuid) from public,anon;
revoke all on function public.rr_cutting_get_multi_art_decision_v1(uuid) from public,anon;
revoke all on function public.rr_cutting_decide_multi_art_v1(uuid,text,integer,jsonb) from public,anon;
revoke all on function public.rr_cutting_multi_art_inbox_v1() from public,anon;
grant execute on function public.rr_cutting_request_multi_art_decision_v1(uuid) to authenticated,service_role;
grant execute on function public.rr_cutting_get_multi_art_decision_v1(uuid) to authenticated,service_role;
grant execute on function public.rr_cutting_decide_multi_art_v1(uuid,text,integer,jsonb) to authenticated,service_role;
grant execute on function public.rr_cutting_multi_art_inbox_v1() to authenticated,service_role;

create or replace function public.rr_test_cutting_department_lifecycle_v615()
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $function$
declare
  v_profile record;
  v_regular uuid;
  v_additional uuid;
  v_art uuid;
  v_art_no text;
  v_cb_no text:='TEST71-V615-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_lot text:='T71C'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_additional_key uuid:=gen_random_uuid();
  v_payload jsonb;
  v_saved jsonb;
  v_cb uuid;
  v_unit uuid;
  v_colour uuid;
  v_art_due jsonb;
  v_hold jsonb;
  v_ready jsonb;
  v_close jsonb;
  v_request_1 jsonb;
  v_request_2 jsonb;
  v_decision_1 jsonb;
  v_decision_2 jsonb;
  v_release_id uuid;
  v_due_release_blocked boolean:=false;
  v_due_release_error text;
  v_retry_blocked boolean:=false;
  v_retry_error text;
  v_ready_bridge_count integer:=0;
  v_release_history_count integer:=0;
  v_request_status text;
  v_result jsonb;
  v_residue integer:=0;
begin
  perform set_config('statement_timeout','45000',true);

  select role_code,full_name into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if lower(coalesce(v_profile.role_code,''))<>'super_admin'
     or lower(coalesce(v_profile.full_name,'')) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required';
  end if;
  if coalesce((public.rr_upm_effective_identity_v200()->>'on_behalf')::boolean,false) then
    raise exception 'Return Act As to signed-in TEST E2E Super Admin before running fixture';
  end if;

  select id into v_regular from public.rr_material_categories
  where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_additional from public.rr_material_categories
  where is_active and id<>v_regular and not lower(coalesce(category_code,'')) like '%matching%'
  order by sort_order,category_name limit 1;
  select id,art_no into v_art,v_art_no from public.rr_art_master
  where is_active order by created_at,id limit 1;
  if v_regular is null or v_additional is null or v_art is null then
    raise exception 'V615 proof requires Regular Cloth, one additional Material and one active Art';
  end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',1,'colour_count',1,
      'remarks','TEST71 V615 rollback-only Cutting lifecycle proof',
      'colours',jsonb_build_array(jsonb_build_object(
        'index',1,'name','TEST COLOUR','image_url','https://example.invalid/test71-v615.jpg','confirmed',true
      )),
      'regular',jsonb_build_object(
        'client_key',gen_random_uuid(),'category_id',v_regular,
        'vendor','TEST71 Supplier','bill_no','TEST71-V615','bill_date',current_date,
        'fabric_name','TEST71 Regular Cloth','qty',1,'rate',1,'amount',1,
        'rolls',jsonb_build_array(jsonb_build_object('colour_index',1,'roll_no',1,'qty',1))
      ),
      'materials',jsonb_build_array(jsonb_build_object(
        'client_key',v_additional_key,'category_id',v_additional,
        'state','DUE','unit','PCS','cutting_blocking',true,
        'vendor','','bill_no','','bill_date','','fabric_name','','qty','','rate',null,'amount',null
      ))
    );

    v_saved:=public.rr_cb_department_save_v600(null,gen_random_uuid(),false,v_payload);
    v_cb:=(v_saved->>'cb_id')::uuid;
    perform public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),true,v_payload);
    select id into v_unit from public.rr_cb_units
    where purchase_id=v_cb and coalesce(is_final,true)
    order by division_index,id limit 1;
    select id into v_colour from public.rr_cb_colours
    where cb_id=v_cb order by colour_order,id limit 1;

    perform public.rr_real_chat_reconcile_cb_children_v105();
    v_art_due:=public.rr_cutting_child_lifecycle_v615(v_unit);

    perform public.rr_pm_save_decision_bundle_v804(
      v_unit,v_art,'NA','{}'::uuid[],'NA','{}'::uuid[],'NA','{}'::uuid[],'TEST'
    );
    v_hold:=public.rr_cutting_child_lifecycle_v615(v_unit);

    begin
      perform public.rr_release_single_lot_v3(
        v_lot,v_unit,current_date,'TEST71 Cutting lifecycle',v_art_no,'N/A','TEST E2E',
        array['L']::text[],1,1,0,0,0,'small','half','without',0,
        'TEST71 V615 DUE gate attempt',jsonb_build_array(jsonb_build_object(
          'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
        ))
      );
    exception when others then
      v_due_release_error:=sqlerrm;
      v_due_release_blocked:=sqlerrm ilike '%Material Due%';
    end;

    update public.rr_cb_purchase_entries
    set requirement_state='CONFIRMED',quantity=1,rate=1,
        vendor_name='TEST71 Supplier',vendor_bill_no='TEST71-V615-M',bill_date=current_date,
        fabric_name='TEST71 Confirmed Material'
    where cb_id=v_cb and client_key=v_additional_key;
    perform public.rr_real_chat_reconcile_cb_children_v105();
    v_ready:=public.rr_cutting_child_lifecycle_v615(v_unit);

    v_request_1:=public.rr_cutting_request_multi_art_decision_v1(v_unit);
    v_request_2:=public.rr_cutting_request_multi_art_decision_v1(v_unit);
    v_decision_1:=public.rr_cutting_decide_multi_art_v1(
      (v_request_1->>'request_id')::uuid,'SAME_EXISTING',2,'[]'::jsonb
    );
    v_decision_2:=public.rr_cutting_decide_multi_art_v1(
      (v_request_1->>'request_id')::uuid,'SAME_EXISTING',2,'[]'::jsonb
    );

    perform public.rr_save_cutting_lot_draft_v1(
      v_cb,v_unit,'single',v_lot,
      jsonb_build_object('source','TEST71_V615_ROLLBACK','lot_no',v_lot),
      'OPEN',null,null
    );
    v_release_id:=public.rr_release_single_lot_v3(
      v_lot,v_unit,current_date,'TEST71 Cutting lifecycle',v_art_no,'N/A','TEST E2E',
      array['L']::text[],1,1,0,0,0,'small','half','without',0,
      'TEST71 V615 rollback-only release',jsonb_build_array(jsonb_build_object(
        'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
      ))
    );
    perform public.rr_real_chat_reconcile_cb_children_v105();
    v_close:=public.rr_cutting_child_lifecycle_v615(v_unit);

    select status into v_request_status
    from public.rr_cutting_multi_art_decisions_v1
    where id=(v_request_1->>'request_id')::uuid;
    select count(*) into v_ready_bridge_count
    from public.rr_real_chat_message_bridge_v70
    where archived_at is null and source_module='CUTTING'
      and source_event_type='READY_FOR_CUTTING' and source_record_id=v_unit::text;
    select count(*) into v_release_history_count
    from public.rr_real_chat_message_bridge_v70 b
    join public.rr_upm_lot_registry l on l.id::text=b.source_record_id
    where b.archived_at is null and b.source_module='CUTTING'
      and b.source_event_type='CUTTING_RELEASE_SUCCEEDED' and upper(l.lot_no)=upper(v_lot)
      and b.personal_payload->>'canonical_state'='CLOSE';

    begin
      perform public.rr_release_single_lot_v3(
        v_lot,v_unit,current_date,'TEST71 Cutting lifecycle',v_art_no,'N/A','TEST E2E',
        array['L']::text[],1,1,0,0,0,'small','half','without',0,
        'TEST71 V615 retry',jsonb_build_array(jsonb_build_object(
          'cb_colour_id',v_colour::text,'colour_name','TEST COLOUR','size_code','L','qty',1
        ))
      );
    exception when others then
      v_retry_error:=sqlerrm;
      v_retry_blocked:=sqlerrm ilike '%already%' or sqlstate='23505';
    end;

    v_result:=jsonb_build_object(
      'art_due',v_art_due,'cutting_hold',v_hold,'ready',v_ready,'close',v_close,
      'due_release_blocked',v_due_release_blocked,'due_release_error',v_due_release_error,
      'request_first',v_request_1,'request_retry',v_request_2,
      'decision_first',v_decision_1,'decision_retry',v_decision_2,
      'release_id',v_release_id,'release_retry_blocked',v_retry_blocked,'release_retry_error',v_retry_error,
      'multi_request_final_status',v_request_status,
      'actionable_ready_count',v_ready_bridge_count,'release_history_count',v_release_history_count
    );

    if v_art_due->>'state'<>'ART_DUE'
       or v_hold->>'state'<>'CUTTING_HOLD'
       or coalesce((v_hold->>'material_due_count')::integer,0)<>1
       or not v_due_release_blocked
       or v_ready->>'state'<>'READY_FOR_CUTTING'
       or v_ready->>'canonical_state'<>'WORKING'
       or v_request_1->>'request_id'<>v_request_2->>'request_id'
       or not coalesce((v_request_2->>'duplicate_blocked')::boolean,false)
       or not coalesce((v_decision_2->>'duplicate_blocked')::boolean,false)
       or v_close->>'state'<>'RELEASED'
       or v_close->>'canonical_state'<>'CLOSE'
       or not v_retry_blocked
       or v_request_status<>'CONSUMED'
       or v_ready_bridge_count<>0
       or v_release_history_count<>1 then
      raise exception 'V615 Cutting lifecycle invariant failed: %',v_result;
    end if;

    raise exception using errcode='P6151',message='TEST71_CUTTING_LIFECYCLE_ROLLBACK';
  exception when sqlstate 'P6151' then
    if sqlerrm<>'TEST71_CUTTING_LIFECYCLE_ROLLBACK' then raise; end if;
  end;

  select
    (select count(*) from public.rr_fabric_purchases where cb_no=v_cb_no)
    +(select count(*) from public.rr_cb_units where id=v_unit)
    +(select count(*) from public.rr_cutting_lots_v3 where cb_unit_id=v_unit)
    +(select count(*) from public.rr_production_lots where cb_unit_id=v_unit)
    +(select count(*) from public.rr_cutting_multi_art_decisions_v1 where cb_unit_id=v_unit)
    +(select count(*) from public.rr_real_chat_message_bridge_v70
      where source_record_id=v_unit::text or personal_payload->>'cb_unit_id'=v_unit::text)
  into v_residue;

  return v_result||jsonb_build_object(
    'exact_invariant',true,'rolled_back',v_residue=0,'fixture_residue',v_residue
  );
end
$function$;

revoke all on function public.rr_test_cutting_department_lifecycle_v615() from public,anon;
grant execute on function public.rr_test_cutting_department_lifecycle_v615() to authenticated,service_role;

select public.rr_real_chat_reconcile_cb_children_v105();
notify pgrst,'reload schema';
commit;
