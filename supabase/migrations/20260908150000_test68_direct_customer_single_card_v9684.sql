-- TEST68: direct REDZED <-> customer canonical Collection and Requirement cards.
-- Existing business tables, numbering and audit rows are reused. Superseded chat
-- messages are archived, never deleted.

create or replace function public.rr_direct_collection_send_v9684(
  p_chat_id uuid,
  p_customer_id uuid,
  p_lots text[],
  p_requirement_id uuid default null,
  p_origin text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
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

  if coalesce(p_origin,'') !~ '^https://([a-z0-9-]+\.)*(vercel\.app|github\.io)$' then
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
$function$;

create or replace function public.rr_direct_collection_submit_requirement_v9684(
  p_token text,
  p_customer_name text,
  p_mobile text,
  p_message text,
  p_lines jsonb,
  p_requirement_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_result jsonb;
  v_req public.rr_market_requirements_v9420%rowtype;
  v_cycle public.rr_collection_cycle_v9586%rowtype;
  v_root uuid;
  v_message uuid;
  v_body text;
begin
  v_result:=public.rr_collection_submit_requirement_v9588(
    p_token,p_customer_name,p_mobile,p_message,p_lines,p_requirement_id
  );
  select * into v_req from public.rr_market_requirements_v9420
  where id=(v_result->>'requirement_id')::uuid;
  select * into v_cycle from public.rr_collection_cycle_v9586
  where id=(v_result->>'collection_cycle_id')::uuid;
  if v_req.id is null or v_cycle.id is null or v_req.customer_id<>v_cycle.customer_id then
    raise exception 'Canonical Requirement cycle unavailable.';
  end if;
  v_root:=coalesce(v_req.root_requirement_id,v_req.id);
  v_body:='[REQ:'||v_req.id::text||'] '||
    coalesce(v_req.requirement_display_no,v_req.requirement_no,'REQUIREMENT')||
    ' · '||coalesce(v_result->>'lot_count','0')||' styles · '||
    coalesce(v_result->>'total_qty','0')||' pcs';

  select m.id into v_message from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=v_cycle.chat_id and m.channel='GROUP' and m.archived_at is null and (
    m.payload->>'direct_requirement_root_id'=v_root::text
    or exists(
      select 1 from public.rr_market_requirements_v9420 r
      where coalesce(r.root_requirement_id,r.id)=v_root
        and (m.payload->>'requirement_id'=r.id::text
          or position('[REQ:'||r.id::text||']' in coalesce(m.body,''))>0)
    )
  ) order by m.created_at desc,m.id desc limit 1 for update;

  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload
    ) values(
      v_cycle.chat_id,'GROUP','CUSTOMER',v_req.customer_id,v_req.customer_name,
      'REQUIREMENT',v_body,jsonb_build_object(
        'source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,
        'direct_requirement_root_id',v_root,'direct_collection_cycle_id',v_cycle.id,
        'requirement_display_no',coalesce(v_req.requirement_display_no,v_req.requirement_no),
        'requirement_update_no',coalesce(v_req.requirement_update_no,0),
        'lot_count',(v_result->>'lot_count')::integer,'total_qty',(v_result->>'total_qty')::integer
      )
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433 set
      sender_customer_id=v_req.customer_id,sender_name=v_req.customer_name,
      message_type='REQUIREMENT',body=v_body,
      payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
        'source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,
        'direct_requirement_root_id',v_root,'direct_collection_cycle_id',v_cycle.id,
        'requirement_display_no',coalesce(v_req.requirement_display_no,v_req.requirement_no),
        'requirement_update_no',coalesce(v_req.requirement_update_no,0),
        'lot_count',(v_result->>'lot_count')::integer,'total_qty',(v_result->>'total_qty')::integer
      ),created_at=clock_timestamp(),archived_at=null,archive_reason=null,archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  update public.rr_customer_chat_messages_v9433 m set
    archived_at=clock_timestamp(),archive_reason='DIRECT_REQUIREMENT_SUPERSEDED_SINGLE_CARD',
    archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('canonical_message_id',v_message,'requirement_root_id',v_root)
  where m.chat_id=v_cycle.chat_id and m.id<>v_message and m.archived_at is null and (
    m.payload->>'direct_requirement_root_id'=v_root::text or exists(
      select 1 from public.rr_market_requirements_v9420 r
      where coalesce(r.root_requirement_id,r.id)=v_root
        and (m.payload->>'requirement_id'=r.id::text
          or position('[REQ:'||r.id::text||']' in coalesce(m.body,''))>0)
    )
  );
  return v_result||jsonb_build_object('chat_message_id',v_message,'requirement_root_id',v_root);
end
$function$;

revoke all on function public.rr_direct_collection_send_v9684(uuid,uuid,text[],uuid,text) from public,anon;
grant execute on function public.rr_direct_collection_send_v9684(uuid,uuid,text[],uuid,text) to authenticated,service_role;
revoke all on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) from public;
grant execute on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) to anon,authenticated,service_role;

comment on function public.rr_direct_collection_send_v9684(uuid,uuid,text[],uuid,text) is
  'TEST68 staff-only direct customer Collection create/update plus one living chat-card upsert.';
comment on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) is
  'TEST68 identity-validated direct Requirement submit/update plus one living chat-card upsert.';
