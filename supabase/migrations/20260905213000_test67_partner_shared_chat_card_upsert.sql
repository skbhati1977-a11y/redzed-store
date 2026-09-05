-- TEST67 only: project distributor collection/requirement activity into the
-- existing rr_customer_chat_v9433 message architecture. One business root is
-- represented by one chat message, so an update moves/refreshes that card
-- instead of copying every previously sent lot into a new chat row.

create or replace function public.rr_market_partner_collection_chat_upsert_v82(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid,
  p_collection_id uuid,
  p_body text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_chat uuid;
  v_collection public.rr_market_partner_collection_v67%rowtype;
  v_root uuid;
  v_message uuid;
  v_name text;
  v_lot_count integer;
  v_payload jsonb;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;

  select pc.* into v_collection
  from public.rr_market_partner_collection_v67 pc
  where pc.id=p_collection_id
    and pc.owner_customer_id=v_owner
    and pc.partner_customer_id=p_partner_customer_id
    and pc.data_mode='TEST';
  if v_collection.id is null then
    raise exception 'Distributor collection relation is unavailable.';
  end if;

  v_root:=coalesce(v_collection.root_collection_id,v_collection.id);
  v_chat:=public.rr_market_partner_relation_chat_resolve_v67(
    v_owner,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER'
  );
  select c.customer_name into v_name from public.rr_customers c where c.id=v_owner;
  select count(distinct l.lot_no)::integer into v_lot_count
  from public.rr_market_partner_collection_v67 pc
  join public.rr_market_partner_collection_line_v67 l on l.collection_id=pc.id
  where coalesce(pc.root_collection_id,pc.id)=v_root
    and pc.status<>'CANCELLED';

  v_payload:=jsonb_build_object(
    'relation_scope','DISTRIBUTOR_CUSTOMER',
    'partner_collection_root_id',v_root,
    'partner_collection_id',v_collection.id,
    'market_share_id',v_collection.share_id,
    'collection_no',v_collection.collection_no,
    'collection_update_no',v_collection.collection_update_no,
    'collection_display_no',v_collection.collection_display_no,
    'lot_count',coalesce(v_lot_count,0),
    'source','PARTNER_MARKET_WINDOW'
  );

  select m.id into v_message
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=v_chat
    and m.channel='GROUP'
    and m.archived_at is null
    and m.payload->>'partner_collection_root_id'=v_root::text
  order by m.created_at desc
  limit 1
  for update;

  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_customer_id,sender_name,
      message_type,body,payload
    ) values(
      v_chat,'GROUP','DISTRIBUTOR',v_owner,
      coalesce(nullif(trim(v_name),''),'Distributor'),
      'LINK',nullif(trim(coalesce(p_body,'')),''),v_payload
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433
    set message_type='LINK',
        body=nullif(trim(coalesce(p_body,'')),''),
        payload=coalesce(payload,'{}'::jsonb)||v_payload,
        created_at=clock_timestamp(),
        archived_at=null,
        archived_by=null,
        archive_reason=null,
        archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  return jsonb_build_object(
    'ok',true,'message_id',v_message,'chat_id',v_chat,
    'collection_root_id',v_root,'lot_count',coalesce(v_lot_count,0)
  );
end
$function$;

create or replace function public.rr_market_partner_requirement_chat_upsert_v82(
  p_session_token text,
  p_device_id text,
  p_order_id uuid,
  p_body text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_ctx jsonb;
  v_chat uuid;
  v_owner uuid;
  v_customer uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_root uuid;
  v_message uuid;
  v_name text;
  v_payload jsonb;
  v_text text;
begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(
    p_session_token,p_device_id
  );
  v_chat:=(v_ctx->>'chat_id')::uuid;
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  v_customer:=(v_ctx->>'partner_customer_id')::uuid;
  v_name:=coalesce(nullif(trim(v_ctx->>'customer_name'),''),'Customer');

  select o.* into v_order
  from public.rr_market_partner_order_v67 o
  where o.id=p_order_id
    and o.owner_customer_id=v_owner
    and o.partner_customer_id=v_customer
    and o.data_mode='TEST';
  if v_order.id is null then
    raise exception 'Private customer requirement is unavailable.';
  end if;

  v_root:=coalesce(v_order.root_order_id,v_order.id);
  v_text:=coalesce(
    nullif(trim(p_body),''),
    '[REQ:'||v_order.id::text||'] '||
      coalesce(v_order.requirement_display_no,'REQUIREMENT')||
      ' · sent to distributor'
  );
  if v_text !~* '\[REQ:[0-9a-f-]{36}\]' then
    v_text:='[REQ:'||v_order.id::text||'] '||v_text;
  end if;
  v_payload:=jsonb_build_object(
    'relation_scope','DISTRIBUTOR_CUSTOMER',
    'partner_requirement_root_id',v_root,
    'partner_order_id',v_order.id,
    'requirement_no',v_order.requirement_no,
    'requirement_update_no',v_order.requirement_update_no,
    'requirement_display_no',v_order.requirement_display_no,
    'source','PARTNER_CUSTOMER_REQUIREMENT'
  );

  select m.id into v_message
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=v_chat
    and m.channel='GROUP'
    and m.archived_at is null
    and m.payload->>'partner_requirement_root_id'=v_root::text
  order by m.created_at desc
  limit 1
  for update;

  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_name,message_type,body,payload
    ) values(
      v_chat,'GROUP','CUSTOMER',v_name,'TEXT',v_text,v_payload
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433
    set sender_name=v_name,
        message_type='TEXT',
        body=v_text,
        payload=coalesce(payload,'{}'::jsonb)||v_payload,
        created_at=clock_timestamp(),
        archived_at=null,
        archived_by=null,
        archive_reason=null,
        archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  return jsonb_build_object(
    'ok',true,'message_id',v_message,'chat_id',v_chat,
    'requirement_root_id',v_root,'order_id',v_order.id
  );
end
$function$;

revoke all on function public.rr_market_partner_collection_chat_upsert_v82(
  text,text,uuid,uuid,text
) from public;
revoke all on function public.rr_market_partner_requirement_chat_upsert_v82(
  text,text,uuid,text
) from public;

grant execute on function public.rr_market_partner_collection_chat_upsert_v82(
  text,text,uuid,uuid,text
) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_requirement_chat_upsert_v82(
  text,text,uuid,text
) to anon,authenticated,service_role;

comment on function public.rr_market_partner_collection_chat_upsert_v82(
  text,text,uuid,uuid,text
) is 'TEST67 shared-chat adapter: one moving collection card per distributor/customer collection root.';
comment on function public.rr_market_partner_requirement_chat_upsert_v82(
  text,text,uuid,text
) is 'TEST67 shared-chat adapter: one moving requirement card per distributor/customer requirement root.';
