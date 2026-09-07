-- Keep one canonical distributor PI card per order. Existing duplicate cards are
-- archived (recoverable) and old TEST67 orders are backfilled to the latest card.
with ranked as (
  select m.id,
         (regexp_match(m.body,'\[DPI:([0-9a-f-]{36})\]','i'))[1]::uuid as order_id,
         row_number() over (
           partition by (regexp_match(m.body,'\[DPI:([0-9a-f-]{36})\]','i'))[1]
           order by m.created_at desc, m.id desc
         ) as rn
    from public.rr_customer_chat_messages_v9433 m
   where m.archived_at is null
     and m.body ~* '\[DPI:[0-9a-f-]{36}\]'
), canonical as (
  select r.order_id,m.id,m.created_at
    from ranked r
    join public.rr_customer_chat_messages_v9433 m on m.id=r.id
   where r.rn=1
)
update public.rr_market_partner_order_v67 o
   set distributor_pi_chat_message_id=c.id,
       distributor_pi_chat_sent_at=c.created_at,
       updated_at=now()
  from canonical c
 where o.id=c.order_id and o.data_mode='TEST';

with ranked as (
  select m.id,
         row_number() over (
           partition by (regexp_match(m.body,'\[DPI:([0-9a-f-]{36})\]','i'))[1]
           order by m.created_at desc, m.id desc
         ) as rn
    from public.rr_customer_chat_messages_v9433 m
   where m.archived_at is null
     and m.body ~* '\[DPI:[0-9a-f-]{36}\]'
)
update public.rr_customer_chat_messages_v9433 m
   set archived_at=now(),
       archive_reason='TEST67_DUPLICATE_DISTRIBUTOR_PI',
       archive_meta=jsonb_build_object('recoverable',true,'canonicalized_at',now())
  from ranked r
 where m.id=r.id and r.rn>1;

create or replace function public.rr_market_partner_pi_chat_status_v67(
  p_session_token text,p_device_id text,p_order_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_ctx jsonb; v_owner uuid; v_order public.rr_market_partner_order_v67%rowtype;
  v_message_id uuid; v_sent_at timestamptz;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner := (v_ctx->>'owner_customer_id')::uuid;
  select * into v_order from public.rr_market_partner_order_v67
   where id=p_order_id and owner_customer_id=v_owner and data_mode='TEST';
  if v_order.id is null then raise exception 'Requirement unavailable.'; end if;
  select m.id,m.created_at into v_message_id,v_sent_at
    from public.rr_customer_chat_messages_v9433 m
   where m.archived_at is null and m.body like '%[DPI:'||v_order.id::text||']%'
   order by m.created_at desc,m.id desc limit 1;
  if v_message_id is not null and
     (v_order.distributor_pi_chat_message_id is distinct from v_message_id or
      v_order.distributor_pi_chat_sent_at is distinct from v_sent_at) then
    update public.rr_market_partner_order_v67
       set distributor_pi_chat_message_id=v_message_id,
           distributor_pi_chat_sent_at=v_sent_at,updated_at=now()
     where id=v_order.id;
  end if;
  return jsonb_build_object('sent',v_message_id is not null,'sent_at',v_sent_at,'message_id',v_message_id);
end
$function$;

create or replace function public.rr_market_partner_pi_chat_send_v67(
  p_session_token text,p_device_id text,p_order_id uuid,p_attachment jsonb
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_ctx jsonb; v_owner uuid; v_order public.rr_market_partner_order_v67%rowtype;
  v_result jsonb; v_sent_at timestamptz; v_existing_id uuid;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner := (v_ctx->>'owner_customer_id')::uuid;
  select * into v_order from public.rr_market_partner_order_v67
   where id=p_order_id and owner_customer_id=v_owner and data_mode='TEST' for update;
  if v_order.id is null then raise exception 'Requirement unavailable.'; end if;
  if nullif(trim(coalesce(v_order.distributor_pi_ref,'')),'') is null then raise exception 'PI is not available.'; end if;
  if exists(select 1 from public.rr_market_partner_customer_ci_v67 ci
             where ci.source_order_id=v_order.id and ci.owner_customer_id=v_owner and ci.data_mode='TEST') then
    raise exception 'PI is locked because customer CI has been created.';
  end if;
  select m.id,m.created_at into v_existing_id,v_sent_at
    from public.rr_customer_chat_messages_v9433 m
   where m.archived_at is null and m.body like '%[DPI:'||v_order.id::text||']%'
   order by m.created_at desc,m.id desc limit 1;
  if v_existing_id is not null then
    update public.rr_market_partner_order_v67 set distributor_pi_chat_sent_at=v_sent_at,
      distributor_pi_chat_message_id=v_existing_id,updated_at=now() where id=v_order.id;
    return jsonb_build_object('ok',true,'already_sent',true,'sent_at',v_sent_at,'message_id',v_existing_id);
  end if;
  v_result := public.rr_market_partner_chat_send_v67(
    p_session_token,p_device_id,'CUSTOMER_GROUP',v_order.partner_customer_id,
    '[DPI:'||v_order.id::text||'] '||v_order.distributor_pi_ref||' · '||
      coalesce(nullif(v_order.requirement_display_no,''),v_order.order_ref,'REQUIREMENT')||' · PI SENT TO CUSTOMER',
    p_attachment);
  v_sent_at := clock_timestamp();
  update public.rr_market_partner_order_v67 set distributor_pi_chat_sent_at=v_sent_at,
    distributor_pi_chat_message_id=nullif(v_result->>'id','')::uuid,updated_at=now() where id=v_order.id;
  return jsonb_build_object('ok',true,'already_sent',false,'sent_at',v_sent_at,'message_id',v_result->>'id');
end
$function$;

revoke all on function public.rr_market_partner_pi_chat_status_v67(text,text,uuid) from public;
revoke all on function public.rr_market_partner_pi_chat_send_v67(text,text,uuid,jsonb) from public;
grant execute on function public.rr_market_partner_pi_chat_status_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_pi_chat_send_v67(text,text,uuid,jsonb) to anon,authenticated,service_role;
