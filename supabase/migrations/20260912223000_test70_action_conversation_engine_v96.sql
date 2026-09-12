-- TEST70 V96: common Action-to-Conversation engine, first vertical slice.
begin;

alter table public.rr_real_chat_action_registry_v70
 add column if not exists parent_type text,
 add column if not exists source_state text,
 add column if not exists success_state text,
 add column if not exists next_action_code text,
 add column if not exists receiver_rule text,
 add column if not exists unit_label text,
 add column if not exists message_template text,
 add column if not exists rollback_rule text;

insert into public.rr_real_chat_action_registry_v70(
 action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,
 opens_exact_card,registry_status,notes,source_department_code,target_department_code,routing_mode,
 parent_type,source_state,success_state,next_action_code,receiver_rule,unit_label,message_template,rollback_rule)
values
 ('CREATE_CB','CREATE CB','CB_PURCHASE','real-cb-new-v9130-fix2.html','rr_create_cb_v713',
  array['OWNER','SUPER_ADMIN','ADMIN'],true,'ACTIVE','Exact existing CB create flow; purchase lines remain authoritative.',
  'PURCHASE','PRODUCT_MASTER','HANDOVER','CB','DRAFT','PURCHASED','ART_DECIDE_SUBMIT','AUTHORIZED_ROLE_QUEUE',
  'KG / ROLLS','{cb_no} purchase completed. {unit_count} child card(s) ready for Art Decide.','Existing form rollback before completion; purchase reversal after completion.'),
 ('ART_DECIDE_SUBMIT','SAVE & EXIT','PRODUCT_MASTER','real-art-decide-master.html','rr_pm_save_decision_bundle_v804',
  array['OWNER','SUPER_ADMIN','ADMIN'],true,'ACTIVE','Exact existing Art → Print → Sticker → Metal ID bundle.',
  'PRODUCT_MASTER','CUTTING','HANDOVER','CB','ART_DUE','ART_DECIDED','CUTTING_RELEASE','AUTHORIZED_ROLE_QUEUE',
  'CB CHILD','{cb_code} Art/Crafting decided and ready for Cutting.','Edit existing decision / authoritative assignment reversal.'),
 ('CUTTING_RELEASE','RELEASE LOT NO','CUTTING','real-cutting-master.html','EXISTING_CUTTING_RELEASE_CHAIN',
  array['OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'],true,'ACTIVE','Existing single/multi Cutting release chain; no duplicate release workflow.',
  'CUTTING','CUTTING','SOURCE_GROUP','LOT','READY_FOR_CUTTING','LOT_RELEASED',null,'INFORMATIONAL_DEPARTMENT_GROUP',
  'PIECES','Lot {lot_no} released from {cb_no}.','Existing cutting cancel/reversal and stock restoration rules.')
on conflict(action_code) do update set
 exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,
 source_page=excluded.source_page,rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,
 opens_exact_card=excluded.opens_exact_card,registry_status='ACTIVE',notes=excluded.notes,
 source_department_code=excluded.source_department_code,target_department_code=excluded.target_department_code,
 routing_mode=excluded.routing_mode,parent_type=excluded.parent_type,source_state=excluded.source_state,
 success_state=excluded.success_state,next_action_code=excluded.next_action_code,
 receiver_rule=excluded.receiver_rule,unit_label=excluded.unit_label,
 message_template=excluded.message_template,rollback_rule=excluded.rollback_rule,updated_at=now();

create table if not exists public.rr_real_chat_canonical_events_v96(
 id uuid primary key default gen_random_uuid(),
 canonical_event_key text not null unique,
 parent_type text not null,
 parent_id text not null,
 action_code text not null references public.rr_real_chat_action_registry_v70(action_code),
 source_module text not null,
 source_record_id text not null,
 source_department_code text not null,
 target_department_code text,
 performer_user_id uuid,
 event_state text not null check(event_state in ('SUCCEEDED','ROLLED_BACK','FAILED')),
 source_view_state text not null check(source_view_state in ('OPEN','WORKING','CLOSE','REOPENED')),
 target_view_state text check(target_view_state in ('OPEN','WORKING','CLOSE','REOPENED')),
 result_payload jsonb not null default '{}'::jsonb,
 source_event_at timestamptz not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 archived_at timestamptz
);
alter table public.rr_real_chat_canonical_events_v96 enable row level security;
revoke all on public.rr_real_chat_canonical_events_v96 from public,anon,authenticated;

alter table public.rr_real_chat_message_bridge_v70
 add column if not exists canonical_event_id uuid references public.rr_real_chat_canonical_events_v96(id),
 add column if not exists projection_type text;

create or replace function public.rr_real_chat_reconcile_cb_slice_v96()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_events integer; v_views integer;
begin
 -- One canonical CREATE_CB event per CB; child queues are projections, not duplicate events.
 insert into public.rr_real_chat_canonical_events_v96(
  canonical_event_key,parent_type,parent_id,action_code,source_module,source_record_id,
  source_department_code,target_department_code,performer_user_id,event_state,
  source_view_state,target_view_state,result_payload,source_event_at)
 select 'CREATE_CB:'||x.purchase_id,'CB',x.purchase_id::text,'CREATE_CB','CB_PURCHASE',x.purchase_id::text,
  'PURCHASE','PRODUCT_MASTER',x.created_by,'SUCCEEDED','CLOSE','OPEN',
  jsonb_build_object('cb_no',x.cb_no,'unit_count',x.unit_count,'quantity',x.quantity,
   'amount',x.amount,'colour_count',x.colour_count,'source_entry_count',x.source_entry_count),x.created_at
 from (
  select u.purchase_id,min(u.cb_base_no) cb_no,count(*)::int unit_count,
   coalesce((select sum(p.quantity) from public.rr_cb_purchase_entries p where p.cb_id=u.purchase_id),sum(u.divided_weight)) quantity,
   coalesce((select sum(p.amount) from public.rr_cb_purchase_entries p where p.cb_id=u.purchase_id),sum(u.divided_amount)) amount,
   (select count(*)::int from public.rr_cb_colours c where c.cb_id=u.purchase_id) colour_count,
   (select count(*)::int from public.rr_cb_purchase_entries p where p.cb_id=u.purchase_id) source_entry_count,
   (select p.created_by from public.rr_cb_purchase_entries p where p.cb_id=u.purchase_id order by p.created_at limit 1) created_by,
   coalesce((select min(p.created_at) from public.rr_cb_purchase_entries p where p.cb_id=u.purchase_id),min(u.created_at)) created_at
  from public.rr_cb_units u group by u.purchase_id
 ) x
 on conflict(canonical_event_key) do update set result_payload=excluded.result_payload,
  performer_user_id=excluded.performer_user_id,updated_at=now(),archived_at=null;

 insert into public.rr_real_chat_canonical_events_v96(
  canonical_event_key,parent_type,parent_id,action_code,source_module,source_record_id,
  source_department_code,target_department_code,performer_user_id,event_state,
  source_view_state,target_view_state,result_payload,source_event_at)
 select 'ART_DECIDE_SUBMIT:'||a.id,'CB',u.purchase_id::text,'ART_DECIDE_SUBMIT','PRODUCT_MASTER',a.id::text,
  'PRODUCT_MASTER','CUTTING',a.assigned_by,'SUCCEEDED','CLOSE','OPEN',
  jsonb_build_object('cb_no',u.cb_base_no,'cb_code',u.cb_code,'cb_unit_id',u.id,
   'art_id',a.art_id,'print_due',a.print_due,'sticker_due',a.sticker_due,'metal_id_due',a.metal_id_due),
  coalesce(a.updated_at,a.created_at)
 from public.rr_cb_art_assignments a join public.rr_cb_units u on u.id=a.cb_id
 on conflict(canonical_event_key) do update set result_payload=excluded.result_payload,
  performer_user_id=excluded.performer_user_id,source_event_at=excluded.source_event_at,updated_at=now(),archived_at=null;

 insert into public.rr_real_chat_canonical_events_v96(
  canonical_event_key,parent_type,parent_id,action_code,source_module,source_record_id,
  source_department_code,target_department_code,performer_user_id,event_state,
  source_view_state,target_view_state,result_payload,source_event_at)
 select 'CUTTING_RELEASE:'||l.id,'LOT',l.id::text,'CUTTING_RELEASE','CUTTING',l.id::text,
  'CUTTING','CUTTING',l.created_by,'SUCCEEDED','CLOSE',null,
  jsonb_build_object('lot_no',l.lot_no,'cb_no',l.cb_no,'quantity',l.total_qty,'art_no',l.art_no,
   'print_no',l.print_no,'status',l.status,'art_images',coalesce(l.art_image_urls,'[]'::jsonb),
   'print_images',coalesce(l.print_image_urls,'[]'::jsonb)),l.created_at
 from public.rr_upm_lot_registry l
 on conflict(canonical_event_key) do update set result_payload=excluded.result_payload,
  performer_user_id=excluded.performer_user_id,source_event_at=excluded.source_event_at,updated_at=now(),archived_at=null;
 get diagnostics v_events=row_count;

 -- Replace destination-fanout legacy cards with event projections.
 update public.rr_real_chat_message_bridge_v70 set archived_at=coalesce(archived_at,now()),
  archive_reason='REPLACED_BY_ACTION_CONVERSATION_V96'
 where archived_at is null and (
  canonical_key like 'CB_PURCHASE:%' or canonical_key like 'MATCHING_PURCHASE:%'
  or canonical_key like 'PRODUCT_DECISION:%' or canonical_key like 'LOT_RELEASE:%');

 -- Purchase source completion, one card per CB conversation.
 insert into public.rr_real_chat_message_bridge_v70(
  canonical_key,source_module,source_record_id,source_event_type,department_code,sender_user_id,
  action_code,action_label,personal_payload,group_payload,deep_link,sent_at,canonical_event_id,projection_type,archived_at,archive_reason)
 select 'ACE:'||e.id||':SOURCE','CB_PURCHASE',e.source_record_id,'CREATE_CB_SUCCEEDED','PURCHASE',e.performer_user_id,
  null,null,payload.j,payload.j,'test70-cb-purchase-real-chat-pilot.html?chat=group&department=PURCHASE',e.source_event_at,e.id,'SOURCE',null,null
 from public.rr_real_chat_canonical_events_v96 e
 left join lateral(select p.vendor_name,p.vendor_bill_no,p.bill_date,p.fabric_name,p.rate
   from public.rr_cb_purchase_entries p where p.cb_id=e.source_record_id::uuid order by p.created_at limit 1) p on true
 cross join lateral(select jsonb_build_object('card_type','PURCHASE','conversation_parent','CB:'||e.source_record_id,
  'cb_no',e.result_payload->>'cb_no','supplier',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
  'fabric_name',p.fabric_name,'quantity',(e.result_payload->>'quantity')::numeric,'quantity_unit','KG',
  'roll_count',(select count(*) from public.rr_cb_purchase_rolls r join public.rr_cb_purchase_entries pe on pe.id=r.purchase_entry_id where pe.cb_id=e.source_record_id::uuid),
  'rate',p.rate,'amount',(e.result_payload->>'amount')::numeric,'colour_count',(e.result_payload->>'colour_count')::int,'purchase_line_count',(e.result_payload->>'source_entry_count')::int,
  'status','COMPLETED','message','CB purchase completed','sender_name','Purchase','source_department_code','PURCHASE',
  'target_department_code','PRODUCT_MASTER') j) payload
 where e.action_code='CREATE_CB'
 on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  sent_at=excluded.sent_at,canonical_event_id=excluded.canonical_event_id,projection_type='SOURCE',archived_at=null,archive_reason=null;

 -- Product Master OPEN queue: one projection per child unit still awaiting Art Decide.
 insert into public.rr_real_chat_message_bridge_v70(
  canonical_key,source_module,source_record_id,source_event_type,department_code,sender_user_id,
  action_code,action_label,personal_payload,group_payload,deep_link,sent_at,canonical_event_id,projection_type,archived_at,archive_reason)
 select 'ACE:'||e.id||':TARGET:'||u.id,'PRODUCT_MASTER',u.id::text,'ART_DECIDE_PENDING','PRODUCT_MASTER',e.performer_user_id,
  'ART_DECIDE_SUBMIT','DECIDE ART / CRAFTING',payload.j,payload.j,
  'real-art-decide-master.html?cb_unit_id='||u.id,e.source_event_at,e.id,'TARGET',null,null
 from public.rr_real_chat_canonical_events_v96 e join public.rr_cb_units u on u.purchase_id=e.source_record_id::uuid
 cross join lateral(select jsonb_build_object('card_type','ART_DECIDE','conversation_parent','CB:'||u.purchase_id,
  'cb_no',u.cb_base_no,'cb_code',u.cb_code,'cb_unit_id',u.id,'quantity',u.divided_weight,'quantity_unit','KG',
  'roll_count',u.divided_rolls,'status','OPEN','message','Art / Crafting decide करना बाकी है',
  'sender_name','Purchase','receiver_name','Product Master Queue','origin_department_code','PURCHASE','source_department_code','PRODUCT_MASTER',
  'target_department_code','PRODUCT_MASTER','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN'),
  'action_href','real-art-decide-master.html?cb_unit_id='||u.id,'action_engine','rr_pm_save_decision_bundle_v804') j) payload
 where e.action_code='CREATE_CB' and not exists(select 1 from public.rr_cb_art_assignments a where a.cb_id=u.id)
 on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;

 -- Art decision completion in Product Master.
 insert into public.rr_real_chat_message_bridge_v70(
  canonical_key,source_module,source_record_id,source_event_type,department_code,sender_user_id,
  action_code,action_label,personal_payload,group_payload,deep_link,sent_at,canonical_event_id,projection_type,archived_at,archive_reason)
 select 'ACE:'||e.id||':SOURCE','PRODUCT_MASTER',a.id::text,'ART_DECIDE_SUCCEEDED','PRODUCT_MASTER',e.performer_user_id,
  null,null,payload.j,payload.j,'real-art-decide-master.html?cb_unit_id='||u.id,e.source_event_at,e.id,'SOURCE',null,null
 from public.rr_real_chat_canonical_events_v96 e join public.rr_cb_art_assignments a on a.id=e.source_record_id::uuid
 join public.rr_cb_units u on u.id=a.cb_id
 left join public.rr_art_master art on art.id=a.art_id
 cross join lateral(select jsonb_build_object('card_type','ART_DECIDE','conversation_parent','CB:'||u.purchase_id,
  'cb_no',u.cb_base_no,'cb_code',u.cb_code,'cb_unit_id',u.id,'art_no',art.art_no,
  'quantity',u.divided_weight,'quantity_unit','KG','status','COMPLETED','message','Art / Crafting decision completed',
  'sender_name','Product Master','source_department_code','PRODUCT_MASTER','target_department_code','CUTTING') j) payload
 where e.action_code='ART_DECIDE_SUBMIT'
 on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  sent_at=excluded.sent_at,canonical_event_id=excluded.canonical_event_id,projection_type='SOURCE',archived_at=null,archive_reason=null;

 -- Cutting OPEN queue after Art Decide, until an authoritative lot exists.
 insert into public.rr_real_chat_message_bridge_v70(
  canonical_key,source_module,source_record_id,source_event_type,department_code,sender_user_id,
  action_code,action_label,personal_payload,group_payload,deep_link,sent_at,canonical_event_id,projection_type,archived_at,archive_reason)
 select 'ACE:'||e.id||':TARGET','CUTTING',u.id::text,'READY_FOR_CUTTING','CUTTING',e.performer_user_id,
  'CUTTING_RELEASE','OPEN CUTTING / RELEASE LOT',payload.j,payload.j,
  'real-cutting-master.html?cb_unit_id='||u.id,e.source_event_at,e.id,'TARGET',null,null
 from public.rr_real_chat_canonical_events_v96 e join public.rr_cb_art_assignments a on a.id=e.source_record_id::uuid
 join public.rr_cb_units u on u.id=a.cb_id
 cross join lateral(select jsonb_build_object('card_type','READY_FOR_CUTTING','conversation_parent','CB:'||u.purchase_id,
  'cb_no',u.cb_base_no,'cb_code',u.cb_code,'cb_unit_id',u.id,'quantity',u.divided_weight,'quantity_unit','KG',
  'status','OPEN','message','Art decided — Cutting lot बनाना बाकी है','sender_name','Product Master',
  'receiver_name','Cutting Queue','origin_department_code','PRODUCT_MASTER','source_department_code','CUTTING','target_department_code','CUTTING',
  'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'),
  'action_href','real-cutting-master.html?cb_unit_id='||u.id,'action_engine','EXISTING_CUTTING_RELEASE_CHAIN') j) payload
 where e.action_code='ART_DECIDE_SUBMIT' and not exists(
  select 1 from public.rr_upm_lot_registry l where upper(coalesce(l.cb_no,''))=upper(u.cb_code)
   or l.metadata->>'cb_unit_id'=u.id::text)
 on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  action_code=excluded.action_code,action_label=excluded.action_label,deep_link=excluded.deep_link,
  department_code=excluded.department_code,canonical_event_id=excluded.canonical_event_id,projection_type='TARGET',archived_at=null,archive_reason=null;

 -- Cutting release source completion.
 insert into public.rr_real_chat_message_bridge_v70(
  canonical_key,source_module,source_record_id,source_event_type,department_code,sender_user_id,
  action_code,action_label,personal_payload,group_payload,deep_link,sent_at,canonical_event_id,projection_type,archived_at,archive_reason)
 select 'ACE:'||e.id||':SOURCE','CUTTING',l.id::text,'CUTTING_RELEASE_SUCCEEDED','CUTTING',e.performer_user_id,
  null,null,payload.j,payload.j,'real-cutting-master.html?lot='||l.lot_no,e.source_event_at,e.id,'SOURCE',null,null
 from public.rr_real_chat_canonical_events_v96 e join public.rr_upm_lot_registry l on l.id=e.source_record_id::uuid
 cross join lateral(select jsonb_build_object('card_type','CUTTING_RELEASED','conversation_parent','LOT:'||l.id,
  'lot_no',l.lot_no,'cb_no',l.cb_no,'quantity',l.total_qty,'quantity_unit','PCS','art_no',l.art_no,
  'print_no',l.print_no,'status','COMPLETED','message','Cutting lot released','sender_name','Cutting',
  'source_department_code','CUTTING','target_department_code','CUTTING') j) payload
 where e.action_code='CUTTING_RELEASE'
 on conflict(canonical_key) do update set personal_payload=excluded.personal_payload,group_payload=excluded.group_payload,
  sent_at=excluded.sent_at,canonical_event_id=excluded.canonical_event_id,projection_type='SOURCE',archived_at=null,archive_reason=null;

 -- Pending projections disappear when their authoritative next success exists.
 update public.rr_real_chat_message_bridge_v70 b set archived_at=coalesce(b.archived_at,now()),archive_reason='NEXT_ACTION_SUCCEEDED_V96'
 where b.projection_type='TARGET' and b.archived_at is null and (
  (b.source_event_type='ART_DECIDE_PENDING' and exists(select 1 from public.rr_cb_art_assignments a where a.cb_id=b.source_record_id::uuid))
  or (b.source_event_type='READY_FOR_CUTTING' and exists(select 1 from public.rr_cb_units u join public.rr_upm_lot_registry l
    on upper(coalesce(l.cb_no,''))=upper(u.cb_code) or l.metadata->>'cb_unit_id'=u.id::text where u.id=b.source_record_id::uuid)));
 get diagnostics v_views=row_count;
 return jsonb_build_object('canonical_events',(select count(*) from public.rr_real_chat_canonical_events_v96 where archived_at is null),
  'active_projections',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and canonical_event_id is not null),
  'art_open',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_event_type='ART_DECIDE_PENDING'),
  'cutting_open',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_event_type='READY_FOR_CUTTING'));
end $$;
revoke all on function public.rr_real_chat_reconcile_cb_slice_v96() from public,anon;
grant execute on function public.rr_real_chat_reconcile_cb_slice_v96() to authenticated,service_role;

create or replace function public.rr_real_chat_cb_slice_trigger_v96()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.rr_real_chat_reconcile_cb_slice_v96(); return null;
exception when others then raise warning 'Action conversation reconciliation deferred: %',sqlerrm; return null; end $$;
do $$ declare t text; begin foreach t in array array['rr_cb_purchase_entries','rr_cb_art_assignments','rr_upm_lot_registry'] loop
 execute format('drop trigger if exists rr_real_chat_action_conversation_v96 on public.%I',t);
 execute format('create trigger rr_real_chat_action_conversation_v96 after insert or update on public.%I for each statement execute function public.rr_real_chat_cb_slice_trigger_v96()',t);
end loop; end $$;

select public.rr_real_chat_reconcile_cb_slice_v96();
commit;
