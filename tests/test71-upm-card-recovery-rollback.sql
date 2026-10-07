begin;
do $$
declare owner_auth uuid; n integer; n2 integer; initial_n integer; pushes bigint; notice uuid;
begin
select linked_auth_user_id into owner_auth from public.rr_worker_directory_unified_v1 where upper(role_code)='OWNER' and is_active limit 1;
perform set_config('request.jwt.claim.sub',owner_auth::text,true);
select count(*) into pushes from public.rr_targeted_push_outbox_v708;
select count(*) into initial_n from rr_chat_notifications_test71.inbox where event_key like 'UPM_CARD_TEST71:%';
perform set_config('request.headers','{"origin":"https://test71-workspace.app.github.dev"}',true);
perform rr_chat_notifications_test71.recover_upm_cards();
if (select count(*) from rr_chat_notifications_test71.inbox where event_key like 'UPM_CARD_TEST71:%')<>initial_n then raise exception 'REAL baseline leaked';end if;
perform set_config('request.headers','{"origin":"https://test71-workspace.app.github.dev","x-client-info":"redzed-test71"}',true);
perform public.rr_chat_notification_inbox_test71();
select count(*) into n from rr_chat_notifications_test71.inbox where event_key like 'UPM_CARD_TEST71:%';
if n=0 then raise exception 'Existing UPM cards not recovered';end if;
select id into notice from rr_chat_notifications_test71.inbox where event_key like 'UPM_CARD_TEST71:%' and read_at is null limit 1;
if public.rr_chat_notification_read_test71(array[notice])<>1 then raise exception 'Baseline read failed';end if;
perform public.rr_chat_notification_inbox_test71();
select count(*) into n2 from rr_chat_notifications_test71.inbox where event_key like 'UPM_CARD_TEST71:%';
if n2<>n or not exists(select 1 from rr_chat_notifications_test71.inbox where id=notice and read_at is not null) then raise exception 'Read reset or duplicate';end if;
if (select count(*) from public.rr_targeted_push_outbox_v708)<>pushes then raise exception 'Historical push queued';end if;
end $$;
rollback;
select 'PASS existing UPM recovery, TEST isolation, no push, idempotent persistent READ' result;
