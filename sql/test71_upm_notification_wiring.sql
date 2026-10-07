-- Add current UPM receipt/submit events to the existing TEST71 inbox.
-- Shared manufacturing data stays authoritative. No historical backfill/push.
alter table rr_chat_notifications_test71.inbox add column if not exists assignment_id uuid;
alter table rr_chat_notifications_test71.inbox add column if not exists submit_request_id uuid;
alter table rr_chat_notifications_test71.inbox add column if not exists worker_ids jsonb;
alter table rr_chat_notifications_test71.inbox add column if not exists chat_status text;

create or replace function rr_chat_notifications_test71.test_request() returns boolean
language sql stable set search_path='' as $$
 select coalesce(current_setting('rr_chat_notifications_test71.test_run',true),'')='on'
 or (nullif(current_setting('request.headers',true),'')::jsonb->>'x-client-info'='redzed-test71' and coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'origin',nullif(current_setting('request.headers',true),'')::jsonb->>'referer','') ~ '^https://[^/]+\.app\.github\.dev(/|$)')
 -- Cross-origin Supabase requests normally carry an origin-only referrer.
 or coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'origin',nullif(current_setting('request.headers',true),'')::jsonb->>'referer','') ~ '^https://[^/]*git-test71-[^/]*\.vercel\.app(/|$)'
 or coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'referer','') ~ '^https://([^/]+\.app\.github\.dev|[^/]*git-test71-[^/]*\.vercel\.app)/(test70-cb-purchase-real-chat-pilot\.html|[^?]+\?[^#]*mode=TEST)';
$$;

create or replace function rr_chat_notifications_test71.emit_upm(
 p_key text,p_department text,p_state text,p_lot text,p_assignment uuid,p_request uuid,p_workers uuid[],p_sender uuid
) returns void language plpgsql security definer set search_path='' as $$
declare w record;dep text:=public.rr_real_chat_canonical_department_v83(p_department);route text;notice uuid;
begin
 if not rr_chat_notifications_test71.test_request() or dep is null or dep='' then return;end if;
 select array_agg(distinct x) into p_workers from (select unnest(p_workers) x union select public.rr_canonical_worker_id_v264(unnest(p_workers))) ids where x is not null;
 route:='test70-cb-purchase-real-chat-pilot.html?rc_view=chat&rc_kind=group&rc_id='||dep||'&rc_parent='||dep||'&rc_status='||p_state||case when p_assignment is not null then '&rc_assignment='||p_assignment else '' end||case when p_request is not null then '&rc_submit='||p_request else '' end;
 for w in select distinct d.worker_id from public.rr_worker_directory_unified_v1 d
 where d.is_active and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE' and d.linked_auth_user_id is not null
 and d.linked_auth_user_id is distinct from auth.uid()
 and d.worker_id is distinct from public.rr_canonical_worker_id_v264(p_sender)
 and (d.worker_id=any(p_workers) or d.linked_auth_user_id=any(p_workers)
 or exists(select 1 from unnest(p_workers) x where public.rr_canonical_worker_id_v264(x)=d.worker_id)
 or upper(coalesce(d.role_code,'')) in ('OWNER','SUPER_ADMIN','ADMIN')
 or exists(select 1 from public.rr_real_chat_department_membership_v70 m where m.worker_id=d.worker_id and m.is_active and public.rr_real_chat_canonical_department_v83(m.department_code)=dep))
 loop
  insert into rr_chat_notifications_test71.inbox(event_key,recipient_worker_id,department_code,title,route_url,lot_no,assignment_id,submit_request_id,worker_ids,chat_status)
  values(p_key||':'||dep,w.worker_id,dep,'REDZED · UPM · '||dep,route,p_lot,p_assignment,p_request,to_jsonb(p_workers),p_state)
  on conflict(event_key,recipient_worker_id) do nothing returning id into notice;
  if notice is not null then
   insert into public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
   values(p_key||':'||dep,w.worker_id,'REDZED · UPM · '||dep,'Lot '||coalesce(p_lot,'')||' · '||p_state||' · नई work update',route,
    jsonb_build_object('source','REAL_CHAT_ACTION_TEST71','source_module','UPM_LIFECYCLE_TEST71','notice_id',notice,'department_code',dep,'assignment_id',p_assignment,'submit_request_id',p_request,'lot_no',p_lot))
   on conflict(event_key,recipient_worker_id) do nothing;
  end if;
 end loop;
end $$;

create or replace function rr_chat_notifications_test71.upm_receipt() returns trigger
language plpgsql security definer set search_path='' as $$
declare a public.rr_upm_work_assignments_v8%rowtype;key text;state text;sender uuid;workers uuid[];
begin
 if not rr_chat_notifications_test71.test_request() then return new;end if;
 if tg_op='UPDATE' and new.status is not distinct from old.status then return new;end if;
 select * into a from public.rr_upm_work_assignments_v8 where id=new.assignment_id;
 if a.id is null or upper(a.status) in ('CANCELLED','CANCELED','VOID') then return new;end if;
 state:=case when upper(new.status) in ('PENDING','DISPUTED') then 'OPEN' when upper(new.status) in ('CONFIRMED','CONFIRMED_SHORT') then 'WORKING' end;
 if state is null then return new;end if;
 sender:=case when state='OPEN' then coalesce(a.assigner_worker_id,new.source_custodian_worker_id) else a.worker_id end;
 workers:=array[a.worker_id,public.rr_canonical_worker_id_v264(a.worker_id),a.assigner_worker_id,new.source_custodian_worker_id];
 key:='UPM_RECEIPT_TEST71:'||coalesce(new.receipt_batch_id,a.assignment_batch_id,a.id)::text||':'||coalesce(a.worker_id::text,'')||':'||state||case when state='WORKING' then ':'||coalesce(new.confirmed_at,now())::text else '' end;
 perform rr_chat_notifications_test71.emit_upm(key,a.department_code,state,a.lot_no,a.id,null,workers,sender);
 return new;
end $$;
drop trigger if exists rr_upm_receipt_notice_test71 on public.rr_upm_assignment_receipts_v9112;
create trigger rr_upm_receipt_notice_test71 after insert or update of status on public.rr_upm_assignment_receipts_v9112 for each row execute function rr_chat_notifications_test71.upm_receipt();

create or replace function rr_chat_notifications_test71.upm_submit() returns trigger
language plpgsql security definer set search_path='' as $$
declare receiver uuid;workers uuid[];key text;state text;sender uuid;
begin
 if not rr_chat_notifications_test71.test_request() then return new;end if;
 if tg_op='UPDATE' and new.status is not distinct from old.status then return new;end if;
 if upper(new.status) in ('CANCELLED','CANCELED','REJECTED','VOID') then return new;end if;
 select w.worker_id into receiver from public.rr_worker_directory_unified_v1 w
 where w.worker_id=new.selected_receiver_worker_id or w.linked_auth_user_id=coalesce(new.selected_receiver_auth_id,new.accepted_lm_id)
 order by (w.worker_id=new.selected_receiver_worker_id) desc nulls last limit 1;
 receiver:=coalesce(receiver,new.selected_receiver_worker_id);
 workers:=array[new.worker_id,public.rr_canonical_worker_id_v264(new.worker_id),receiver,new.accepted_lm_id];
 sender:=case when upper(new.status)='WAITING_LM' then new.worker_id else receiver end;
 key:='UPM_SUBMIT_TEST71:'||new.id||':'||upper(new.status);
 state:=case when upper(new.status)='WAITING_LM' then 'OPEN' when upper(new.status)='COMPLETED' then 'CLOSE' else 'WORKING' end;
 perform rr_chat_notifications_test71.emit_upm(key,coalesce(new.target_department_code,'FABRICATION'),state,new.lot_no,new.assignment_ids[1],new.id,workers,sender);
 if tg_op='INSERT' then
  perform rr_chat_notifications_test71.emit_upm(key,new.department_code,'CLOSE',new.lot_no,new.assignment_ids[1],new.id,workers,sender);
 end if;
 return new;
end $$;
drop trigger if exists rr_upm_submit_notice_test71 on public.rr_upm_submit_requests_v794;
create trigger rr_upm_submit_notice_test71 after insert or update of status on public.rr_upm_submit_requests_v794 for each row execute function rr_chat_notifications_test71.upm_submit();
revoke all on all functions in schema rr_chat_notifications_test71 from public,anon,authenticated;

-- Resolve unread events to the card's current lifecycle state, without re-pushing.
create or replace function rr_chat_notifications_test71.current_state(p_assignment uuid,p_request uuid,p_department text,p_default text)
returns text language plpgsql stable security definer set search_path='' as $$
declare a record;r record;q record;
begin
 if p_request is not null then
  select * into q from public.rr_upm_submit_requests_v794 where id=p_request;
  if not found or upper(q.status) in ('CANCELLED','CANCELED','REJECTED','VOID') then return null;end if;
  if public.rr_real_chat_canonical_department_v83(q.department_code)=p_department and public.rr_real_chat_canonical_department_v83(coalesce(q.target_department_code,'FABRICATION'))<>p_department then return 'CLOSE';end if;
  return case when upper(q.status)='WAITING_LM' then 'OPEN' when upper(q.status)='COMPLETED' then 'CLOSE' else 'WORKING' end;
 elsif p_assignment is not null then
  select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment;
  if not found or upper(a.status) in ('CANCELLED','CANCELED','VOID') then return null;end if;
  if upper(a.status) in ('COMPLETED','CLOSED') or exists(select 1 from public.rr_upm_submit_requests_v794 x where p_assignment=any(x.assignment_ids) and upper(x.status) not in ('CANCELLED','CANCELED','REJECTED','VOID')) then return 'CLOSE';end if;
  select status into r from public.rr_upm_assignment_receipts_v9112 where assignment_id=p_assignment;
  return case when upper(coalesce(r.status,'')) in ('PENDING','DISPUTED') then 'OPEN' else 'WORKING' end;
 end if;
 return p_default;
end $$;
revoke all on function rr_chat_notifications_test71.current_state(uuid,uuid,text,text) from public,anon,authenticated;
