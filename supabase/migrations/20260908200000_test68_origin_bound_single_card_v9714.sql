-- Bind every Market Window share to its originating chat lane and keep one
-- active Requirement card per direct Collection cycle. Existing business rows
-- remain intact; only duplicate/misrouted chat cards are archived.

alter table public.rr_market_share_v9420
  add column if not exists origin_chat_id uuid references public.rr_customer_chat_v9433(id),
  add column if not exists origin_relation_kind text,
  add column if not exists origin_collection_cycle_id uuid,
  add column if not exists origin_owner_customer_id uuid,
  add column if not exists origin_partner_customer_id uuid;

alter table public.rr_market_share_v9420
  drop constraint if exists rr_market_share_origin_relation_v9714_ck;
alter table public.rr_market_share_v9420
  add constraint rr_market_share_origin_relation_v9714_ck check(
    origin_relation_kind is null or origin_relation_kind in
      ('DIRECT_CUSTOMER','DISTRIBUTOR_REDZED','DISTRIBUTOR_CUSTOMER')
  );

create index if not exists rr_market_share_origin_chat_v9714_idx
  on public.rr_market_share_v9420(origin_chat_id,origin_relation_kind)
  where origin_chat_id is not null;

-- Existing direct shares already have a canonical Collection cycle/chat.
update public.rr_market_share_v9420 s set
  origin_chat_id=c.chat_id,
  origin_relation_kind='DIRECT_CUSTOMER',
  origin_collection_cycle_id=c.id,
  origin_owner_customer_id=c.customer_id,
  origin_partner_customer_id=null
from public.rr_collection_send_v9586 cs
join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
where cs.share_id=s.id
  and (s.origin_chat_id is null or s.origin_relation_kind is null);

-- Existing distributor-to-own-customer shares are bound to that private lane.
update public.rr_market_share_v9420 s set
  origin_chat_id=rc.chat_id,
  origin_relation_kind='DISTRIBUTOR_CUSTOMER',
  origin_collection_cycle_id=coalesce(pc.root_collection_id,pc.id),
  origin_owner_customer_id=pc.owner_customer_id,
  origin_partner_customer_id=pc.partner_customer_id
from public.rr_market_partner_collection_v67 pc
join public.rr_market_partner_relation_chat_v67 rc
  on rc.owner_customer_id=pc.owner_customer_id
 and rc.partner_customer_id=pc.partner_customer_id
 and rc.relation_kind='DISTRIBUTOR_CUSTOMER'
 and rc.status='ACTIVE'
where pc.share_id=s.id;

create or replace function public.rr_collection_create_first_v9587(
  p_customer_id uuid,p_lots text[],p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path='public' as $$
declare dm text:=upper(coalesce(nullif(trim(p_data_mode),''),'TEST'));ch uuid;cn int;cy uuid;sj jsonb;sid uuid;disp text;actor uuid:=auth.uid();
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if p_customer_id is null then raise exception 'Customer is required.';end if;
 if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.';end if;
 select id into ch from public.rr_customer_chat_v9433
 where customer_id=p_customer_id and data_mode=dm and status='OPEN'
   and relation_kind='DIRECT_CUSTOMER' limit 1;
 if ch is null then raise exception 'Permanent customer chat is required before Collection creation.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text||'|'||dm,9587));
 select coalesce(max(collection_no),0)+1 into cn from public.rr_collection_cycle_v9586
 where customer_id=p_customer_id and data_mode=dm;
 disp:='RZ COLLECTION '||lpad(cn::text,2,'0');
 insert into public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status,created_by)
 values(p_customer_id,ch,dm,cn,disp,'DRAFT',actor) returning id into cy;
 sj:=public.rr_market_create_share_v9420(p_lots,p_customer_id,
   (select customer_name from public.rr_customer_chat_v9433 where id=ch),dm);
 sid:=(sj->>'share_id')::uuid;
 update public.rr_market_share_v9420 set origin_chat_id=ch,
   origin_relation_kind='DIRECT_CUSTOMER',origin_collection_cycle_id=cy,
   origin_owner_customer_id=p_customer_id,origin_partner_customer_id=null
 where id=sid;
 insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)
 values(cy,sid,1,'FIRST',actor);
 update public.rr_collection_cycle_v9586 set status='SENT_NOT_OPENED' where id=cy;
 return sj||jsonb_build_object('collection_cycle_id',cy,'collection_no',cn,
   'collection_display_no',disp,'send_seq',1,'send_kind','FIRST','chat_id',ch,
   'relation_kind','DIRECT_CUSTOMER');
end $$;

create or replace function public.rr_collection_add_update_v9587(
  p_collection_cycle_id uuid,p_lots text[]
) returns jsonb language plpgsql security definer set search_path='public' as $$
declare cy public.rr_collection_cycle_v9586%rowtype;seq int;sj jsonb;sid uuid;dupes text[];actor uuid:=auth.uid();
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.';end if;
 select * into cy from public.rr_collection_cycle_v9586 where id=p_collection_cycle_id for update;
 if cy.id is null then raise exception 'Collection not found.';end if;
 if cy.status in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED') then raise exception 'Closed/Cancelled Collection cannot be updated.';end if;
 if not exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id
   and ch.customer_id=cy.customer_id and ch.relation_kind='DIRECT_CUSTOMER' and ch.status='OPEN')
 then raise exception 'Collection is not bound to the direct Customer chat.';end if;
 select array_agg(distinct trim(x)) into dupes from unnest(p_lots)x
 where trim(x)<>'' and exists(select 1 from public.rr_collection_send_v9586 s
   join public.rr_market_share_lots_v9420 l on l.share_id=s.share_id
   where s.collection_cycle_id=cy.id and l.lot_no=trim(x));
 if coalesce(array_length(dupes,1),0)>0 then raise exception 'Lot(s) already sent in this Collection: %',array_to_string(dupes,', ');end if;
 select coalesce(max(send_seq),0)+1 into seq from public.rr_collection_send_v9586 where collection_cycle_id=cy.id;
 sj:=public.rr_market_create_share_v9420(p_lots,cy.customer_id,
   (select customer_name from public.rr_customer_chat_v9433 where id=cy.chat_id),cy.data_mode);
 sid:=(sj->>'share_id')::uuid;
 update public.rr_market_share_v9420 set origin_chat_id=cy.chat_id,
   origin_relation_kind='DIRECT_CUSTOMER',origin_collection_cycle_id=cy.id,
   origin_owner_customer_id=cy.customer_id,origin_partner_customer_id=null
 where id=sid;
 insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)
 values(cy.id,sid,seq,'UPDATE',actor);
 return sj||jsonb_build_object('collection_cycle_id',cy.id,'collection_no',cy.collection_no,
   'collection_display_no',cy.display_no,'send_seq',seq,'send_kind','UPDATE',
   'chat_id',cy.chat_id,'relation_kind','DIRECT_CUSTOMER');
end $$;

-- Legacy direct submit now posts only into the share's fixed Customer lane.
create or replace function public.rr_market_submit_requirement_v9508_legacy_v67(
 p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb,p_requirement_id uuid default null
) returns jsonb language plpgsql security definer set search_path='public' as $$
declare s public.rr_market_share_v9420%rowtype;rid uuid;cj jsonb;cid uuid;ln jsonb;av int;req int;acc int;chat uuid;
 is_append boolean:=p_requirement_id is not null;total_qty int;lot_count int;
begin
 select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE'
 order by case when token=p_token then 0 else 1 end limit 1;
 if not found then raise exception 'Share link unavailable.';end if;
 cj:=public.rr_market_register_customer_v9423(p_customer_name,p_mobile);cid:=(cj->>'customer_id')::uuid;
 if s.customer_id is not null and s.customer_id<>cid then raise exception 'Collection belongs to another customer.';end if;
 if is_append then
   select id into rid from public.rr_market_requirements_v9420 where id=p_requirement_id and customer_id=cid limit 1;
   if rid is null then raise exception 'REQUIREMENT NOT AVAILABLE FOR THIS CUSTOMER';end if;
 else
   insert into public.rr_market_requirements_v9420(share_id,customer_id,customer_is_new,customer_name,mobile,message)
   values(s.id,cid,coalesce((cj->>'is_new')::boolean,false),cj->>'customer_name',cj->>'mobile',p_message) returning id into rid;
 end if;
 for ln in select * from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop
   if not exists(select 1 from public.rr_market_share_lots_v9420 where share_id=s.id and lot_no=ln->>'lot_no')then continue;end if;
   if is_append and exists(select 1 from public.rr_market_requirement_lines_v9420 x where x.requirement_id=rid and x.lot_no=ln->>'lot_no')then continue;end if;
   select coalesce(sum(available_qty),0)::int into av from public.rr_fg_stock_balance_v787 where data_mode=s.data_mode and lot_no=ln->>'lot_no';
   req:=greatest(0,coalesce((ln->>'qty')::int,0));acc:=least(req,av);
   if acc>0 then insert into public.rr_market_requirement_lines_v9420(requirement_id,lot_no,requested_qty,accepted_qty,max_available_at_submit)
     values(rid,ln->>'lot_no',req,acc,av);end if;
 end loop;
 select count(*),coalesce(sum(accepted_qty),0) into lot_count,total_qty from public.rr_market_requirement_lines_v9420 where requirement_id=rid;
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
 return jsonb_build_object('requirement_id',rid,'customer',cj,'is_append',is_append,'lot_count',lot_count,'total_qty',total_qty,
   'lines',(select coalesce(jsonb_agg(jsonb_build_object('lot_no',lot_no,'requested_qty',requested_qty,'accepted_qty',accepted_qty,'max_available',max_available_at_submit)),'[]'::jsonb)
   from public.rr_market_requirement_lines_v9420 where requirement_id=rid));
end $$;

-- If the UI omits the Requirement id, continue the latest active Requirement
-- belonging to this exact Collection cycle instead of creating a new root.
create or replace function public.rr_direct_collection_submit_requirement_v9684(
 p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb,p_requirement_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;v_req public.rr_market_requirements_v9420%rowtype;v_cycle public.rr_collection_cycle_v9586%rowtype;
 v_share public.rr_market_share_v9420%rowtype;v_effective uuid:=p_requirement_id;v_root uuid;v_message uuid;v_body text;
begin
 select * into v_share from public.rr_market_share_v9420 s
 where(s.token=p_token or s.short_code=upper(p_token))and s.status='ACTIVE'
 order by case when s.token=p_token then 0 else 1 end limit 1;
 if v_share.id is null then raise exception 'Share link unavailable.';end if;
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
end $$;

-- Repair current direct cycles conservatively: keep the newest active root,
-- mark older active roots superseded, and archive only their duplicate cards.
with ranked as(
 select r.id,r.collection_cycle_id,row_number()over(partition by r.collection_cycle_id order by r.submitted_at desc,r.id desc)rn
 from public.rr_market_requirements_v9420 r
 where r.collection_cycle_id is not null and coalesce(r.lifecycle_stage,r.status,'') not in('SUPERSEDED','CI_FINAL','CANCELLED')
   and r.pi_generated_at is null
), losers as(select id,collection_cycle_id from ranked where rn>1)
update public.rr_market_requirements_v9420 r set lifecycle_stage='SUPERSEDED'
from losers l where r.id=l.id;

update public.rr_customer_chat_messages_v9433 m set archived_at=clock_timestamp(),
 archive_reason='CROSS_LANE_REQUIREMENT_CARD_V9714',
 archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('repair','origin-bound-v9714')
from public.rr_market_requirements_v9420 r
join public.rr_collection_cycle_v9586 c on c.id=r.collection_cycle_id
where m.message_type='REQUIREMENT' and m.archived_at is null
  and m.payload->>'requirement_id'=r.id::text and m.chat_id<>c.chat_id;

update public.rr_customer_chat_messages_v9433 m set archived_at=clock_timestamp(),
 archive_reason='DUPLICATE_REQUIREMENT_CARD_V9714',
 archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('repair','single-card-v9714')
from public.rr_market_requirements_v9420 r
where m.message_type='REQUIREMENT' and m.archived_at is null
  and m.payload->>'requirement_id'=r.id::text and r.lifecycle_stage='SUPERSEDED'
  and r.collection_cycle_id is not null;

revoke all on function public.rr_market_submit_requirement_v9508_legacy_v67(text,text,text,text,jsonb,uuid) from public;
grant execute on function public.rr_market_submit_requirement_v9508_legacy_v67(text,text,text,text,jsonb,uuid) to anon,authenticated,service_role;
revoke all on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) from public;
grant execute on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) to anon,authenticated,service_role;

comment on function public.rr_direct_collection_submit_requirement_v9684(text,text,text,text,jsonb,uuid) is
  'Origin-bound direct Customer Requirement submit. Reuses one active Requirement root/card per Collection cycle.';
