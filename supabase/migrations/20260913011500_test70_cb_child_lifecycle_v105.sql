-- TEST70 V105: one canonical lifecycle per CB child across legacy + current Lot sources.
begin;

create or replace function public.rr_real_chat_reconcile_cb_children_v105()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_rows integer:=0; v_ready integer:=0;
begin
 create temporary table if not exists pg_temp.rr_cb_child_truth_v105(
  purchase_id uuid,unit_id uuid primary key,cb_code text,created_at timestamptz,
  child_state text,lots jsonb
 ) on commit drop;
 truncate pg_temp.rr_cb_child_truth_v105;

 insert into pg_temp.rr_cb_child_truth_v105(purchase_id,unit_id,cb_code,created_at,child_state,lots)
 with child_truth as (
  select u.purchase_id,u.id unit_id,u.cb_code,u.created_at,
   coalesce(d.all_decisions_complete,false) decisions_complete,
   coalesce((
    select jsonb_agg(jsonb_build_object('lot_no',z.lot_no,'cutting_pieces',z.pcs) order by z.lot_no)
    from (
     select distinct on (lot_no) lot_no,pcs from (
      select l.lot_no,coalesce(nullif(l.actual_pcs,0),nullif(l.planned_pcs,0),0)::numeric pcs,1 priority
      from public.rr_cutting_lots_v3 l where l.cb_unit_id=u.id
      union all
      select l.lot_no,coalesce(nullif(l.verified_cut_qty,0),nullif(l.original_cut_qty,0),nullif(l.total_qty,0),0)::numeric,2
      from public.rr_upm_lot_registry l
      where upper(coalesce(l.cb_no,''))=upper(u.cb_code) or l.metadata->>'cb_unit_id'=u.id::text
     ) s order by lot_no,priority desc
    ) z
   ),'[]'::jsonb) lots
  from public.rr_cb_units u
  left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
 )
 select c.purchase_id,c.unit_id,c.cb_code,c.created_at,
   case when jsonb_array_length(c.lots)>0 then 'RELEASED'
        when c.decisions_complete then 'READY_FOR_CUTTING' else 'ART_DUE' end,
   c.lots
 from child_truth c;

 with parent_truth as (
  select purchase_id,
   case when bool_or(child_state='ART_DUE') then 'OPEN'
        when bool_and(child_state='RELEASED') then 'CLOSE' else 'WORKING' end canonical_state,
   jsonb_agg(jsonb_build_object('cb_unit_id',unit_id,'cb_code',cb_code,'state',child_state,'lots',lots)
    order by created_at,cb_code) children,
   coalesce(jsonb_agg(jsonb_build_object(
    'code',case when child_state='ART_DUE' then 'ART_DECIDE_SUBMIT' else 'CUTTING_RELEASE' end,
    'label',case when child_state='ART_DUE' then 'DECIDE ART · '||cb_code else 'READY FOR CUTTING · '||cb_code end,
    'href',case when child_state='ART_DUE' then 'real-art-decide-master.html?cb_unit_id='||unit_id
                else 'real-cutting-master.html?cb_unit_id='||unit_id end,
    'engine',case when child_state='ART_DUE' then 'rr_pm_save_decision_bundle_v804'
                  else 'EXISTING_CUTTING_RELEASE_CHAIN' end,
    'cb_unit_id',unit_id,
    'allowed_roles',case when child_state='ART_DUE' then jsonb_build_array('OWNER','SUPER_ADMIN')
                         else jsonb_build_array('OWNER','SUPER_ADMIN','CUTTING_MASTER') end
   ) order by created_at,cb_code) filter(where child_state in ('ART_DUE','READY_FOR_CUTTING')),'[]'::jsonb) actions
  from pg_temp.rr_cb_child_truth_v105 group by purchase_id
 ), first_action as (
  select p.*,p.actions->0 a from parent_truth p
 )
 update public.rr_real_chat_message_bridge_v70 b
 set personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions'-'cb_children'-'action_href'-'action_engine')
      ||jsonb_build_object('canonical_state',p.canonical_state,'cb_children',p.children,'next_actions',p.actions,
       'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','CUTTING_MASTER'))
      ||case when p.a is null then '{}'::jsonb else jsonb_build_object(
       'action_href',p.a->>'href','action_engine',p.a->>'engine') end,
     group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'next_actions'-'cb_children'-'action_href'-'action_engine')
      ||jsonb_build_object('canonical_state',p.canonical_state,'cb_children',p.children,'next_actions',p.actions,
       'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','CUTTING_MASTER'))
      ||case when p.a is null then '{}'::jsonb else jsonb_build_object(
       'action_href',p.a->>'href','action_engine',p.a->>'engine') end,
     action_code=p.a->>'code',action_label=p.a->>'label',deep_link=coalesce(p.a->>'href',b.deep_link)
 from first_action p
 where b.archived_at is null and b.source_module='CB_PURCHASE'
  and b.source_event_type='CREATE_CB_SUCCEEDED' and b.source_record_id=p.purchase_id::text;
 get diagnostics v_rows=row_count;

 -- Rebuild a missing Cutting OPEN projection only for a truly ready, unreleased child.
 insert into public.rr_real_chat_message_bridge_v70(
  canonical_key,source_module,source_record_id,source_event_type,department_code,sender_user_id,
  action_code,action_label,personal_payload,group_payload,deep_link,sent_at,canonical_event_id,
  projection_type,archived_at,archive_reason)
 select 'ACE:'||e.id||':TARGET','CUTTING',c.unit_id::text,'READY_FOR_CUTTING','CUTTING',e.performer_user_id,
  'CUTTING_RELEASE','READY FOR CUTTING · '||c.cb_code,payload.j,payload.j,
  'real-cutting-master.html?cb_unit_id='||c.unit_id,e.source_event_at,e.id,'TARGET',null,null
 from pg_temp.rr_cb_child_truth_v105 c
 join public.rr_cb_art_assignments a on a.cb_id=c.unit_id
 join public.rr_real_chat_canonical_events_v96 e
  on e.action_code='ART_DECIDE_SUBMIT' and e.source_record_id=a.id::text and e.archived_at is null
 cross join lateral(select jsonb_build_object(
  'card_type','READY_FOR_CUTTING','conversation_parent','CB:'||c.purchase_id,
  'cb_no',split_part(c.cb_code,'-S',1),'cb_code',c.cb_code,'cb_unit_id',c.unit_id,
  'status','OPEN','canonical_state','OPEN','message','Art decided — Cutting lot बनाना बाकी है',
  'sender_name','Product Master','receiver_name','Cutting Master Queue',
  'source_department_code','CUTTING','target_department_code','CUTTING',
  'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','CUTTING_MASTER'),
  'action_href','real-cutting-master.html?cb_unit_id='||c.unit_id,
  'action_engine','EXISTING_CUTTING_RELEASE_CHAIN') j) payload
 where c.child_state='READY_FOR_CUTTING'
 on conflict(canonical_key) do update set
  action_code=excluded.action_code,action_label=excluded.action_label,
  personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  deep_link=excluded.deep_link,archived_at=null,archive_reason=null;
 get diagnostics v_ready=row_count;

 update public.rr_real_chat_message_bridge_v70 q
 set archived_at=coalesce(q.archived_at,now()),archive_reason='CHILD_RELEASED_V105'
 where q.archived_at is null and q.source_module='CUTTING' and q.source_event_type='READY_FOR_CUTTING'
  and exists(select 1 from pg_temp.rr_cb_child_truth_v105 c where c.unit_id::text=q.source_record_id and c.child_state='RELEASED');

 return jsonb_build_object('purchase_parents',v_rows,'ready_projections_upserted',v_ready,
  'missing_ready_projection',(select count(*) from pg_temp.rr_cb_child_truth_v105 c where c.child_state='READY_FOR_CUTTING'
   and not exists(select 1 from public.rr_real_chat_message_bridge_v70 q where q.archived_at is null
    and q.source_module='CUTTING' and q.source_event_type='READY_FOR_CUTTING' and q.source_record_id=c.unit_id::text)),
  'premature_closed_parent',(select count(*)
   from public.rr_real_chat_message_bridge_v70 b
   where b.archived_at is null and b.source_module='CB_PURCHASE'
    and b.source_event_type='CREATE_CB_SUCCEEDED'
    and coalesce(b.personal_payload->>'canonical_state','')='CLOSE'
    and exists(select 1 from pg_temp.rr_cb_child_truth_v105 c
     where c.purchase_id::text=b.source_record_id and c.child_state<>'RELEASED')));
end $$;

revoke all on function public.rr_real_chat_reconcile_cb_children_v105() from public,anon,authenticated;
grant execute on function public.rr_real_chat_reconcile_cb_children_v105() to service_role;

create or replace function public.rr_real_chat_cb_children_trigger_v105()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.rr_real_chat_reconcile_cb_children_v105(); return null;
exception when others then raise warning 'V105 CB child reconciliation deferred: %',sqlerrm; return null; end $$;

do $$ declare t text; begin
 foreach t in array array['rr_cb_units','rr_cb_art_assignments','rr_cutting_lots_v3','rr_upm_lot_registry'] loop
  execute format('drop trigger if exists zzzzzzzzz_rr_cb_children_v105 on public.%I',t);
  execute format('create trigger zzzzzzzzz_rr_cb_children_v105 after insert or update or delete on public.%I for each statement execute function public.rr_real_chat_cb_children_trigger_v105()',t);
 end loop;
end $$;

select public.rr_real_chat_reconcile_cb_children_v105();
commit;
