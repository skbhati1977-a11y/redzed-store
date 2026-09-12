-- TEST70 V113: project the existing Cutting Master actions into Real Chat.
begin;

insert into public.rr_real_chat_action_registry_v70(
 action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,
 opens_exact_card,registry_status,notes,source_department_code,target_department_code,routing_mode,
 parent_type,source_state,success_state,next_action_code,receiver_rule,unit_label,message_template,rollback_rule)
values
 ('CUTTING_SINGLE_LOT','SINGLE LOT','CUTTING','real-cutting-master.html','EXISTING_CUTTING_RELEASE_CHAIN',
  array['OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'],true,'ACTIVE','Opens the existing Single Lot sheet for the exact CB child.',
  'CUTTING','CUTTING','SOURCE_GROUP','CB_CHILD','READY_FOR_CUTTING','LOT_RELEASED','ASSIGN_WORKER','FIRST_AUTHORITATIVE_ASSIGNMENT',
  'PIECES','{cb_code} Single Lot cutting released as {lot_no}.','Existing cutting release reversal.'),
 ('CUTTING_MULTI_LOT','MULTI LOT','CUTTING','real-cutting-master.html','EXISTING_CUTTING_RELEASE_CHAIN',
  array['OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'],true,'ACTIVE','Opens the existing Multi Lot sheet for the exact CB child.',
  'CUTTING','CUTTING','SOURCE_GROUP','CB_CHILD','READY_FOR_CUTTING','LOT_RELEASED','ASSIGN_WORKER','FIRST_AUTHORITATIVE_ASSIGNMENT',
  'PIECES','{cb_code} Multi Lot cutting released.','Existing cutting release reversal.')
on conflict(action_code) do update set
 exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,source_page=excluded.source_page,
 rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,opens_exact_card=true,registry_status='ACTIVE',
 notes=excluded.notes,source_department_code='CUTTING',target_department_code='CUTTING',routing_mode='SOURCE_GROUP',
 parent_type=excluded.parent_type,source_state=excluded.source_state,success_state=excluded.success_state,
 next_action_code=excluded.next_action_code,receiver_rule=excluded.receiver_rule,unit_label=excluded.unit_label,
 message_template=excluded.message_template,rollback_rule=excluded.rollback_rule,updated_at=now();

create or replace function public.rr_real_chat_reconcile_cutting_v113()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_open integer:=0; v_released integer:=0;
begin
 update public.rr_real_chat_message_bridge_v70 b
 set action_code='CUTTING_SINGLE_LOT',action_label='SINGLE LOT',
     personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object(
      'canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है',
      'next_actions',jsonb_build_array(
       jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),
       jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),
     group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object(
      'canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है',
      'next_actions',jsonb_build_array(
       jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),
       jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),
     deep_link='real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single'
 where b.archived_at is null and b.source_module='CUTTING' and b.source_event_type='READY_FOR_CUTTING';
 get diagnostics v_open=row_count;

 with x as (
  select b0.id bridge_id,l.lot_no,exists(select 1 from public.rr_upm_work_assignments_v8 a
   where a.canonical_lot_id=l.canonical_lot_id and upper(coalesce(a.status,'')) not in ('CANCELLED','CANCELED')) assigned
  from public.rr_real_chat_message_bridge_v70 b0
  join public.rr_upm_lot_registry l on l.id::text=b0.source_record_id
  where b0.archived_at is null and b0.source_module='CUTTING' and b0.source_event_type='CUTTING_RELEASE_SUCCEEDED'
 )
 update public.rr_real_chat_message_bridge_v70 b
 set personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
      'canonical_state',case when x.assigned then 'CLOSE' else 'WORKING' end,
      'status',case when x.assigned then 'CLOSE' else 'WORKING' end,
      'message',case when x.assigned then 'Cutting complete — Lot अगले department ने स्वीकार किया' else 'Cutting complete — Lot assignment के लिए उपलब्ध है' end,
      'action_href',case when x.assigned then null else 'real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&lot='||x.lot_no end,
      'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')),
     group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
      'canonical_state',case when x.assigned then 'CLOSE' else 'WORKING' end,
      'status',case when x.assigned then 'CLOSE' else 'WORKING' end,
      'message',case when x.assigned then 'Cutting complete — Lot अगले department ने स्वीकार किया' else 'Cutting complete — Lot assignment के लिए उपलब्ध है' end,
      'action_href',case when x.assigned then null else 'real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&lot='||x.lot_no end,
      'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')),
     action_code=case when x.assigned then null else 'ASSIGN_WORKER' end,
     action_label=case when x.assigned then null else 'ASSIGN WORKER' end
 from x where b.id=x.bridge_id;
 get diagnostics v_released=row_count;
 return jsonb_build_object('cutting_open',v_open,'cutting_released',v_released,
  'working_unassigned',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type='CUTTING_RELEASE_SUCCEEDED' and personal_payload->>'canonical_state'='WORKING'),
  'closed_assigned',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type='CUTTING_RELEASE_SUCCEEDED' and personal_payload->>'canonical_state'='CLOSE'));
end $$;
revoke all on function public.rr_real_chat_reconcile_cutting_v113() from public,anon,authenticated;
grant execute on function public.rr_real_chat_reconcile_cutting_v113() to service_role;

create or replace function public.rr_real_chat_cutting_trigger_v113()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.rr_real_chat_reconcile_cutting_v113(); return null;
exception when others then raise warning 'V113 Cutting reconciliation deferred: %',sqlerrm; return null; end $$;

do $$ declare t text; begin
 foreach t in array array['rr_cb_art_assignments','rr_cutting_lots_v3','rr_upm_lot_registry','rr_upm_work_assignments_v8'] loop
  execute format('drop trigger if exists zzzzzzzzzzz_rr_cutting_v113 on public.%I',t);
  execute format('create trigger zzzzzzzzzzz_rr_cutting_v113 after insert or update or delete on public.%I for each statement execute function public.rr_real_chat_cutting_trigger_v113()',t);
 end loop;
end $$;

select public.rr_real_chat_reconcile_cutting_v113();
commit;
