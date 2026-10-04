CREATE OR REPLACE FUNCTION public.rr_direct_collection_send_v9684(p_chat_id uuid, p_customer_id uuid, p_lots text[], p_requirement_id uuid DEFAULT NULL::uuid, p_origin text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cycle public.rr_collection_cycle_v9586%rowtype;
  v_result jsonb;
  v_message uuid;
  v_profile public.rr_user_profiles%rowtype;
  v_url text;
  v_body text;
  v_update integer;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active limit 1;
  if v_profile.id is null then raise exception 'Active staff profile required.'; end if;
  if p_customer_id is null then
    select c.customer_id into p_customer_id from public.rr_customer_chat_v9433 c
    where c.id=p_chat_id and c.data_mode='TEST' and c.status='OPEN' and c.relation_kind='DIRECT_CUSTOMER';
  end if;
  if not exists(
    select 1 from public.rr_customer_chat_v9433 c
    where c.id=p_chat_id and c.customer_id=p_customer_id
      and c.data_mode='TEST' and c.status='OPEN'
  ) then raise exception 'Customer chat identity mismatch.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_chat_id::text||'|DIRECT_COLLECTION',9684));
  if p_requirement_id is not null then
    select c.* into v_cycle
    from public.rr_market_requirements_v9420 r
    join public.rr_collection_cycle_v9586 c on c.id=r.collection_cycle_id
    where r.id=p_requirement_id and r.customer_id=p_customer_id
      and c.chat_id=p_chat_id and c.data_mode='TEST';
    if v_cycle.id is null then raise exception 'Requirement Collection cycle not found.'; end if;
  else
    select * into v_cycle from public.rr_collection_cycle_v9586 c
    where c.chat_id=p_chat_id and c.customer_id=p_customer_id and c.data_mode='TEST'
      and c.status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
    order by c.created_at desc limit 1 for update;
  end if;

  if v_cycle.id is null then
    v_result:=public.rr_collection_create_first_v67(p_customer_id,p_lots,'TEST');
  else
    v_result:=public.rr_collection_add_update_v9587(v_cycle.id,p_lots);
  end if;
  select * into v_cycle from public.rr_collection_cycle_v9586
  where id=(v_result->>'collection_cycle_id')::uuid;
  v_update:=greatest(coalesce((v_result->>'send_seq')::integer,1)-1,0);

  if p_origin is distinct from 'https://redzed-customer-collection.jggfab2011.chatgpt.site'
     and coalesce(p_origin,'') !~ '^https://([a-z0-9-]+\.)*(vercel\.app|github\.io)$' then
    raise exception 'Approved application origin required.';
  end if;
  v_url:=rtrim(p_origin,'/')||'/s.html?t='||(v_result->>'token')||
    case when nullif(v_result->>'short_code','') is null then ''
         else '&c='||(v_result->>'short_code') end||
    case when p_requirement_id is null then '' else '&r='||p_requirement_id::text end||'&v=9684';
  v_body:=coalesce(v_cycle.display_no,'RZ COLLECTION')||
    case when v_update>0 then ' · UPDATE '||v_update else '' end||
    ' · '||coalesce(v_result->>'lot_count','0')||' styles\nOpen collection: '||v_url;

  select m.id into v_message
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=p_chat_id and m.channel='GROUP' and m.archived_at is null
    and (
      m.payload->>'direct_collection_cycle_id'=v_cycle.id::text
      or exists(
        select 1 from public.rr_collection_send_v9586 cs
        join public.rr_market_share_v9420 s on s.id=cs.share_id
        where cs.collection_cycle_id=v_cycle.id
          and (position(s.token in coalesce(m.body,''))>0
            or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
      )
    )
  order by m.created_at desc,m.id desc limit 1 for update;

  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_profile_id,sender_name,message_type,body,payload
    ) values(
      p_chat_id,'GROUP','STAFF',v_profile.id,coalesce(nullif(trim(v_profile.full_name),''),'REDZED Staff'),
      'LINK',v_body,jsonb_build_object(
        'source','DIRECT_MARKET_WINDOW','url',v_url,'market_share_id',v_result->>'share_id',
        'direct_collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
        'collection_display_no',v_cycle.display_no,'collection_update_no',v_update,
        'lot_count',(v_result->>'lot_count')::integer
      )
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433 set
      sender_kind='STAFF',sender_profile_id=v_profile.id,
      sender_name=coalesce(nullif(trim(v_profile.full_name),''),'REDZED Staff'),
      message_type='LINK',body=v_body,
      payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
        'source','DIRECT_MARKET_WINDOW','url',v_url,'market_share_id',v_result->>'share_id',
        'direct_collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
        'collection_display_no',v_cycle.display_no,'collection_update_no',v_update,
        'lot_count',(v_result->>'lot_count')::integer
      ),created_at=clock_timestamp(),archived_at=null,archived_by=null,
      archive_reason=null,archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  update public.rr_customer_chat_messages_v9433 m set
    archived_at=clock_timestamp(),archive_reason='DIRECT_COLLECTION_SUPERSEDED_SINGLE_CARD',
    archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('canonical_message_id',v_message,'collection_cycle_id',v_cycle.id)
  where m.chat_id=p_chat_id and m.id<>v_message and m.archived_at is null and (
    m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or exists(
      select 1 from public.rr_collection_send_v9586 cs
      join public.rr_market_share_v9420 s on s.id=cs.share_id
      where cs.collection_cycle_id=v_cycle.id
        and (position(s.token in coalesce(m.body,''))>0
          or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
    )
  );
  return v_result||jsonb_build_object('chat_message_id',v_message,'url',v_url,'collection_update_no',v_update);
end
$function$
