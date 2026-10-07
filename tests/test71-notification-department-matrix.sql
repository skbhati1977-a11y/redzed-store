-- No push delivery or retained fixtures: all changes roll back.
begin;
alter table public.rr_targeted_push_outbox_v708 disable trigger rr_targeted_push_deliver_v708;
create temporary table notice_matrix_bridge (like public.rr_real_chat_message_bridge_v70 including defaults);
create trigger test_notify after insert on notice_matrix_bridge for each row execute function rr_chat_notifications_test71.notify_bridge();
create temporary table notice_matrix_results(department text, role_code text, recipients integer);
do $$
declare b public.rr_real_chat_message_bridge_v70%rowtype; d record; w record; sender record; mine uuid; result jsonb; expected integer; actual integer;
begin
 select * into b from public.rr_real_chat_message_bridge_v70 where data_mode='TEST' and source_module='UPM' and archived_at is null limit 1;
 if b.id is null then raise exception 'Missing UPM baseline';end if;
 select worker_id,linked_auth_user_id into sender from public.rr_worker_directory_unified_v1 where is_active and linked_auth_user_id is not null limit 1;
 for d in select distinct public.rr_real_chat_canonical_department_v83(department_code) code from public.rr_real_chat_department_membership_v70 where is_active loop
  for w in select worker_id,linked_auth_user_id,role_code from public.rr_worker_directory_unified_v1 where is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' and linked_auth_user_id is not null and linked_auth_user_id<>sender.linked_auth_user_id loop
   b.id:=gen_random_uuid();b.canonical_key:='NOTICE_MATRIX:'||b.id;b.data_mode:='TEST';b.archived_at:=null;b.source_module:='UPM';b.source_event_type:='ASSIGNED';b.action_code:='ASSIGN';b.department_code:=d.code;b.receiver_worker_id:=w.worker_id;b.receiver_user_id:=w.linked_auth_user_id;b.sender_worker_id:=sender.worker_id;b.sender_user_id:=sender.linked_auth_user_id;b.sent_at:=clock_timestamp();b.projection_type:='ACTION';
   insert into notice_matrix_bridge select b.*;
   if not exists(select 1 from rr_chat_notifications_test71.inbox where bridge_id=b.id and recipient_worker_id=w.worker_id and department_code=d.code and route_url like '%rc_id='||d.code||'&%' and route_url like '%rc_bridge='||b.id) then raise exception 'Missing direct recipient %/%',d.code,w.role_code;end if;
   if exists(select 1 from rr_chat_notifications_test71.inbox where bridge_id=b.id and recipient_worker_id=sender.worker_id) then raise exception 'Self notification';end if;
   select count(distinct x.worker_id) into expected from public.rr_worker_directory_unified_v1 x where x.is_active and upper(coalesce(x.access_status,'ACTIVE'))='ACTIVE' and x.linked_auth_user_id is not null and x.linked_auth_user_id is distinct from b.sender_user_id and x.worker_id is distinct from b.sender_worker_id and x.worker_id is distinct from public.rr_canonical_worker_id_v264(b.sender_worker_id) and (x.worker_id=b.receiver_worker_id or x.worker_id=public.rr_canonical_worker_id_v264(b.receiver_worker_id) or x.linked_auth_user_id=b.receiver_user_id or exists(select 1 from public.rr_real_chat_department_membership_v70 m where m.worker_id=x.worker_id and m.is_active and public.rr_real_chat_canonical_department_v83(m.department_code)=d.code));
   select count(*) into actual from rr_chat_notifications_test71.inbox where bridge_id=b.id;
   if actual<>expected then raise exception 'Recipient mismatch % expected % got %',d.code,expected,actual;end if;
   insert into notice_matrix_bridge select b.*;
   if (select count(*) from rr_chat_notifications_test71.inbox where bridge_id=b.id)<>expected then raise exception 'Duplicate notice';end if;
   -- Standalone notice exercises authenticated inbox/read independently of temporary bridge visibility.
   insert into rr_chat_notifications_test71.inbox(event_key,recipient_worker_id,department_code,title,route_url,lot_no) values('NOTICE_MATRIX_READ:'||b.id,w.worker_id,d.code,'Matrix','test70-cb-purchase-real-chat-pilot.html?rc_status=OPEN','MATRIX') returning id into mine;
   perform set_config('request.jwt.claim.sub',w.linked_auth_user_id::text,true);
   result:=public.rr_chat_notification_inbox_test71();
   if not result @> jsonb_build_array(jsonb_build_object('id',mine,'lot_no','MATRIX')) then raise exception 'Unread missing %',w.role_code;end if;
   if public.rr_chat_notification_read_test71(array[mine])<>1 or public.rr_chat_notification_read_test71(array[mine])<>0 then raise exception 'Read idempotence %',w.role_code;end if;
   perform set_config('request.jwt.claim.sub',sender.linked_auth_user_id::text,true);
   perform set_config('request.jwt.claim.sub',w.linked_auth_user_id::text,true);
   if public.rr_chat_notification_inbox_test71() @> jsonb_build_array(jsonb_build_object('id',mine)) then raise exception 'Read lost after actor re-entry';end if;
   insert into notice_matrix_results values(d.code,w.role_code,actual);
  end loop;
 end loop;
end $$;
select count(*) cases,count(distinct department) departments,count(distinct role_code) roles from notice_matrix_results;
rollback;
