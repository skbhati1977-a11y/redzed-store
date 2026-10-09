-- TEST71 action receipts: business rows and production routes are unchanged.
alter table rr_chat_notifications_test71.inbox add column if not exists delivered_at timestamptz;
alter table rr_chat_notifications_test71.inbox add column if not exists action_label text;
alter table rr_chat_notifications_test71.inbox add column if not exists actor_user_id uuid;
alter table rr_chat_notifications_test71.inbox add column if not exists action_detail jsonb;
create index if not exists inbox_event_receipts_test71 on rr_chat_notifications_test71.inbox(event_key);

create or replace function rr_chat_notifications_test71.snapshot_action() returns trigger
language plpgsql security definer set search_path='' as $$
declare a record;r record;q record;b record;begin
 new.actor_user_id:=auth.uid();
 if new.event_key like 'UPM_CARD_TEST71:%' then
  new.action_label:='Existing card · historical recovery';new.actor_user_id:=null;
 elsif new.event_key like 'UPM_RECEIPT_TEST71:%' then
  select * into a from public.rr_upm_work_assignments_v8 where id=new.assignment_id;
  select * into r from public.rr_upm_assignment_receipts_v9112 where assignment_id=new.assignment_id;
  new.action_label:=case when new.chat_status='OPEN' then 'Assign / receipt pending' else 'Accept & Count' end;
  new.action_detail:=jsonb_build_object('expected_pcs',r.expected_qty,'received_pcs',r.confirmed_qty,'difference_pcs',r.confirmed_qty-r.expected_qty,'colour',a.colour_code,'worker',a.worker_name_snapshot,'note',r.note);
 elsif new.event_key like 'UPM_SUBMIT_TEST71:%' then
  select * into q from public.rr_upm_submit_requests_v794 where id=new.submit_request_id;
  new.action_label:='Submit · '||replace(q.status,'_',' ');
  new.action_detail:=jsonb_build_object('assigned_pcs',q.assigned_total,'ready_pcs',q.worker_ready_total,'counted_pcs',q.lm_counted_total,'difference_pcs',q.difference_qty,'worker',q.worker_name,'receiver',q.selected_receiver_name,'note',q.dispute_note);
 elsif new.bridge_id is not null then
  select * into b from public.rr_real_chat_message_bridge_v70 where id=new.bridge_id;
  new.action_label:=coalesce(b.action_label,b.source_event_type,new.title);new.actor_user_id:=b.sender_user_id;
  -- Never copy private costing payloads into notification receipts.
  new.action_detail:=jsonb_build_object('qty',b.group_payload->'qty','colour',b.group_payload->>'colour_code','worker',b.group_payload->>'worker_name','note',b.group_payload->>'reason');
 end if;
 new.action_label:=coalesce(new.action_label,new.title);return new;
end $$;
drop trigger if exists rr_action_snapshot_test71 on rr_chat_notifications_test71.inbox;
create trigger rr_action_snapshot_test71 before insert on rr_chat_notifications_test71.inbox for each row execute function rr_chat_notifications_test71.snapshot_action();

-- Preserve old receipts honestly; recovered cards are not new unread actions.
update rr_chat_notifications_test71.inbox set action_label='Existing card · historical recovery' where event_key like 'UPM_CARD_TEST71:%' and action_label is null;
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


create or replace function public.rr_chat_action_receipts_test71(p_event_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 perform public.rr_assert_active_user_v1();
 if not exists(select 1 from rr_chat_notifications_test71.inbox i where i.event_key=p_event_key and
  (i.actor_user_id=auth.uid() or exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'))) then raise exception 'Action access denied';end if;
 return (select coalesce(jsonb_agg(to_jsonb(t) order by t.worker_name),'[]'::jsonb) from (
  select w.linked_auth_user_id recipient_id,min(w.worker_name) worker_name,min(w.role_code) role_code,
   min(i.delivered_at) delivered_at,min(i.read_at) read_at
  from rr_chat_notifications_test71.inbox i join public.rr_worker_directory_unified_v1 w on w.worker_id=i.recipient_worker_id
  where i.event_key=p_event_key and w.linked_auth_user_id is not null group by w.linked_auth_user_id
 ) t);
end $$;

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

create or replace function public.rr_chat_action_delivered_test71(p_ids uuid[]) returns integer
language plpgsql security definer set search_path='' as $$
declare n integer;begin
 perform public.rr_assert_active_user_v1();
 update rr_chat_notifications_test71.inbox i set delivered_at=now() where i.id=any(p_ids) and i.delivered_at is null
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE');
 get diagnostics n=row_count;return n;
end $$;

create or replace function public.rr_chat_notification_read_test71(p_ids uuid[]) returns integer
language plpgsql security definer set search_path='' as $$
declare n integer;begin
 perform public.rr_assert_active_user_v1();
 update rr_chat_notifications_test71.inbox i set read_at=now(),delivered_at=coalesce(i.delivered_at,now())
 where i.read_at is null and i.event_key in(select x.event_key from rr_chat_notifications_test71.inbox x where x.id=any(p_ids)
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=x.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'))
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE');
 get diagnostics n=row_count;return n;
end $$;

-- Action/Alter/Rectify source events are snapshots, not extra work cards.
create or replace function rr_chat_notifications_test71.upm_action_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare j jsonb:=to_jsonb(new);dep text;aid uuid;wid uuid;sender uuid;key text;label text;lot text;detail jsonb;journey record;begin
 if not rr_chat_notifications_test71.test_request() then return new;end if;
 if tg_op='UPDATE' and (j->>'status') is not distinct from (to_jsonb(old)->>'status') then return new;end if;
 if tg_table_name='rr_upm_actions_v726' then
  dep:=j->>'department_code';aid:=nullif(j->>'assignment_id','')::uuid;wid:=nullif(j->>'worker_id','')::uuid;sender:=nullif(j->>'actor_user_id','')::uuid;label:=j->>'action_type';
 elsif tg_table_name='rr_upm_alter_events_v740' then
  select * into journey from public.rr_upm_alter_journey_v740 where id=(j->>'journey_id')::uuid;
  dep:=coalesce(journey.responsible_department_code,journey.origin_department_code);wid:=coalesce(new.responsible_id,journey.karigar_id);sender:=new.actor_id;label:=new.event_type;j:=j||jsonb_build_object('lot_no',journey.lot_no,'colour_code',journey.colour_code);
 else
  dep:=coalesce(j->>'target_department_code',j->>'origin_department_code');aid:=nullif(j->>'original_assignment_id','')::uuid;wid:=coalesce(nullif(j->>'assigned_worker_id','')::uuid,nullif(j->>'original_worker_id','')::uuid);sender:=nullif(j->>'created_by','')::uuid;label:='Rectify · '||(j->>'status');
 end if;
 dep:=public.rr_real_chat_canonical_department_v83(dep);lot:=j->>'lot_no';
 key:='UPM_EVENT_TEST71:'||tg_table_name||':'||(j->>'id')||':'||coalesce(j->>'status',j->>'event_type',j->>'action_type','ACTION')||':'||case when tg_op='UPDATE' then clock_timestamp()::text else coalesce(j->>'created_at',clock_timestamp()::text) end;
 perform rr_chat_notifications_test71.emit_upm(key,dep,'WORKING',lot,aid,null,array[wid],sender);
 detail:=jsonb_build_object('journey_id',j->>'journey_id','rectification_case_id',case when tg_table_name='rr_upm_rectification_cases_v9101' then j->>'id' else null end,'qty',coalesce(j->'qty',j->'recalled_good_qty'),'colour',j->>'colour_code','from',j->>'from_stage','to',j->>'to_stage','note',coalesce(j->>'remarks',j->>'reason'));
 update rr_chat_notifications_test71.inbox set action_label=replace(label,'_',' '),action_detail=detail,actor_user_id=auth.uid() where event_key=key||':'||dep;
 return new;
end $$;
drop trigger if exists rr_action_receipt_event_test71 on public.rr_upm_actions_v726;
create trigger rr_action_receipt_event_test71 after insert on public.rr_upm_actions_v726 for each row execute function rr_chat_notifications_test71.upm_action_event();
drop trigger if exists rr_alter_receipt_event_test71 on public.rr_upm_alter_events_v740;
create trigger rr_alter_receipt_event_test71 after insert on public.rr_upm_alter_events_v740 for each row execute function rr_chat_notifications_test71.upm_action_event();
drop trigger if exists rr_rectify_receipt_event_test71 on public.rr_upm_rectification_cases_v9101;
create trigger rr_rectify_receipt_event_test71 after insert or update of status on public.rr_upm_rectification_cases_v9101 for each row execute function rr_chat_notifications_test71.upm_action_event();

revoke all on all functions in schema rr_chat_notifications_test71 from public,anon,authenticated;
revoke all on function public.rr_chat_action_receipts_test71(text),public.rr_chat_action_history_test71(text,uuid),public.rr_chat_action_delivered_test71(uuid[]) from public,anon;
grant execute on function public.rr_chat_action_receipts_test71(text),public.rr_chat_action_history_test71(text,uuid),public.rr_chat_action_delivered_test71(uuid[]) to authenticated;

create or replace function public.rr_chat_notification_inbox_test71() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
begin
 perform public.rr_assert_active_user_v1();
 perform rr_chat_notifications_test71.recover_upm_cards();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'department_code',i.department_code,'title',i.title,'route_url',case when i.assignment_id is not null or i.submit_request_id is not null then regexp_replace(i.route_url,'([?&]rc_status=)[^&]*', E'\\1'||rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status)) else i.route_url end,'bridge_id',i.bridge_id,'action_key',i.event_key,'action_label',i.action_label,'action_detail',i.action_detail,'actor_user_id',i.actor_user_id,'event_key',b.canonical_key,'assignment_id',i.assignment_id,'submit_request_id',i.submit_request_id,'worker_ids',coalesce(i.worker_ids,jsonb_build_array(b.sender_worker_id,public.rr_canonical_worker_id_v264(b.sender_worker_id),b.receiver_worker_id,public.rr_canonical_worker_id_v264(b.receiver_worker_id))),'lot_no',coalesce(i.lot_no,b.group_payload->>'lot_no'),'cb_no',coalesce(b.group_payload->>'cb_no',b.group_payload->>'cb_code'),'created_at',i.created_at) order by i.created_at),'[]'::jsonb)
 from (select distinct on(x.event_key) x.* from rr_chat_notifications_test71.inbox x where exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=x.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE') order by x.event_key,(x.read_at is null),x.created_at) i left join public.rr_real_chat_message_bridge_v70 b on b.id=i.bridge_id and b.data_mode='TEST' where i.read_at is null and (i.event_key not like 'UPM_CARD_TEST71:%' or (i.action_detail->>'source_verified'='true' and rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status) in ('OPEN','WORKING'))) and i.actor_user_id is distinct from auth.uid()
 and ((i.assignment_id is null and i.submit_request_id is null) or rr_chat_notifications_test71.current_state(i.assignment_id,i.submit_request_id,i.department_code,i.chat_status) is not null)
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE')
 and (i.login_request_id is null or public.rr_customer_login_push_pending_test71(i.login_request_id,i.recipient_worker_id))
 and (i.bridge_id is null or exists(select 1 from public.rr_real_chat_message_bridge_v70 b where b.id=i.bridge_id and b.data_mode='TEST' and b.archived_at is null)));
end $$;


create or replace function rr_chat_notifications_test71.notify_bridge() returns trigger
language plpgsql security definer set search_path='' as $$
declare dep text;state text;route text;r record;event text;begin
 if rr_chat_notifications_test71.test_request() and (new.canonical_key like 'UPM_ASSIGNMENT:%' or new.canonical_key like 'UPM_SUBMIT:%' or new.canonical_key like 'UPM_RECTIFICATION:%') then return new;end if;
 if new.data_mode<>'TEST' or new.archived_at is not null or coalesce(new.projection_type,'')='SOURCE' or upper(new.source_module)='UPM_RATE' or new.canonical_key like 'UPM_ALTER_EVENT:%' or new.canonical_key like 'UPM_ACTION:%' then return new;end if;
 if tg_op='UPDATE' and (new.source_event_type,new.action_code,new.sent_at) is not distinct from (old.source_event_type,old.action_code,old.sent_at) then return new;end if;
 dep:=public.rr_real_chat_canonical_department_v83(new.department_code);if dep is null or dep='' then return new;end if;
 state:=public.rr_real_chat_canonical_state_v83(new.source_module,new.source_event_type,new.action_code,new.personal_payload);
 if state not in ('OPEN','WORKING','CLOSE') then state:='OPEN';end if;
 event:='REAL_CHAT_ACTION_TEST71:'||new.id::text||':'||new.source_event_type||':'||new.sent_at::text;
 route:='test70-cb-purchase-real-chat-pilot.html?rc_view=chat&rc_kind=group&rc_id='||dep||'&rc_parent='||dep||'&rc_status='||state||'&rc_bridge='||new.id::text;
 for r in select distinct w.worker_id from public.rr_worker_directory_unified_v1 w
 where w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE' and w.linked_auth_user_id is not null
 and w.linked_auth_user_id is distinct from new.sender_user_id and w.worker_id is distinct from new.sender_worker_id and w.worker_id is distinct from public.rr_canonical_worker_id_v264(new.sender_worker_id)
 and (w.worker_id=new.receiver_worker_id or w.worker_id=public.rr_canonical_worker_id_v264(new.receiver_worker_id) or w.linked_auth_user_id=new.receiver_user_id
 or (coalesce(new.projection_type,'')<>'SOURCE' and exists(select 1 from public.rr_real_chat_department_membership_v70 m where m.worker_id=w.worker_id and m.is_active and public.rr_real_chat_canonical_department_v83(m.department_code)=dep)))
 loop
 insert into public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
 values(event,r.worker_id,'REDZED · '||dep,'नई chat update · '||coalesce(new.action_label,'Open chat'),route,jsonb_build_object('source','REAL_CHAT_ACTION_TEST71','bridge_id',new.id,'department_code',dep,'chat_status',state))
 on conflict(event_key,recipient_worker_id) do nothing;
 end loop;return new;
end $$;

update rr_chat_notifications_test71.inbox set action_label='Earlier work update · detail not recorded' where action_label is null;
