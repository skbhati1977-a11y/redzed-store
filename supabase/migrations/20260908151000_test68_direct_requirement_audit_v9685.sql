-- TEST68 follow-up: preserve technical Requirement messages as recoverable audit
-- rows and maintain canonical numbering for future direct-customer updates.

create or replace function public.rr_collection_submit_requirement_v9588(
  p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb,
  p_requirement_id uuid default null
) returns jsonb language plpgsql security definer set search_path='public' as $function$
declare
  s public.rr_market_share_v9420%rowtype; cy public.rr_collection_cycle_v9586%rowtype;
  outj jsonb; rid uuid; req public.rr_market_requirements_v9420%rowtype;
  existing_cycle uuid; req_seq int; ch uuid; cn int; dm text; v_update int; v_kind text;
begin
  select * into s from public.rr_market_share_v9420
  where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if s.id is null then raise exception 'Share link unavailable.'; end if;
  select c.* into cy from public.rr_collection_send_v9586 cs
  join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
  where cs.share_id=s.id limit 1;
  if cy.id is null then
    if s.customer_id is null then raise exception 'Permanent customer identity is required before Requirement submit.'; end if;
    dm:=upper(coalesce(nullif(trim(s.data_mode),''),'TEST'));
    select id into ch from public.rr_customer_chat_v9433
    where customer_id=s.customer_id and data_mode=dm and status='OPEN'
    order by created_at asc limit 1;
    if ch is null then raise exception 'Permanent customer chat is required before Requirement submit.'; end if;
    perform pg_advisory_xact_lock(hashtextextended(s.customer_id::text||'|'||dm||'|COLLECTION_ADOPT',9628));
    select c.* into cy from public.rr_collection_send_v9586 cs
    join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
    where cs.share_id=s.id limit 1;
    if cy.id is null then
      select coalesce(max(collection_no),0)+1 into cn from public.rr_collection_cycle_v9586
      where customer_id=s.customer_id and data_mode=dm;
      insert into public.rr_collection_cycle_v9586(
        customer_id,chat_id,data_mode,collection_no,display_no,status,opened_at,created_by
      ) values(s.customer_id,ch,dm,cn,'RZ COLLECTION '||lpad(cn::text,2,'0'),'OPENED_NO_RESPONSE',now(),auth.uid())
      returning * into cy;
      insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)
      values(cy.id,s.id,1,'FIRST',auth.uid());
    end if;
  end if;
  if cy.status in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED') then raise exception 'Collection is closed/cancelled.'; end if;
  if p_requirement_id is not null then
    select collection_cycle_id into existing_cycle from public.rr_collection_requirement_link_v9586
    where requirement_id=p_requirement_id;
    if existing_cycle is null or existing_cycle<>cy.id then raise exception 'Requirement is not linked to this Collection flow.'; end if;
  end if;
  outj:=public.rr_market_submit_requirement_v9508(
    p_token,p_customer_name,p_mobile,p_message,p_lines,p_requirement_id
  );
  rid:=(outj->>'requirement_id')::uuid;
  select * into req from public.rr_market_requirements_v9420 where id=rid;
  if req.id is null then raise exception 'Requirement submit failed.'; end if;
  if req.customer_id is distinct from cy.customer_id then raise exception 'Requirement customer does not match Collection customer.'; end if;
  if p_requirement_id is null then
    perform pg_advisory_xact_lock(hashtextextended(cy.id::text||'|REQ',9588));
    select coalesce(max(requirement_seq),0)+1 into req_seq
    from public.rr_collection_requirement_link_v9586 where collection_cycle_id=cy.id;
    insert into public.rr_collection_requirement_link_v9586(
      collection_cycle_id,requirement_id,requirement_seq,is_primary
    ) values(cy.id,rid,req_seq,true);
    v_kind:='REQUIREMENT';
  else
    select requirement_seq into req_seq from public.rr_collection_requirement_link_v9586
    where requirement_id=rid;
    v_kind:='REQUIREMENT_UPDATE';
  end if;
  v_update:=public.rr_collection_next_update_v9633(cy.id);
  insert into public.rr_collection_activity_v9633(
    collection_cycle_id,update_no,activity_kind,actor_kind,reference_id,payload
  ) values(cy.id,v_update,v_kind,'CUSTOMER',rid,jsonb_build_object(
    'requirement_no',req.requirement_no,'lot_count',outj->'lot_count','total_qty',outj->'total_qty'
  ));
  update public.rr_customer_chat_messages_v9433 set
    archived_at=coalesce(archived_at,clock_timestamp()),
    archive_reason=coalesce(archive_reason,'DIRECT_REQUIREMENT_TECHNICAL_AUDIT'),
    archive_meta=coalesce(archive_meta,'{}'::jsonb)||jsonb_build_object('requirement_id',rid,'collection_cycle_id',cy.id)
  where chat_id=cy.chat_id and message_type='REQUIREMENT'
    and payload->>'requirement_id'=rid::text;
  update public.rr_collection_cycle_v9586 set status='REQUIREMENT_RECEIVED'
  where id=cy.id and status not in('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED');
  return outj||jsonb_build_object(
    'collection_cycle_id',cy.id,'collection_no',cy.collection_no,'collection_display_no',cy.display_no,
    'requirement_seq',req_seq,'requirement_no',req.requirement_no,'update_no',v_update,
    'collection_status',(select status from public.rr_collection_cycle_v9586 where id=cy.id)
  );
end
$function$;

create or replace function public.rr_direct_requirement_identity_v9685(
  p_requirement_id uuid,p_collection_cycle_id uuid,p_is_update boolean
) returns public.rr_market_requirements_v9420
language plpgsql security definer set search_path='' as $function$
declare v_req public.rr_market_requirements_v9420%rowtype; v_seq bigint; v_up integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_requirement_id::text||'|DIRECT_REQ_ID',9685));
  select * into v_req from public.rr_market_requirements_v9420 where id=p_requirement_id for update;
  if v_req.id is null then raise exception 'Requirement unavailable.'; end if;
  v_seq:=v_req.requirement_sequence_no;
  if v_seq is null then
    select coalesce(max(requirement_sequence_no),0)+1 into v_seq from public.rr_market_requirements_v9420;
  end if;
  v_up:=case when p_is_update then coalesce(v_req.requirement_update_no,0)+1
             else coalesce(v_req.requirement_update_no,0) end;
  update public.rr_market_requirements_v9420 set
    root_requirement_id=coalesce(root_requirement_id,id),requirement_sequence_no=v_seq,
    requirement_update_no=v_up,
    requirement_display_no='REQUIREMENT '||lpad(v_seq::text,2,'0')||case when v_up>0 then ' · UPDATE '||v_up else '' end,
    collection_cycle_id=p_collection_cycle_id,
    collection_no=(select collection_no from public.rr_collection_cycle_v9586 where id=p_collection_cycle_id),
    collection_update_no=greatest(coalesce((select max(send_seq) from public.rr_collection_send_v9586 where collection_cycle_id=p_collection_cycle_id),1)-1,0),
    collection_display_no=(select display_no from public.rr_collection_cycle_v9586 where id=p_collection_cycle_id),
    lifecycle_stage=case when lifecycle_stage='CI_FINAL' then lifecycle_stage else 'READY_FOR_PI' end
  where id=p_requirement_id returning * into v_req;
  return v_req;
end
$function$;

revoke all on function public.rr_direct_requirement_identity_v9685(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.rr_direct_requirement_identity_v9685(uuid,uuid,boolean) to service_role;

-- Add canonical identity assignment to the public wrapper while keeping its
-- token/identity validation in rr_collection_submit_requirement_v9588.
create or replace function public.rr_direct_collection_submit_requirement_v9684(
  p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb,
  p_requirement_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_result jsonb; v_req public.rr_market_requirements_v9420%rowtype;
  v_cycle public.rr_collection_cycle_v9586%rowtype; v_root uuid; v_message uuid; v_body text;
begin
  v_result:=public.rr_collection_submit_requirement_v9588(
    p_token,p_customer_name,p_mobile,p_message,p_lines,p_requirement_id
  );
  select * into v_cycle from public.rr_collection_cycle_v9586
  where id=(v_result->>'collection_cycle_id')::uuid;
  v_req:=public.rr_direct_requirement_identity_v9685(
    (v_result->>'requirement_id')::uuid,v_cycle.id,p_requirement_id is not null
  );
  if v_req.id is null or v_cycle.id is null or v_req.customer_id<>v_cycle.customer_id then
    raise exception 'Canonical Requirement cycle unavailable.';
  end if;
  v_root:=coalesce(v_req.root_requirement_id,v_req.id);
  v_body:='[REQ:'||v_req.id::text||'] '||v_req.requirement_display_no||' · '||
    coalesce(v_result->>'lot_count','0')||' styles · '||coalesce(v_result->>'total_qty','0')||' pcs';
  select m.id into v_message from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=v_cycle.chat_id and m.channel='GROUP' and m.archived_at is null
    and (m.payload->>'direct_requirement_root_id'=v_root::text
      or m.payload->>'requirement_id'=v_req.id::text
      or position('[REQ:'||v_req.id::text||']' in coalesce(m.body,''))>0)
  order by m.created_at desc,m.id desc limit 1 for update;
  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload
    ) values(v_cycle.chat_id,'GROUP','CUSTOMER',v_req.customer_id,v_req.customer_name,'REQUIREMENT',v_body,
      jsonb_build_object('source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,
        'direct_requirement_root_id',v_root,'direct_collection_cycle_id',v_cycle.id,
        'requirement_display_no',v_req.requirement_display_no,'requirement_update_no',v_req.requirement_update_no,
        'lot_count',(v_result->>'lot_count')::integer,'total_qty',(v_result->>'total_qty')::integer))
    returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433 set body=v_body,message_type='REQUIREMENT',
      payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
        'source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,
        'direct_requirement_root_id',v_root,'direct_collection_cycle_id',v_cycle.id,
        'requirement_display_no',v_req.requirement_display_no,'requirement_update_no',v_req.requirement_update_no,
        'lot_count',(v_result->>'lot_count')::integer,'total_qty',(v_result->>'total_qty')::integer),
      created_at=clock_timestamp(),archived_at=null,archive_reason=null,archive_meta='{}'::jsonb
    where id=v_message;
  end if;
  update public.rr_customer_chat_messages_v9433 m set archived_at=clock_timestamp(),
    archive_reason='DIRECT_REQUIREMENT_SUPERSEDED_SINGLE_CARD',
    archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('canonical_message_id',v_message,'requirement_root_id',v_root)
  where m.chat_id=v_cycle.chat_id and m.id<>v_message and m.archived_at is null
    and (m.payload->>'direct_requirement_root_id'=v_root::text
      or m.payload->>'requirement_id'=v_req.id::text
      or position('[REQ:'||v_req.id::text||']' in coalesce(m.body,''))>0);
  return v_result||jsonb_build_object('chat_message_id',v_message,'requirement_root_id',v_root,
    'requirement_display_no',v_req.requirement_display_no,'requirement_update_no',v_req.requirement_update_no);
end
$function$;

revoke all on function public.rr_collection_submit_requirement_v9588(text,text,text,text,jsonb,uuid) from public;
grant execute on function public.rr_collection_submit_requirement_v9588(text,text,text,text,jsonb,uuid) to anon,authenticated,service_role;
revoke all on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) from public;
grant execute on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) to anon,authenticated,service_role;
