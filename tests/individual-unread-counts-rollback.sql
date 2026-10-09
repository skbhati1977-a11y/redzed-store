begin;
alter table public.rr_targeted_push_outbox_v708 disable trigger rr_targeted_push_deliver_v708;
create temp table receipt_before as select id,read_at,delivered_at from rr_chat_notifications_test71.inbox;
do $$
declare a record;b record;c record; dep text; deps jsonb; k text; mine uuid[]; theirs uuid[]; items jsonb;prefix text:='INDIVIDUAL_COUNT_FIXTURE:'||gen_random_uuid();begin
 select w.* into a from public.rr_worker_directory_unified_v1 w join public.rr_user_profiles p on p.auth_user_id=w.linked_auth_user_id where lower(p.role_code)='owner' and w.is_active and p.is_active limit 1;
 select w.* into b from public.rr_worker_directory_unified_v1 w join public.rr_user_profiles p on p.auth_user_id=w.linked_auth_user_id where w.is_active and p.is_active and upper(p.access_status)='ACTIVE' and w.linked_auth_user_id<>a.linked_auth_user_id limit 1;
 select w.* into c from public.rr_worker_directory_unified_v1 w join public.rr_user_profiles p on p.auth_user_id=w.linked_auth_user_id where w.is_active and p.is_active and upper(p.access_status)='ACTIVE' and w.linked_auth_user_id not in(a.linked_auth_user_id,b.linked_auth_user_id) limit 1;
 if c.worker_id is null then raise exception 'Missing identities';end if;
 perform set_config('request.jwt.claim.sub',a.linked_auth_user_id::text,true);
 deps:=(public.rr_real_chat_directory_v85()->'departments')||jsonb_build_array(jsonb_build_object('department_code','READYMADE'));
 if jsonb_array_length(deps)<>21 then raise exception 'Expected all 21 chat departments';end if;
 for dep in select x->>'department_code' from jsonb_array_elements(deps) x loop
  k:=prefix||':'||dep;
  perform set_config('request.jwt.claim.sub',c.linked_auth_user_id::text,true);
  insert into rr_chat_notifications_test71.inbox(event_key,recipient_worker_id,department_code,title,route_url,chat_status,actor_user_id)
  select k||':'||n,w,dep,'Fixture action', '?rc_status=CLOSE','CLOSE',c.linked_auth_user_id from generate_series(1,2) n cross join unnest(array[a.worker_id,b.worker_id]) w;
  select array_agg(id order by event_key) into mine from rr_chat_notifications_test71.inbox where event_key like k||':%' and recipient_worker_id=a.worker_id;
  select array_agg(id order by event_key) into theirs from rr_chat_notifications_test71.inbox where event_key like k||':%' and recipient_worker_id=b.worker_id;
  perform set_config('request.jwt.claim.sub',a.linked_auth_user_id::text,true);
  items:=public.rr_chat_notification_inbox_test71();
  if (select count(*) from jsonb_array_elements(items) x where x->>'action_key' like k||':%')<>2 then raise exception '% own initial count',dep;end if;
  if public.rr_chat_notification_read_test71(array[theirs[1]])<>0 then raise exception '% changed other ID',dep;end if;
  perform public.rr_chat_notification_read_test71(array[mine[1]]);
  items:=public.rr_chat_notification_inbox_test71();
  if (select count(*) from jsonb_array_elements(items) x where x->>'action_key' like k||':%')<>1 then raise exception '% decrement failed',dep;end if;
  perform public.rr_chat_notification_read_test71(mine);
  items:=public.rr_chat_notification_inbox_test71();
  if exists(select 1 from jsonb_array_elements(items) x where x->>'action_key' like k||':%') then raise exception '% zero failed',dep;end if;
  if exists(select 1 from jsonb_array_elements(items) x where x->>'action_key' like 'UPM_CARD_TEST71:%' and x->>'route_url' like '%rc_status=CLOSE%') then raise exception '% archived recovery counted unread',dep;end if;
  perform set_config('request.jwt.claim.sub',b.linked_auth_user_id::text,true);
  items:=public.rr_chat_notification_inbox_test71();
  if (select count(*) from jsonb_array_elements(items) x where x->>'action_key' like k||':%')<>2 then raise exception '% other ID unread lost',dep;end if;
 end loop;
 if exists(select 1 from receipt_before previous join rr_chat_notifications_test71.inbox i using(id) where previous.read_at is distinct from i.read_at or previous.delivered_at is distinct from i.delivered_at) then raise exception 'Existing receipts mutated';end if;
end $$;
rollback;
