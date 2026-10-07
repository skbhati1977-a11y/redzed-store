begin;
-- Push delivery is disabled only inside this rolled-back test transaction.
alter table public.rr_targeted_push_outbox_v708 disable trigger rr_targeted_push_deliver_v708;
create temporary table upm_receipt_notice_fixture(like public.rr_upm_assignment_receipts_v9112 including defaults);
create trigger test_receipt after insert or update on upm_receipt_notice_fixture for each row execute function rr_chat_notifications_test71.upm_receipt();
create temporary table upm_submit_notice_fixture(like public.rr_upm_submit_requests_v794 including defaults);
create trigger test_submit after insert or update on upm_submit_notice_fixture for each row execute function rr_chat_notifications_test71.upm_submit();
do $$
declare a record;r public.rr_upm_assignment_receipts_v9112%rowtype;q public.rr_upm_submit_requests_v794%rowtype;n integer;before_n integer;owner_id uuid;owner_auth uuid;notice uuid;dep text;person record;notice_key text;
begin
 select worker_id,linked_auth_user_id into owner_id,owner_auth from public.rr_worker_directory_unified_v1 where upper(role_code)='OWNER' and is_active limit 1;
 perform set_config('request.jwt.claim.sub',owner_auth::text,true);
 perform set_config('request.headers','{"origin":"https://test71-workspace.app.github.dev","x-client-info":"redzed-test71"}',true);
 if not rr_chat_notifications_test71.test_request() then raise exception 'Codespaces TEST marker rejected';end if;
 perform set_config('request.headers','{"origin":"https://test71-workspace.app.github.dev"}',true);
 if rr_chat_notifications_test71.test_request() then raise exception 'Unmarked Codespaces REAL accepted';end if;
 -- Every mapped department and every linked worker/staff identity: authorized
 -- members/global admins receive the notice; outsiders and the actor do not.
 perform set_config('request.headers','{"origin":"https://redzed-test65-git-test71-real-chat-e2e-6adad3-skbhati1977-4414.vercel.app"}',true);
 for dep in select distinct public.rr_real_chat_canonical_department_v83(department_code) from public.rr_real_chat_department_membership_v70 where is_active loop
  notice_key:='UPM_ROLE_MATRIX_TEST71:'||gen_random_uuid();
  perform rr_chat_notifications_test71.emit_upm(notice_key,dep,'OPEN','MATRIX',null,null,array[]::uuid[],owner_id);
  for person in select d.*,exists(select 1 from public.rr_real_chat_department_membership_v70 m where m.worker_id=d.worker_id and m.is_active and public.rr_real_chat_canonical_department_v83(m.department_code)=dep) member from public.rr_worker_directory_unified_v1 d where d.is_active and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE' and d.linked_auth_user_id is not null loop
   if exists(select 1 from rr_chat_notifications_test71.inbox i where i.event_key=notice_key||':'||dep and i.recipient_worker_id=person.worker_id) is distinct from (person.linked_auth_user_id<>owner_auth and person.worker_id<>owner_id and (person.member or upper(person.role_code) in('OWNER','SUPER_ADMIN','ADMIN'))) then raise exception 'UPM department/role routing mismatch: % %',dep,person.role_code;end if;
  end loop;
 end loop;
 -- Production/unknown requests must not emit any UPM event.
 perform set_config('request.headers','{"referer":"https://production.example/real-universal-production-v770-v9059.html?mode=REAL"}',true);
 for a in select distinct on(department_code) x.* from public.rr_upm_work_assignments_v8 x join public.rr_upm_assignment_receipts_v9112 y on y.assignment_id=x.id where upper(x.status) not in('CANCELLED','CANCELED','VOID') order by department_code,assigned_at desc loop
  select * into r from public.rr_upm_assignment_receipts_v9112 where assignment_id=a.id;
  r.receipt_batch_id:=gen_random_uuid();r.status:='PENDING';r.confirmed_at:=null;
  insert into upm_receipt_notice_fixture select r.*;
  if exists(select 1 from rr_chat_notifications_test71.inbox where event_key like 'UPM_RECEIPT_TEST71:'||r.receipt_batch_id||'%') then raise exception 'REAL request emitted UPM notice';end if;
  perform set_config('request.headers','{"origin":"https://redzed-test65-git-test71-real-chat-e2e-6adad3-skbhati1977-4414.vercel.app"}',true);
  insert into upm_receipt_notice_fixture select r.*;
  select count(*) into n from rr_chat_notifications_test71.inbox where event_key like 'UPM_RECEIPT_TEST71:'||r.receipt_batch_id||'%';
  if n=0 then raise exception 'Assign OPEN notice missing %',a.department_code;end if;
  if exists(select 1 from rr_chat_notifications_test71.inbox where event_key like 'UPM_RECEIPT_TEST71:'||r.receipt_batch_id||'%' and recipient_worker_id=owner_id) then raise exception 'Assign sender self-notification';end if;
  before_n:=n;insert into upm_receipt_notice_fixture select r.*;
  select count(*) into n from rr_chat_notifications_test71.inbox where event_key like 'UPM_RECEIPT_TEST71:'||r.receipt_batch_id||'%';if n<>before_n then raise exception 'Duplicate assign';end if;
  update upm_receipt_notice_fixture set status='CONFIRMED',confirmed_at=now() where receipt_batch_id=r.receipt_batch_id;
  if not exists(select 1 from rr_chat_notifications_test71.inbox where event_key like 'UPM_RECEIPT_TEST71:'||r.receipt_batch_id||'%' and chat_status='WORKING') then raise exception 'Accept WORKING notice missing %',a.department_code;end if;
  if exists(select 1 from public.rr_targeted_push_outbox_v708 where event_key like 'UPM_RECEIPT_TEST71:'||r.receipt_batch_id||'%' and (payload->>'notice_id' is null or route_url not like '%rc_notice=%' or payload->>'source'<>'REAL_CHAT_ACTION_TEST71' or payload->>'source_module'<>'UPM_LIFECYCLE_TEST71')) then raise exception 'Exact notice route missing';end if;
  perform set_config('request.headers','{"referer":"https://production.example/real-universal-production-v770-v9059.html?mode=REAL"}',true);
 end loop;
 select * into q from public.rr_upm_submit_requests_v794 where selected_receiver_worker_id is not null limit 1;
 if q.id is null then raise exception 'Submit baseline missing';end if;
 q.id:=gen_random_uuid();q.status:='WAITING_LM';q.department_code:='PRESS';q.target_department_code:='PACKING';
 perform set_config('request.headers','{"origin":"https://redzed-test65-git-test71-real-chat-e2e-6adad3-skbhati1977-4414.vercel.app"}',true);
 insert into upm_submit_notice_fixture select q.*;
 if not exists(select 1 from rr_chat_notifications_test71.inbox where submit_request_id=q.id and department_code='PACKING' and chat_status='OPEN') then raise exception 'Press to Packing OPEN missing';end if;
 if not exists(select 1 from rr_chat_notifications_test71.inbox where submit_request_id=q.id and department_code='PRESS' and chat_status='CLOSE') then raise exception 'Source Submit CLOSE missing';end if;
 update upm_submit_notice_fixture set status='LM_ACCEPTED' where id=q.id;
 if not exists(select 1 from rr_chat_notifications_test71.inbox where submit_request_id=q.id and department_code='PACKING' and chat_status='WORKING') then raise exception 'Receiver WORKING missing';end if;
 update upm_submit_notice_fixture set status='COMPLETED' where id=q.id;
 if not exists(select 1 from rr_chat_notifications_test71.inbox where submit_request_id=q.id and department_code='PACKING' and chat_status='CLOSE') then raise exception 'Receiver CLOSE missing';end if;
 -- Authenticated persistent READ for current assignment card.
 insert into rr_chat_notifications_test71.inbox(event_key,recipient_worker_id,department_code,title,route_url,assignment_id,lot_no,chat_status)
 values('UPM_SOURCE_READ_TEST71',owner_id,public.rr_real_chat_canonical_department_v83(a.department_code),'test','test70-cb-purchase-real-chat-pilot.html?rc_status=OPEN',a.id,a.lot_no,'OPEN') returning id into notice;
 if not public.rr_chat_notification_inbox_test71() @> jsonb_build_array(jsonb_build_object('id',notice,'assignment_id',a.id)) then raise exception 'Current assignment notice hidden';end if;
 if public.rr_chat_notification_read_test71(array[notice])<>1 or public.rr_chat_notification_read_test71(array[notice])<>0 then raise exception 'Durable source read failed';end if;
 if public.rr_chat_notification_inbox_test71() @> jsonb_build_array(jsonb_build_object('id',notice)) then raise exception 'Read still counted';end if;
 if has_function_privilege('authenticated','rr_chat_notifications_test71.emit_upm(text,text,text,text,uuid,uuid,uuid[],uuid)','execute') then raise exception 'Internal emitter exposed';end if;
end $$;
rollback;
select 'PASS: current UPM Assign/Accept/Submit source triggers, Press-Packing routing, TEST request gate, self/duplicate suppression, exact-card payload, durable read' result;
