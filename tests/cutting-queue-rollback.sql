begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
do $$
declare q jsonb;c jsonb;life jsonb;n int;notice jsonb;
begin
 q:=public.rr_chat_cutting_queue_test71('OPEN');
 select count(*) into n from public.rr_cb_units u where u.is_final and u.is_cutting_enabled and upper(u.operation_status)='ACTIVE' and public.rr_cutting_child_lifecycle_v615(u.id)->>'state'='READY_FOR_CUTTING';
 if jsonb_array_length(q->'cards')<>n then raise exception 'Canonical cutting cards missing';end if;
 for c in select * from jsonb_array_elements(q->'cards') loop
  life:=public.rr_cutting_child_lifecycle_v615((c->>'cb_unit_id')::uuid);
  if life->>'state'<>'READY_FOR_CUTTING' or c->>'chat_status'<>'OPEN' or jsonb_array_length(c->'actions')=0 then raise exception 'Invalid cutting readiness';end if;
 end loop;
 for notice in select * from jsonb_array_elements(public.rr_chat_notification_inbox_test71()) where value->>'department_code'='CUTTING' loop
  if not exists(select 1 from jsonb_array_elements(q->'cards') as rows(card) where rows.card->>'cb_unit_id'=notice->>'cb_unit_id' and rows.card->'source_event_keys' @> jsonb_build_array(notice->>'event_key')) then raise exception 'Unread cutting action has no exact card';end if;
 end loop;
end $$;
select 'canonical readiness, visible card count and exact unread mapping passed' result;
rollback;
