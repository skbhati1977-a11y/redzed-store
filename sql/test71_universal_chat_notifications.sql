-- TEST71 only: one recipient/event, durable read state, existing web-push outbox.
create schema if not exists rr_chat_notifications_test71;
revoke all on schema rr_chat_notifications_test71 from public,anon,authenticated;
create table if not exists rr_chat_notifications_test71.inbox(
 id uuid primary key default gen_random_uuid(),event_key text not null,recipient_worker_id uuid not null,
 department_code text not null,title text not null,route_url text not null,
 bridge_id uuid,read_at timestamptz,created_at timestamptz not null default now(),
 unique(event_key,recipient_worker_id));
alter table rr_chat_notifications_test71.inbox add column if not exists lot_no text;
alter table rr_chat_notifications_test71.inbox add column if not exists login_request_id uuid;
alter table rr_chat_notifications_test71.inbox enable row level security;
drop policy if exists deny_direct_access on rr_chat_notifications_test71.inbox;
create policy deny_direct_access on rr_chat_notifications_test71.inbox for all to anon,authenticated using(false) with check(false);
create index if not exists inbox_unread_recipient on rr_chat_notifications_test71.inbox(recipient_worker_id,created_at) where read_at is null;
create or replace function rr_chat_notifications_test71.capture_targeted() returns trigger
language plpgsql security definer set search_path='' as $$
declare dept text;notice uuid;inbox_key text:=new.event_key;begin
 if coalesce(new.payload->>'source','') not in ('CUSTOMER_LOGIN_APPROVAL_TEST71','REAL_CHAT_ACTION_TEST71','RM_APPROVAL_TEST71','PI_RATE_RECOVERY_TEST71')
 and not (coalesce(new.payload->>'type','')='ACTUAL_RATE_REQUIRED' and exists(select 1 from public.rr_upm_rate_requests_v760 q where q.id::text=new.payload->>'request_id' and upper(coalesce(q.metadata->>'data_mode','TEST'))='TEST'))
 and not (coalesce(new.payload->>'type','')='FINAL_RATE' and exists(select 1 from public.rr_pack_rate_approval_v9340 q where q.id::text=new.payload->>'approval_id' and q.data_mode='TEST')) then return new;end if;
 dept:=coalesce(new.payload->>'department_code',new.payload->>'destination_department',(regexp_match(new.route_url,'[?&]rc_id=([^&]+)'))[1],case when new.payload->>'source'='RM_APPROVAL_TEST71' then 'READYMADE' when new.payload->>'source'='PI_RATE_RECOVERY_TEST71' then 'SALES' else 'ADMIN' end);
 if new.payload->>'source'='CUSTOMER_LOGIN_APPROVAL_TEST71' then select 'CUSTOMER_LOGIN_APPROVAL_TEST71:'||a.id::text||':'||a.requested_at::text into inbox_key from rr_customer_auth_test71.login_approvals a where a.id::text=new.payload->>'login_request_id';end if;
 insert into rr_chat_notifications_test71.inbox(event_key,recipient_worker_id,department_code,title,route_url,bridge_id,lot_no,login_request_id)
 values(coalesce(inbox_key,new.event_key),new.recipient_worker_id,upper(dept),new.title,new.route_url,case when new.payload->>'source'='REAL_CHAT_ACTION_TEST71' then (new.payload->>'bridge_id')::uuid end,new.payload->>'lot_no',case when new.payload->>'source'='CUSTOMER_LOGIN_APPROVAL_TEST71' then (new.payload->>'login_request_id')::uuid end)
 on conflict(event_key,recipient_worker_id) do nothing returning id into notice;
 if notice is null then select id into notice from rr_chat_notifications_test71.inbox where event_key=coalesce(inbox_key,new.event_key) and recipient_worker_id=new.recipient_worker_id;end if;
 new.route_url:=new.route_url||case when strpos(new.route_url,'?')>0 then '&' else '?' end||'rc_notice='||notice::text;
 new.payload:=new.payload||jsonb_build_object('notice_id',notice);
 return new;
end $$;
drop trigger if exists rr_capture_chat_notice_test71 on public.rr_targeted_push_outbox_v708;
create trigger rr_capture_chat_notice_test71 before insert on public.rr_targeted_push_outbox_v708 for each row execute function rr_chat_notifications_test71.capture_targeted();
create or replace function rr_chat_notifications_test71.notify_bridge() returns trigger
language plpgsql security definer set search_path='' as $$
declare dep text;state text;route text;r record;event text;begin
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
drop trigger if exists rr_universal_chat_notice_test71 on public.rr_real_chat_message_bridge_v70;
create trigger rr_universal_chat_notice_test71 after insert or update of source_event_type,action_code,sent_at on public.rr_real_chat_message_bridge_v70 for each row execute function rr_chat_notifications_test71.notify_bridge();
create or replace function public.rr_chat_notification_inbox_test71() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform public.rr_assert_active_user_v1();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'department_code',i.department_code,'title',i.title,'route_url',i.route_url,'bridge_id',i.bridge_id,'event_key',b.canonical_key,'worker_ids',jsonb_build_array(b.sender_worker_id,public.rr_canonical_worker_id_v264(b.sender_worker_id),b.receiver_worker_id,public.rr_canonical_worker_id_v264(b.receiver_worker_id)),'lot_no',coalesce(i.lot_no,b.group_payload->>'lot_no'),'cb_no',coalesce(b.group_payload->>'cb_no',b.group_payload->>'cb_code'),'created_at',i.created_at) order by i.created_at),'[]'::jsonb)
 from rr_chat_notifications_test71.inbox i left join public.rr_real_chat_message_bridge_v70 b on b.id=i.bridge_id and b.data_mode='TEST' where i.read_at is null
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE')
 and (i.login_request_id is null or public.rr_customer_login_push_pending_test71(i.login_request_id,i.recipient_worker_id))
 and (i.bridge_id is null or exists(select 1 from public.rr_real_chat_message_bridge_v70 b where b.id=i.bridge_id and b.data_mode='TEST' and b.archived_at is null)));
end $$;
create or replace function public.rr_chat_notification_read_test71(p_ids uuid[]) returns integer
language plpgsql security definer set search_path='' as $$
declare n integer;begin
 perform public.rr_assert_active_user_v1();
 update rr_chat_notifications_test71.inbox i set read_at=now() where i.id=any(p_ids) and i.read_at is null
 and exists(select 1 from public.rr_worker_directory_unified_v1 w where w.worker_id=i.recipient_worker_id and w.linked_auth_user_id=auth.uid() and w.is_active and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE');
 get diagnostics n=row_count;return n;
end $$;
revoke all on function public.rr_chat_notification_inbox_test71() from public,anon;
revoke all on function public.rr_chat_notification_read_test71(uuid[]) from public,anon;
grant execute on function public.rr_chat_notification_inbox_test71(),public.rr_chat_notification_read_test71(uuid[]) to authenticated;
revoke all on all functions in schema rr_chat_notifications_test71 from public,anon,authenticated;

-- Recover current pending approvals without enqueuing/sending any notification.
insert into rr_chat_notifications_test71.inbox(event_key,recipient_worker_id,department_code,title,route_url,login_request_id)
select distinct on(a.id,o.recipient_worker_id) 'CUSTOMER_LOGIN_APPROVAL_TEST71:'||a.id::text||':'||a.requested_at::text,o.recipient_worker_id,'ADMIN',o.title,o.route_url,a.id
from public.rr_targeted_push_outbox_v708 o join rr_customer_auth_test71.login_approvals a on a.id::text=o.payload->>'login_request_id'
where o.payload->>'source'='CUSTOMER_LOGIN_APPROVAL_TEST71' and public.rr_customer_login_push_pending_test71(a.id,o.recipient_worker_id)
order by a.id,o.recipient_worker_id,o.created_at desc
on conflict(event_key,recipient_worker_id) do nothing;
