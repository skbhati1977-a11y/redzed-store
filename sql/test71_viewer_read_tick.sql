-- Current viewer receipt is independent of participant totals.
create or replace function public.rr_chat_action_history_test71(p_department text,p_worker uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform public.rr_assert_active_user_v1();
 return (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at),'[]'::jsonb) from (
  select distinct on(i.event_key) i.id,i.event_key action_key,i.action_label,i.action_detail,i.actor_user_id,
   (select w.worker_name from public.rr_worker_directory_unified_v1 w where w.linked_auth_user_id=i.actor_user_id limit 1) actor_name,
   i.created_at,i.read_at,i.department_code,i.assignment_id,i.submit_request_id,i.bridge_id,i.lot_no,
   exists(select 1 from rr_chat_notifications_test71.inbox own join public.rr_worker_directory_unified_v1 ow on ow.worker_id=own.recipient_worker_id where own.event_key=i.event_key and ow.linked_auth_user_id=auth.uid()) viewer_is_recipient,
   (select min(own.read_at) from rr_chat_notifications_test71.inbox own join public.rr_worker_directory_unified_v1 ow on ow.worker_id=own.recipient_worker_id where own.event_key=i.event_key and ow.linked_auth_user_id=auth.uid()) viewer_read_at,
   coalesce(i.worker_ids,jsonb_build_array(b.sender_worker_id,b.receiver_worker_id)) worker_ids,
   b.canonical_key event_key,coalesce(b.group_payload->>'cb_no',b.group_payload->>'cb_code') cb_no,
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
end $$;
