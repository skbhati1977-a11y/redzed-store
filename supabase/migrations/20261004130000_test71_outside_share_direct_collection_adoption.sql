CREATE OR REPLACE FUNCTION public.rr_direct_collection_submit_requirement_v9684(p_token text, p_customer_name text, p_mobile text, p_message text, p_lines jsonb, p_requirement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb;v_req public.rr_market_requirements_v9420%rowtype;v_cycle public.rr_collection_cycle_v9586%rowtype;
 v_share public.rr_market_share_v9420%rowtype;v_effective uuid:=p_requirement_id;v_root uuid;v_message uuid;v_body text;
begin
 select * into v_share from public.rr_market_share_v9420 s
 where(s.token=p_token or s.short_code=upper(p_token))and s.status='ACTIVE'
 order by case when s.token=p_token then 0 else 1 end limit 1 for update;
 if v_share.id is null then raise exception 'Share link unavailable.';end if;
 -- Adopt a verified TEST outside share into the existing direct Collection flow.
 -- Never adopt distributor links, another customer's share, or a conflicting route.
 if v_share.data_mode='TEST' and v_share.origin_relation_kind is null then
   if exists(select 1 from public.rr_market_partner_collection_v67 pc where pc.share_id=v_share.id) then
     raise exception 'This collection belongs to the distributor flow.';
   end if;
   declare cj jsonb; cid uuid; ch uuid; cn integer;
   begin
     cj:=public.rr_market_register_customer_v9423(p_customer_name,p_mobile);
     cid:=(cj->>'customer_id')::uuid;
     if cid is null or (v_share.customer_id is not null and v_share.customer_id<>cid) then
       raise exception 'Collection belongs to another customer.';
     end if;
     select id into ch from public.rr_customer_chat_v9433
       where customer_id=cid and data_mode='TEST' and status='OPEN' and relation_kind='DIRECT_CUSTOMER'
       order by created_at asc limit 1;
     if ch is null or (v_share.origin_chat_id is not null and v_share.origin_chat_id<>ch) then
       raise exception 'Collection is not bound to this Customer chat.';
     end if;
     select c.* into v_cycle from public.rr_collection_send_v9586 cs
       join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id where cs.share_id=v_share.id limit 1;
     if v_cycle.id is not null and (v_cycle.customer_id<>cid or v_cycle.chat_id<>ch or v_cycle.data_mode<>'TEST') then
       raise exception 'Collection customer route mismatch.';
     end if;
     if v_cycle.id is null then
       perform pg_advisory_xact_lock(hashtextextended(cid::text||'|TEST|COLLECTION_ADOPT',9628));
       select coalesce(max(collection_no),0)+1 into cn from public.rr_collection_cycle_v9586
         where customer_id=cid and data_mode='TEST';
       insert into public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status,opened_at,created_by)
         values(cid,ch,'TEST',cn,'RZ COLLECTION '||lpad(cn::text,2,'0'),'OPENED_NO_RESPONSE',now(),auth.uid())
         returning * into v_cycle;
       insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)
         values(v_cycle.id,v_share.id,1,'FIRST',auth.uid());
     end if;
     update public.rr_market_share_v9420 set customer_id=cid,origin_relation_kind='DIRECT_CUSTOMER',origin_chat_id=ch
       where id=v_share.id returning * into v_share;
   end;
 end if;
 select c.* into v_cycle from public.rr_collection_send_v9586 cs
 join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id where cs.share_id=v_share.id limit 1;
 if v_cycle.id is null or v_share.origin_relation_kind is distinct from 'DIRECT_CUSTOMER'
   or v_share.origin_chat_id is distinct from v_cycle.chat_id
 then raise exception 'Direct Collection routing is unavailable.';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_cycle.id::text||'|DIRECT_REQUIREMENT',9714));
 if v_effective is null then
   select r.id into v_effective from public.rr_collection_requirement_link_v9586 l
   join public.rr_market_requirements_v9420 r on r.id=l.requirement_id
   where l.collection_cycle_id=v_cycle.id
     and coalesce(r.lifecycle_stage,r.status,'') not in('SUPERSEDED','CI_FINAL','CANCELLED')
     and r.pi_generated_at is null
   order by r.submitted_at desc,r.id desc limit 1;
 end if;
 v_result:=public.rr_collection_submit_requirement_v9588(
   p_token,p_customer_name,p_mobile,p_message,p_lines,v_effective);
 select * into v_cycle from public.rr_collection_cycle_v9586 where id=(v_result->>'collection_cycle_id')::uuid;
 v_req:=public.rr_direct_requirement_identity_v9685((v_result->>'requirement_id')::uuid,v_cycle.id,v_effective is not null);
 if v_req.id is null or v_cycle.id is null or v_req.customer_id<>v_cycle.customer_id then raise exception 'Canonical Requirement cycle unavailable.';end if;
 v_root:=coalesce(v_req.root_requirement_id,v_req.id);
 v_body:='[REQ:'||v_req.id::text||'] '||v_req.requirement_display_no||' · '||coalesce(v_result->>'lot_count','0')||' styles · '||coalesce(v_result->>'total_qty','0')||' pcs';
 select m.id into v_message from public.rr_customer_chat_messages_v9433 m
 where m.chat_id=v_cycle.chat_id and m.channel='GROUP' and m.archived_at is null
   and(m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or m.payload->>'direct_requirement_root_id'=v_root::text)
 order by m.created_at desc,m.id desc limit 1 for update;
 if v_message is null then
   insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload)
   values(v_cycle.chat_id,'GROUP','CUSTOMER',v_req.customer_id,v_req.customer_name,'REQUIREMENT',v_body,
    jsonb_build_object('source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,'direct_requirement_root_id',v_root,
     'direct_collection_cycle_id',v_cycle.id,'requirement_display_no',v_req.requirement_display_no,
     'requirement_update_no',v_req.requirement_update_no,'lot_count',(v_result->>'lot_count')::integer,
     'total_qty',(v_result->>'total_qty')::integer)) returning id into v_message;
 else
   update public.rr_customer_chat_messages_v9433 set body=v_body,message_type='REQUIREMENT',
    payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,
     'direct_requirement_root_id',v_root,'direct_collection_cycle_id',v_cycle.id,'requirement_display_no',v_req.requirement_display_no,
     'requirement_update_no',v_req.requirement_update_no,'lot_count',(v_result->>'lot_count')::integer,
     'total_qty',(v_result->>'total_qty')::integer),created_at=clock_timestamp(),archived_at=null,archive_reason=null,archive_meta='{}'::jsonb
   where id=v_message;
 end if;
 update public.rr_customer_chat_messages_v9433 m set archived_at=clock_timestamp(),archive_reason='DIRECT_REQUIREMENT_SUPERSEDED_SINGLE_CARD',
  archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('canonical_message_id',v_message,'collection_cycle_id',v_cycle.id)
 where m.chat_id=v_cycle.chat_id and m.id<>v_message and m.archived_at is null and m.message_type='REQUIREMENT'
   and(m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or m.payload->>'requirement_id'=v_req.id::text);
 return v_result||jsonb_build_object('chat_message_id',v_message,'requirement_root_id',v_root,
   'requirement_display_no',v_req.requirement_display_no,'requirement_update_no',v_req.requirement_update_no,
   'relation_kind','DIRECT_CUSTOMER','chat_id',v_cycle.chat_id);
end $function$
