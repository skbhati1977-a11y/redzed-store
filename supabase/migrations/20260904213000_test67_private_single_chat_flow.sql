-- TEST67 private single-chat journey: distributor customer -> distributor -> REDZED.
-- TEST-only. MAIN/REAL flows, rows and numbering are untouched.

alter table public.rr_market_partner_collection_line_v67
  add column if not exists size_text text;

alter table public.rr_market_partner_order_v67
  add column if not exists customer_closed_at timestamptz,
  add column if not exists redzed_pushed_at timestamptz,
  add column if not exists customer_pi_visible boolean not null default false,
  add column if not exists customer_pi_pushed_at timestamptz,
  add column if not exists customer_pi_status text not null default 'WAITING',
  add column if not exists customer_pi_note text,
  add column if not exists customer_pi_responded_at timestamptz,
  add column if not exists distributor_confirmed_at timestamptz,
  add column if not exists customer_ci_visible boolean not null default false,
  add column if not exists customer_ci_pushed_at timestamptz;

alter table public.rr_market_partner_order_line_v67
  add column if not exists size_text text,
  add column if not exists category text,
  add column if not exists customer_pi_decision text not null default 'WAITING',
  add column if not exists customer_pi_qty integer,
  add column if not exists customer_pi_note text;

alter table public.rr_market_partner_order_v67
  drop constraint if exists rr_market_partner_order_v67_status_check;
alter table public.rr_market_partner_order_v67
  add constraint rr_market_partner_order_v67_status_check check(status in(
    'DRAFT','SUPERSEDED','READY','BATCHED','PI_PROPOSED','CONFIRMED',
    'PARTIAL_CONFIRMED','CANCELLED','CI_FINAL','CLOSED'
  ));

do $$ begin
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_order_v67_customer_pi_status_check')then
    alter table public.rr_market_partner_order_v67
      add constraint rr_market_partner_order_v67_customer_pi_status_check
      check(customer_pi_status in('WAITING','CONFIRMED','CHANGE_REQUESTED','PARTIAL','CANCELLED'));
  end if;
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_order_line_v67_customer_pi_decision_check')then
    alter table public.rr_market_partner_order_line_v67
      add constraint rr_market_partner_order_line_v67_customer_pi_decision_check
      check(customer_pi_decision in('WAITING','CONFIRM','CHANGE','CANCEL'));
  end if;
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_order_line_v67_customer_pi_qty_check')then
    alter table public.rr_market_partner_order_line_v67
      add constraint rr_market_partner_order_line_v67_customer_pi_qty_check
      check(customer_pi_qty is null or customer_pi_qty>=0);
  end if;
end $$;

create table if not exists public.rr_market_partner_document_sequence_v67(
  document_kind text primary key check(document_kind in('CI')),
  current_no bigint not null default 0 check(current_no>=0),
  data_mode text not null default 'TEST' check(data_mode='TEST'),
  updated_at timestamptz not null default now()
);
alter table public.rr_market_partner_document_sequence_v67 enable row level security;
revoke all on public.rr_market_partner_document_sequence_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_document_sequence_v67 to service_role;
insert into public.rr_market_partner_document_sequence_v67(document_kind,current_no)
values('CI',0)on conflict(document_kind)do nothing;

update public.rr_market_partner_collection_line_v67 l
set size_text=(select r.size_text
 from public.rr_web_lot_fields_resolve_v9624(l.lot_no,'TEST')r limit 1)
where l.size_text is null;

update public.rr_market_partner_order_line_v67 l
set(size_text,category)=(select r.size_text,coalesce(nullif(l.article_name,''),r.category)
 from public.rr_web_lot_fields_resolve_v9624(l.lot_no,'TEST')r limit 1)
where l.size_text is null or l.category is null;

create or replace function public.rr_market_partner_collection_line_meta_v67()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_size text;v_category text;
begin
 if new.size_text is null or new.category is null then
  select size_text,category into v_size,v_category
  from public.rr_web_lot_fields_resolve_v9624(new.lot_no,'TEST');
  new.size_text:=coalesce(new.size_text,v_size);
  new.category:=coalesce(new.category,v_category);
 end if;
 return new;
end $$;
drop trigger if exists rr_market_partner_collection_line_meta_v67 on public.rr_market_partner_collection_line_v67;
create trigger rr_market_partner_collection_line_meta_v67 before insert or update of lot_no,size_text,category
on public.rr_market_partner_collection_line_v67 for each row execute function public.rr_market_partner_collection_line_meta_v67();
revoke all on function public.rr_market_partner_collection_line_meta_v67()from public,anon,authenticated;

create or replace function public.rr_market_partner_next_ci_v67()
returns text language plpgsql security definer set search_path=public as $$
declare v_no bigint;
begin
 perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_CI'));
 update public.rr_market_partner_document_sequence_v67 set current_no=current_no+1,updated_at=now()
 where document_kind='CI' returning current_no into v_no;
 return 'CI67-'||lpad(v_no::text,6,'0');
end $$;
revoke all on function public.rr_market_partner_next_ci_v67()from public,anon,authenticated;

create or replace function public.rr_market_partner_collection_priced_create_v67(
 p_session_token text,p_device_id text,p_partner_customer_id uuid,p_lines jsonb
)returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_ctx jsonb;v_owner uuid;v_creator uuid;v_share uuid;v_collection uuid:=gen_random_uuid();
 v_root uuid;v_token text;v_code text;v_name text;v_mobile text;v_tries int:=0;
 v_line jsonb;v_card record;v_lot text;v_margin numeric;v_discount numeric;v_sale numeric;v_final numeric;
 v_collection_no bigint;v_update_no integer;v_display text;v_header text;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not(v_ctx->>'send_collection_enabled')::boolean then raise exception 'Collection sending is disabled.';end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select private_name,private_mobile into v_name,v_mobile from public.rr_market_partner_customer_v67
 where id=p_partner_customer_id and owner_customer_id=v_owner and status='ACTIVE';
 if v_name is null then raise exception 'Private customer not found.';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Select at least one lot.';end if;
 v_margin:=greatest(0,coalesce((p_lines->0->>'margin_amount')::numeric,0));
 v_discount:=greatest(0,coalesce((p_lines->0->>'discount_amount')::numeric,0));
 select s.created_by into v_creator
 from public.rr_customer_session_v9590 cs join public.rr_market_share_v9420 s on s.id=cs.share_id
 where cs.session_token_hash=encode(extensions.digest(trim(p_session_token),'sha256'),'hex')
 and cs.customer_id=v_owner and cs.revoked_at is null and cs.expires_at>now()limit 1;
 if v_creator is null then raise exception 'Verified share owner is unavailable.';end if;

 perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_COLLECTION'));
 select pc.root_collection_id,pc.collection_no,max(pc.collection_update_no)+1
 into v_root,v_collection_no,v_update_no
 from public.rr_market_partner_collection_v67 pc
 where pc.owner_customer_id=v_owner and pc.partner_customer_id=p_partner_customer_id and pc.status<>'CANCELLED'
 and not exists(
  select 1 from public.rr_market_partner_collection_v67 cx
  join public.rr_market_partner_order_v67 ox on ox.collection_id=cx.id
  where cx.root_collection_id=pc.root_collection_id
  and ox.status in('READY','BATCHED','PI_PROPOSED','CONFIRMED','PARTIAL_CONFIRMED','CANCELLED','CI_FINAL','CLOSED')
 )group by pc.root_collection_id,pc.collection_no order by max(pc.created_at)desc limit 1;
 if v_root is null then
  update public.rr_market_partner_global_sequence_v67 set current_no=current_no+1,updated_at=now()
  where sequence_kind='COLLECTION'returning current_no into v_collection_no;
  v_root:=v_collection;v_update_no:=0;
 end if;
 v_display:='COLLECTION '||v_collection_no::text||case when v_update_no>0 then ' · UPDATE '||v_update_no::text else '' end;
 loop
  v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,10));
  begin
   insert into public.rr_market_share_v9420(customer_id,customer_name,created_by,data_mode,status,short_code)
   values(null,v_name,v_creator,'TEST','ACTIVE',v_code)returning id,token into v_share,v_token;exit;
  exception when unique_violation then v_tries:=v_tries+1;if v_tries>8 then raise;end if;end;
 end loop;
 insert into public.rr_market_partner_collection_v67(
  id,owner_customer_id,partner_customer_id,share_id,root_collection_id,collection_no,collection_update_no,collection_display_no
 )values(v_collection,v_owner,p_partner_customer_id,v_share,v_root,v_collection_no,v_update_no,v_display);
 for v_line in select value from jsonb_array_elements(p_lines)loop
  v_lot:=nullif(trim(v_line->>'lot_no'),'');
  select * into v_card from public.rr_web_window_cards_v9329(v_lot,null,null,'TEST',10,0)where lot_no=v_lot limit 1;
  if v_card.lot_no is null then raise exception 'TEST lot % is unavailable.',v_lot;end if;
  v_sale:=coalesce(v_card.sale_rate,0)+v_margin;v_final:=greatest(0,v_sale-v_discount);
  insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)
  values(v_share,v_lot,(select count(*)+1 from public.rr_market_share_lots_v9420 where share_id=v_share))on conflict do nothing;
  insert into public.rr_market_partner_collection_line_v67(
   collection_id,lot_no,category,size_text,cloth_name,primary_image_url,media,stock_status,
   base_rate,margin_amount,distributor_sale_rate,discount_amount,final_customer_rate
  )values(v_collection,v_lot,coalesce(v_card.category,''),v_card.size_text,v_card.cloth_name,v_card.primary_image_url,
   coalesce(v_card.media,'[]'::jsonb),case when coalesce(v_card.available_qty,0)<=0 then 'OUT OF STOCK'
   when upper(coalesce(v_card.stock_status,''))='LOW_STOCK'then'LOW STOCK'else'STOCK-IN'end,
   coalesce(v_card.sale_rate,0),v_margin,v_sale,v_discount,v_final);
 end loop;
 update public.rr_market_partner_customer_v67 set default_margin_amount=v_margin,
 default_discount_amount=v_discount,updated_at=now()where id=p_partner_customer_id;
 v_header:=public.rr_market_partner_header_v67(v_owner,p_partner_customer_id);
 insert into public.rr_market_partner_event_v67(owner_customer_id,event_type,actor_kind,payload)
 values(v_owner,'COLLECTION_SENT_TO_CUSTOMER','DISTRIBUTOR',jsonb_build_object(
  'collection_id',v_collection,'collection_display_no',v_display,'customer_ref',
  (select customer_ref from public.rr_market_partner_customer_v67 where id=p_partner_customer_id),'channel','PRIVATE_CUSTOMER_CHAT'));
 return jsonb_build_object('collection_id',v_collection,'share_id',v_share,'token',v_token,
  'short_code',v_code,'lot_count',(select count(*)from public.rr_market_partner_collection_line_v67 where collection_id=v_collection),
  'collection_no',v_collection_no,'collection_update_no',v_update_no,'collection_display_no',v_display,
  'header_title',v_header,'customer_mobile',v_mobile,'redzed_status','NOT_SENT');
end $$;

create or replace function public.rr_market_partner_submit_requirement_v67(
 p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb
)returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_map public.rr_market_partner_collection_v67%rowtype;v_result jsonb;v_req uuid;v_owner_seq bigint;v_prefix text;
 v_ref text;v_order uuid:=gen_random_uuid();v_root_order uuid;v_root uuid;v_line record;
 v_price public.rr_market_partner_collection_line_v67%rowtype;v_requirement_no bigint;v_update_no integer;
begin
 select pc.* into v_map from public.rr_market_partner_collection_v67 pc
 join public.rr_market_share_v9420 s on s.id=pc.share_id
 where(s.token=p_token or s.short_code=upper(p_token))and s.data_mode='TEST'and s.status='ACTIVE'for update of pc;
 if v_map.id is null then return public.rr_market_submit_requirement_v9508(p_token,p_customer_name,p_mobile,p_message,p_lines,null);end if;
 v_root:=coalesce(v_map.root_collection_id,v_map.id);
 if exists(select 1 from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=v_root and o.status not in('DRAFT','SUPERSEDED'))then
  raise exception 'Requirement is closed. Distributor will continue with REDZED.';
 end if;
 v_result:=public.rr_market_submit_requirement_v9508(p_token,p_customer_name,p_mobile,p_message,p_lines,null);
 v_req:=(v_result->>'requirement_id')::uuid;
 perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_REQUIREMENT'));
 select o.requirement_no,coalesce(o.root_order_id,o.id)into v_requirement_no,v_root_order
 from public.rr_market_partner_order_v67 o join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
 where pc.root_collection_id=v_root and o.requirement_no is not null
 order by o.requirement_update_no,o.created_at,o.id limit 1;
 if v_requirement_no is null then
  update public.rr_market_partner_global_sequence_v67 set current_no=current_no+1,updated_at=now()
  where sequence_kind='REQUIREMENT'returning current_no into v_requirement_no;
  v_root_order:=v_order;v_update_no:=0;
 else
  select coalesce(max(o.requirement_update_no),-1)+1 into v_update_no
  from public.rr_market_partner_order_v67 o join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=v_root and o.requirement_no=v_requirement_no;
 end if;
 v_ref:='REQUIREMENT '||v_requirement_no::text||case when v_update_no>0 then ' · UPDATE '||v_update_no::text else '' end;
 select prefix,current_no+1 into v_prefix,v_owner_seq from public.rr_market_owner_sequence_v67
 where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST'for update;
 if v_prefix is null then raise exception 'Distributor prefix is not configured.';end if;
 update public.rr_market_owner_sequence_v67 set current_no=v_owner_seq,updated_at=now()
 where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST';
 update public.rr_market_partner_order_v67 o set status='SUPERSEDED',updated_at=now()
 where o.status='DRAFT'and exists(select 1 from public.rr_market_partner_collection_v67 pc
  where pc.id=o.collection_id and pc.root_collection_id=v_root);
 insert into public.rr_market_partner_order_v67(
  id,owner_customer_id,partner_customer_id,sequence_no,order_ref,status,linked_requirement_id,
  collection_id,root_order_id,requirement_no,requirement_update_no,requirement_display_no
 )values(v_order,v_map.owner_customer_id,v_map.partner_customer_id,v_owner_seq,v_ref,'DRAFT',v_req,
  v_map.id,v_root_order,v_requirement_no,v_update_no,v_ref);
 for v_line in select l.* from public.rr_market_requirement_lines_v9420 l where l.requirement_id=v_req loop
  select * into v_price from public.rr_market_partner_collection_line_v67 where collection_id=v_map.id and lot_no=v_line.lot_no;
  insert into public.rr_market_partner_order_line_v67(
   order_id,lot_no,article_name,category,size_text,image_url,requested_qty,base_rate,rate_enhancement,
   customer_discount,final_customer_rate
  )values(v_order,v_line.lot_no,coalesce(v_price.category,v_line.lot_no),v_price.category,v_price.size_text,
   v_price.primary_image_url,v_line.accepted_qty,v_price.base_rate,v_price.margin_amount,
   v_price.discount_amount,v_price.final_customer_rate);
 end loop;
 update public.rr_market_partner_collection_v67 set requirement_id=v_req,order_id=v_order,status='REQUIREMENT_RECEIVED',
 requirement_no=v_requirement_no,requirement_update_no=v_update_no,requirement_display_no=v_ref,updated_at=now()
 where id=v_map.id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,note,actor_kind,payload)
 values(v_map.owner_customer_id,v_order,'CUSTOMER_REQUIREMENT_DRAFT',nullif(trim(p_message),''),'CUSTOMER',
 jsonb_build_object('requirement_display_no',v_ref,'collection_display_no',v_map.collection_display_no,
 'customer_ref',(select customer_ref from public.rr_market_partner_customer_v67 where id=v_map.partner_customer_id)));
 return v_result||jsonb_build_object('order_id',v_order,'order_ref',v_ref,'requirement_no',v_requirement_no,
 'requirement_update_no',v_update_no,'requirement_display_no',v_ref,'collection_display_no',v_map.collection_display_no,
 'status','DRAFT','can_close',true,'sent_to','DISTRIBUTOR');
end $$;

create or replace function public.rr_market_partner_customer_requirement_close_v67(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_map public.rr_market_partner_collection_v67%rowtype;v_root uuid;v_order public.rr_market_partner_order_v67%rowtype;
begin
 select pc.* into v_map from public.rr_market_partner_collection_v67 pc
 join public.rr_market_share_v9420 s on s.id=pc.share_id
 where(s.token=p_token or s.short_code=upper(p_token))and s.data_mode='TEST'and s.status='ACTIVE'for update of pc;
 if v_map.id is null then raise exception 'Distributor collection is unavailable.';end if;
 v_root:=coalesce(v_map.root_collection_id,v_map.id);
 perform pg_advisory_xact_lock(hashtext('RR_TEST67_REQUIREMENT_CLOSE'));
 select o.* into v_order from public.rr_market_partner_order_v67 o
 join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
 where pc.root_collection_id=v_root and o.status='DRAFT'
 order by o.requirement_update_no desc,o.created_at desc limit 1 for update of o;
 if v_order.id is null then
  select o.* into v_order from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=v_root and o.status in('READY','BATCHED','PI_PROPOSED','CONFIRMED','PARTIAL_CONFIRMED','CI_FINAL')
  order by o.requirement_update_no desc,o.created_at desc limit 1;
  if v_order.id is not null then return jsonb_build_object('ok',true,'already_closed',true,
   'order_id',v_order.id,'requirement_display_no',v_order.requirement_display_no,'status',v_order.status);end if;
  raise exception 'Send requirement before closing it.';
 end if;
 update public.rr_market_partner_order_v67 set status='READY',customer_closed_at=now(),updated_at=now()
 where id=v_order.id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)
 values(v_order.owner_customer_id,v_order.id,'CUSTOMER_REQUIREMENT_CLOSED','CUSTOMER',jsonb_build_object(
  'requirement_display_no',v_order.requirement_display_no,'next_action','DISTRIBUTOR_SEND_TO_REDZED'));
 return jsonb_build_object('ok',true,'order_id',v_order.id,'requirement_display_no',v_order.requirement_display_no,
  'status','READY','sent_to','DISTRIBUTOR');
end $$;

create or replace function public.rr_market_partner_batch_submit_v67(
 p_session_token text,p_device_id text,p_order_ids uuid[]
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_batch uuid;v_batch_ref text;v_count int;v_refs jsonb;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not(v_ctx->>'send_collection_enabled')::boolean then raise exception 'Requirement push is disabled.';end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select count(*)into v_count from public.rr_market_partner_order_v67
 where id=any(p_order_ids)and owner_customer_id=v_owner and status='READY'and customer_closed_at is not null;
 if coalesce(array_length(p_order_ids,1),0)=0 or v_count<>array_length(p_order_ids,1)then
  raise exception 'Only customer-closed requirements can be sent to REDZED.';
 end if;
 select jsonb_agg(requirement_display_no order by requirement_no,requirement_update_no)into v_refs
 from public.rr_market_partner_order_v67 where id=any(p_order_ids);
 v_batch_ref:='B-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.rr_market_partner_batch_v67(owner_customer_id,batch_ref)values(v_owner,v_batch_ref)returning id into v_batch;
 insert into public.rr_market_partner_batch_member_v67(batch_id,order_id)select v_batch,unnest(p_order_ids);
 update public.rr_market_partner_order_v67 set status='BATCHED',redzed_pushed_at=now(),updated_at=now()where id=any(p_order_ids);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,payload)
 values(v_owner,v_batch,'CLOSED_REQUIREMENTS_PUSHED_TO_REDZED','DISTRIBUTOR',jsonb_build_object(
  'order_count',v_count,'requirements',coalesce(v_refs,'[]'::jsonb),'destination','REDZED_STAFF_QUEUE'));
 return jsonb_build_object('batch_id',v_batch,'batch_ref',v_batch_ref,'order_count',v_count,'status','SUBMITTED',
  'redzed_status','PUSHED','requirements',coalesce(v_refs,'[]'::jsonb));
end $$;

create or replace function public.rr_market_staff_propose_batch_v67(
 p_batch_id uuid,p_line_proposals jsonb,p_pi_ref text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_line jsonb;v_line_id uuid;v_qty int;v_owner uuid;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if nullif(trim(p_pi_ref),'')is null then raise exception 'PI reference is required.';end if;
 select owner_customer_id into v_owner from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and status in('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION')for update;
 if v_owner is null then raise exception 'Batch cannot receive a PI proposal.';end if;
 for v_line in select value from jsonb_array_elements(p_line_proposals)loop
  v_line_id:=(v_line->>'line_id')::uuid;v_qty:=(v_line->>'proposed_qty')::int;
  if v_qty<0 then raise exception 'Proposed quantity cannot be negative.';end if;
  update public.rr_market_partner_order_line_v67 l set proposed_qty=v_qty,confirmed_qty=null,
   confirmation_status='WAITING',customer_pi_decision='WAITING',customer_pi_qty=null,customer_pi_note=null,updated_at=now()
  where l.id=v_line_id and exists(select 1 from public.rr_market_partner_batch_member_v67 m
   where m.batch_id=p_batch_id and m.order_id=l.order_id);
  if not found then raise exception 'Proposal line does not belong to batch.';end if;
 end loop;
 update public.rr_market_partner_order_v67 o set status='PI_PROPOSED',pi_ref=trim(p_pi_ref),
  customer_pi_visible=false,customer_pi_pushed_at=null,customer_pi_status='WAITING',customer_pi_note=null,
  customer_pi_responded_at=null,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 update public.rr_market_partner_batch_v67 set status='WAITING_CONFIRMATION',pi_ref=trim(p_pi_ref),updated_at=now()where id=p_batch_id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_PI_SENT_TO_DISTRIBUTOR','STAFF',auth.uid(),jsonb_build_object('pi_ref',trim(p_pi_ref)));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_partner_pi_push_v67(
 p_session_token text,p_device_id text,p_order_ids uuid[]
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_count int;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select count(*)into v_count from public.rr_market_partner_order_v67
 where id=any(p_order_ids)and owner_customer_id=v_owner and pi_ref is not null
 and status in('PI_PROPOSED','CONFIRMED','PARTIAL_CONFIRMED','CI_FINAL');
 if coalesce(array_length(p_order_ids,1),0)=0 or v_count<>array_length(p_order_ids,1)then
  raise exception 'Select only PI-ready customer requirements.';
 end if;
 update public.rr_market_partner_order_v67 set customer_pi_visible=true,customer_pi_pushed_at=now(),updated_at=now()
 where id=any(p_order_ids);
 insert into public.rr_market_partner_event_v67(owner_customer_id,event_type,actor_kind,payload)
 values(v_owner,'DISTRIBUTOR_PI_PUSHED_TO_CUSTOMERS','DISTRIBUTOR',jsonb_build_object('order_ids',to_jsonb(p_order_ids),'count',v_count));
 return jsonb_build_object('ok',true,'count',v_count,'status','PI_PUSHED_TO_CUSTOMERS');
end $$;

create or replace function public.rr_market_partner_customer_pi_response_v67(
 p_token text,p_decisions jsonb,p_note text default null
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_map public.rr_market_partner_collection_v67%rowtype;v_root uuid;v_order public.rr_market_partner_order_v67%rowtype;
 v_dec jsonb;v_line uuid;v_action text;v_qty int;v_wait int;v_confirm int;v_change int;v_cancel int;v_status text;
begin
 select pc.* into v_map from public.rr_market_partner_collection_v67 pc join public.rr_market_share_v9420 s on s.id=pc.share_id
 where(s.token=p_token or s.short_code=upper(p_token))and s.data_mode='TEST'and s.status='ACTIVE';
 if v_map.id is null then raise exception 'Distributor collection is unavailable.';end if;
 v_root:=coalesce(v_map.root_collection_id,v_map.id);
 select o.* into v_order from public.rr_market_partner_order_v67 o
 join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
 where pc.root_collection_id=v_root and o.customer_pi_visible and o.pi_ref is not null
 order by o.requirement_update_no desc,o.created_at desc limit 1 for update of o;
 if v_order.id is null then raise exception 'PI has not been pushed by distributor.';end if;
 if jsonb_typeof(p_decisions)<>'array'then raise exception 'PI decisions are required.';end if;
 for v_dec in select value from jsonb_array_elements(p_decisions)loop
  v_line:=(v_dec->>'line_id')::uuid;v_action:=upper(v_dec->>'action');
  if v_action not in('CONFIRM','CHANGE','CANCEL')then raise exception 'Invalid PI action.';end if;
  v_qty:=case when v_action='CONFIRM'then null else greatest(0,coalesce((v_dec->>'qty')::int,0))end;
  update public.rr_market_partner_order_line_v67 set customer_pi_decision=v_action,
   customer_pi_qty=case when v_action='CONFIRM'then coalesce(proposed_qty,requested_qty)when v_action='CANCEL'then 0 else v_qty end,
   customer_pi_note=nullif(trim(v_dec->>'note'),''),updated_at=now()
  where id=v_line and order_id=v_order.id;
  if not found then raise exception 'PI line does not belong to this customer.';end if;
 end loop;
 select count(*)filter(where customer_pi_decision='WAITING'),count(*)filter(where customer_pi_decision='CONFIRM'),
 count(*)filter(where customer_pi_decision='CHANGE'),count(*)filter(where customer_pi_decision='CANCEL')
 into v_wait,v_confirm,v_change,v_cancel from public.rr_market_partner_order_line_v67 where order_id=v_order.id;
 if v_wait>0 then raise exception 'Every PI line needs a decision.';end if;
 v_status:=case when v_confirm=0 and v_change=0 then'CANCELLED'when v_change>0 then'CHANGE_REQUESTED'
  when v_cancel>0 then'PARTIAL'else'CONFIRMED'end;
 update public.rr_market_partner_order_v67 set customer_pi_status=v_status,customer_pi_note=nullif(trim(p_note),''),
 customer_pi_responded_at=now(),updated_at=now()where id=v_order.id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,note,actor_kind,payload)
 values(v_order.owner_customer_id,v_order.id,'CUSTOMER_PI_RESPONSE',nullif(trim(p_note),''),'CUSTOMER',
 jsonb_build_object('pi_ref',v_order.pi_ref,'customer_pi_status',v_status));
 return jsonb_build_object('ok',true,'order_id',v_order.id,'pi_ref',v_order.pi_ref,'customer_pi_status',v_status,
 'sent_to','DISTRIBUTOR');
end $$;

create or replace function public.rr_market_partner_confirm_order_v67(
 p_session_token text,p_device_id text,p_order_id uuid,p_decisions jsonb,p_note text default null
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_batch uuid;v_dec jsonb;v_line uuid;v_action text;v_qty int;
 v_wait int;v_confirm int;v_cancel int;v_batch_status text;v_ci_ref text;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select m.batch_id into v_batch from public.rr_market_partner_batch_member_v67 m
 join public.rr_market_partner_order_v67 o on o.id=m.order_id
 where o.id=p_order_id and o.owner_customer_id=v_owner and o.status='PI_PROPOSED';
 if v_batch is null then raise exception 'Requirement is not waiting for distributor confirmation.';end if;
 for v_dec in select value from jsonb_array_elements(p_decisions)loop
  v_line:=(v_dec->>'line_id')::uuid;v_action:=upper(v_dec->>'action');
  if v_action not in('CONFIRM','CHANGE','CANCEL')then raise exception 'Invalid confirmation action.';end if;
  update public.rr_market_partner_order_line_v67 set
   confirmed_qty=case when v_action='CONFIRM'then coalesce(proposed_qty,requested_qty)
    when v_action='CHANGE'then greatest(0,(v_dec->>'confirmed_qty')::int)else 0 end,
   confirmation_status=case v_action when'CONFIRM'then'CONFIRMED'when'CHANGE'then'CHANGE_REQUESTED'else'CANCELLED'end,
   updated_at=now()where id=v_line and order_id=p_order_id;
  if not found then raise exception 'Confirmation line does not belong to requirement.';end if;
 end loop;
 select count(*)filter(where confirmation_status='WAITING'),count(*)filter(where confirmation_status in('CONFIRMED','CHANGE_REQUESTED')),
 count(*)filter(where confirmation_status='CANCELLED')into v_wait,v_confirm,v_cancel
 from public.rr_market_partner_order_line_v67 where order_id=p_order_id;
 if v_wait>0 then raise exception 'Every requirement line needs a distributor decision.';end if;
 update public.rr_market_partner_order_v67 set status=case when v_confirm=0 then'CANCELLED'
  when v_cancel>0 then'PARTIAL_CONFIRMED'else'CONFIRMED'end,confirmation_note=nullif(trim(p_note),''),
  distributor_confirmed_at=now(),updated_at=now()where id=p_order_id;
 update public.rr_market_partner_batch_v67 b set status=case
  when exists(select 1 from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
   where m.batch_id=b.id and o.status='PI_PROPOSED')then'WAITING_CONFIRMATION'
  when exists(select 1 from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
   where m.batch_id=b.id and o.status in('PARTIAL_CONFIRMED','CANCELLED'))then'PARTIAL_CONFIRMED'
  else'CONFIRMED'end,updated_at=now()where b.id=v_batch returning status into v_batch_status;
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,order_id,event_type,note,actor_kind,payload)
 values(v_owner,v_batch,p_order_id,'DISTRIBUTOR_PI_CONFIRMATION',nullif(trim(p_note),''),'DISTRIBUTOR',
 jsonb_build_object('confirmed_lines',v_confirm,'cancelled_lines',v_cancel));
 if v_batch_status in('CONFIRMED','PARTIAL_CONFIRMED')then
  select ci_ref into v_ci_ref from public.rr_market_partner_batch_v67 where id=v_batch;
  if v_ci_ref is null then v_ci_ref:=public.rr_market_partner_next_ci_v67();end if;
  update public.rr_market_partner_batch_v67 set status='CI_FINAL',ci_ref=v_ci_ref,updated_at=now()where id=v_batch;
  update public.rr_market_partner_order_v67 o set status=case when o.status='CANCELLED'then'CANCELLED'else'CI_FINAL'end,
   ci_ref=v_ci_ref,customer_ci_visible=false,updated_at=now()
  where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=v_batch and m.order_id=o.id);
  insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,payload)
  values(v_owner,v_batch,'CI_AUTO_GENERATED_AFTER_DISTRIBUTOR_CONFIRM','SYSTEM',jsonb_build_object('ci_ref',v_ci_ref));
 end if;
 return jsonb_build_object('ok',true,'order_id',p_order_id,'batch_id',v_batch,
  'batch_status',(select status from public.rr_market_partner_batch_v67 where id=v_batch),'ci_ref',v_ci_ref);
end $$;

create or replace function public.rr_market_staff_finalize_ci_v67(p_batch_id uuid,p_ci_ref text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;v_ref text;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select owner_customer_id,ci_ref into v_owner,v_ref from public.rr_market_partner_batch_v67
 where id=p_batch_id and data_mode='TEST'and status in('WAITING_CONFIRMATION','CONFIRMED','PARTIAL_CONFIRMED','CI_FINAL')for update;
 if v_owner is null then raise exception 'REDZED PI must exist before CI.';end if;
 if nullif(trim(p_ci_ref),'')is not null then v_ref:=trim(p_ci_ref);end if;
 if v_ref is null then v_ref:=public.rr_market_partner_next_ci_v67();end if;
 update public.rr_market_partner_batch_v67 set status='CI_FINAL',ci_ref=v_ref,updated_at=now()where id=p_batch_id;
 update public.rr_market_partner_order_v67 o set status=case when o.status='CANCELLED'then'CANCELLED'else'CI_FINAL'end,
  ci_ref=v_ref,customer_ci_visible=false,updated_at=now()
 where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
 values(v_owner,p_batch_id,'REDZED_CI_SENT_TO_DISTRIBUTOR','STAFF',auth.uid(),jsonb_build_object(
  'ci_ref',v_ref,'pi_confirmation_required',false));
 return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_partner_ci_push_v67(
 p_session_token text,p_device_id text,p_order_ids uuid[]
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_count int;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select count(*)into v_count from public.rr_market_partner_order_v67
 where id=any(p_order_ids)and owner_customer_id=v_owner and status='CI_FINAL'and ci_ref is not null;
 if coalesce(array_length(p_order_ids,1),0)=0 or v_count<>array_length(p_order_ids,1)then
  raise exception 'Select only CI-ready customer requirements.';
 end if;
 update public.rr_market_partner_order_v67 set customer_ci_visible=true,customer_ci_pushed_at=now(),updated_at=now()
 where id=any(p_order_ids);
 insert into public.rr_market_partner_event_v67(owner_customer_id,event_type,actor_kind,payload)
 values(v_owner,'DISTRIBUTOR_CI_PUSHED_TO_CUSTOMERS','DISTRIBUTOR',jsonb_build_object('order_ids',to_jsonb(p_order_ids),'count',v_count));
 return jsonb_build_object('ok',true,'count',v_count,'status','CI_PUSHED_TO_CUSTOMERS');
end $$;

create or replace function public.rr_market_staff_batch_detail_v67(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch public.rr_market_partner_batch_v67%rowtype;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into v_batch from public.rr_market_partner_batch_v67 where id=p_batch_id and data_mode='TEST';
 if v_batch.id is null then raise exception 'TEST67 batch not found.';end if;
 return jsonb_build_object('id',v_batch.id,'batch_ref',v_batch.batch_ref,'status',v_batch.status,
  'direct_customer_id',v_batch.owner_customer_id,
  'direct_customer_name',(select customer_name from public.rr_customers where id=v_batch.owner_customer_id),
  'pi_ref',v_batch.pi_ref,'ci_ref',v_batch.ci_ref,'pi_confirmation_required',false,
  'orders',(select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,'status',o.status,
   'customer_ref',c.customer_ref,'customer_pi_status',o.customer_pi_status,
   'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,
    'category',l.category,'size_text',l.size_text,'image_url',l.image_url,'requested_qty',l.requested_qty,
    'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,'base_rate',l.base_rate,
    'confirmation_status',l.confirmation_status,'customer_pi_decision',l.customer_pi_decision,
    'customer_pi_qty',l.customer_pi_qty)order by l.lot_no)
    from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))order by o.requirement_no,o.requirement_update_no)
   from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
   join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id where m.batch_id=v_batch.id),
  'consolidated',(select jsonb_agg(x order by x->>'lot_no')from(
   select jsonb_build_object('lot_no',l.lot_no,'article_name',max(l.article_name),'category',max(l.category),
    'size_text',max(l.size_text),'customer_count',count(distinct o.partner_customer_id),'order_count',count(distinct o.id),
    'total_requested_qty',sum(l.requested_qty),'total_proposed_qty',sum(coalesce(l.proposed_qty,l.requested_qty)),
    'total_confirmed_qty',sum(coalesce(l.confirmed_qty,0)))x
   from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
   join public.rr_market_partner_order_line_v67 l on l.order_id=o.id where m.batch_id=v_batch.id group by l.lot_no
  )q));
end $$;

create or replace function public.rr_market_share_view_v9420(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.rr_market_share_v9420%rowtype;v_map public.rr_market_partner_collection_v67%rowtype;
 v_latest public.rr_market_partner_order_v67%rowtype;v_root uuid;rows jsonb;v_header text;v_collections jsonb;
 v_requirements jsonb;v_requirement jsonb;v_pi jsonb;v_ci jsonb;
begin
 select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE'
 order by case when token=p_token then 0 else 1 end limit 1;
 if not found then raise exception 'Share link unavailable.';end if;
 update public.rr_market_share_v9420 set last_opened_at=now()where id=s.id;
 select * into v_map from public.rr_market_partner_collection_v67 where share_id=s.id;
 if v_map.id is not null then
  v_root:=coalesce(v_map.root_collection_id,v_map.id);
  v_header:=public.rr_market_partner_header_v67(v_map.owner_customer_id,v_map.partner_customer_id);
  select o.* into v_latest from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=v_root and o.status<>'SUPERSEDED'
  order by o.requirement_update_no desc,o.created_at desc limit 1;
 end if;
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
  'cloth_name',coalesce(pl.cloth_name,r.cloth_name),'category',coalesce(pl.category,r.category),
  'size_text',coalesce(pl.size_text,r.size_text),'item_name',r.item_name,
  'sale_rate',coalesce(pl.final_customer_rate,c.sale_rate),'display_sale_rate',coalesce(pl.distributor_sale_rate,c.sale_rate),
  'discount_amount',coalesce(pl.discount_amount,0),'stock_status',coalesce(pl.stock_status,c.stock_status),
  'hide_exact_stock',pl.collection_id is not null)order by l.sort_no),'[]'::jsonb)into rows
 from public.rr_market_share_lots_v9420 l
 cross join lateral public.rr_web_window_cards_v9329(l.lot_no,null,null,s.data_mode,1,0)c
 cross join lateral public.rr_web_lot_fields_resolve_v9624(l.lot_no,s.data_mode)r
 left join public.rr_market_partner_collection_v67 pc on pc.share_id=l.share_id
 left join public.rr_market_partner_collection_line_v67 pl on pl.collection_id=pc.id and pl.lot_no=l.lot_no
 where l.share_id=s.id and c.lot_no=l.lot_no;
 if v_map.id is not null then
  select coalesce(jsonb_agg(jsonb_build_object('id',pc.id,'display_no',pc.collection_display_no,
   'created_at',pc.created_at,'lines',(select jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'category',l.category,
    'size_text',l.size_text,'image_url',l.primary_image_url,'stock_status',l.stock_status,
    'sale_rate',l.distributor_sale_rate,'discount',l.discount_amount,'final_rate',l.final_customer_rate)order by l.lot_no)
    from public.rr_market_partner_collection_line_v67 l where l.collection_id=pc.id))
   order by pc.collection_update_no),'[]'::jsonb)into v_collections
  from public.rr_market_partner_collection_v67 pc where pc.root_collection_id=v_root;
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'display_no',o.requirement_display_no,'status',o.status,
   'created_at',o.created_at,'closed_at',o.customer_closed_at,'redzed_pushed_at',o.redzed_pushed_at,
   'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
    'image_url',l.image_url,'qty',l.requested_qty,'rate',l.final_customer_rate)order by l.lot_no)
    from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))order by o.requirement_update_no),'[]'::jsonb)into v_requirements
  from public.rr_market_partner_order_v67 o join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=v_root;
  if v_latest.id is not null then
   select jsonb_build_object('id',o.id,'display_no',o.requirement_display_no,'status',o.status,
    'can_update',o.status='DRAFT','can_close',o.status='DRAFT','customer_closed_at',o.customer_closed_at,
    'redzed_pushed_at',o.redzed_pushed_at)into v_requirement
   from public.rr_market_partner_order_v67 o where o.id=v_latest.id;
   if v_latest.customer_pi_visible and v_latest.pi_ref is not null then
    select jsonb_build_object('ref',o.pi_ref,'status',o.customer_pi_status,'note',o.customer_pi_note,
     'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'category',l.category,
      'size_text',l.size_text,'image_url',l.image_url,'requested_qty',l.requested_qty,
      'proposed_qty',coalesce(l.proposed_qty,l.requested_qty),'rate',l.final_customer_rate,
      'decision',l.customer_pi_decision,'customer_qty',l.customer_pi_qty)order by l.lot_no)
      from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))into v_pi
    from public.rr_market_partner_order_v67 o where o.id=v_latest.id;
   end if;
   if v_latest.customer_ci_visible and v_latest.ci_ref is not null then
    select jsonb_build_object('ref',o.ci_ref,'pi_ref',o.pi_ref,
     'lines',(select jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
      'image_url',l.image_url,'qty',coalesce(l.confirmed_qty,l.customer_pi_qty,l.proposed_qty,l.requested_qty),
      'rate',l.final_customer_rate)order by l.lot_no)
      from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))into v_ci
    from public.rr_market_partner_order_v67 o where o.id=v_latest.id;
   end if;
  end if;
 end if;
 return jsonb_build_object('share_id',s.id,'customer_name',s.customer_name,'created_at',s.created_at,'rows',rows,
  'header_title',coalesce(v_header,'REDZED · COLLECTION'),'collection_display_no',v_map.collection_display_no,
  'collections',coalesce(v_collections,'[]'::jsonb),'requirements',coalesce(v_requirements,'[]'::jsonb),
  'requirement',v_requirement,'pi',v_pi,'ci',v_ci,
  'requirement_locked',coalesce(v_latest.status<>'DRAFT',false));
end $$;

create or replace function public.rr_market_partner_workspace_v67(p_session_token text,p_device_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 return v_ctx||jsonb_build_object(
 'owner_name',(select customer_name from public.rr_customers where id=v_owner),
 'customers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'customer_ref',c.customer_ref,'name',c.private_name,
  'mobile',c.private_mobile,'status',c.status,'group_id',c.group_id,'group_name',g.group_name,
  'margin',c.default_margin_amount,'discount',c.default_discount_amount)order by c.customer_ref)
  from public.rr_market_partner_customer_v67 c left join public.rr_market_partner_group_v67 g on g.id=c.group_id
  where c.owner_customer_id=v_owner),'[]'::jsonb),
 'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.group_name,'info',g.group_info,'status',g.status)order by g.group_name)
  from public.rr_market_partner_group_v67 g where g.owner_customer_id=v_owner),'[]'::jsonb),
 'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.staff_name,'mobile',s.private_mobile,'role',s.staff_role,'status',s.status)order by s.staff_name)
  from public.rr_market_partner_staff_v67 s where s.owner_customer_id=v_owner),'[]'::jsonb),
 'collections',coalesce((select jsonb_agg(jsonb_build_object('id',pc.id,'customer_id',pc.partner_customer_id,
  'customer_ref',c.customer_ref,'customer_name',c.private_name,'group_name',g.group_name,'status',pc.status,
  'collection_no',pc.collection_no,'collection_update_no',pc.collection_update_no,'collection_display_no',pc.collection_display_no,
  'requirement_display_no',pc.requirement_display_no,'created_at',pc.created_at,
  'lines',(select jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
   'image_url',l.primary_image_url,'stock_status',l.stock_status,'final_rate',l.final_customer_rate)order by l.lot_no)
   from public.rr_market_partner_collection_line_v67 l where l.collection_id=pc.id),
  'lot_count',(select count(*)from public.rr_market_partner_collection_line_v67 pl where pl.collection_id=pc.id))
  order by pc.collection_no desc,pc.collection_update_no desc)
  from public.rr_market_partner_collection_v67 pc join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
  left join public.rr_market_partner_group_v67 g on g.id=c.group_id where pc.owner_customer_id=v_owner),'[]'::jsonb),
 'orders',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,
  'requirement_no',o.requirement_no,'requirement_update_no',o.requirement_update_no,'requirement_display_no',o.requirement_display_no,
  'collection_display_no',pc.collection_display_no,'status',o.status,'customer_id',o.partner_customer_id,
  'customer_ref',c.customer_ref,'customer_name',c.private_name,'pi_ref',o.pi_ref,'ci_ref',o.ci_ref,
  'customer_closed_at',o.customer_closed_at,'redzed_pushed_at',o.redzed_pushed_at,
  'customer_pi_visible',o.customer_pi_visible,'customer_pi_status',o.customer_pi_status,
  'customer_pi_pushed_at',o.customer_pi_pushed_at,'distributor_confirmed_at',o.distributor_confirmed_at,
  'customer_ci_visible',o.customer_ci_visible,'customer_ci_pushed_at',o.customer_ci_pushed_at,'created_at',o.created_at,
  'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,
   'category',l.category,'size_text',l.size_text,'image_url',l.image_url,'requested_qty',l.requested_qty,
   'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,'base_rate',l.base_rate,
   'rate_enhancement',l.rate_enhancement,'sale_rate',l.customer_rate,'discount',l.customer_discount,
   'final_rate',l.final_customer_rate,'confirmation_status',l.confirmation_status,
   'customer_pi_decision',l.customer_pi_decision,'customer_pi_qty',l.customer_pi_qty)order by l.lot_no)
   from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))order by o.requirement_no desc,o.requirement_update_no desc)
  from public.rr_market_partner_order_v67 o join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id
  left join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id where o.owner_customer_id=v_owner),'[]'::jsonb),
 'summary',(select jsonb_build_object(
  'present_qty',coalesce(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner and status<>'SUPERSEDED'order by created_at desc limit 1)then l.requested_qty else 0 end),0),
  'present_amount',coalesce(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner and status<>'SUPERSEDED'order by created_at desc limit 1)then l.requested_qty*l.final_customer_rate else 0 end),0),
  'present_average',coalesce(round(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner and status<>'SUPERSEDED'order by created_at desc limit 1)then l.requested_qty*l.final_customer_rate else 0 end)/nullif(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner and status<>'SUPERSEDED'order by created_at desc limit 1)then l.requested_qty else 0 end),0),2),0),
  'all_qty',coalesce(sum(l.requested_qty)filter(where o.status<>'SUPERSEDED'),0),
  'all_amount',coalesce(sum(l.requested_qty*l.final_customer_rate)filter(where o.status<>'SUPERSEDED'),0),
  'all_average',coalesce(round(sum(l.requested_qty*l.final_customer_rate)filter(where o.status<>'SUPERSEDED')/
   nullif(sum(l.requested_qty)filter(where o.status<>'SUPERSEDED'),0),2),0))
  from public.rr_market_partner_order_v67 o join public.rr_market_partner_order_line_v67 l on l.order_id=o.id
  where o.owner_customer_id=v_owner and o.status<>'CANCELLED'),
 'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'type',e.event_type,'note',e.note,
  'actor',e.actor_kind,'payload',e.payload,'created_at',e.created_at)order by e.created_at)
  from public.rr_market_partner_event_v67 e where e.owner_customer_id=v_owner),'[]'::jsonb),
 'batches',coalesce((select jsonb_agg(jsonb_build_object('id',id,'batch_ref',batch_ref,'status',status,
  'pi_ref',pi_ref,'ci_ref',ci_ref,'submitted_at',submitted_at)order by submitted_at desc)
  from public.rr_market_partner_batch_v67 where owner_customer_id=v_owner),'[]'::jsonb));
end $$;

revoke all on function public.rr_market_partner_customer_requirement_close_v67(text)from public;
revoke all on function public.rr_market_partner_pi_push_v67(text,text,uuid[])from public;
revoke all on function public.rr_market_partner_customer_pi_response_v67(text,jsonb,text)from public;
revoke all on function public.rr_market_partner_ci_push_v67(text,text,uuid[])from public;
grant execute on function public.rr_market_partner_customer_requirement_close_v67(text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_pi_push_v67(text,text,uuid[])to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_pi_response_v67(text,jsonb,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_ci_push_v67(text,text,uuid[])to anon,authenticated,service_role;

revoke all on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb)from public;
revoke all on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)from public;
revoke all on function public.rr_market_partner_batch_submit_v67(text,text,uuid[])from public;
revoke all on function public.rr_market_staff_propose_batch_v67(uuid,jsonb,text)from public,anon;
revoke all on function public.rr_market_partner_confirm_order_v67(text,text,uuid,jsonb,text)from public;
revoke all on function public.rr_market_staff_finalize_ci_v67(uuid,text)from public,anon;
revoke all on function public.rr_market_staff_batch_detail_v67(uuid)from public,anon;
revoke all on function public.rr_market_share_view_v9420(text)from public;
revoke all on function public.rr_market_partner_workspace_v67(text,text)from public;
grant execute on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_batch_submit_v67(text,text,uuid[])to anon,authenticated,service_role;
grant execute on function public.rr_market_staff_propose_batch_v67(uuid,jsonb,text)to authenticated,service_role;
grant execute on function public.rr_market_partner_confirm_order_v67(text,text,uuid,jsonb,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_staff_finalize_ci_v67(uuid,text)to authenticated,service_role;
grant execute on function public.rr_market_staff_batch_detail_v67(uuid)to authenticated,service_role;
grant execute on function public.rr_market_share_view_v9420(text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_workspace_v67(text,text)to anon,authenticated,service_role;
