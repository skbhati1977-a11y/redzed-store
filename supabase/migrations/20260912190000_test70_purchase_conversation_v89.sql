-- TEST70 V89: one truthful Purchase conversation per source entry.
begin;

insert into public.rr_real_chat_action_registry_v70
 (action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,
  opens_exact_card,registry_status,notes,source_department_code,target_department_code,routing_mode)
values
 ('CREATE_CB','CREATE CB','CB_PURCHASE','real-cb-new-v9130-fix2.html','rr_create_cb_v713',
  array['OWNER','SUPER_ADMIN','ADMIN'],true,'ACTIVE','Existing CB form submit; no duplicate workflow.',
  'PURCHASE','PRODUCT_MASTER','HANDOVER'),
 ('ART_DECIDE_SUBMIT','SUBMIT & CONTINUE','PRODUCT_MASTER','real-art-decide-master.html',
  'EXISTING_ART_DECIDE_SAVE_CHAIN',array['OWNER','SUPER_ADMIN','ADMIN'],true,'ACTIVE',
  'Existing Art Decide step chain.','PRODUCT_MASTER','PRODUCT_MASTER','SOURCE_GROUP')
on conflict(action_code) do update set exact_button_label=excluded.exact_button_label,
 source_module=excluded.source_module,source_page=excluded.source_page,rpc_name=excluded.rpc_name,
 allowed_roles=excluded.allowed_roles,registry_status='ACTIVE',notes=excluded.notes,
 source_department_code=excluded.source_department_code,target_department_code=excluded.target_department_code,
 routing_mode=excluded.routing_mode,updated_at=now();

-- Destination fan-out was a view concern, not two business events. Keep one source event.
update public.rr_real_chat_message_bridge_v70
set archived_at=coalesce(archived_at,now()),archive_reason='LEGACY_DESTINATION_DUPLICATE_V89'
where archived_at is null and source_module in ('CB_PURCHASE','MATCHING_PURCHASE')
 and canonical_key like '%:ACCOUNTS';

update public.rr_real_chat_message_bridge_v70 b set
 source_event_type='CB_PURCHASE_CONFIRMED',
 action_code=null,action_label=null,
 personal_payload=jsonb_build_object(
  'conversation_type','PURCHASE','purchase_kind','REGULAR_CLOTH','cb_no',coalesce(c.cb_no,p.cb_id::text),
  'supplier',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
  'fabric_name',p.fabric_name,'quantity',p.quantity,'quantity_unit','KG','rate',p.rate,
  'amount',p.amount,'available_quantity',p.available_quantity,'roll_count',coalesce(r.roll_count,0),
  'roll_quantity',coalesce(r.roll_quantity,0),'colour_count',coalesce(c.colour_count,0),
  'colour_images',coalesce(i.images,'[]'::jsonb),'status',coalesce(p.operation_status,'ACTIVE'),
  'message','Regular cloth purchase confirmed','sender_name','Purchase Team',
  'receiver_name',d.worker_name,'source_department_code','PURCHASE',
  'target_department_code','PRODUCT_MASTER','performed_by_user_id',p.created_by),
 group_payload=jsonb_build_object(
  'conversation_type','PURCHASE','purchase_kind','REGULAR_CLOTH','cb_no',coalesce(c.cb_no,p.cb_id::text),
  'supplier',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
  'fabric_name',p.fabric_name,'quantity',p.quantity,'quantity_unit','KG','rate',p.rate,
  'amount',p.amount,'roll_count',coalesce(r.roll_count,0),'colour_count',coalesce(c.colour_count,0),
  'status',coalesce(p.operation_status,'ACTIVE'),'message','Regular cloth purchase confirmed',
  'sender_name','Purchase Team','source_department_code','PURCHASE','target_department_code','PRODUCT_MASTER')
from public.rr_cb_purchase_entries p
left join public.rr_cb_master c on c.id=p.cb_id
left join lateral(select count(*)::int roll_count,coalesce(sum(x.quantity),0) roll_quantity
 from public.rr_cb_purchase_rolls x where x.purchase_entry_id=p.id
 and coalesce(x.operation_status,'ACTIVE')<>'REVERSED') r on true
left join lateral(select coalesce(jsonb_agg(x.image_url order by x.colour_order)
 filter(where x.image_url is not null),'[]'::jsonb) images
 from public.rr_cb_colours x where x.cb_id=p.cb_id) i on true
left join public.rr_real_chat_department_receiver_v86 pr on pr.department_code='PURCHASE' and pr.is_active
left join public.rr_worker_directory_unified_v1 d on d.worker_id=pr.worker_id
where b.source_module='CB_PURCHASE' and b.archived_at is null and b.source_record_id=p.id::text;

update public.rr_real_chat_message_bridge_v70 b set
 source_event_type='MATCHING_PURCHASE_CONFIRMED',action_code=null,action_label=null,
 personal_payload=jsonb_build_object(
  'conversation_type','PURCHASE','purchase_kind','MATCHING_CLOTH','cb_no',coalesce(c.cb_no,p.cb_id::text),
  'supplier',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
  'fabric_name',p.fabric_name,'quantity',p.quantity,'quantity_unit','KG','rate',p.rate,
  'amount',p.amount,'roll_count',0,'status',coalesce(p.status,'ACTIVE'),
  'message','Matching cloth purchase confirmed','sender_name','Purchase Team',
  'receiver_name',d.worker_name,'source_department_code','PURCHASE',
  'target_department_code','PRODUCT_MASTER','performed_by_user_id',p.created_by),
 group_payload=jsonb_build_object(
  'conversation_type','PURCHASE','purchase_kind','MATCHING_CLOTH','cb_no',coalesce(c.cb_no,p.cb_id::text),
  'supplier',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
  'fabric_name',p.fabric_name,'quantity',p.quantity,'quantity_unit','KG','rate',p.rate,
  'amount',p.amount,'roll_count',0,'status',coalesce(p.status,'ACTIVE'),
  'message','Matching cloth purchase confirmed','sender_name','Purchase Team',
  'source_department_code','PURCHASE','target_department_code','PRODUCT_MASTER')
from public.rr_matching_purchase_entries p
left join public.rr_cb_master c on c.id=p.cb_id
left join public.rr_real_chat_department_receiver_v86 pr on pr.department_code='PURCHASE' and pr.is_active
left join public.rr_worker_directory_unified_v1 d on d.worker_id=pr.worker_id
where b.source_module='MATCHING_PURCHASE' and b.archived_at is null and b.source_record_id=p.id::text;

commit;
