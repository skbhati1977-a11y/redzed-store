-- TEST67 distributor personal workspace, pricing snapshots and private directories.
-- Additive and TEST-only. MAIN/REAL numbering and rows are not changed.

create table if not exists public.rr_market_partner_group_v67(
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references public.rr_customers(id),
  group_name text not null,
  group_info text,
  status text not null default 'ACTIVE' check(status in('ACTIVE','INACTIVE')),
  data_mode text not null default 'TEST' check(data_mode='TEST'),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  unique(owner_customer_id,group_name,data_mode)
);
create table if not exists public.rr_market_partner_staff_v67(
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references public.rr_customers(id),
  staff_name text not null,private_mobile text,staff_role text not null default 'SALES',
  status text not null default 'ACTIVE' check(status in('ACTIVE','INACTIVE')),
  data_mode text not null default 'TEST' check(data_mode='TEST'),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.rr_market_partner_group_v67 enable row level security;
alter table public.rr_market_partner_staff_v67 enable row level security;
revoke all on public.rr_market_partner_group_v67 from public,anon,authenticated;
revoke all on public.rr_market_partner_staff_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_group_v67 to service_role;
grant all on public.rr_market_partner_staff_v67 to service_role;

create index if not exists rr_market_partner_staff_v67_owner_idx
  on public.rr_market_partner_staff_v67(owner_customer_id);

alter table public.rr_market_partner_customer_v67 add column if not exists group_id uuid references public.rr_market_partner_group_v67(id);
alter table public.rr_market_partner_customer_v67 add column if not exists default_margin_amount numeric(14,2) not null default 0 check(default_margin_amount>=0);
alter table public.rr_market_partner_customer_v67 add column if not exists default_discount_amount numeric(14,2) not null default 0 check(default_discount_amount>=0);
alter table public.rr_market_partner_order_line_v67 add column if not exists customer_discount numeric(14,2) not null default 0 check(customer_discount>=0);
alter table public.rr_market_partner_order_line_v67 add column if not exists final_customer_rate numeric(14,2) not null default 0 check(final_customer_rate>=0);

create index if not exists rr_market_partner_customer_v67_group_idx
  on public.rr_market_partner_customer_v67(group_id);
create index if not exists rr_market_partner_collection_v67_owner_idx
  on public.rr_market_partner_collection_v67(owner_customer_id);
create index if not exists rr_market_partner_collection_v67_customer_idx
  on public.rr_market_partner_collection_v67(partner_customer_id);
create index if not exists rr_market_partner_collection_v67_order_idx
  on public.rr_market_partner_collection_v67(order_id);
create index if not exists rr_market_partner_collection_v67_requirement_idx
  on public.rr_market_partner_collection_v67(requirement_id);
create index if not exists rr_market_partner_order_v67_customer_idx
  on public.rr_market_partner_order_v67(partner_customer_id);
create index if not exists rr_market_partner_order_v67_requirement_idx
  on public.rr_market_partner_order_v67(linked_requirement_id);

create table if not exists public.rr_market_partner_collection_line_v67(
  collection_id uuid not null references public.rr_market_partner_collection_v67(id) on delete cascade,
  lot_no text not null,category text,cloth_name text,primary_image_url text,media jsonb not null default '[]'::jsonb,
  stock_status text not null,base_rate numeric(14,2) not null check(base_rate>=0),
  margin_amount numeric(14,2) not null default 0 check(margin_amount>=0),
  distributor_sale_rate numeric(14,2) not null check(distributor_sale_rate>=0),
  discount_amount numeric(14,2) not null default 0 check(discount_amount>=0),
  final_customer_rate numeric(14,2) not null check(final_customer_rate>=0),
  created_at timestamptz not null default now(),primary key(collection_id,lot_no)
);
alter table public.rr_market_partner_collection_line_v67 enable row level security;
revoke all on public.rr_market_partner_collection_line_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_collection_line_v67 to service_role;

create or replace function public.rr_market_partner_customer_bulk_vcf_v67(
 p_session_token text,p_device_id text,p_contacts jsonb
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_row jsonb;v_name text;v_mobile text;v_prefix text;v_no bigint;v_ref text;v_added int:=0;v_skipped int:=0;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 if jsonb_typeof(p_contacts)<>'array' then raise exception 'VCF contacts must be an array.';end if;
 select prefix into v_prefix from public.rr_market_owner_sequence_v67 where owner_key='CUSTOMER:'||v_owner::text and data_mode='TEST';
 if v_prefix is null then raise exception 'Distributor prefix is not configured.';end if;
 for v_row in select value from jsonb_array_elements(p_contacts) loop
  v_name:=nullif(trim(v_row->>'name'),'');v_mobile:=nullif(regexp_replace(coalesce(v_row->>'mobile',''),'[^0-9+]','','g'),'');
  if v_name is null or v_mobile is null or exists(select 1 from public.rr_market_partner_customer_v67 where owner_customer_id=v_owner and regexp_replace(coalesce(private_mobile,''),'[^0-9+]','','g')=v_mobile)then v_skipped:=v_skipped+1;continue;end if;
  select coalesce(max((regexp_match(customer_ref,'([0-9]+)$'))[1]::bigint),0)+1 into v_no from public.rr_market_partner_customer_v67 where owner_customer_id=v_owner and data_mode='TEST';
  v_ref:=v_prefix||'-C-'||lpad(v_no::text,4,'0');
  insert into public.rr_market_partner_customer_v67(owner_customer_id,customer_ref,private_name,private_mobile)values(v_owner,v_ref,v_name,v_mobile);v_added:=v_added+1;
 end loop;
 return jsonb_build_object('added',v_added,'skipped',v_skipped,'total',jsonb_array_length(p_contacts));
end $$;

create or replace function public.rr_market_partner_group_create_v67(p_session_token text,p_device_id text,p_name text,p_info text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_id uuid;begin v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
if nullif(trim(p_name),'')is null then raise exception 'Group name is required.';end if;
insert into public.rr_market_partner_group_v67(owner_customer_id,group_name,group_info)values(v_owner,trim(p_name),nullif(trim(p_info),''))returning id into v_id;
return jsonb_build_object('id',v_id,'group_name',trim(p_name));end $$;

create or replace function public.rr_market_partner_staff_create_v67(p_session_token text,p_device_id text,p_name text,p_mobile text,p_role text default 'SALES')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_id uuid;begin v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
if nullif(trim(p_name),'')is null then raise exception 'Staff name is required.';end if;
insert into public.rr_market_partner_staff_v67(owner_customer_id,staff_name,private_mobile,staff_role)values(v_owner,trim(p_name),nullif(regexp_replace(coalesce(p_mobile,''),'[^0-9+]','','g'),''),upper(coalesce(nullif(trim(p_role),''),'SALES')))returning id into v_id;
return jsonb_build_object('id',v_id,'staff_name',trim(p_name));end $$;

create or replace function public.rr_market_partner_cards_v67(p_session_token text,p_device_id text,p_search text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin perform public.rr_market_partner_context_v67(p_session_token,p_device_id);
return coalesce((select jsonb_agg((to_jsonb(x)-'available_qty')||jsonb_build_object('stock_label',case when coalesce(x.available_qty,0)<=0 then 'OUT OF STOCK' when upper(coalesce(x.stock_status,''))='LOW_STOCK' then 'LOW STOCK' else 'STOCK-IN' end)order by x.lot_no)from public.rr_web_window_cards_v9329(p_search,null,null,'TEST',150,0)x),'[]'::jsonb);end $$;

create or replace function public.rr_market_partner_collection_priced_create_v67(
 p_session_token text,p_device_id text,p_partner_customer_id uuid,p_lines jsonb
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;v_share uuid;v_collection uuid;v_token text;v_code text;v_name text;v_tries int:=0;v_line jsonb;v_card record;v_lot text;v_margin numeric;v_discount numeric;v_sale numeric;v_final numeric;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);if not(v_ctx->>'send_collection_enabled')::boolean then raise exception 'Collection sending is disabled.';end if;v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select private_name into v_name from public.rr_market_partner_customer_v67 where id=p_partner_customer_id and owner_customer_id=v_owner and status='ACTIVE';if v_name is null then raise exception 'Private customer not found.';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Select at least one lot.';end if;
 loop v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,10));begin insert into public.rr_market_share_v9420(customer_id,customer_name,data_mode,status,short_code)values(null,v_name,'TEST','ACTIVE',v_code)returning id,token into v_share,v_token;exit;exception when unique_violation then v_tries:=v_tries+1;if v_tries>8 then raise;end if;end;end loop;
 insert into public.rr_market_partner_collection_v67(owner_customer_id,partner_customer_id,share_id)values(v_owner,p_partner_customer_id,v_share)returning id into v_collection;
 for v_line in select value from jsonb_array_elements(p_lines)loop
  v_lot:=nullif(trim(v_line->>'lot_no'),'');v_margin:=greatest(0,coalesce((v_line->>'margin_amount')::numeric,0));v_discount:=greatest(0,coalesce((v_line->>'discount_amount')::numeric,0));
  select * into v_card from public.rr_web_window_cards_v9329(v_lot,null,null,'TEST',10,0)where lot_no=v_lot limit 1;if v_card.lot_no is null then raise exception 'TEST lot % is unavailable.',v_lot;end if;
  v_sale:=coalesce(v_card.sale_rate,0)+v_margin;v_final:=greatest(0,v_sale-v_discount);
  insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)values(v_share,v_lot,(select count(*)+1 from public.rr_market_share_lots_v9420 where share_id=v_share))on conflict do nothing;
  insert into public.rr_market_partner_collection_line_v67(collection_id,lot_no,category,cloth_name,primary_image_url,media,stock_status,base_rate,margin_amount,distributor_sale_rate,discount_amount,final_customer_rate)
  values(v_collection,v_lot,coalesce(v_card.category,''),v_card.cloth_name,v_card.primary_image_url,coalesce(v_card.media,'[]'::jsonb),case when coalesce(v_card.available_qty,0)<=0 then 'OUT OF STOCK' when upper(coalesce(v_card.stock_status,''))='LOW_STOCK' then 'LOW STOCK' else 'STOCK-IN' end,coalesce(v_card.sale_rate,0),v_margin,v_sale,v_discount,v_final);
 end loop;
 return jsonb_build_object('collection_id',v_collection,'share_id',v_share,'token',v_token,'short_code',v_code,'lot_count',(select count(*) from public.rr_market_partner_collection_line_v67 where collection_id=v_collection));
end $$;

create or replace function public.rr_market_share_view_v9420(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.rr_market_share_v9420%rowtype;rows jsonb;begin
select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE' order by case when token=p_token then 0 else 1 end limit 1;if not found then raise exception 'Share link unavailable.';end if;update public.rr_market_share_v9420 set last_opened_at=now()where id=s.id;
select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('cloth_name',coalesce(pl.cloth_name,r.cloth_name),'category',coalesce(pl.category,r.category),'item_name',r.item_name,'sale_rate',coalesce(pl.final_customer_rate,c.sale_rate),'display_sale_rate',coalesce(pl.distributor_sale_rate,c.sale_rate),'discount_amount',coalesce(pl.discount_amount,0),'stock_status',coalesce(pl.stock_status,c.stock_status),'hide_exact_stock',pl.collection_id is not null)order by l.sort_no),'[]'::jsonb)into rows
from public.rr_market_share_lots_v9420 l cross join lateral public.rr_web_window_cards_v9329(l.lot_no,null,null,s.data_mode,1,0)c cross join lateral public.rr_web_lot_fields_resolve_v9624(l.lot_no,s.data_mode)r
left join public.rr_market_partner_collection_v67 pc on pc.share_id=l.share_id left join public.rr_market_partner_collection_line_v67 pl on pl.collection_id=pc.id and pl.lot_no=l.lot_no where l.share_id=s.id and c.lot_no=l.lot_no;
return jsonb_build_object('share_id',s.id,'customer_name',s.customer_name,'created_at',s.created_at,'rows',rows);end $$;

create or replace function public.rr_market_partner_submit_requirement_v67(p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_map public.rr_market_partner_collection_v67%rowtype;v_result jsonb;v_req uuid;v_seq bigint;v_prefix text;v_ref text;v_order uuid;v_line record;v_price public.rr_market_partner_collection_line_v67%rowtype;
begin
select pc.* into v_map from public.rr_market_partner_collection_v67 pc join public.rr_market_share_v9420 s on s.id=pc.share_id where(s.token=p_token or s.short_code=upper(p_token))and s.data_mode='TEST' and s.status='ACTIVE';
v_result:=public.rr_market_submit_requirement_v9508(p_token,p_customer_name,p_mobile,p_message,p_lines,null);if v_map.id is null then return v_result;end if;v_req:=(v_result->>'requirement_id')::uuid;
select prefix,current_no+1 into v_prefix,v_seq from public.rr_market_owner_sequence_v67 where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST' for update;if v_prefix is null then raise exception 'Distributor prefix is not configured.';end if;
update public.rr_market_owner_sequence_v67 set current_no=v_seq,updated_at=now()where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST';v_ref:=v_prefix||'-'||lpad(v_seq::text,3,'0');
insert into public.rr_market_partner_order_v67(owner_customer_id,partner_customer_id,sequence_no,order_ref,status,linked_requirement_id)values(v_map.owner_customer_id,v_map.partner_customer_id,v_seq,v_ref,'READY',v_req)returning id into v_order;
for v_line in select l.* from public.rr_market_requirement_lines_v9420 l where l.requirement_id=v_req loop
 select * into v_price from public.rr_market_partner_collection_line_v67 where collection_id=v_map.id and lot_no=v_line.lot_no;
 insert into public.rr_market_partner_order_line_v67(order_id,lot_no,article_name,image_url,requested_qty,base_rate,rate_enhancement,customer_discount,final_customer_rate)
 values(v_order,v_line.lot_no,coalesce(v_price.category,v_line.lot_no),v_price.primary_image_url,v_line.accepted_qty,v_price.base_rate,v_price.margin_amount,v_price.discount_amount,v_price.final_customer_rate);
end loop;
update public.rr_market_partner_collection_v67 set requirement_id=v_req,order_id=v_order,status='REQUIREMENT_RECEIVED',updated_at=now()where id=v_map.id;
insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)values(v_map.owner_customer_id,v_order,'COLLECTION_REQUIREMENT_RECEIVED','SYSTEM',jsonb_build_object('order_ref',v_ref,'share_id',v_map.share_id));
return v_result||jsonb_build_object('order_id',v_order,'order_ref',v_ref,'requirement_no',v_ref);end $$;

create or replace function public.rr_market_partner_workspace_v67(p_session_token text,p_device_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;begin v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);v_owner:=(v_ctx->>'owner_customer_id')::uuid;
return v_ctx||jsonb_build_object(
'customers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'customer_ref',c.customer_ref,'name',c.private_name,'mobile',c.private_mobile,'status',c.status,'group_id',c.group_id,'margin',c.default_margin_amount,'discount',c.default_discount_amount)order by c.customer_ref)from public.rr_market_partner_customer_v67 c where c.owner_customer_id=v_owner),'[]'::jsonb),
'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.group_name,'info',g.group_info,'status',g.status)order by g.group_name)from public.rr_market_partner_group_v67 g where g.owner_customer_id=v_owner),'[]'::jsonb),
'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.staff_name,'mobile',s.private_mobile,'role',s.staff_role,'status',s.status)order by s.staff_name)from public.rr_market_partner_staff_v67 s where s.owner_customer_id=v_owner),'[]'::jsonb),
'collections',coalesce((select jsonb_agg(jsonb_build_object('id',pc.id,'customer_id',pc.partner_customer_id,'customer_ref',c.customer_ref,'status',pc.status,'created_at',pc.created_at,'lot_count',(select count(*)from public.rr_market_partner_collection_line_v67 pl where pl.collection_id=pc.id))order by pc.created_at desc)from public.rr_market_partner_collection_v67 pc join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id where pc.owner_customer_id=v_owner),'[]'::jsonb),
'orders',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,'status',o.status,'customer_id',o.partner_customer_id,'customer_ref',c.customer_ref,'customer_name',c.private_name,'pi_ref',o.pi_ref,'ci_ref',o.ci_ref,'created_at',o.created_at,'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,'image_url',l.image_url,'requested_qty',l.requested_qty,'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,'base_rate',l.base_rate,'rate_enhancement',l.rate_enhancement,'sale_rate',l.customer_rate,'discount',l.customer_discount,'final_rate',l.final_customer_rate,'confirmation_status',l.confirmation_status)order by l.lot_no)from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))order by o.sequence_no desc)from public.rr_market_partner_order_v67 o join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id where o.owner_customer_id=v_owner),'[]'::jsonb),
'summary',(select jsonb_build_object('present_qty',coalesce(sum(case when o.id=last_order.id then l.requested_qty else 0 end),0),'present_amount',coalesce(sum(case when o.id=last_order.id then l.requested_qty*l.final_customer_rate else 0 end),0),'present_average',coalesce(round(sum(case when o.id=last_order.id then l.requested_qty*l.final_customer_rate else 0 end)/nullif(sum(case when o.id=last_order.id then l.requested_qty else 0 end),0),2),0),'all_qty',coalesce(sum(l.requested_qty),0),'all_amount',coalesce(sum(l.requested_qty*l.final_customer_rate),0),'all_average',coalesce(round(sum(l.requested_qty*l.final_customer_rate)/nullif(sum(l.requested_qty),0),2),0))from public.rr_market_partner_order_v67 o join public.rr_market_partner_order_line_v67 l on l.order_id=o.id cross join lateral(select id from public.rr_market_partner_order_v67 where owner_customer_id=v_owner order by sequence_no desc limit 1)last_order where o.owner_customer_id=v_owner and o.status<>'CANCELLED'),
'batches',coalesce((select jsonb_agg(jsonb_build_object('id',id,'batch_ref',batch_ref,'status',status,'pi_ref',pi_ref,'ci_ref',ci_ref,'submitted_at',submitted_at)order by submitted_at desc)from public.rr_market_partner_batch_v67 where owner_customer_id=v_owner),'[]'::jsonb));end $$;

revoke all on function public.rr_market_partner_customer_bulk_vcf_v67(text,text,jsonb)from public;
revoke all on function public.rr_market_partner_group_create_v67(text,text,text,text)from public;
revoke all on function public.rr_market_partner_staff_create_v67(text,text,text,text,text)from public;
revoke all on function public.rr_market_partner_cards_v67(text,text,text)from public;
revoke all on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb)from public;
revoke all on function public.rr_market_share_view_v9420(text)from public;
revoke all on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)from public;
revoke all on function public.rr_market_partner_workspace_v67(text,text)from public;
grant execute on function public.rr_market_partner_customer_bulk_vcf_v67(text,text,jsonb)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_group_create_v67(text,text,text,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_staff_create_v67(text,text,text,text,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_cards_v67(text,text,text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb)to anon,authenticated,service_role;
grant execute on function public.rr_market_share_view_v9420(text)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb)to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_workspace_v67(text,text)to anon,authenticated,service_role;
