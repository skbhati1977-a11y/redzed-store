-- TEST67 only: private relation-chat messages for Distributor <-> Customer and REDZED <-> Distributor.
-- Lanes are physically filtered by owner/customer relation; no cross-lane reads.

create or replace function public.rr_market_partner_chat_attachment_validate_v67(p_attachment jsonb)
returns jsonb
language plpgsql
immutable
set search_path=''
as $$
declare
  v_url text;
  v_type text;
begin
  if p_attachment is null or p_attachment='null'::jsonb then return null; end if;
  if jsonb_typeof(p_attachment)<>'object' then raise exception 'Invalid attachment.'; end if;
  v_url:=coalesce(p_attachment->>'data_url','');
  v_type:=lower(coalesce(p_attachment->>'type',''));
  if length(v_url)>2000000 then raise exception 'Attachment is too large for TEST67 chat.'; end if;
  if v_url!~'^data:(image/|audio/|application/pdf)' then raise exception 'Only image, audio or PDF attachment is allowed.'; end if;
  if v_type<>'' and v_type!~'^(image/|audio/|application/pdf)' then raise exception 'Attachment type is not allowed.'; end if;
  return jsonb_build_object(
    'name',left(coalesce(p_attachment->>'name','attachment'),160),
    'type',left(v_type,100),
    'data_url',v_url,
    'duration',case when coalesce(p_attachment->>'duration','')~'^[0-9]+$' then (p_attachment->>'duration')::integer else null end
  );
end
$$;

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
  if v_lane not in('CUSTOMER','REDZED') then raise exception 'Invalid private chat lane.'; end if;
  if v_lane='CUSTOMER' and not exists(
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
  if v_lane not in('CUSTOMER','REDZED') then raise exception 'Invalid private chat lane.'; end if;
  if v_lane='CUSTOMER' and not exists(
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
        and e.payload->>'lane'=v_lane
        and (v_lane='REDZED' or e.payload->>'customer_id'=p_partner_customer_id::text)
      order by e.created_at desc
      limit 200
    ) q
  ),'[]'::jsonb);
end
$$;

create or replace function public.rr_market_partner_customer_chat_send_v67(
  p_token text,
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
  v_attachment jsonb;
  v_id bigint;
begin
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
    jsonb_strip_nulls(jsonb_build_object('lane','CUSTOMER','customer_id',v_customer,'attachment',v_attachment)))
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end
$$;

create or replace function public.rr_market_partner_customer_chat_messages_v67(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_owner uuid;
  v_customer uuid;
begin
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
        and e.payload->>'lane'='CUSTOMER'
        and e.payload->>'customer_id'=v_customer::text
      order by e.created_at desc
      limit 200
    ) q
  ),'[]'::jsonb);
end
$$;

revoke all on function public.rr_market_partner_chat_attachment_validate_v67(jsonb) from public,anon,authenticated;
revoke all on function public.rr_market_partner_chat_send_v67(text,text,text,uuid,text,jsonb) from public;
revoke all on function public.rr_market_partner_chat_messages_v67(text,text,text,uuid) from public;
revoke all on function public.rr_market_partner_customer_chat_send_v67(text,text,jsonb) from public;
revoke all on function public.rr_market_partner_customer_chat_messages_v67(text) from public;
grant execute on function public.rr_market_partner_chat_send_v67(text,text,text,uuid,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_chat_messages_v67(text,text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_send_v67(text,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_messages_v67(text) to anon,authenticated,service_role;
