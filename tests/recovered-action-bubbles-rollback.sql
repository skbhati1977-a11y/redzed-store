begin;
create temp table notice_before as select id,read_at,delivered_at from rr_chat_notifications_test71.inbox;
create temp table pushes_before as select count(*) n from public.rr_targeted_push_outbox_v708;
do $$
declare actor uuid;items jsonb;begin
 select distinct w.linked_auth_user_id into actor from rr_chat_notifications_test71.inbox i join public.rr_worker_directory_unified_v1 w on w.worker_id=i.recipient_worker_id limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.headers','{"origin":"https://test71-workspace.app.github.dev","x-client-info":"redzed-test71"}',true);
 items:=public.rr_chat_notification_inbox_test71();
 if jsonb_array_length(items)=0 then raise exception 'Source-backed existing unread actions still hidden';end if;
 if exists(select 1 from jsonb_array_elements(items) x where x->>'action_key' like 'UPM_CARD_TEST71:%' and (x->'action_detail'->>'source_verified' is distinct from 'true' or x->'action_detail'->>'occurred_at' is null)) then raise exception 'Recovered event has no verified source/time';end if;
 if exists(select 1 from notice_before b full join rr_chat_notifications_test71.inbox i using(id) where b.id is null or i.id is null or b.read_at is distinct from i.read_at or b.delivered_at is distinct from i.delivered_at) then raise exception 'Recovery altered read/delivery or created notices';end if;
 if (select count(*) from public.rr_targeted_push_outbox_v708)<>(select n from pushes_before) then raise exception 'Recovery queued pushes';end if;
 if exists(select 1 from jsonb_array_elements(items) x where x->>'actor_user_id'=actor::text) then raise exception 'Own recovered action counted unread';end if;
end $$;
rollback;
