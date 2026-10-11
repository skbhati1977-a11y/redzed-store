-- Preserve REAL reconciliation; only equivalent TEST rows skip trigger fan-out.
CREATE OR REPLACE FUNCTION public.rr_real_chat_reconcile_cutting_v113()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_open integer:=0;v_stale integer:=0;v_released integer:=0;
begin
 update public.rr_real_chat_message_bridge_v70 b set archived_at=coalesce(b.archived_at,now()),archive_reason='LOT_RELEASED_CANONICAL_CLOSE',action_code=null,action_label=null
 where b.archived_at is null and b.source_module='CUTTING' and b.source_event_type='READY_FOR_CUTTING' and (exists(select 1 from public.rr_cutting_lots_v3 l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')) or exists(select 1 from public.rr_production_lots l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'))); get diagnostics v_stale=row_count;
 update public.rr_real_chat_message_bridge_v70 b set action_code='CUTTING_SINGLE_LOT',action_label='SINGLE LOT',personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है','next_actions',jsonb_build_array(jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है','next_actions',jsonb_build_array(jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),deep_link='real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single'
 where b.archived_at is null and b.source_module='CUTTING' and b.source_event_type='READY_FOR_CUTTING' and not exists(select 1 from public.rr_cutting_lots_v3 l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')) and not exists(select 1 from public.rr_production_lots l where l.cb_unit_id::text=b.source_record_id and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED'))
 and (b.data_mode is distinct from 'TEST' or row(b.action_code,b.action_label,b.personal_payload,b.group_payload,b.deep_link) is distinct from row('CUTTING_SINGLE_LOT','SINGLE LOT',(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है','next_actions',jsonb_build_array(jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),(coalesce(b.group_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state','OPEN','status','OPEN','message','Art / Print decision complete — Cutting Lot बनाना बाकी है','next_actions',jsonb_build_array(jsonb_build_object('code','CUTTING_SINGLE_LOT','label','SINGLE LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')),jsonb_build_object('code','CUTTING_MULTI_LOT','label','MULTI LOT','href','real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=multi','engine','EXISTING_CUTTING_RELEASE_CHAIN','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER')))),'real-cutting-master.html?cb_unit_id='||b.source_record_id||'&lot_mode=single')); get diagnostics v_open=row_count;
 with released as(select b0.id bridge_id,l.canonical_lot_id,l.lot_no,exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=l.canonical_lot_id) assigned from public.rr_real_chat_message_bridge_v70 b0 join public.rr_upm_lot_registry l on l.id::text=b0.source_record_id where b0.archived_at is null and b0.source_module='CUTTING' and b0.source_event_type='CUTTING_RELEASE_SUCCEEDED')
 update public.rr_real_chat_message_bridge_v70 b set personal_payload=(coalesce(b.personal_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state',case when r.assigned then 'CLOSE' else 'WORKING' end,'status',case when r.assigned then 'CLOSE' else 'WORKING' end,'message',case when r.assigned then 'Work assigned — Cutting handoff complete' else 'Lot released — worker assignment pending' end,'next_actions',case when r.assigned then '[]'::jsonb else jsonb_build_array(jsonb_build_object('code','ASSIGN_WORKER','label','ASSIGN WORK','href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&lot='||r.lot_no,'engine','rr_upm_ready_to_assign_v9107')) end,'action_href',case when r.assigned then null else 'real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&lot='||r.lot_no end,'allowed_roles',case when r.assigned then '[]'::jsonb else jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER','MANAGER','LINE_MANAGER','LINE_MAN') end),group_payload=(coalesce(b.group_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state',case when r.assigned then 'CLOSE' else 'WORKING' end,'status',case when r.assigned then 'CLOSE' else 'WORKING' end,'message',case when r.assigned then 'Work assigned — Cutting handoff complete' else 'Lot released — worker assignment pending' end,'next_actions',case when r.assigned then '[]'::jsonb else jsonb_build_array(jsonb_build_object('code','ASSIGN_WORKER','label','ASSIGN WORK','href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&lot='||r.lot_no,'engine','rr_upm_ready_to_assign_v9107')) end),action_code=case when r.assigned then null else 'ASSIGN_WORKER' end,action_label=case when r.assigned then null else 'ASSIGN WORK' end from released r where b.id=r.bridge_id
 and (b.data_mode is distinct from 'TEST' or row(b.personal_payload,b.group_payload,b.action_code,b.action_label) is distinct from row((coalesce(b.personal_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state',case when r.assigned then 'CLOSE' else 'WORKING' end,'status',case when r.assigned then 'CLOSE' else 'WORKING' end,'message',case when r.assigned then 'Work assigned — Cutting handoff complete' else 'Lot released — worker assignment pending' end,'next_actions',case when r.assigned then '[]'::jsonb else jsonb_build_array(jsonb_build_object('code','ASSIGN_WORKER','label','ASSIGN WORK','href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&lot='||r.lot_no,'engine','rr_upm_ready_to_assign_v9107')) end,'action_href',case when r.assigned then null else 'real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&lot='||r.lot_no end,'allowed_roles',case when r.assigned then '[]'::jsonb else jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER','MANAGER','LINE_MANAGER','LINE_MAN') end),(coalesce(b.group_payload,'{}'::jsonb)-'next_actions')||jsonb_build_object('canonical_state',case when r.assigned then 'CLOSE' else 'WORKING' end,'status',case when r.assigned then 'CLOSE' else 'WORKING' end,'message',case when r.assigned then 'Work assigned — Cutting handoff complete' else 'Lot released — worker assignment pending' end,'next_actions',case when r.assigned then '[]'::jsonb else jsonb_build_array(jsonb_build_object('code','ASSIGN_WORKER','label','ASSIGN WORK','href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&rrMode=ASSIGN&lot='||r.lot_no,'engine','rr_upm_ready_to_assign_v9107')) end),case when r.assigned then null else 'ASSIGN_WORKER' end,case when r.assigned then null else 'ASSIGN WORK' end)); get diagnostics v_released=row_count;
 return jsonb_build_object('cutting_open',v_open,'stale_ready_archived',v_stale,'cutting_released',v_released,'working_unassigned',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type='CUTTING_RELEASE_SUCCEEDED' and personal_payload->>'canonical_state'='WORKING'),'closed_assigned',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type='CUTTING_RELEASE_SUCCEEDED' and personal_payload->>'canonical_state'='CLOSE'));
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_real_chat_purchase_next_actions_v104()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid; v_worker uuid; v_name text; v_rows integer:=0;
begin
 select p.auth_user_id,d.worker_id,coalesce(d.worker_name,p.full_name)
 into v_user,v_worker,v_name
 from public.rr_user_profiles p
 left join public.rr_worker_directory_unified_v1 d
  on d.linked_auth_user_id=p.auth_user_id and coalesce(d.is_active,false)
 where coalesce(p.is_active,false) and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  and regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g') in ('SUPERADMIN','OWNER')
 order by case when regexp_replace(upper(coalesce(p.role_code,'')),'[^A-Z]','','g')='SUPERADMIN' then 0 else 1 end,
  p.updated_at desc nulls last,d.worker_id limit 1;

 with pending as (
  select b.id,
   jsonb_agg(jsonb_build_object(
    'code','ART_DECIDE_SUBMIT','label','DECIDE ART · '||u.cb_code,
    'href','real-art-decide-master.html?cb_unit_id='||u.id,
    'engine','rr_pm_save_decision_bundle_v804','cb_unit_id',u.id
   ) order by u.created_at,u.cb_code) actions,
   min('real-art-decide-master.html?cb_unit_id='||u.id::text) first_href
  from public.rr_real_chat_message_bridge_v70 b
  join public.rr_cb_units u on u.purchase_id=b.source_record_id::uuid
  left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
  where b.archived_at is null and b.source_module='CB_PURCHASE'
   and b.source_event_type='CREATE_CB_SUCCEEDED'
   and b.personal_payload->>'canonical_state'='OPEN'
   and coalesce(d.all_decisions_complete,false)=false
  group by b.id
 )
 update public.rr_real_chat_message_bridge_v70 b set receiver_user_id=v_user,receiver_worker_id=v_worker,
  action_code='ART_DECIDE_SUBMIT',action_label='DECIDE ART / PRINT / STICKER / METAL ID',
  deep_link=p.first_href,
  personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
   'action_href',p.first_href,'action_engine','rr_pm_save_decision_bundle_v804',
   'next_actions',p.actions,'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
   'receiver_name',v_name,'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
   'message','अगले pending CB unit का Art / Print / Sticker / Metal ID decide करें'),
  group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
   'action_href',p.first_href,'action_engine','rr_pm_save_decision_bundle_v804',
   'next_actions',p.actions,'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
   'receiver_name',v_name,'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
   'message','अगले pending CB unit का Art / Print / Sticker / Metal ID decide करें')
 from pending p where b.id=p.id
 and (b.data_mode is distinct from 'TEST' or row(b.receiver_user_id,b.receiver_worker_id,b.action_code,b.action_label,b.deep_link,b.personal_payload,b.group_payload) is distinct from row(v_user,v_worker,'ART_DECIDE_SUBMIT','DECIDE ART / PRINT / STICKER / METAL ID',p.first_href,coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
   'action_href',p.first_href,'action_engine','rr_pm_save_decision_bundle_v804',
   'next_actions',p.actions,'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
   'receiver_name',v_name,'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
   'message','अगले pending CB unit का Art / Print / Sticker / Metal ID decide करें'),coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
   'action_href',p.first_href,'action_engine','rr_pm_save_decision_bundle_v804',
   'next_actions',p.actions,'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN'),
   'receiver_name',v_name,'receiver_rule','EXACT_SUPERADMIN_THEN_OWNER',
   'message','अगले pending CB unit का Art / Print / Sticker / Metal ID decide करें')));
 get diagnostics v_rows=row_count;

 update public.rr_real_chat_message_bridge_v70 b set personal_payload=coalesce(b.personal_payload,'{}'::jsonb)-'action_href'-'action_engine'-'next_actions',
     group_payload=coalesce(b.group_payload,'{}'::jsonb)-'action_href'-'action_engine'-'next_actions'
 where b.archived_at is null and b.source_module='CB_PURCHASE'
  and coalesce(b.personal_payload->>'canonical_state','')<>'OPEN'
 and (b.data_mode is distinct from 'TEST' or row(b.personal_payload,b.group_payload) is distinct from row(coalesce(b.personal_payload,'{}'::jsonb)-'action_href'-'action_engine'-'next_actions',coalesce(b.group_payload,'{}'::jsonb)-'action_href'-'action_engine'-'next_actions'));

 return jsonb_build_object('open_purchase_cards',v_rows,
  'open_missing_action',(select count(*) from public.rr_real_chat_message_bridge_v70
   where archived_at is null and source_module='CB_PURCHASE'
    and personal_payload->>'canonical_state'='OPEN'
    and (action_code is null or nullif(personal_payload->>'action_href','') is null)));
end $function$
;

NOTIFY pgrst, 'reload schema';
