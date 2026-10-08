-- Resolve existing recovered TEST71 entries against actual workflow records.
-- Preserve notice IDs/read_at/delivered_at; do not create pushes or business rows.
create or replace function rr_chat_notifications_test71.recover_upm_cards() returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then return;end if;
 update rr_chat_notifications_test71.inbox i
 set action_label=case when r.status in ('CONFIRMED','CONFIRMED_SHORT') then 'Accept & Count · recovered' else 'Assign · recovered' end,
 actor_user_id=case when r.status in ('CONFIRMED','CONFIRMED_SHORT') then r.confirmed_by else a.assigned_by end,
 action_detail=jsonb_build_object('source_verified',true,'occurred_at',case when r.status in ('CONFIRMED','CONFIRMED_SHORT') then r.confirmed_at else coalesce(a.assigned_at,a.created_at) end,
 'expected_pcs',coalesce(r.expected_qty,a.assigned_qty),'received_pcs',r.confirmed_qty,'difference_pcs',r.confirmed_qty-r.expected_qty,'colour',a.colour_code,'worker',a.worker_name_snapshot,'note',r.note)
 from public.rr_upm_work_assignments_v8 a left join public.rr_upm_assignment_receipts_v9112 r on r.assignment_id=a.id
 where i.event_key like 'UPM_CARD_TEST71:%' and i.submit_request_id is null and i.assignment_id=a.id
 and coalesce(i.action_detail->>'source_verified','false')<>'true'
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE');
 update rr_chat_notifications_test71.inbox i
 set action_label='Submit · '||replace(q.status,'_',' ')||' · recovered',
 actor_user_id=case when q.status='WAITING_LM' then coalesce(q.worker_auth_id,q.created_by) else q.selected_receiver_auth_id end,
 action_detail=jsonb_build_object('source_verified',true,'occurred_at',coalesce(q.completed_at,q.worker_decided_at,q.counted_at,q.accepted_at,q.created_at),
 'assigned_pcs',q.assigned_total,'ready_pcs',q.worker_ready_total,'counted_pcs',q.lm_counted_total,'difference_pcs',q.difference_qty,'worker',q.worker_name,'receiver',q.selected_receiver_name,'note',q.dispute_note)
 from public.rr_upm_submit_requests_v794 q
 where i.event_key like 'UPM_CARD_TEST71:%' and i.submit_request_id=q.id
 and coalesce(i.action_detail->>'source_verified','false')<>'true'
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE');
end $$;
revoke all on function rr_chat_notifications_test71.recover_upm_cards() from public,anon,authenticated;

create or replace function public.rr_chat_notification_inbox_test71() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
begin
 perform public.rr_assert_active_user_v1();
 perform rr_chat_notifications_test71.recover_upm_cards();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'department_code',i.department_code,'title',i.title,'route_url',case when i.assignment_id is not null or i.submit_request_id is not null then regexp_replace(i.route_url,'([?&]rc_status=)[^&]*', E'\\1'||rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status)) else i.route_url end,'bridge_id',i.bridge_id,'action_key',i.event_key,'action_label',i.action_label,'action_detail',i.action_detail,'actor_user_id',i.actor_user_id,'event_key',b.canonical_key,'assignment_id',i.assignment_id,'submit_request_id',i.submit_request_id,'worker_ids',coalesce(i.worker_ids,jsonb_build_array(b.sender_worker_id,public.rr_canonical_worker_id_v264(b.sender_worker_id),b.receiver_worker_id,public.rr_canonical_worker_id_v264(b.receiver_worker_id))),'lot_no',coalesce(i.lot_no,b.group_payload->>'lot_no'),'cb_no',coalesce(b.group_payload->>'cb_no',b.group_payload->>'cb_code'),'created_at',i.created_at) order by i.created_at),'[]'::jsonb)
 from (select distinct on(x.event_key) x.* from rr_chat_notifications_test71.inbox x where exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=x.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE') order by x.event_key,x.created_at) i left join public.rr_real_chat_message_bridge_v70 b on b.id=i.bridge_id and b.data_mode='TEST' where i.read_at is null and (i.event_key not like 'UPM_CARD_TEST71:%' or i.action_detail->>'source_verified'='true') and i.actor_user_id is distinct from auth.uid()
 and ((i.assignment_id is null and i.submit_request_id is null) or rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status) is not null)
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE')
 and (i.login_request_id is null or public.rr_customer_login_push_pending_test71(i.login_request_id,i.recipient_worker_id))
 and (i.bridge_id is null or exists(select 1 from public.rr_real_chat_message_bridge_v70 b where b.id=i.bridge_id and b.data_mode='TEST' and b.archived_at is null)));
end $$;

