-- TEST67 follow-up: partner collections inherit TEST scope through the linked
-- rr_market_share_v9420 row; rr_market_partner_collection_v67 itself has no
-- data_mode column. Keep the shared-chat upsert on the real schema contract.

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
  join public.rr_market_share_v9420 s on s.id=pc.share_id
  where pc.id=p_collection_id
    and pc.owner_customer_id=v_owner
    and pc.partner_customer_id=p_partner_customer_id
    and s.data_mode='TEST'
    and s.status='ACTIVE';
  if v_collection.id is null then
    raise exception 'Distributor collection relation is unavailable.';
  end if;

  v_root:=coalesce(v_collection.root_collection_id,v_collection.id);
  v_chat:=public.rr_market_partner_relation_chat_resolve_v67(
    v_owner,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER'
  );
  select c.customer_name into v_name
  from public.rr_customers c
  where c.id=v_owner;

  select count(distinct lower(btrim(l.lot_no)))::integer into v_lot_count
  from public.rr_market_partner_collection_v67 pc
  join public.rr_market_share_v9420 s on s.id=pc.share_id
  join public.rr_market_partner_collection_line_v67 l on l.collection_id=pc.id
  where coalesce(pc.root_collection_id,pc.id)=v_root
    and pc.status<>'CANCELLED'
    and s.data_mode='TEST';

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

revoke all on function public.rr_market_partner_collection_chat_upsert_v82(
  text,text,uuid,uuid,text
) from public;
grant execute on function public.rr_market_partner_collection_chat_upsert_v82(
  text,text,uuid,uuid,text
) to anon,authenticated,service_role;

comment on function public.rr_market_partner_collection_chat_upsert_v82(
  text,text,uuid,uuid,text
) is 'TEST67 shared-chat adapter: one moving collection card per distributor/customer root, scoped through the linked TEST share.';
