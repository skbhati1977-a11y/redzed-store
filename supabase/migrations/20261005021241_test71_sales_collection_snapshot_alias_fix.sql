CREATE OR REPLACE FUNCTION public.rr_market_submit_requirement_v9508_legacy_v67(p_token text, p_customer_name text, p_mobile text, p_message text, p_lines jsonb, p_requirement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.rr_market_share_v9420%rowtype;rid uuid;cj jsonb;cid uuid;ln jsonb;av int;req int;acc int;chat uuid;
 is_append boolean:=p_requirement_id is not null;total_qty int;lot_count int;
 cy public.rr_collection_cycle_v9586%rowtype; previous_lines jsonb; direct_snapshot boolean:=false;
begin
 select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE'
 order by case when token=p_token then 0 else 1 end limit 1;
 if not found then raise exception 'Share link unavailable.';end if;

 select c.* into cy from public.rr_collection_send_v9586 cs join public.rr_collection_cycle_v9586 c
  on c.id=cs.collection_cycle_id where cs.share_id=s.id and c.data_mode='TEST'
  and c.customer_id=s.customer_id and c.chat_id=s.origin_chat_id
  and s.origin_relation_kind='DIRECT_CUSTOMER' limit 1;
 direct_snapshot:=cy.id is not null;
 if direct_snapshot then
  perform pg_advisory_xact_lock(hashtextextended(cy.id::text||'|DIRECT_REQUIREMENT',9714));
  if cy.status not in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
   then raise exception 'This requirement is complete and cannot be changed.'; end if;
  if p_requirement_id is not null and not exists(select 1 from public.rr_market_requirements_v9420 r
   where r.id=p_requirement_id and r.collection_cycle_id=cy.id and r.customer_id=cy.customer_id
    and r.pi_generated_at is null and coalesce(r.lifecycle_stage,r.status,'') not in('SUPERSEDED','PI_GENERATED','CI_FINAL','CANCELLED')
    and not exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id))
   then raise exception 'This requirement is unavailable for update.'; end if;
  select ch.customer_name,ch.mobile into p_customer_name,p_mobile from public.rr_customer_chat_v9433 ch
   where ch.id=cy.chat_id and ch.customer_id=cy.customer_id and ch.data_mode=cy.data_mode and ch.status='OPEN';
  if not found then raise exception 'This party chat is unavailable.'; end if;
 end if;
 cj:=public.rr_market_register_customer_v9423(p_customer_name,p_mobile);cid:=(cj->>'customer_id')::uuid;
 if s.customer_id is not null and s.customer_id<>cid then raise exception 'Collection belongs to another customer.';end if;
 if is_append then
   select id into rid from public.rr_market_requirements_v9420 where id=p_requirement_id and customer_id=cid limit 1;
   if rid is null then raise exception 'REQUIREMENT NOT AVAILABLE FOR THIS CUSTOMER';end if;
 else
   insert into public.rr_market_requirements_v9420(share_id,customer_id,customer_is_new,customer_name,mobile,message)
   values(s.id,cid,coalesce((cj->>'is_new')::boolean,false),cj->>'customer_name',cj->>'mobile',p_message) returning id into rid;
 end if;

 if direct_snapshot then
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)=0 then raise exception 'Select required quantity first.'; end if;
  if exists(select 1 from jsonb_array_elements(p_lines) incoming
   where coalesce(incoming->>'qty','') !~ '^[0-9]+$' or not exists(
    select 1 from public.rr_collection_send_v9586 cs join public.rr_market_share_lots_v9420 sl on sl.share_id=cs.share_id
    where cs.collection_cycle_id=cy.id and upper(trim(sl.lot_no))=upper(trim(incoming->>'lot_no'))))
   then raise exception 'Use designs from this party collection and enter whole quantities.'; end if;
  if exists(select 1 from jsonb_array_elements(p_lines) incoming group by upper(trim(incoming->>'lot_no')) having count(*)>1)
   then raise exception 'Each design can appear once in a requirement.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('lot_no',lot_no,'requested_qty',requested_qty,'accepted_qty',accepted_qty)),'[]')
   into previous_lines from public.rr_market_requirement_lines_v9420 where requirement_id=rid;
  -- Keep removed rows with an authoritative zero, preserving audit and preventing old quantity resurrection.
  update public.rr_market_requirement_lines_v9420 set requested_qty=0,accepted_qty=0 where requirement_id=rid;
  for ln in select * from jsonb_array_elements(p_lines) loop
   select coalesce(sum(available_qty),0)::int into av from public.rr_fg_stock_balance_v787
    where data_mode=s.data_mode and upper(trim(lot_no))=upper(trim(ln->>'lot_no'));
   req:=(ln->>'qty')::int; acc:=least(req,greatest(av,0));
   update public.rr_market_requirement_lines_v9420 set requested_qty=req,accepted_qty=acc,max_available_at_submit=av
    where requirement_id=rid and upper(trim(lot_no))=upper(trim(ln->>'lot_no'));
   if not found then
    insert into public.rr_market_requirement_lines_v9420(requirement_id,lot_no,requested_qty,accepted_qty,max_available_at_submit)
     values(rid,upper(trim(ln->>'lot_no')),req,acc,av);
   end if;
  end loop;
  update public.rr_market_requirements_v9420 set message=p_message,submitted_at=clock_timestamp() where id=rid;
 else
 for ln in select * from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop
   if not exists(select 1 from public.rr_market_share_lots_v9420 where share_id=s.id and lot_no=ln->>'lot_no')then continue;end if;
   if is_append and exists(select 1 from public.rr_market_requirement_lines_v9420 x where x.requirement_id=rid and x.lot_no=ln->>'lot_no')then continue;end if;
   select coalesce(sum(available_qty),0)::int into av from public.rr_fg_stock_balance_v787 where data_mode=s.data_mode and lot_no=ln->>'lot_no';
   req:=greatest(0,coalesce((ln->>'qty')::int,0));acc:=least(req,av);
   if acc>0 then insert into public.rr_market_requirement_lines_v9420(requirement_id,lot_no,requested_qty,accepted_qty,max_available_at_submit)
     values(rid,ln->>'lot_no',req,acc,av);end if;
 end loop;
 end if;
 select count(*) filter(where requested_qty>0),coalesce(sum(accepted_qty),0) into lot_count,total_qty from public.rr_market_requirement_lines_v9420 where requirement_id=rid;
 chat:=s.origin_chat_id;
 if chat is null then select id into chat from public.rr_customer_chat_v9433
   where customer_id=cid and data_mode=s.data_mode and status='OPEN' and relation_kind='DIRECT_CUSTOMER' limit 1;end if;
 if not exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=chat and ch.customer_id=cid
   and ch.data_mode=s.data_mode and ch.status='OPEN' and ch.relation_kind='DIRECT_CUSTOMER')
 then raise exception 'Collection is not bound to this Customer chat.';end if;
 if chat is not null then insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload)
   values(chat,'GROUP','CUSTOMER',cid,cj->>'customer_name','REQUIREMENT',
    (case when is_append then 'Requirement updated' else 'New requirement received' end)||' [REQ:'||rid::text||']',
    jsonb_build_object('source','MARKET_REQUIREMENT','requirement_id',rid,'share_id',s.id,'lot_count',lot_count,'total_qty',total_qty,'is_append',is_append));end if;
 return jsonb_build_object('previous_lines',previous_lines,'requirement_id',rid,'customer',cj,'is_append',is_append,'lot_count',lot_count,'total_qty',total_qty,
   'lines',(select coalesce(jsonb_agg(jsonb_build_object('lot_no',lot_no,'requested_qty',requested_qty,'accepted_qty',accepted_qty,'max_available',max_available_at_submit)),'[]'::jsonb)
   from public.rr_market_requirement_lines_v9420 where requirement_id=rid));
end $function$;
