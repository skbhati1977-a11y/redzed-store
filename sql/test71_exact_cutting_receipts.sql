CREATE OR REPLACE FUNCTION public.rr_chat_action_history_test71(p_department text, p_worker uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.rr_assert_active_user_v1();
 return (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at),'[]'::jsonb) from (
  select distinct on(i.event_key) i.id,i.event_key action_key,case when b.source_event_type='READY_FOR_CUTTING' then 'Art / Print decision complete' else i.action_label end action_label,i.action_detail,i.actor_user_id,
   coalesce((select w.worker_name from public.rr_worker_directory_unified_v1 w where w.linked_auth_user_id=i.actor_user_id limit 1),b.group_payload->>'performed_by_name') actor_name,
   i.created_at,i.read_at,i.department_code,i.assignment_id,i.submit_request_id,i.bridge_id,i.lot_no,
   exists(select 1 from rr_chat_notifications_test71.inbox own join public.rr_worker_directory_unified_v1 ow on ow.worker_id=own.recipient_worker_id where own.event_key=i.event_key and ow.linked_auth_user_id=auth.uid()) viewer_is_recipient,
   (select min(own.read_at) from rr_chat_notifications_test71.inbox own join public.rr_worker_directory_unified_v1 ow on ow.worker_id=own.recipient_worker_id where own.event_key=i.event_key and ow.linked_auth_user_id=auth.uid()) viewer_read_at,
   coalesce(i.worker_ids,jsonb_build_array(b.sender_worker_id,b.receiver_worker_id)) worker_ids,
   b.canonical_key event_key,b.group_payload->>'cb_unit_id' cb_unit_id,coalesce(b.group_payload->>'cb_no',b.group_payload->>'cb_code') cb_no,
   case when i.assignment_id is not null or i.submit_request_id is not null then
    regexp_replace(i.route_url,'([?&]rc_status=)[^&]*',E'\\1'||rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status)) else i.route_url end route_url,
   public.rr_chat_action_receipts_test71(i.event_key) recipients
  from rr_chat_notifications_test71.inbox i left join public.rr_real_chat_message_bridge_v70 b on b.id=i.bridge_id and b.data_mode='TEST'
  where i.department_code=upper(p_department)
  and (p_worker is null or coalesce(i.worker_ids,jsonb_build_array(b.sender_worker_id,b.receiver_worker_id)) @> jsonb_build_array(p_worker))
  and (i.actor_user_id=auth.uid() or exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'))
  and (i.bridge_id is null or b.archived_at is null)
  order by i.event_key,(i.actor_user_id=auth.uid()) desc,i.created_at
 ) t);
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_chat_notification_inbox_test71()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.rr_assert_active_user_v1();
 perform rr_chat_notifications_test71.recover_upm_cards();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'department_code',i.department_code,'title',i.title,'route_url',case when i.assignment_id is not null or i.submit_request_id is not null then regexp_replace(i.route_url,'([?&]rc_status=)[^&]*', E'\\1'||rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status)) else i.route_url end,'bridge_id',i.bridge_id,'action_key',i.event_key,'action_label',case when b.source_event_type='READY_FOR_CUTTING' then 'Art / Print decision complete' else i.action_label end,'action_detail',i.action_detail,'actor_user_id',i.actor_user_id,'event_key',b.canonical_key,'assignment_id',i.assignment_id,'submit_request_id',i.submit_request_id,'worker_ids',coalesce(i.worker_ids,jsonb_build_array(b.sender_worker_id,public.rr_canonical_worker_id_v264(b.sender_worker_id),b.receiver_worker_id,public.rr_canonical_worker_id_v264(b.receiver_worker_id))),'lot_no',coalesce(i.lot_no,b.group_payload->>'lot_no'),'cb_unit_id',b.group_payload->>'cb_unit_id','cb_no',coalesce(b.group_payload->>'cb_no',b.group_payload->>'cb_code'),'created_at',i.created_at) order by i.created_at),'[]'::jsonb)
 from (select distinct on(x.event_key) x.* from rr_chat_notifications_test71.inbox x where exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=x.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE') order by x.event_key,(x.read_at is null),x.created_at) i left join public.rr_real_chat_message_bridge_v70 b on b.id=i.bridge_id and b.data_mode='TEST' where i.read_at is null and (b.source_event_type is distinct from 'READY_FOR_CUTTING' or public.rr_cutting_child_lifecycle_v615((b.group_payload->>'cb_unit_id')::uuid)->>'state'='READY_FOR_CUTTING') and (i.event_key not like 'UPM_CARD_TEST71:%' or (i.action_detail->>'source_verified'='true' and rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status) in ('OPEN','WORKING'))) and i.actor_user_id is distinct from auth.uid()
 and ((i.assignment_id is null and i.submit_request_id is null) or rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status) is not null)
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE')
 and (i.login_request_id is null or public.rr_customer_login_push_pending_test71(i.login_request_id,i.recipient_worker_id))
 and (i.bridge_id is null or exists(select 1 from public.rr_real_chat_message_bridge_v70 b where b.id=i.bridge_id and b.data_mode='TEST' and b.archived_at is null)));
end $function$
;
