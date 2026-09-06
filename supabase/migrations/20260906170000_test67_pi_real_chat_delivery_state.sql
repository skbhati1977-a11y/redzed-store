alter table public.rr_market_partner_order_v67
  add column if not exists distributor_pi_chat_sent_at timestamptz,
  add column if not exists distributor_pi_chat_message_id uuid;

create or replace function public.rr_market_partner_pi_chat_status_v67(
  p_session_token text,
  p_device_id text,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner := (v_ctx->>'owner_customer_id')::uuid;
  select * into v_order
    from public.rr_market_partner_order_v67
   where id=p_order_id and owner_customer_id=v_owner and data_mode='TEST';
  if v_order.id is null then raise exception 'Requirement unavailable.'; end if;
  return jsonb_build_object(
    'sent',v_order.distributor_pi_chat_sent_at is not null,
    'sent_at',v_order.distributor_pi_chat_sent_at,
    'message_id',v_order.distributor_pi_chat_message_id
  );
end
$function$;

create or replace function public.rr_market_partner_pi_chat_send_v67(
  p_session_token text,
  p_device_id text,
  p_order_id uuid,
  p_attachment jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_result jsonb;
  v_sent_at timestamptz;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner := (v_ctx->>'owner_customer_id')::uuid;
  select * into v_order
    from public.rr_market_partner_order_v67
   where id=p_order_id and owner_customer_id=v_owner and data_mode='TEST'
   for update;
  if v_order.id is null then raise exception 'Requirement unavailable.'; end if;
  if nullif(trim(coalesce(v_order.distributor_pi_ref,'')),'') is null then
    raise exception 'PI is not available.';
  end if;
  if v_order.distributor_pi_chat_sent_at is not null then
    return jsonb_build_object(
      'ok',true,'already_sent',true,
      'sent_at',v_order.distributor_pi_chat_sent_at,
      'message_id',v_order.distributor_pi_chat_message_id
    );
  end if;
  v_result := public.rr_market_partner_chat_send_v67(
    p_session_token,p_device_id,'CUSTOMER_GROUP',v_order.partner_customer_id,
    '[DPI:'||v_order.id::text||'] '||v_order.distributor_pi_ref||' · '||
      coalesce(nullif(v_order.requirement_display_no,''),v_order.order_ref,'REQUIREMENT')||
      ' · PI SENT TO CUSTOMER',
    p_attachment
  );
  v_sent_at := clock_timestamp();
  update public.rr_market_partner_order_v67
     set distributor_pi_chat_sent_at=v_sent_at,
         distributor_pi_chat_message_id=nullif(v_result->>'id','')::uuid,
         updated_at=now()
   where id=v_order.id;
  return jsonb_build_object(
    'ok',true,'already_sent',false,'sent_at',v_sent_at,
    'message_id',v_result->>'id'
  );
end
$function$;

revoke all on function public.rr_market_partner_pi_chat_status_v67(text,text,uuid) from public;
revoke all on function public.rr_market_partner_pi_chat_send_v67(text,text,uuid,jsonb) from public;
grant execute on function public.rr_market_partner_pi_chat_status_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_pi_chat_send_v67(text,text,uuid,jsonb) to anon,authenticated,service_role;
