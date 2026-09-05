-- TEST67: keep the distributor/customer collection card on the same media
-- contract as the existing REDZED/customer flow. The market window already
-- builds the poster; this RPC stores it on the one moving root message.

create or replace function public.rr_market_partner_collection_chat_upsert_v86(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid,
  p_collection_id uuid,
  p_body text,
  p_attachment jsonb default null
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
  v_data_url text;
  v_raw bytea;
  v_mime text;
  v_file text;
  v_attachment uuid;
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
      case when p_attachment is null or p_attachment='null'::jsonb
        then 'LINK' else 'ATTACHMENT' end,
      nullif(trim(coalesce(p_body,'')),''),v_payload
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433
    set message_type=case when p_attachment is null or p_attachment='null'::jsonb
          then 'LINK' else 'ATTACHMENT' end,
        body=nullif(trim(coalesce(p_body,'')),''),
        payload=coalesce(payload,'{}'::jsonb)||v_payload,
        created_at=clock_timestamp(),
        archived_at=null,
        archived_by=null,
        archive_reason=null,
        archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  if p_attachment is not null and p_attachment<>'null'::jsonb then
    v_data_url:=p_attachment->>'data_url';
    if v_data_url !~ '^data:image/[^;]+;base64,' then
      raise exception 'Collection poster must be an image.';
    end if;
    v_raw:=decode(split_part(v_data_url,',',2),'base64');
    if octet_length(v_raw)<1 or octet_length(v_raw)>6291456 then
      raise exception 'Collection poster must be 1 byte to 6 MB.';
    end if;
    v_mime:=coalesce(
      nullif(trim(p_attachment->>'type'),''),
      split_part(split_part(v_data_url,';',1),':',2),
      'image/jpeg'
    );
    if lower(v_mime) not like 'image/%' then
      raise exception 'Collection poster must be an image.';
    end if;
    v_file:=coalesce(nullif(trim(p_attachment->>'name'),''),'collection-poster.jpg');

    delete from public.rr_customer_chat_attachments_v9434
    where message_id=v_message;
    insert into public.rr_customer_chat_attachments_v9434(
      message_id,chat_id,file_name,mime_type,byte_size,file_data
    ) values(
      v_message,v_chat,v_file,v_mime,octet_length(v_raw),v_raw
    ) returning id into v_attachment;

    update public.rr_customer_chat_messages_v9433
    set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
      'attachment_id',v_attachment,
      'file_name',v_file,
      'mime_type',v_mime,
      'byte_size',octet_length(v_raw),
      'media_kind','IMAGE'
    )
    where id=v_message;
  end if;

  return jsonb_build_object(
    'ok',true,
    'message_id',v_message,
    'chat_id',v_chat,
    'collection_root_id',v_root,
    'lot_count',coalesce(v_lot_count,0),
    'attachment_id',v_attachment
  );
end
$function$;

revoke all on function public.rr_market_partner_collection_chat_upsert_v86(
  text,text,uuid,uuid,text,jsonb
) from public;
grant execute on function public.rr_market_partner_collection_chat_upsert_v86(
  text,text,uuid,uuid,text,jsonb
) to anon,authenticated,service_role;

comment on function public.rr_market_partner_collection_chat_upsert_v86(
  text,text,uuid,uuid,text,jsonb
) is 'TEST67: one moving distributor/customer collection card with the REDZED/customer poster attachment contract.';
