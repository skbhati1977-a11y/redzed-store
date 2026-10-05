-- One TEST direct-customer follow-up contract. Existing business tables remain authoritative.
create or replace function public.rr_sales_collection_context_test71(
 p_chat_id uuid,p_requirement_id uuid default null,p_collection_cycle_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ch public.rr_customer_chat_v9433%rowtype; cy public.rr_collection_cycle_v9586%rowtype;
 req public.rr_market_requirements_v9420%rowtype; cats jsonb; sent jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into ch from public.rr_customer_chat_v9433 where id=p_chat_id and data_mode='TEST'
  and status='OPEN' and relation_kind='DIRECT_CUSTOMER';
 if ch.id is null or not exists(select 1 from public.rr_customer_chat_members_v9433 m
 join public.rr_user_profiles p on p.id=m.profile_id where m.chat_id=ch.id and m.is_active
 and p.auth_user_id=auth.uid() and p.is_active) then raise exception 'This party chat is unavailable for your account.'; end if;
 if p_requirement_id is not null then
  select * into req from public.rr_market_requirements_v9420
   where id=p_requirement_id and customer_id=ch.customer_id;
  if req.id is null or (p_collection_cycle_id is not null and req.collection_cycle_id is distinct from p_collection_cycle_id)
   then raise exception 'Requirement does not belong to this collection.'; end if;
  p_collection_cycle_id:=req.collection_cycle_id;
 end if;
 if p_collection_cycle_id is not null then
  select * into cy from public.rr_collection_cycle_v9586
   where id=p_collection_cycle_id and chat_id=ch.id and customer_id=ch.customer_id and data_mode=ch.data_mode;
  if cy.id is null then raise exception 'Collection does not belong to this party chat.'; end if;
 else
  select * into cy from public.rr_collection_cycle_v9586
   where chat_id=ch.id and customer_id=ch.customer_id and data_mode=ch.data_mode
   and status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
   order by created_at desc,id desc limit 1;
 end if;
 if cy.id is not null then
  select * into req from public.rr_market_requirements_v9420 where collection_cycle_id=cy.id
   and coalesce(lifecycle_stage,status,'') not in('SUPERSEDED','CANCELLED')
   order by submitted_at desc,id desc limit 1;
 end if;
 select coalesce(jsonb_agg(x.category order by x.category),'[]'::jsonb) into cats from (
  select distinct trim(c.category) category from public.rr_collection_update_request_v9630 r
  join public.rr_collection_update_category_v9630 c on c.update_request_id=r.id
  where r.collection_cycle_id=cy.id and r.request_kind='MORE_SAMPLES' and (r.status='OPEN' or (r.status='FULFILLED'
   and not exists(select 1 from public.rr_collection_update_request_v9630 pending where pending.collection_cycle_id=cy.id and pending.status='OPEN' and pending.request_kind='MORE_SAMPLES')
   and r.update_no=(select max(done.update_no) from public.rr_collection_update_request_v9630 done where done.collection_cycle_id=cy.id and done.status='FULFILLED' and done.request_kind='MORE_SAMPLES')))
  and nullif(trim(c.category),'') is not null
 ) x;
 select coalesce(jsonb_agg(x.lot_no order by x.lot_no),'[]'::jsonb) into sent from (
  select distinct upper(trim(l.lot_no)) lot_no from public.rr_collection_send_v9586 s
  join public.rr_market_share_lots_v9420 l on l.share_id=s.share_id where s.collection_cycle_id=cy.id
 ) x;
 return jsonb_build_object('chat_id',ch.id,'customer_id',ch.customer_id,'customer_name',ch.customer_name,
 'data_mode',ch.data_mode,'collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
 'requirement_id',req.id,'categories',cats,'sent_lots',sent,
 'can_send',coalesce(cy.status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED'),cy.id is null)
   and req.pi_generated_at is null and coalesce(req.lifecycle_stage,req.status,'') not in('PI_GENERATED','CI_FINAL','CANCELLED')
   and not exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=req.id));
end $$;
revoke all on function public.rr_sales_collection_context_test71(uuid,uuid,uuid) from public,anon;
grant execute on function public.rr_sales_collection_context_test71(uuid,uuid,uuid) to authenticated,service_role;

-- Filter BEFORE pagination; a page of previously sent cards must not hide later eligible cards.
create or replace function public.rr_sales_collection_cards_test71(
 p_chat_id uuid,p_requirement_id uuid default null,p_collection_cycle_id uuid default null,
 p_search text default null,p_category text default null,p_stock_status text default null,
 p_limit integer default 150,p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ctx jsonb; rowsj jsonb:='[]'; chunk jsonb; offn integer:=0; filtered jsonb;
begin
 ctx:=public.rr_sales_collection_context_test71(p_chat_id,p_requirement_id,p_collection_cycle_id);
 if not (ctx->>'can_send')::boolean then raise exception 'This collection is complete. Open a new collection to send designs.'; end if;
 loop
  select coalesce(jsonb_agg(to_jsonb(w)),'[]') into chunk
   from public.rr_web_window_cards_v9329(p_search,p_category,p_stock_status,'TEST',150,offn) w;
  rowsj:=rowsj||chunk;
  exit when jsonb_array_length(chunk)<150;
  offn:=offn+150;
 end loop;
 select coalesce(jsonb_agg(x.val order by x.ord),'[]') into filtered from (
  select e.value val,e.ordinality ord from jsonb_array_elements(rowsj) with ordinality e
  where not (ctx->'sent_lots' ? upper(trim(e.value->>'lot_no')))
   and (jsonb_array_length(ctx->'categories')=0 or exists(
    select 1 from jsonb_array_elements_text(ctx->'categories') c
    where lower(trim(c))=lower(trim(e.value->>'category'))))
  order by e.ordinality limit greatest(1,least(coalesce(p_limit,150),150)) offset greatest(0,coalesce(p_offset,0))
 ) x;
 return jsonb_build_object('context',ctx,'rows',filtered);
end $$;
revoke all on function public.rr_sales_collection_cards_test71(uuid,uuid,uuid,text,text,text,integer,integer) from public,anon;
grant execute on function public.rr_sales_collection_cards_test71(uuid,uuid,uuid,text,text,text,integer,integer) to authenticated,service_role;

-- Token-bound summary; retire the customer-wide "latest cycle" lookup.
create or replace function public.rr_collection_customer_requirement_summary_v9637(p_token text)
returns jsonb language sql security definer set search_path='' as $$
 select public.rr_collection_customer_requirement_summary_v9778(p_token)
$$;
revoke all on function public.rr_collection_customer_requirement_summary_v9637(text) from public;
grant execute on function public.rr_collection_customer_requirement_summary_v9637(text) to anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rr_sales_collection_send_test71(p_chat_id uuid, p_customer_id uuid, p_lots text[], p_requirement_id uuid DEFAULT NULL::uuid, p_origin text DEFAULT NULL::text, p_collection_cycle_id uuid DEFAULT NULL::uuid)
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
  ctx jsonb; lot text; cat text; chosen_cats text[]:=array[]::text[];
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active limit 1;
  if v_profile.id is null then raise exception 'Active staff profile required.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_chat_id::text||'|DIRECT_COLLECTION',9684));
  ctx:=public.rr_sales_collection_context_test71(p_chat_id,p_requirement_id,p_collection_cycle_id);
  if p_customer_id is not null and p_customer_id::text is distinct from ctx->>'customer_id'
   then raise exception 'Collection belongs to another party.'; end if;
  p_customer_id:=(ctx->>'customer_id')::uuid;
  if not (ctx->>'can_send')::boolean then raise exception 'This collection is complete. Open a new collection.'; end if;
  p_requirement_id:=(ctx->>'requirement_id')::uuid;
  select * into v_cycle from public.rr_collection_cycle_v9586 where id=(ctx->>'collection_cycle_id')::uuid for update;
  if v_cycle.id is not null then
   perform pg_advisory_xact_lock(hashtextextended(v_cycle.id::text||'|DIRECT_REQUIREMENT',9714));
  end if;
  select array_agg(distinct upper(trim(x))) into p_lots from unnest(p_lots) x where nullif(trim(x),'') is not null;
  if coalesce(cardinality(p_lots),0)=0 then raise exception 'Select at least one design.'; end if;
  foreach lot in array p_lots loop
   if ctx->'sent_lots' ? lot then raise exception 'This design was already sent. Refresh the collection list.'; end if;
   select w.category into cat from public.rr_web_window_cards_v9329(lot,null,null,'TEST',1,0) w where upper(trim(w.lot_no))=lot;
   if not found then raise exception 'Selected design is unavailable. Refresh the collection list.'; end if;
   if jsonb_array_length(ctx->'categories')>0 and not exists(
    select 1 from jsonb_array_elements_text(ctx->'categories') c where lower(trim(c))=lower(trim(cat)))
    then raise exception 'Select designs from the categories requested by this party.'; end if;
   chosen_cats:=array_append(chosen_cats,lower(trim(cat)));
  end loop;

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
  where m.chat_id=p_chat_id and m.channel='GROUP' and m.archived_at is null and m.message_type<>'REQUIREMENT' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id')
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
  where m.chat_id=p_chat_id and m.id<>v_message and m.archived_at is null and m.message_type<>'REQUIREMENT' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id') and (
    m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or exists(
      select 1 from public.rr_collection_send_v9586 cs
      join public.rr_market_share_v9420 s on s.id=cs.share_id
      where cs.collection_cycle_id=v_cycle.id
        and (position(s.token in coalesce(m.body,''))>0
          or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
    )
  );
  update public.rr_collection_update_request_v9630 r set status='FULFILLED',fulfilled_at=clock_timestamp()
   where r.collection_cycle_id=v_cycle.id and r.status='OPEN' and r.request_kind='MORE_SAMPLES'
    and not exists(select 1 from public.rr_collection_update_category_v9630 c where c.update_request_id=r.id
      and not (lower(trim(c.category))=any(chosen_cats)));
  return v_result||jsonb_build_object('chat_message_id',v_message,'url',v_url,'collection_update_no',v_update);
end
$function$;


revoke all on function public.rr_sales_collection_send_test71(uuid,uuid,text[],uuid,text,uuid) from public,anon;
grant execute on function public.rr_sales_collection_send_test71(uuid,uuid,text[],uuid,text,uuid) to authenticated,service_role;
create or replace function public.rr_direct_collection_send_v9684(
 p_chat_id uuid,p_customer_id uuid,p_lots text[],p_requirement_id uuid default null,p_origin text default null
) returns jsonb language sql security definer set search_path='' as $$
 select public.rr_sales_collection_send_test71(p_chat_id,p_customer_id,p_lots,p_requirement_id,p_origin,null)
$$;
revoke all on function public.rr_direct_collection_send_v9684(uuid,uuid,text[],uuid,text) from public,anon;
grant execute on function public.rr_direct_collection_send_v9684(uuid,uuid,text[],uuid,text) to authenticated,service_role;
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

 update public.rr_collection_activity_v9633 a set payload=coalesce(a.payload,'{}')||jsonb_build_object(
  'previous_lines',v_result->'previous_lines','requirement_lines',v_result->'lines')
 where a.collection_cycle_id=v_cycle.id and a.reference_id=(v_result->>'requirement_id')::uuid
  and a.update_no=(v_result->>'update_no')::integer;
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
end $function$;
create or replace function public.rr_collection_categories_v9630()
returns table(category text) language plpgsql stable security definer set search_path='' as $$
declare rowsj jsonb:='[]'; chunk jsonb; offn integer:=0;
begin
 loop
  select coalesce(jsonb_agg(to_jsonb(w)),'[]') into chunk
   from public.rr_web_window_cards_v9329(null,null,null,'TEST',150,offn) w;
  rowsj:=rowsj||chunk; exit when jsonb_array_length(chunk)<150; offn:=offn+150;
 end loop;
 return query select x.name from (
 select distinct trim(e.value->>'category') name from jsonb_array_elements(rowsj) e
  where nullif(trim(e.value->>'category'),'') is not null
 union select trim(a.category_name) from public.rr_art_categories a where nullif(trim(a.category_name),'') is not null
 ) x order by 1;
end $$;
revoke all on function public.rr_collection_categories_v9630() from public;
grant execute on function public.rr_collection_categories_v9630() to anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rr_collection_more_samples_request_v9630(p_token text, p_categories text[], p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cy public.rr_collection_cycle_v9586%rowtype; v_no integer; v_id uuid; c text; cyid uuid;
begin
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid for update;
  if cy.status in ('CLOSED','CLOSED_NO_RESPONSE','CANCELLED','CI_GENERATED','PI_GENERATED') then raise exception 'Collection is already closed.'; end if;
  if coalesce(array_length(p_categories,1),0)=0 then raise exception 'Select at least one category.'; end if;

  if cy.data_mode='TEST' and exists(select 1 from unnest(p_categories) picked where not exists(
    select 1 from public.rr_collection_categories_v9630() available
    where lower(trim(available.category))=lower(trim(picked))))
   then raise exception 'Choose categories from the available collection list.'; end if;
  v_no:=public.rr_collection_next_update_v9633(cy.id);
  insert into public.rr_collection_update_request_v9630(collection_cycle_id,update_no,request_kind,requested_by,note)
  values(cy.id,v_no,'MORE_SAMPLES','CUSTOMER',nullif(trim(coalesce(p_note,'')),'')) returning id into v_id;
  foreach c in array p_categories loop
    c:=trim(coalesce(c,''));
    if c<>'' then insert into public.rr_collection_update_category_v9630(update_request_id,category) values(v_id,c) on conflict do nothing; end if;
  end loop;
  if not exists(select 1 from public.rr_collection_update_category_v9630 where update_request_id=v_id) then raise exception 'Select at least one valid category.'; end if;
  insert into public.rr_collection_activity_v9633(collection_cycle_id,update_no,activity_kind,actor_kind,reference_id,payload)
  values(cy.id,v_no,'MORE_SAMPLES','CUSTOMER',v_id,jsonb_build_object('categories',p_categories,'note',nullif(trim(coalesce(p_note,'')),'')));

  -- Refresh the existing workflow card; no duplicate chat message or notification seed.
  update public.rr_customer_chat_messages_v9433 m set created_at=clock_timestamp(),
   payload=coalesce(m.payload,'{}')||jsonb_build_object('sample_request_update_no',v_no,'requested_categories',p_categories)
   where m.id=(select latest.id from public.rr_customer_chat_messages_v9433 latest
    where latest.chat_id=cy.chat_id and latest.archived_at is null and latest.channel='GROUP'
     and latest.payload->>'direct_collection_cycle_id'=cy.id::text
    order by (latest.message_type='REQUIREMENT') desc,latest.created_at desc,latest.id desc limit 1)
    and cy.data_mode='TEST';
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,'collection_status',cy.status,'update_request_id',v_id,'update_no',v_no,'request_kind','MORE_SAMPLES');
end$function$;
CREATE OR REPLACE FUNCTION public.rr_collection_cycle_share_view_v9686(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cycle public.rr_collection_cycle_v9586%rowtype; v_data jsonb;
 v_rows jsonb:='[]'::jsonb; v_update integer:=0; x record; summary jsonb; newest uuid;
begin
 select c.* into v_cycle from public.rr_market_share_v9420 s
 join public.rr_collection_send_v9586 cs on cs.share_id=s.id
 join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
 where (s.token=p_token or s.short_code=upper(p_token)) and s.status='ACTIVE'
 order by case when s.token=p_token then 0 else 1 end limit 1;
 if v_cycle.id is null then return public.rr_market_share_view_v9420(p_token); end if;
 for x in select s.token,cs.send_seq from public.rr_collection_send_v9586 cs
  join public.rr_market_share_v9420 s on s.id=cs.share_id
  where cs.collection_cycle_id=v_cycle.id and s.status='ACTIVE' order by cs.send_seq
 loop
  v_data:=public.rr_market_share_view_v9420(x.token);
  v_rows:=v_rows||coalesce(v_data->'rows','[]'::jsonb);
  v_update:=greatest(v_update,x.send_seq-1);
 end loop;

 summary:=public.rr_collection_customer_requirement_summary_v9778(p_token);
 select cs.share_id into newest from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=v_cycle.id
 order by cs.send_seq desc limit 1;
 select coalesce(jsonb_agg(q.val||jsonb_build_object('requested_qty',coalesce(r.qty,0))
  order by case when exists(select 1 from public.rr_market_share_lots_v9420 l where l.share_id=newest and l.lot_no=q.val->>'lot_no') then 0
   when coalesce(r.qty,0)>0 then 1 else 2 end,q.ord),'[]'::jsonb) into v_rows from (
  select distinct on (e.value->>'lot_no') e.value val,e.ordinality ord
  from jsonb_array_elements(v_rows) with ordinality e(value,ordinality)
  order by e.value->>'lot_no',e.ordinality desc
 ) q left join lateral (
  select (l->>'requested_qty')::integer qty from jsonb_array_elements(summary->'lines') l
   where l->>'lot_no'=q.val->>'lot_no' limit 1
 ) r on true;
 return coalesce(v_data,'{}'::jsonb)||jsonb_build_object('rows',v_rows,
  'collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
  'collection_display_no',v_cycle.display_no,'collection_update_no',v_update);
end $function$;
