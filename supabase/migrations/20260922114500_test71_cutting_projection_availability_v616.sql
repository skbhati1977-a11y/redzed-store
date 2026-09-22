-- TEST71 V616: make the existing CB/Cutting reconciliation close every
-- non-actionable child, including disabled/non-final historical units.
-- This replaces the shared reconciliation rule; it does not patch named rows.
begin;

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
  set archived_at=coalesce(q.archived_at,now()),archive_reason='CHILD_NOT_READY_V616'
  where q.archived_at is null and q.source_module='CUTTING' and q.source_event_type='READY_FOR_CUTTING'
    and not exists(select 1 from pg_temp.rr_cb_child_truth_v615 c
      where c.unit_id::text=q.source_record_id and c.child_state='READY_FOR_CUTTING');

  update public.rr_cutting_multi_art_decisions_v1 r
  set status=case when r.status='DECIDED' then 'CONSUMED' else 'CANCELLED' end,
      consumed_at=case when r.status='DECIDED' then coalesce(r.consumed_at,now()) else r.consumed_at end,
      updated_at=now()
  where r.status in('PENDING_SUPERADMIN','DECIDED')
    and not exists(select 1 from pg_temp.rr_cb_child_truth_v615 c
      where c.unit_id=r.cb_unit_id and c.child_state='READY_FOR_CUTTING');
  get diagnostics v_retired=row_count;

  update public.rr_real_chat_message_bridge_v70 b
  set archived_at=coalesce(b.archived_at,now()),archive_reason='CUTTING_CHILD_NOT_READY_V616'
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
        and not exists(select 1 from pg_temp.rr_cb_child_truth_v615 c
          where c.unit_id::text=q.source_record_id and c.child_state='READY_FOR_CUTTING')),
    'stale_multi_art_projection',(select count(*) from public.rr_real_chat_message_bridge_v70 b
      join public.rr_cutting_multi_art_decisions_v1 r on b.canonical_key='CUTTING_MULTI_ART:'||r.id
      where b.archived_at is null and r.status in('CANCELLED','CONSUMED'))
  );
end
$function$;

select public.rr_real_chat_reconcile_cb_children_v105();

commit;
