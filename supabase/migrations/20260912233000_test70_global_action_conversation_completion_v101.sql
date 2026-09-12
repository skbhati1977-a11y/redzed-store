-- TEST70 V101: complete the existing-action conversation contract.
-- This does not create a parallel business workflow.  It only registers and
-- projects successful writes from the authoritative application engines.
begin;

insert into public.rr_real_chat_action_registry_v70(
 action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,
 opens_exact_card,registry_status,notes,source_department_code,target_department_code,routing_mode,
 parent_type,source_state,success_state,next_action_code,receiver_rule,unit_label,message_template,rollback_rule)
values
 ('ASSIGN_WORKER','ASSIGN WORKER','UPM','real-universal-production-v770-v9059.html','rr_upm_assign_colours_v8_3',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],true,'ACTIVE',
  'Receiver is the exact worker and department selected by the existing assignment; never infer a fixed next department.',
  null,null,'HANDOVER','LOT','OPEN','WORKING','SUBMIT','EXACT_ASSIGNED_WORKER','PCS',
  'Lot {lot_no} assigned to {worker_name} in {department_name}.','Existing reassign/cancel rules.'),
 ('SUBMIT','SUBMIT','UPM','real-universal-production-v770-v9059.html','rr_upm_submit_colours_v741',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD','WORKER'],true,'ACTIVE',
  'Successful department submit closes only that department projection; next OPEN appears only from an actual downstream assignment queue.',
  null,null,'SOURCE_GROUP','LOT','WORKING','CLOSE',null,'ACTUAL_NEXT_ASSIGNMENT_ONLY','PCS',
  '{department_name} submitted {qty} PCS for Lot {lot_no}.','Existing submit reversal / rectification.'),
 ('ALTER_FILL','ALTER FILL','UPM','real-universal-production-v770-v9059.html','rr_upm_alter_stage_v740',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],true,'ACTIVE',
  'Starts the existing evidence-backed Alter custody journey.','UPM',null,'SOURCE_GROUP','LOT','WORKING','REOPENED','REMAKE_ISSUE','MAPPED_LINE_MAN','PCS',
  'Alter {qty} PCS opened for Lot {lot_no}.','Resolve to Good, Damage, or existing cancellation.'),
 ('REMAKE_ISSUE','REMAKE ISSUE · CM','UPM','real-universal-production-v770-v9059.html','rr_upm_alter_stage_v740',
  array['OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'],true,'ACTIVE','Existing Cutting Master remake issue stage.',
  'UPM',null,'HANDOVER','LOT','REOPENED','WORKING','RECEIVE_MASTER','EXACT_CUSTODIAN','PCS',
  'Remake issued by Cutting Master for Lot {lot_no}.','Existing alter-stage reversal.'),
 ('RECEIVE_MASTER','RECEIVE MASTER · LM','UPM','real-universal-production-v770-v9059.html','rr_upm_alter_stage_v740',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'],true,'ACTIVE','Line Man receives remade goods from Master.',
  'UPM',null,'HANDOVER','LOT','WORKING','WORKING','DELIVER_KARIGAR','EXACT_CUSTODIAN','PCS',
  'Line Man received {qty} PCS from Master.','Existing alter-stage reversal.'),
 ('DELIVER_KARIGAR','DELIVER KARIGAR · LM','UPM','real-universal-production-v770-v9059.html','rr_upm_alter_stage_v740',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'],true,'ACTIVE','Line Man hands the remake to the exact Karigar.',
  'UPM',null,'HANDOVER','LOT','WORKING','WORKING','RECEIVE_KARIGAR','EXACT_KARIGAR','PCS',
  'Line Man delivered {qty} PCS to Karigar.','Existing alter-stage reversal.'),
 ('RECEIVE_KARIGAR','RECEIVE KARIGAR · LM','UPM','real-universal-production-v770-v9059.html','rr_upm_alter_stage_v740',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'],true,'ACTIVE','Final receive merges corrected quantity back to Good.',
  'UPM',null,'SOURCE_GROUP','LOT','WORKING','CLOSE',null,'EXACT_CUSTODIAN','PCS',
  'Corrected {qty} PCS received and merged to Good.','Existing correction/reversal audit.'),
 ('RECTIFICATION','RECTIFICATION · SAVE & EXIT','UPM_RECTIFICATION','real-upm-department-view-v789.js','rr_upm_open_rectification_v9110',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],true,'ACTIVE','Recall of already submitted Good quantity.',
  null,null,'SOURCE_GROUP','LOT','CLOSE','REOPENED',null,'EXACT_ORIGINAL_WORKER_AND_LINE_MAN','PCS',
  'Rectification opened for {qty} PCS of Lot {lot_no}.','Existing resubmit/close case.'),
 ('DAMAGE','SAVE DAMAGE','UPM','real-universal-production-v770-v9059.html','rr_upm_save_damage_v731',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD'],true,'ACTIVE','Damage is posted from its exact source bucket with frozen cost and responsibility.',
  null,null,'SOURCE_GROUP','LOT','WORKING','CLOSE',null,'RESPONSIBLE_WORKER_OR_DEPARTMENT','PCS',
  'Damage {qty} PCS locked for Lot {lot_no}.','Existing claim/no-claim and owner decision rules.'),
 ('PACKING_ASSIGN','ASSIGN WORK','PACKING','real-finished-goods-v787.html?view=packing','rr_fg_assign_packing_v788',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','PACKING'],true,'ACTIVE','Exact selected packing worker becomes receiver.',
  'PACKING','PACKING','HANDOVER','LOT','OPEN','WORKING','PACKING_ACCEPT','EXACT_ASSIGNED_WORKER','PCS','Lot {lot_no} assigned for Packing.','Existing packing reassign.'),
 ('PACKING_ACCEPT','ACCEPT WORK','PACKING','real-finished-goods-v787.html?view=packing','rr_fg_accept_packing_v788',
  array['OWNER','SUPER_ADMIN','ADMIN','PACKING'],true,'ACTIVE','Existing packing ownership acceptance.',
  'PACKING','PACKING','SOURCE_GROUP','LOT','WORKING','WORKING','PACKING_SUBMIT','EXACT_ASSIGNED_WORKER','PCS','Packing accepted for Lot {lot_no}.','Existing assignment reset.'),
 ('PACKING_SUBMIT','SUBMIT PACKING','PACKING','real-finished-goods-v787.html?view=packing','rr_fg_submit_assigned_pack_v788',
  array['OWNER','SUPER_ADMIN','ADMIN','PACKING'],true,'ACTIVE','Packing completion creates ready boxes.',
  'PACKING','DESPATCH','HANDOVER','LOT','WORKING','CLOSE','DESPATCH_CREATE','DESPATCH_QUEUE','BOX / PCS','Lot {lot_no} packed and ready for Despatch.','Existing pack-plan reset/reversal.'),
 ('DESPATCH_CREATE','CREATE LOCKED CHALLAN','DESPATCH','real-finished-goods-v787.html?view=despatch','rr_fg_create_despatch_queue_v9375',
  array['OWNER','SUPER_ADMIN','ADMIN','MANAGER','DESPATCH'],true,'ACTIVE','Existing Packer to exact selected Lineman custody transfer.',
  'DESPATCH','DESPATCH','HANDOVER','LOT','OPEN','WORKING','STORE_RECEIVE','EXACT_LINE_MAN','BOX / PCS','Challan {challan_no} is in transit.','Existing despatch cancellation/reversal.'),
 ('STORE_RECEIVE','STORE RECEIVE','DESPATCH','real-finished-goods-v787.html?view=receive','rr_fg_receive_accept_v9361',
  array['OWNER','SUPER_ADMIN','ADMIN','STORE','DESPATCH'],true,'ACTIVE','Exact receive result decides completed or Difference Hold.',
  'DESPATCH','STOCK','HANDOVER','LOT','WORKING','CLOSE','STOCK_POST','EXACT_STORE_RECEIVER','BOX / PCS','Challan {challan_no} received.','Difference Hold / receive correction.'),
 ('STOCK_POST','POST STOCK','STOCK_LEDGER','real-finished-goods-v787.html?view=stock','rr_fg_receive_accept_v9361',
  array['OWNER','SUPER_ADMIN','ADMIN','STORE','ACCOUNTS'],false,'ACTIVE','Stock posting is an automatic successful effect of authoritative receive, not a second manual workflow.',
  'STOCK','STOCK','SOURCE_GROUP','LOT','WORKING','CLOSE',null,'INFORMATIONAL_DEPARTMENT_GROUP','PCS','Lot {lot_no} stock posted.','Authoritative stock reversal only.'),
 ('OPEN_PI','SAVE PI & EXIT','SALES','real-finished-goods-v787.html?view=sale','rr_fg_save_pi_v787',
  array['OWNER','SUPER_ADMIN','ADMIN','SALES'],true,'ACTIVE','Existing editable PI; no stock deduction.',
  'SALES','SALES','SOURCE_GROUP','SALE','OPEN','WORKING','FINALIZE_CI','EXACT_CUSTOMER_RELATION','PCS / AMOUNT','PI {pi_no} saved.','Existing PI edit/cancel.'),
 ('FINALIZE_CI','SUBMIT AS CI','SALES','real-finished-goods-v787.html?view=sale','rr_fg_save_pi_v787',
  array['OWNER','SUPER_ADMIN','ADMIN','SALES'],true,'ACTIVE','Existing final CI and stock-out lock.',
  'SALES','SALES','SOURCE_GROUP','SALE','WORKING','WORKING','VERIFY_CPI_QTY','EXACT_CUSTOMER_RELATION','PCS / AMOUNT','CI {cpi_no} finalized.','Existing CI cancellation/reversal.'),
 ('VERIFY_CPI_QTY','QTY VERIFIED','SALES','real-finished-goods-v787.html?view=verify','rr_fg_verify_cpi_qty_v787',
  array['OWNER','SUPER_ADMIN','ADMIN','SALES'],true,'ACTIVE','Authoritative physical quantity verification.',
  'SALES','SALES','SOURCE_GROUP','SALE','WORKING','CLOSE',null,'EXACT_CUSTOMER_RELATION','PCS / AMOUNT','CI {cpi_no} quantity verified.','Existing verification correction.'),
 ('POST_SALES_RETURN','POST REVERSE RETURN','SALES_RETURN','real-finished-goods-v787.html?view=returns','rr_fg_post_return_v787',
  array['OWNER','SUPER_ADMIN','ADMIN','SALES','STORE','ACCOUNTS'],true,'ACTIVE','Existing known/anonymous return with stock and account reversal.',
  'SALES_RETURN','STOCK','HANDOVER','SALE_RETURN','OPEN','CLOSE',null,'EXACT_CUSTOMER_RELATION','PCS / AMOUNT','Return {return_no} posted and reversed.','Return cancellation through authoritative reversal only.'),
 ('DIFFERENCE_HOLD_RESOLVE','RESOLVE DIFFERENCE HOLD','DESPATCH','real-finished-goods-v787.html?view=receive','rr_fg_receive_accept_v9361',
  array['OWNER','SUPER_ADMIN','ADMIN','STORE','DESPATCH'],true,'ACTIVE','First-class receive mismatch exception; exact existing receive correction remains authoritative.',
  'DESPATCH','STOCK','HANDOVER','LOT','WORKING','CLOSE','STOCK_POST','EXACT_STORE_RECEIVER','BOX / PCS','Difference Hold resolved for {challan_no}.','Existing receive correction and evidence audit.')
on conflict(action_code) do update set
 exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,source_page=excluded.source_page,
 rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,opens_exact_card=excluded.opens_exact_card,
 registry_status=excluded.registry_status,notes=excluded.notes,source_department_code=excluded.source_department_code,
 target_department_code=excluded.target_department_code,routing_mode=excluded.routing_mode,parent_type=excluded.parent_type,
 source_state=excluded.source_state,success_state=excluded.success_state,next_action_code=excluded.next_action_code,
 receiver_rule=excluded.receiver_rule,unit_label=excluded.unit_label,message_template=excluded.message_template,
 rollback_rule=excluded.rollback_rule,updated_at=now();

-- Exact lifecycle resolver.  No LIKE/regex inference is allowed here.
create or replace function public.rr_real_chat_canonical_state_v83(
 p_source_module text,p_event_type text,p_action_code text,p_payload jsonb default '{}'::jsonb)
returns text language sql immutable set search_path='' as $$
 with x as (
  select upper(coalesce(p_source_module,'')) m,upper(coalesce(p_event_type,'')) e,
   upper(coalesce(p_action_code,'')) a,
   upper(coalesce(p_payload->>'canonical_state',p_payload->>'chat_status',p_payload->>'message_status',p_payload->>'status','')) s)
 select case
  when s in ('OPEN','WORKING','CLOSE','REOPENED') then s
  when e in ('ART_DECIDE_PENDING','READY_FOR_CUTTING','READY_TO_ASSIGN','LOT_OPEN','SALE_DRAFT','REQUIREMENT_OPEN','COLLECTION_OPEN') then 'OPEN'
  when e in ('WORK_ASSIGNED','CUTTING_RELEASE_SUCCEEDED','ALTER_FILL','LM_ACCEPT_REQUEST','LM_ACCEPT','REMAKE_ISSUE','RECEIVE_FROM_MASTER','DELIVER_TO_KARIGAR',
             'PACKING_ASSIGNED','PACKING_ACCEPTED','DESPATCH_IN_TRANSIT','SALE_CI_FINAL','DIFFERENCE_HOLD') then 'WORKING'
  when e in ('ART_DECIDE_SUCCEEDED','ASSIGNMENT_COMPLETED','ASSIGNMENT_CANCELLED',
             'WORK_SUBMITTED','KARIGAR_SUBMIT_GOOD','RECEIVE_FROM_KARIGAR','DAMAGE_POSTED','RECTIFICATION_CLOSED','PACKING_SUBMITTED',
             'DESPATCH_ACCEPTANCE_FINALIZED','DESPATCH_RECEIVED','STOCK_POSTED','SALE_CANCELLED','SALE_QTY_VERIFIED','SALES_RETURN_POSTED',
             'RCI_POSTED','RCI_REVERSED','PAYMENT_POSTED','ORDER_CLOSED','COLLECTION_CLOSED') then 'CLOSE'
  when a in ('ASSIGN_WORKER','PACKING_ASSIGN','PACKING_ACCEPT','OPEN_PI','FINALIZE_CI','STORE_RECEIVE','DIFFERENCE_HOLD_RESOLVE') then 'WORKING'
  when a in ('SUBMIT','PACKING_SUBMIT','DESPATCH_CREATE','STOCK_POST','VERIFY_CPI_QTY','POST_SALES_RETURN','DAMAGE','RECEIVE_KARIGAR') then 'CLOSE'
  else 'WORKING' end from x
$$;

-- Stable cross-module lineage key.  A sale/return keeps the actual lot key in
-- each line; the document parent stays separately available as SALE/RETURN.
create or replace function public.rr_real_chat_parent_key_v101(
 p_source_module text,p_source_record_id text,p_payload jsonb default '{}'::jsonb)
returns text language sql immutable set search_path='' as $$
 select case
  when nullif(p_payload->>'conversation_parent','') is not null then p_payload->>'conversation_parent'
  when nullif(p_payload->>'canonical_lot_id','') is not null then 'LOT:'||(p_payload->>'canonical_lot_id')
  when nullif(p_payload->>'lot_no','') is not null then 'LOTNO:'||upper(p_payload->>'lot_no')
  when nullif(p_payload->>'cb_id','') is not null then 'CB:'||(p_payload->>'cb_id')
  when nullif(p_payload->>'pi_id','') is not null then 'SALE:'||(p_payload->>'pi_id')
  when nullif(p_payload->>'return_id','') is not null then 'SALE_RETURN:'||(p_payload->>'return_id')
  else upper(coalesce(p_source_module,'WORK'))||':'||coalesce(p_source_record_id,'UNKNOWN') end
$$;

-- Enrich existing projections without changing their business records.
update public.rr_real_chat_message_bridge_v70 b
set personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
     'conversation_parent',public.rr_real_chat_parent_key_v101(b.source_module,b.source_record_id,b.personal_payload),
     'canonical_state',public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)),
    group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
     'conversation_parent',public.rr_real_chat_parent_key_v101(b.source_module,b.source_record_id,b.group_payload),
     'canonical_state',public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.group_payload))
where b.archived_at is null;

-- Dynamic lifecycle reconciliation for Purchase and Cutting.  Cutting has no
-- predetermined destination: the first authoritative UPM assignment decides
-- the department and exact worker.
create or replace function public.rr_real_chat_reconcile_dynamic_lifecycle_v101()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_purchase integer:=0; v_cutting integer:=0;
begin
 update public.rr_real_chat_message_bridge_v70 b
 set personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
      'canonical_state',case when exists(
        select 1 from public.rr_cb_units u
        left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
        where u.purchase_id=b.source_record_id::uuid
          and coalesce(d.all_decisions_complete,false)=false
      ) then 'OPEN' else 'CLOSE' end,
      'conversation_parent','CB:'||b.source_record_id),
     group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
      'canonical_state',case when exists(
        select 1 from public.rr_cb_units u
        left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
        where u.purchase_id=b.source_record_id::uuid
          and coalesce(d.all_decisions_complete,false)=false
      ) then 'OPEN' else 'CLOSE' end,
      'conversation_parent','CB:'||b.source_record_id),
     action_code=case when exists(
       select 1 from public.rr_cb_units u
       left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
       where u.purchase_id=b.source_record_id::uuid
        and coalesce(d.all_decisions_complete,false)=false
     ) then 'ART_DECIDE_SUBMIT' else null end,
     action_label=case when exists(
       select 1 from public.rr_cb_units u
       left join public.rr_pm_decision_status_v802 d on d.cb_unit_id=u.id
       where u.purchase_id=b.source_record_id::uuid
        and coalesce(d.all_decisions_complete,false)=false
     ) then 'DECIDE ART / PRINT / STICKER / METAL ID' else null end
 where b.archived_at is null and b.source_module='CB_PURCHASE'
  and b.source_event_type='CREATE_CB_SUCCEEDED'
  and b.source_record_id ~* '^[0-9a-f-]{36}$';
 get diagnostics v_purchase=row_count;

 update public.rr_real_chat_message_bridge_v70 b
 set personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object(
      'canonical_state',case when exists(
       select 1 from public.rr_upm_lot_registry l
       join public.rr_upm_work_assignments_v8 a on a.canonical_lot_id=l.canonical_lot_id
       where l.id=b.source_record_id::uuid
      ) then 'CLOSE' else 'WORKING' end,
      'conversation_parent','LOT:'||b.source_record_id,
      'action_href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&lot='||
        coalesce(b.personal_payload->>'lot_no',''),
      'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')),
     group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object(
      'canonical_state',case when exists(
       select 1 from public.rr_upm_lot_registry l
       join public.rr_upm_work_assignments_v8 a on a.canonical_lot_id=l.canonical_lot_id
       where l.id=b.source_record_id::uuid
      ) then 'CLOSE' else 'WORKING' end,
      'conversation_parent','LOT:'||b.source_record_id,
      'action_href','real-universal-production-v770-v9059.html?mode=TEST&from=TEST70_REAL_CHAT&lot='||
        coalesce(b.group_payload->>'lot_no',''),
      'allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')),
     action_code=case when exists(
       select 1 from public.rr_upm_lot_registry l
       join public.rr_upm_work_assignments_v8 a on a.canonical_lot_id=l.canonical_lot_id
       where l.id=b.source_record_id::uuid
     ) then null else 'ASSIGN_WORKER' end,
     action_label=case when exists(
       select 1 from public.rr_upm_lot_registry l
       join public.rr_upm_work_assignments_v8 a on a.canonical_lot_id=l.canonical_lot_id
       where l.id=b.source_record_id::uuid
     ) then null else 'ASSIGN WORKER' end
 where b.archived_at is null and b.source_module='CUTTING'
  and b.source_event_type='CUTTING_RELEASE_SUCCEEDED'
  and b.source_record_id ~* '^[0-9a-f-]{36}$';
 get diagnostics v_cutting=row_count;

 return jsonb_build_object('purchase_reconciled',v_purchase,'cutting_reconciled',v_cutting,
  'receiver_rule','FIRST_AUTHORITATIVE_ASSIGNMENT');
end $$;
revoke all on function public.rr_real_chat_reconcile_dynamic_lifecycle_v101() from public,anon;
grant execute on function public.rr_real_chat_reconcile_dynamic_lifecycle_v101() to authenticated,service_role;

create or replace function public.rr_real_chat_dynamic_lifecycle_trigger_v101()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.rr_real_chat_reconcile_dynamic_lifecycle_v101(); return null;
exception when others then raise warning 'V101 lifecycle reconciliation deferred: %',sqlerrm; return null; end $$;

do $$ declare t text; begin
 foreach t in array array['rr_cb_art_assignments','rr_upm_lot_registry','rr_upm_work_assignments_v8'] loop
  execute format('drop trigger if exists zzz_rr_dynamic_lifecycle_v101 on public.%I',t);
  execute format('create trigger zzz_rr_dynamic_lifecycle_v101 after insert or update or delete on public.%I for each statement execute function public.rr_real_chat_dynamic_lifecycle_trigger_v101()',t);
 end loop;
end $$;

select public.rr_real_chat_reconcile_dynamic_lifecycle_v101();

-- Normalize known bridge action codes to the exact existing registry action.
update public.rr_real_chat_message_bridge_v70 set action_code='PACKING_SUBMIT',action_label='SUBMIT PACKING'
 where archived_at is null and source_module='PACKING' and source_event_type='PACKING_SUBMITTED' and action_code is not null;
update public.rr_real_chat_message_bridge_v70 set action_code='VERIFY_CPI_QTY',action_label='QTY VERIFIED'
 where archived_at is null and source_module='SALES' and source_event_type='SALE_CI_FINAL' and action_code is not null;
update public.rr_real_chat_message_bridge_v70 set action_code='POST_SALES_RETURN',action_label='POST REVERSE RETURN'
 where archived_at is null and source_module='SALES_RETURN' and source_event_type='SALES_RETURN_POSTED' and action_code is not null;

-- A completed projection can never remain actionable.
update public.rr_real_chat_message_bridge_v70 b set action_code=null,action_label=null
where b.archived_at is null
 and public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)='CLOSE'
 and b.source_event_type not in ('SALE_CI_FINAL');

commit;
