-- TEST67 only: customer-token access to its own group/direct distributor chat lanes.

create or replace function public.rr_market_partner_customer_chat_send_lane_v67(
  p_token text,
  p_lane text,
  p_message text default null,
  p_attachment jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_owner uuid;
  v_customer uuid;
  v_lane text:=upper(trim(coalesce(p_lane,'')));
  v_attachment jsonb;
  v_id bigint;
begin
  if v_lane not in('CUSTOMER_GROUP','CUSTOMER_DIRECT') then raise exception 'Invalid customer chat lane.'; end if;
  select pc.owner_customer_id,pc.partner_customer_id
  into v_owner,v_customer
  from public.rr_market_share_v9420 s
  join public.rr_market_partner_collection_v67 pc on pc.share_id=s.id
  where (s.token=p_token or s.short_code=upper(p_token))
    and s.status='ACTIVE' and s.data_mode='TEST'
  order by case when s.token=p_token then 0 else 1 end
  limit 1;
  if v_owner is null or v_customer is null then raise exception 'Distributor customer share relation is unavailable.'; end if;
  if nullif(trim(coalesce(p_message,'')),'') is null and (p_attachment is null or p_attachment='null'::jsonb) then
    raise exception 'Message or attachment is required.';
  end if;
  v_attachment:=public.rr_market_partner_chat_attachment_validate_v67(p_attachment);
  insert into public.rr_market_partner_event_v67(owner_customer_id,event_type,note,actor_kind,payload)
  values(v_owner,'CHAT_MESSAGE',left(nullif(trim(coalesce(p_message,'')),''),4000),'CUSTOMER',
    jsonb_strip_nulls(jsonb_build_object('lane',v_lane,'customer_id',v_customer,'attachment',v_attachment)))
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id,'lane',v_lane);
end
$$;

create or replace function public.rr_market_partner_customer_chat_messages_lane_v67(
  p_token text,
  p_lane text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_owner uuid;
  v_customer uuid;
  v_lane text:=upper(trim(coalesce(p_lane,'')));
begin
  if v_lane not in('CUSTOMER_GROUP','CUSTOMER_DIRECT') then raise exception 'Invalid customer chat lane.'; end if;
  select pc.owner_customer_id,pc.partner_customer_id
  into v_owner,v_customer
  from public.rr_market_share_v9420 s
  join public.rr_market_partner_collection_v67 pc on pc.share_id=s.id
  where (s.token=p_token or s.short_code=upper(p_token))
    and s.status='ACTIVE' and s.data_mode='TEST'
  order by case when s.token=p_token then 0 else 1 end
  limit 1;
  if v_owner is null or v_customer is null then raise exception 'Distributor customer share relation is unavailable.'; end if;
  return coalesce((
    select jsonb_agg(x order by (x->>'created_at')::timestamptz)
    from (
      select jsonb_build_object(
        'id',e.id,'actor',e.actor_kind,'message',e.note,
        'attachment',e.payload->'attachment','created_at',e.created_at
      ) x
      from public.rr_market_partner_event_v67 e
      where e.owner_customer_id=v_owner and e.event_type='CHAT_MESSAGE'
        and (e.payload->>'lane'=v_lane or (v_lane='CUSTOMER_GROUP' and e.payload->>'lane'='CUSTOMER'))
        and e.payload->>'customer_id'=v_customer::text
      order by e.created_at desc limit 200
    ) q
  ),'[]'::jsonb);
end
$$;

revoke all on function public.rr_market_partner_customer_chat_send_lane_v67(text,text,text,jsonb) from public;
revoke all on function public.rr_market_partner_customer_chat_messages_lane_v67(text,text) from public;
grant execute on function public.rr_market_partner_customer_chat_send_lane_v67(text,text,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_messages_lane_v67(text,text) to anon,authenticated,service_role;
