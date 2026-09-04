-- TEST67 distributor collection/requirement chains.
-- Additive and TEST-only: MAIN/REAL rows and numbering are untouched.

create table if not exists public.rr_market_partner_global_sequence_v67(
  sequence_kind text primary key check(sequence_kind in('COLLECTION','REQUIREMENT')),
  current_no bigint not null default 0 check(current_no>=0),
  data_mode text not null default 'TEST' check(data_mode='TEST'),
  updated_at timestamptz not null default now()
);
alter table public.rr_market_partner_global_sequence_v67 enable row level security;
revoke all on public.rr_market_partner_global_sequence_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_global_sequence_v67 to service_role;

alter table public.rr_market_partner_collection_v67
  add column if not exists root_collection_id uuid,
  add column if not exists collection_no bigint,
  add column if not exists collection_update_no integer not null default 0,
  add column if not exists collection_display_no text,
  add column if not exists requirement_no bigint,
  add column if not exists requirement_update_no integer,
  add column if not exists requirement_display_no text;

alter table public.rr_market_partner_order_v67
  add column if not exists collection_id uuid,
  add column if not exists root_order_id uuid,
  add column if not exists requirement_no bigint,
  add column if not exists requirement_update_no integer not null default 0,
  add column if not exists requirement_display_no text;

-- Existing TEST67 sends are one open chain per distributor customer.  The oldest
-- send is the base collection and later sends become its ordered updates.
with customer_roots as(
  select owner_customer_id,partner_customer_id,
    min(created_at) as first_created_at,
    (array_agg(id order by created_at,id))[1] as root_id
  from public.rr_market_partner_collection_v67
  group by owner_customer_id,partner_customer_id
), numbered as(
  select cr.*,row_number()over(order by first_created_at,owner_customer_id,partner_customer_id)::bigint as global_no
  from customer_roots cr
), ranked as(
  select pc.id,n.root_id,n.global_no,
    (row_number()over(partition by pc.owner_customer_id,pc.partner_customer_id order by pc.created_at,pc.id)-1)::integer as update_no
  from public.rr_market_partner_collection_v67 pc
  join numbered n using(owner_customer_id,partner_customer_id)
)
update public.rr_market_partner_collection_v67 pc set
  root_collection_id=r.root_id,
  collection_no=r.global_no,
  collection_update_no=r.update_no,
  collection_display_no='COLLECTION '||r.global_no::text||case when r.update_no>0 then ' · UPDATE '||r.update_no::text else '' end
from ranked r where r.id=pc.id and pc.collection_no is null;

insert into public.rr_market_partner_global_sequence_v67(sequence_kind,current_no)
values('COLLECTION',coalesce((select max(collection_no)from public.rr_market_partner_collection_v67),0)),
      ('REQUIREMENT',0)
on conflict(sequence_kind)do update set
 current_no=greatest(public.rr_market_partner_global_sequence_v67.current_no,excluded.current_no),updated_at=now();

-- No distributor requirements existed when this migration was introduced, but
-- keep a deterministic backfill for any TEST copy that already has rows.
with ranked as(
  select o.id,row_number()over(order by o.created_at,o.id)::bigint as global_no,
    pc.id as linked_collection_id
  from public.rr_market_partner_order_v67 o
  left join public.rr_market_partner_collection_v67 pc on pc.order_id=o.id
  where o.requirement_no is null
)
update public.rr_market_partner_order_v67 o set
  collection_id=r.linked_collection_id,
  root_order_id=o.id,
  requirement_no=r.global_no,
  requirement_update_no=0,
  requirement_display_no='REQUIREMENT '||r.global_no::text,
  order_ref='REQUIREMENT '||r.global_no::text
from ranked r where r.id=o.id;

update public.rr_market_partner_collection_v67 pc set
  requirement_no=o.requirement_no,
  requirement_update_no=o.requirement_update_no,
  requirement_display_no=o.requirement_display_no
from public.rr_market_partner_order_v67 o where pc.order_id=o.id;

update public.rr_market_partner_global_sequence_v67 set
 current_no=greatest(current_no,coalesce((select max(requirement_no)from public.rr_market_partner_order_v67),0)),updated_at=now()
where sequence_kind='REQUIREMENT';

do $$ begin
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_collection_v67_root_fkey')then
    alter table public.rr_market_partner_collection_v67 add constraint rr_market_partner_collection_v67_root_fkey
      foreign key(root_collection_id)references public.rr_market_partner_collection_v67(id);
  end if;
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_order_v67_collection_fkey')then
    alter table public.rr_market_partner_order_v67 add constraint rr_market_partner_order_v67_collection_fkey
      foreign key(collection_id)references public.rr_market_partner_collection_v67(id);
  end if;
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_order_v67_root_fkey')then
    alter table public.rr_market_partner_order_v67 add constraint rr_market_partner_order_v67_root_fkey
      foreign key(root_order_id)references public.rr_market_partner_order_v67(id);
  end if;
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_collection_v67_update_check')then
    alter table public.rr_market_partner_collection_v67 add constraint rr_market_partner_collection_v67_update_check
      check(collection_update_no>=0 and(requirement_update_no is null or requirement_update_no>=0));
  end if;
  if not exists(select 1 from pg_constraint where conname='rr_market_partner_order_v67_update_check')then
    alter table public.rr_market_partner_order_v67 add constraint rr_market_partner_order_v67_update_check
      check(requirement_update_no>=0);
  end if;
end $$;

create unique index if not exists rr_market_partner_collection_v67_global_chain_uniq
  on public.rr_market_partner_collection_v67(collection_no,collection_update_no)
  where collection_no is not null;
create unique index if not exists rr_market_partner_order_v67_global_chain_uniq
  on public.rr_market_partner_order_v67(requirement_no,requirement_update_no)
  where requirement_no is not null;
create index if not exists rr_market_partner_collection_v67_root_idx
  on public.rr_market_partner_collection_v67(root_collection_id,collection_update_no);
create index if not exists rr_market_partner_order_v67_collection_idx
  on public.rr_market_partner_order_v67(collection_id);
create index if not exists rr_market_partner_order_v67_root_idx
  on public.rr_market_partner_order_v67(root_order_id,requirement_update_no);

create or replace function public.rr_market_partner_header_v67(p_owner_customer_id uuid,p_partner_customer_id uuid)
returns text language sql stable security definer set search_path=public as $$
 select 'REDZED · '||upper(trim(rc.customer_name))||
  case when upper(trim(rc.customer_name))like '%DISTRIBUTOR%' then '' else ' DISTRIBUTOR' end||
  ' · '||upper(trim(coalesce(nullif(g.group_name,''),c.private_name)))||
  case when upper(trim(coalesce(nullif(g.group_name,''),c.private_name)))like '%GROUP%' then '' else ' GROUP' end
 from public.rr_customers rc
 join public.rr_market_partner_customer_v67 c on c.id=p_partner_customer_id and c.owner_customer_id=rc.id
 left join public.rr_market_partner_group_v67 g on g.id=c.group_id
 where rc.id=p_owner_customer_id;
$$;
revoke all on function public.rr_market_partner_header_v67(uuid,uuid)from public,anon,authenticated;
grant execute on function public.rr_market_partner_header_v67(uuid,uuid)to service_role;

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
  and cs.customer_id=v_owner and cs.revoked_at is null and cs.expires_at>now() limit 1;
 if v_creator is null then raise exception 'Verified share owner is unavailable.';end if;

 perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_COLLECTION'));
 select pc.root_collection_id,pc.collection_no,max(pc.collection_update_no)+1
 into v_root,v_collection_no,v_update_no
 from public.rr_market_partner_collection_v67 pc
 where pc.owner_customer_id=v_owner and pc.partner_customer_id=p_partner_customer_id
  and pc.status<>'CANCELLED'
  and not exists(
    select 1 from public.rr_market_partner_collection_v67 cx
    join public.rr_market_partner_order_v67 ox on ox.collection_id=cx.id
    where cx.root_collection_id=pc.root_collection_id and ox.status in('CANCELLED','CI_FINAL','CLOSED')
  )
 group by pc.root_collection_id,pc.collection_no
 order by max(pc.created_at)desc limit 1;
 if v_root is null then
  update public.rr_market_partner_global_sequence_v67 set current_no=current_no+1,updated_at=now()
   where sequence_kind='COLLECTION' returning current_no into v_collection_no;
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
  select * into v_card from public.rr_web_window_cards_v9329(v_lot,null,null,'TEST',10,0)
   where lot_no=v_lot limit 1;
  if v_card.lot_no is null then raise exception 'TEST lot % is unavailable.',v_lot;end if;
  v_sale:=coalesce(v_card.sale_rate,0)+v_margin;v_final:=greatest(0,v_sale-v_discount);
  insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)
   values(v_share,v_lot,(select count(*)+1 from public.rr_market_share_lots_v9420 where share_id=v_share))on conflict do nothing;
  insert into public.rr_market_partner_collection_line_v67(
   collection_id,lot_no,category,cloth_name,primary_image_url,media,stock_status,
   base_rate,margin_amount,distributor_sale_rate,discount_amount,final_customer_rate
  )values(v_collection,v_lot,coalesce(v_card.category,''),v_card.cloth_name,v_card.primary_image_url,
   coalesce(v_card.media,'[]'::jsonb),case when coalesce(v_card.available_qty,0)<=0 then 'OUT OF STOCK'
   when upper(coalesce(v_card.stock_status,''))='LOW_STOCK' then 'LOW STOCK' else 'STOCK-IN' end,
   coalesce(v_card.sale_rate,0),v_margin,v_sale,v_discount,v_final);
 end loop;

 update public.rr_market_partner_customer_v67 set default_margin_amount=v_margin,
  default_discount_amount=v_discount,updated_at=now()where id=p_partner_customer_id;
 v_header:=public.rr_market_partner_header_v67(v_owner,p_partner_customer_id);
 insert into public.rr_market_partner_event_v67(owner_customer_id,event_type,actor_kind,payload)
 values(v_owner,'COLLECTION_PUSHED_TO_REDZED','DISTRIBUTOR',jsonb_build_object(
  'collection_id',v_collection,'collection_display_no',v_display,'customer_ref',
  (select customer_ref from public.rr_market_partner_customer_v67 where id=p_partner_customer_id),
  'channels',jsonb_build_array('REDZED','WHATSAPP')));
 return jsonb_build_object('collection_id',v_collection,'share_id',v_share,'token',v_token,
  'short_code',v_code,'lot_count',(select count(*)from public.rr_market_partner_collection_line_v67 where collection_id=v_collection),
  'collection_no',v_collection_no,'collection_update_no',v_update_no,'collection_display_no',v_display,
  'header_title',v_header,'customer_mobile',v_mobile,'redzed_status','PUSHED');
end $$;

create or replace function public.rr_market_share_view_v9420(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.rr_market_share_v9420%rowtype;v_map public.rr_market_partner_collection_v67%rowtype;rows jsonb;v_header text;
begin
 select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
 if not found then raise exception 'Share link unavailable.';end if;
 update public.rr_market_share_v9420 set last_opened_at=now()where id=s.id;
 select * into v_map from public.rr_market_partner_collection_v67 where share_id=s.id;
 if v_map.id is not null then v_header:=public.rr_market_partner_header_v67(v_map.owner_customer_id,v_map.partner_customer_id);end if;
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
  'cloth_name',coalesce(pl.cloth_name,r.cloth_name),'category',coalesce(pl.category,r.category),'item_name',r.item_name,
  'sale_rate',coalesce(pl.final_customer_rate,c.sale_rate),'display_sale_rate',coalesce(pl.distributor_sale_rate,c.sale_rate),
  'discount_amount',coalesce(pl.discount_amount,0),'stock_status',coalesce(pl.stock_status,c.stock_status),
  'hide_exact_stock',pl.collection_id is not null)order by l.sort_no),'[]'::jsonb)into rows
 from public.rr_market_share_lots_v9420 l
 cross join lateral public.rr_web_window_cards_v9329(l.lot_no,null,null,s.data_mode,1,0)c
 cross join lateral public.rr_web_lot_fields_resolve_v9624(l.lot_no,s.data_mode)r
 left join public.rr_market_partner_collection_v67 pc on pc.share_id=l.share_id
 left join public.rr_market_partner_collection_line_v67 pl on pl.collection_id=pc.id and pl.lot_no=l.lot_no
 where l.share_id=s.id and c.lot_no=l.lot_no;
 return jsonb_build_object('share_id',s.id,'customer_name',s.customer_name,'created_at',s.created_at,'rows',rows,
  'header_title',coalesce(v_header,'REDZED · COLLECTION'),'collection_display_no',v_map.collection_display_no,
  'requirement_display_no',v_map.requirement_display_no);
end $$;

create or replace function public.rr_market_partner_submit_requirement_v67(
 p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb
)returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_map public.rr_market_partner_collection_v67%rowtype;v_result jsonb;v_req uuid;v_owner_seq bigint;v_prefix text;
 v_ref text;v_order uuid:=gen_random_uuid();v_root_order uuid;v_line record;
 v_price public.rr_market_partner_collection_line_v67%rowtype;v_requirement_no bigint;v_update_no integer;
begin
 select pc.* into v_map from public.rr_market_partner_collection_v67 pc
 join public.rr_market_share_v9420 s on s.id=pc.share_id
 where(s.token=p_token or s.short_code=upper(p_token))and s.data_mode='TEST' and s.status='ACTIVE' for update of pc;
 v_result:=public.rr_market_submit_requirement_v9508(p_token,p_customer_name,p_mobile,p_message,p_lines,null);
 if v_map.id is null then return v_result;end if;
 if v_map.order_id is not null then raise exception 'This collection requirement is already submitted.';end if;
 v_req:=(v_result->>'requirement_id')::uuid;

 perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_REQUIREMENT'));
 select o.requirement_no,coalesce(o.root_order_id,o.id) into v_requirement_no,v_root_order
 from public.rr_market_partner_order_v67 o
 join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
 where pc.root_collection_id=coalesce(v_map.root_collection_id,v_map.id)and o.requirement_no is not null
 order by o.requirement_update_no,o.created_at,o.id limit 1;
 if v_requirement_no is null then
  update public.rr_market_partner_global_sequence_v67 set current_no=current_no+1,updated_at=now()
   where sequence_kind='REQUIREMENT' returning current_no into v_requirement_no;
  v_root_order:=v_order;v_update_no:=0;
 else
  select coalesce(max(o.requirement_update_no),-1)+1 into v_update_no
  from public.rr_market_partner_order_v67 o join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=coalesce(v_map.root_collection_id,v_map.id)and o.requirement_no=v_requirement_no;
 end if;
 v_ref:='REQUIREMENT '||v_requirement_no::text||case when v_update_no>0 then ' · UPDATE '||v_update_no::text else '' end;

 select prefix,current_no+1 into v_prefix,v_owner_seq from public.rr_market_owner_sequence_v67
  where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST' for update;
 if v_prefix is null then raise exception 'Distributor prefix is not configured.';end if;
 update public.rr_market_owner_sequence_v67 set current_no=v_owner_seq,updated_at=now()
  where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST';
 insert into public.rr_market_partner_order_v67(
  id,owner_customer_id,partner_customer_id,sequence_no,order_ref,status,linked_requirement_id,
  collection_id,root_order_id,requirement_no,requirement_update_no,requirement_display_no
 )values(v_order,v_map.owner_customer_id,v_map.partner_customer_id,v_owner_seq,v_ref,'READY',v_req,
  v_map.id,v_root_order,v_requirement_no,v_update_no,v_ref);
 for v_line in select l.* from public.rr_market_requirement_lines_v9420 l where l.requirement_id=v_req loop
  select * into v_price from public.rr_market_partner_collection_line_v67
   where collection_id=v_map.id and lot_no=v_line.lot_no;
  insert into public.rr_market_partner_order_line_v67(
   order_id,lot_no,article_name,image_url,requested_qty,base_rate,rate_enhancement,customer_discount,final_customer_rate
  )values(v_order,v_line.lot_no,coalesce(v_price.category,v_line.lot_no),v_price.primary_image_url,
   v_line.accepted_qty,v_price.base_rate,v_price.margin_amount,v_price.discount_amount,v_price.final_customer_rate);
 end loop;
 update public.rr_market_partner_collection_v67 set requirement_id=v_req,order_id=v_order,status='REQUIREMENT_RECEIVED',
  requirement_no=v_requirement_no,requirement_update_no=v_update_no,requirement_display_no=v_ref,updated_at=now()
  where id=v_map.id;
 insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)
 values(v_map.owner_customer_id,v_order,'CUSTOMER_REQUIREMENT_RECEIVED','SYSTEM',jsonb_build_object(
  'requirement_display_no',v_ref,'collection_display_no',v_map.collection_display_no,'share_id',v_map.share_id));
 return v_result||jsonb_build_object('order_id',v_order,'order_ref',v_ref,'requirement_no',v_requirement_no,
  'requirement_update_no',v_update_no,'requirement_display_no',v_ref,'collection_display_no',v_map.collection_display_no);
end $$;

create or replace function public.rr_market_partner_batch_submit_v67(
 p_session_token text,p_device_id text,p_order_ids uuid[]
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_batch uuid;v_batch_ref text;v_count int;v_refs jsonb;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not(v_ctx->>'send_collection_enabled')::boolean then raise exception 'Requirement push is disabled.';end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select count(*) into v_count from public.rr_market_partner_order_v67
  where id=any(p_order_ids)and owner_customer_id=v_owner and status='READY';
 if coalesce(array_length(p_order_ids,1),0)=0 or v_count<>array_length(p_order_ids,1)then
  raise exception 'Select only your READY requirements.';
 end if;
 select jsonb_agg(requirement_display_no order by requirement_no,requirement_update_no)into v_refs
  from public.rr_market_partner_order_v67 where id=any(p_order_ids);
 v_batch_ref:='B-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.rr_market_partner_batch_v67(owner_customer_id,batch_ref)values(v_owner,v_batch_ref)returning id into v_batch;
 insert into public.rr_market_partner_batch_member_v67(batch_id,order_id)select v_batch,unnest(p_order_ids);
 update public.rr_market_partner_order_v67 set status='BATCHED',updated_at=now()where id=any(p_order_ids);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,payload)
 values(v_owner,v_batch,'REQUIREMENTS_PUSHED_TO_REDZED','DISTRIBUTOR',jsonb_build_object(
  'order_count',v_count,'requirements',coalesce(v_refs,'[]'::jsonb),'destination','REDZED_STAFF_QUEUE'));
 return jsonb_build_object('batch_id',v_batch,'batch_ref',v_batch_ref,'order_count',v_count,'status','SUBMITTED',
  'redzed_status','PUSHED','requirements',coalesce(v_refs,'[]'::jsonb));
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
  'lot_count',(select count(*)from public.rr_market_partner_collection_line_v67 pl where pl.collection_id=pc.id))
  order by pc.collection_no desc,pc.collection_update_no desc)
  from public.rr_market_partner_collection_v67 pc join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
  left join public.rr_market_partner_group_v67 g on g.id=c.group_id where pc.owner_customer_id=v_owner),'[]'::jsonb),
 'orders',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,
  'requirement_no',o.requirement_no,'requirement_update_no',o.requirement_update_no,'requirement_display_no',o.requirement_display_no,
  'collection_display_no',pc.collection_display_no,'status',o.status,'customer_id',o.partner_customer_id,
  'customer_ref',c.customer_ref,'customer_name',c.private_name,'pi_ref',o.pi_ref,'ci_ref',o.ci_ref,'created_at',o.created_at,
  'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,
   'image_url',l.image_url,'requested_qty',l.requested_qty,'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,
   'base_rate',l.base_rate,'rate_enhancement',l.rate_enhancement,'sale_rate',l.customer_rate,'discount',l.customer_discount,
   'final_rate',l.final_customer_rate,'confirmation_status',l.confirmation_status)order by l.lot_no)
   from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))order by o.requirement_no desc,o.requirement_update_no desc)
  from public.rr_market_partner_order_v67 o join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id
  left join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id where o.owner_customer_id=v_owner),'[]'::jsonb),
 'summary',(select jsonb_build_object(
  'present_qty',coalesce(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner order by created_at desc limit 1)then l.requested_qty else 0 end),0),
  'present_amount',coalesce(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner order by created_at desc limit 1)then l.requested_qty*l.final_customer_rate else 0 end),0),
  'present_average',coalesce(round(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner order by created_at desc limit 1)then l.requested_qty*l.final_customer_rate else 0 end)/nullif(sum(case when o.id=(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner order by created_at desc limit 1)then l.requested_qty else 0 end),0),2),0),
  'all_qty',coalesce(sum(l.requested_qty),0),'all_amount',coalesce(sum(l.requested_qty*l.final_customer_rate),0),
  'all_average',coalesce(round(sum(l.requested_qty*l.final_customer_rate)/nullif(sum(l.requested_qty),0),2),0))
  from public.rr_market_partner_order_v67 o join public.rr_market_partner_order_line_v67 l on l.order_id=o.id
  where o.owner_customer_id=v_owner and o.status<>'CANCELLED'),
 'batches',coalesce((select jsonb_agg(jsonb_build_object('id',id,'batch_ref',batch_ref,'status',status,'pi_ref',pi_ref,'ci_ref',ci_ref,'submitted_at',submitted_at)order by submitted_at desc)
  from public.rr_market_partner_batch_v67 where owner_customer_id=v_owner),'[]'::jsonb));
end $$;

revoke all on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb)from public;
revoke all on function public.rr_market_share_view_v9420(text)from public;
revoke all on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)from public;
revoke all on function public.rr_market_partner_batch_submit_v67(text,text,uuid[])from public;
revoke all on function public.rr_market_partner_workspace_v67(text,text)from public;
grant execute on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb)to anon,authenticated,service_role;
grant execute on function public.rr_market_share_view_v9420(text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_batch_submit_v67(text,text,uuid[])to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_workspace_v67(text,text)to anon,authenticated,service_role;
