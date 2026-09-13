-- TEST70 V114: authoritative Cutting Damage / GR lifecycle projection.
begin;

insert into public.rr_real_chat_action_registry_v70(
 action_code,exact_button_label,source_module,source_page,rpc_name,allowed_roles,
 opens_exact_card,registry_status,notes,source_department_code,target_department_code,routing_mode,
 parent_type,source_state,success_state,next_action_code,receiver_rule,unit_label,message_template,rollback_rule)
values
 ('CUTTING_ADMIN_VERIFY','ADMIN VERIFY','CUTTING','real-cutting-master.html','rr_cutting_admin_decide_cb_action_v1',array['OWNER','SUPER_ADMIN','ADMIN'],true,'ACTIVE','Existing Cutting Damage admin verification.','CUTTING','CUTTING','HANDOVER','DAMAGE_CASE','PENDING_ADMIN','ADMIN_VERIFIED','CUTTING_OWNER_APPROVE','ADMIN_ROLE','KG','{lot_no} damage Admin verified.','RECHECK'),
 ('CUTTING_ADMIN_RECHECK','RECHECK','CUTTING','real-cutting-master.html','rr_cutting_admin_decide_cb_action_v1',array['OWNER','SUPER_ADMIN','ADMIN'],true,'ACTIVE','Existing Cutting Damage recheck.','CUTTING','CUTTING','HANDOVER','DAMAGE_CASE','PENDING_ADMIN','RECHECK_REQUIRED','CUTTING_ADMIN_VERIFY','ADMIN_ROLE','KG','{lot_no} damage recheck required.','ADMIN_VERIFY'),
 ('CUTTING_ADMIN_REJECT','REJECT','CUTTING','real-cutting-master.html','rr_cutting_admin_decide_cb_action_v1',array['OWNER','SUPER_ADMIN','ADMIN'],true,'ACTIVE','Existing Cutting Damage admin rejection.','CUTTING','CUTTING','HANDOVER','DAMAGE_CASE','PENDING_ADMIN','REJECTED',null,'ADMIN_ROLE','KG','{lot_no} damage rejected.','NEW_DAMAGE_REPORT'),
 ('CUTTING_OWNER_APPROVE','OWNER APPROVE & APPLY','CUTTING','real-cutting-master.html','rr_cutting_owner_decide_cb_action_v1',array['OWNER','SUPER_ADMIN'],true,'ACTIVE','Existing Cutting Damage owner approval and effect posting.','CUTTING','CUTTING','HANDOVER','DAMAGE_CASE','ADMIN_VERIFIED','OWNER_APPROVED',null,'OWNER_ROLE','KG','{lot_no} damage approved and applied.','OWNER_REJECT'),
 ('CUTTING_OWNER_REJECT','OWNER REJECT','CUTTING','real-cutting-master.html','rr_cutting_owner_decide_cb_action_v1',array['OWNER','SUPER_ADMIN'],true,'ACTIVE','Existing Cutting Damage owner rejection.','CUTTING','CUTTING','HANDOVER','DAMAGE_CASE','ADMIN_VERIFIED','REJECTED',null,'OWNER_ROLE','KG','{lot_no} damage rejected by owner.','NEW_DAMAGE_REPORT')
on conflict(action_code) do update set
 exact_button_label=excluded.exact_button_label,source_module=excluded.source_module,source_page=excluded.source_page,
 rpc_name=excluded.rpc_name,allowed_roles=excluded.allowed_roles,opens_exact_card=true,registry_status='ACTIVE',
 notes=excluded.notes,source_department_code=excluded.source_department_code,target_department_code=excluded.target_department_code,
 routing_mode=excluded.routing_mode,parent_type=excluded.parent_type,source_state=excluded.source_state,
 success_state=excluded.success_state,next_action_code=excluded.next_action_code,receiver_rule=excluded.receiver_rule,
 unit_label=excluded.unit_label,message_template=excluded.message_template,rollback_rule=excluded.rollback_rule,updated_at=now();

create or replace function public.rr_real_chat_reconcile_cutting_damage_v114()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer:=0;
begin
 with profiles as (
  select distinct on (upper(role_code)) upper(role_code) role_code,auth_user_id,full_name
  from public.rr_user_profiles
  where is_active=true and coalesce(access_status,'ACTIVE')='ACTIVE'
  order by upper(role_code),updated_at desc nulls last,created_at desc
 ), source as (
  select a.*,
   case when upper(a.status) in ('REJECTED','CLOSED','OWNER_APPROVED','VENDOR_MESSAGE_SENT') then 'CLOSE' else 'WORKING' end canonical_state,
   case when upper(a.status) in ('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then coalesce(ad.auth_user_id,sa.auth_user_id,ow.auth_user_id)
        when upper(a.status)='ADMIN_VERIFIED' and not coalesce(a.effect_posted,false) then coalesce(ow.auth_user_id,sa.auth_user_id) end receiver_user,
   case when upper(a.status) in ('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then coalesce(ad.full_name,sa.full_name,'Admin')
        when upper(a.status)='ADMIN_VERIFIED' and not coalesce(a.effect_posted,false) then coalesce(ow.full_name,sa.full_name,'Owner') end receiver_name,
   coalesce(actor.full_name,'Sudesh Bhati') performer_name
  from public.rr_cutting_cb_actions a
  left join profiles ad on ad.role_code='ADMIN'
  left join profiles sa on sa.role_code='SUPER_ADMIN'
  left join profiles ow on ow.role_code='OWNER'
  left join public.rr_user_profiles actor on actor.auth_user_id=a.created_by and actor.is_active=true
 ), shaped as (
  select s.*,
   case when s.receiver_user is null then null else (select w.worker_id from public.rr_worker_directory_unified_v1 w where w.linked_auth_user_id=s.receiver_user and coalesce(w.is_active,true) limit 1) end receiver_worker,
   case
    when upper(s.status) in ('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then jsonb_build_array(
     jsonb_build_object('code','CUTTING_ADMIN_VERIFY','label','ADMIN VERIFY','href','real-cutting-master.html?action_id='||s.id,'engine','rr_cutting_admin_decide_cb_action_v1','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN')),
     jsonb_build_object('code','CUTTING_ADMIN_RECHECK','label','RECHECK','href','real-cutting-master.html?action_id='||s.id,'engine','rr_cutting_admin_decide_cb_action_v1','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN')),
     jsonb_build_object('code','CUTTING_ADMIN_REJECT','label','REJECT','href','real-cutting-master.html?action_id='||s.id,'engine','rr_cutting_admin_decide_cb_action_v1','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN')))
    when upper(s.status)='ADMIN_VERIFIED' and not coalesce(s.effect_posted,false) then jsonb_build_array(
     jsonb_build_object('code','CUTTING_OWNER_APPROVE','label','OWNER APPROVE & APPLY','href','real-cutting-master.html?action_id='||s.id,'engine','rr_cutting_owner_decide_cb_action_v1','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN')),
     jsonb_build_object('code','CUTTING_OWNER_REJECT','label','OWNER REJECT','href','real-cutting-master.html?action_id='||s.id,'engine','rr_cutting_owner_decide_cb_action_v1','allowed_roles',jsonb_build_array('OWNER','SUPER_ADMIN')))
    else '[]'::jsonb end next_actions,
   case
    when upper(s.status) in ('PENDING_ADMIN','ADMIN_MESSAGE_SENT') then 'Damage approval pending with Admin'
    when upper(s.status)='RECHECK_REQUIRED' then 'Damage recheck required'
    when upper(s.status)='ADMIN_VERIFIED' and not coalesce(s.effect_posted,false) then 'Admin verified — Owner approval pending'
    when upper(s.status)='OWNER_APPROVED' then 'Damage approved and inventory/cost effect applied'
    when upper(s.status)='VENDOR_MESSAGE_SENT' then 'Damage approved — Vendor informed'
    when upper(s.status)='REJECTED' then 'Damage rejected'
    else replace(initcap(lower(s.status)),'_',' ') end message
  from source s
 ), payloads as (
  select s.*,
   jsonb_build_object(
    'card_type','DAMAGE_CASE','conversation_parent','DAMAGE:'||s.id,'canonical_state',s.canonical_state,
    'status',upper(s.status),'lot_no',s.source_lot_no,'qty',s.qty,'quantity_unit','KG','unit_label','KG',
    'rate',s.rate_snapshot,'amount',s.value_snapshot,'reason',s.reason,'message',s.message,
    'sender_name','Cutting Master','receiver_name',s.receiver_name,
    'performed_by_name',s.performer_name,'on_behalf_of_name','Cutting Master',
    'allowed_roles',case when s.canonical_state='CLOSE' then '[]'::jsonb when upper(s.status)='ADMIN_VERIFIED' then jsonb_build_array('OWNER','SUPER_ADMIN') else jsonb_build_array('OWNER','SUPER_ADMIN','ADMIN') end,
    'next_actions',s.next_actions,'action_href',case when jsonb_array_length(s.next_actions)>0 then 'real-cutting-master.html?action_id='||s.id else null end,
    'action_engine',case when upper(s.status)='ADMIN_VERIFIED' then 'rr_cutting_owner_decide_cb_action_v1' else 'rr_cutting_admin_decide_cb_action_v1' end
   ) payload
  from shaped s
 )
 update public.rr_real_chat_message_bridge_v70 b
 set source_event_type=upper(p.action_type)||'_'||upper(p.status),
     receiver_user_id=p.receiver_user,receiver_worker_id=p.receiver_worker,
     action_code=case when upper(p.status) in ('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then 'CUTTING_ADMIN_VERIFY'
                      when upper(p.status)='ADMIN_VERIFIED' and not coalesce(p.effect_posted,false) then 'CUTTING_OWNER_APPROVE' end,
     action_label=case when upper(p.status) in ('PENDING_ADMIN','ADMIN_MESSAGE_SENT','RECHECK_REQUIRED') then 'ADMIN VERIFY'
                       when upper(p.status)='ADMIN_VERIFIED' and not coalesce(p.effect_posted,false) then 'OWNER APPROVE & APPLY' end,
     personal_payload=p.payload,group_payload=p.payload,
     deep_link='real-cutting-master.html?action_id='||p.id,
     sent_at=coalesce(p.updated_at,p.created_at)
 from payloads p
 where b.archived_at is null and b.source_module='CUTTING' and b.source_record_id=p.id::text
   and b.canonical_key='CUTTING_ACTION:'||p.id;
 get diagnostics v_count=row_count;
 return jsonb_build_object('reconciled',v_count,
  'working',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type like 'DAMAGE_%' and personal_payload->>'canonical_state'='WORKING'),
  'closed',(select count(*) from public.rr_real_chat_message_bridge_v70 where archived_at is null and source_module='CUTTING' and source_event_type like 'DAMAGE_%' and personal_payload->>'canonical_state'='CLOSE'));
end $$;

revoke all on function public.rr_real_chat_reconcile_cutting_damage_v114() from public,anon,authenticated;
grant execute on function public.rr_real_chat_reconcile_cutting_damage_v114() to service_role;

create or replace function public.rr_real_chat_cutting_damage_trigger_v114()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform public.rr_real_chat_sync_e2e_events_v71('CUTTING_ACTION:'||new.id);
 perform public.rr_real_chat_reconcile_cutting_damage_v114();
 return null;
exception when others then raise warning 'V114 Cutting damage reconciliation deferred: %',sqlerrm; return null; end $$;

drop trigger if exists zzzzzzzzzzz_rr_cutting_damage_v114 on public.rr_cutting_cb_actions;
create trigger zzzzzzzzzzz_rr_cutting_damage_v114 after insert or update on public.rr_cutting_cb_actions
for each row execute function public.rr_real_chat_cutting_damage_trigger_v114();

select public.rr_real_chat_reconcile_cutting_damage_v114();
commit;
