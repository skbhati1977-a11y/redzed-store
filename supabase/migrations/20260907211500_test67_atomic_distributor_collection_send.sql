-- TEST67: atomically create a distributor collection and its private-chat card.
-- Open DRAFT requirements keep collection updates. Customer-closed requirements
-- (READY or later) make the existing creator start the next collection number.

create or replace function public.rr_market_partner_collection_send_v87(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid,
  p_lines jsonb,
  p_link_base text,
  p_attachment jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_collection jsonb;
  v_chat jsonb;
  v_url text;
  v_body text;
begin
  if coalesce(trim(p_link_base),'') !~ '^https://[^[:space:]]+/s\.html$' then
    raise exception 'Valid secure collection link is required.';
  end if;

  -- Both nested functions participate in this transaction. Chat failure rolls
  -- the collection, share and lines back, so the UI cannot report false SENT.
  v_collection:=public.rr_market_partner_collection_priced_create_v67(
    p_session_token,p_device_id,p_partner_customer_id,p_lines
  );
  if nullif(v_collection->>'collection_id','') is null
     or nullif(v_collection->>'token','') is null then
    raise exception 'Collection was not created.';
  end if;

  v_url:=trim(p_link_base)||'?t='||replace(v_collection->>'token',' ','%20');
  if nullif(v_collection->>'short_code','') is not null then
    v_url:=v_url||'&c='||replace(v_collection->>'short_code',' ','%20');
  end if;
  v_url:=v_url||'&v=partner87';
  v_body:=coalesce(v_collection->>'collection_display_no','COLLECTION')
    ||' · '||coalesce(v_collection->>'lot_count','0')||E' selected styles\nOpen collection: '||v_url;

  v_chat:=public.rr_market_partner_collection_chat_upsert_v86(
    p_session_token,p_device_id,p_partner_customer_id,
    (v_collection->>'collection_id')::uuid,v_body,p_attachment
  );
  if coalesce((v_chat->>'ok')::boolean,false) is not true
     or nullif(v_chat->>'message_id','') is null then
    raise exception 'Collection chat card was not created.';
  end if;

  return v_collection||jsonb_build_object(
    'ok',true,
    'chat_message_id',v_chat->>'message_id',
    'chat_id',v_chat->>'chat_id',
    'url',v_url,
    'atomic_send',true
  );
end
$function$;

revoke all on function public.rr_market_partner_collection_send_v87(
  text,text,uuid,jsonb,text,jsonb
) from public;
grant execute on function public.rr_market_partner_collection_send_v87(
  text,text,uuid,jsonb,text,jsonb
) to anon,authenticated,service_role;

comment on function public.rr_market_partner_collection_send_v87(
  text,text,uuid,jsonb,text,jsonb
) is 'TEST67 atomic distributor collection + mapped customer chat card send.';
