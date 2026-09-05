-- TEST67 only: split Distributor <-> Customer group chat and direct Distributor chat channels.

create or replace function public.rr_market_partner_chat_send_v67(
  p_session_token text,
  p_device_id text,
  p_lane text,
  p_partner_customer_id uuid default null,
  p_message text default null,
  p_attachment jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_lane text:=upper(trim(coalesce(p_lane,'')));
  v_attachment jsonb;
  v_id bigint;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if v_lane not in('CUSTOMER_GROUP','CUSTOMER_DIRECT','REDZED') then raise exception 'Invalid private chat lane.'; end if;
  if v_lane like 'CUSTOMER_%' and not exists(
    select 1 from public.rr_market_partner_customer_v67 c
    where c.id=p_partner_customer_id and c.owner_customer_id=v_owner and c.status='ACTIVE'
  ) then raise exception 'Distributor customer relation is unavailable.'; end if;
  if v_lane='REDZED' then p_partner_customer_id:=null; end if;
  if nullif(trim(coalesce(p_message,'')),'') is null and (p_attachment is null or p_attachment='null'::jsonb) then
    raise exception 'Message or attachment is required.';
  end if;
  v_attachment:=public.rr_market_partner_chat_attachment_validate_v67(p_attachment);
  insert into public.rr_market_partner_event_v67(owner_customer_id,event_type,note,actor_kind,payload)
  values(v_owner,'CHAT_MESSAGE',left(nullif(trim(coalesce(p_message,'')),''),4000),'DISTRIBUTOR',
    jsonb_strip_nulls(jsonb_build_object('lane',v_lane,'customer_id',p_partner_customer_id,'attachment',v_attachment)))
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id,'lane',v_lane);
end
$$;

create or replace function public.rr_market_partner_chat_messages_v67(
  p_session_token text,
  p_device_id text,
  p_lane text,
  p_partner_customer_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_lane text:=upper(trim(coalesce(p_lane,'')));
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if v_lane not in('CUSTOMER_GROUP','CUSTOMER_DIRECT','REDZED') then raise exception 'Invalid private chat lane.'; end if;
  if v_lane like 'CUSTOMER_%' and not exists(
    select 1 from public.rr_market_partner_customer_v67 c
    where c.id=p_partner_customer_id and c.owner_customer_id=v_owner and c.status='ACTIVE'
  ) then raise exception 'Distributor customer relation is unavailable.'; end if;
  return coalesce((
    select jsonb_agg(x order by (x->>'created_at')::timestamptz)
    from (
      select jsonb_build_object(
        'id',e.id,'actor',e.actor_kind,'message',e.note,
        'attachment',e.payload->'attachment','created_at',e.created_at
      ) x
      from public.rr_market_partner_event_v67 e
      where e.owner_customer_id=v_owner
        and e.event_type='CHAT_MESSAGE'
        and (
          e.payload->>'lane'=v_lane
          or (v_lane='CUSTOMER_GROUP' and e.payload->>'lane'='CUSTOMER')
        )
        and (v_lane='REDZED' or e.payload->>'customer_id'=p_partner_customer_id::text)
      order by e.created_at desc
      limit 200
    ) q
  ),'[]'::jsonb);
end
$$;

revoke all on function public.rr_market_partner_chat_send_v67(text,text,text,uuid,text,jsonb) from public;
revoke all on function public.rr_market_partner_chat_messages_v67(text,text,text,uuid) from public;
grant execute on function public.rr_market_partner_chat_send_v67(text,text,text,uuid,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_chat_messages_v67(text,text,text,uuid) to anon,authenticated,service_role;
