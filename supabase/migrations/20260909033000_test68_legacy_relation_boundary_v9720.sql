-- Keep legacy REDZED <-> distributor workflow messages out of the direct
-- customer timeline. Ambiguous/personal messages deliberately remain in the
-- direct customer chat; only explicit distributor markers are migrated.
do $$
declare
  v_contact record;
  v_pair jsonb;
  v_distributor_chat uuid;
begin
  for v_contact in
    select distinct direct_chat.customer_id, direct_chat.id as direct_chat_id
    from public.rr_customer_chat_v9433 direct_chat
    join public.rr_customer_chat_messages_v9433 message
      on message.chat_id = direct_chat.id
    where direct_chat.relation_kind = 'DIRECT_CUSTOMER'
      and direct_chat.customer_id is not null
      and (
        coalesce(message.payload->>'relation_scope', '') = 'DISTRIBUTOR_REDZED'
        or coalesce(message.payload->>'lane', '') = 'REDZED'
        or coalesce(message.payload->>'batch_id', '') <> ''
        or coalesce(message.body, '') ~* '\[PBATCH:[0-9a-f-]{36}\]'
      )
  loop
    v_pair := public.rr_ensure_contact_relation_chats_v9704(v_contact.customer_id);
    v_distributor_chat := (v_pair->>'distributor_chat_id')::uuid;

    update public.rr_customer_chat_messages_v9433 message
       set chat_id = v_distributor_chat
     where message.chat_id = v_contact.direct_chat_id
       and (
         coalesce(message.payload->>'relation_scope', '') = 'DISTRIBUTOR_REDZED'
         or coalesce(message.payload->>'lane', '') = 'REDZED'
         or coalesce(message.payload->>'batch_id', '') <> ''
         or coalesce(message.body, '') ~* '\[PBATCH:[0-9a-f-]{36}\]'
       );
  end loop;
end $$;
