-- V9745: permanent cross-module party map for chat/customer/distributor -> sales -> CI/lot/RCI.
-- Additive and idempotent: existing PI, CI, sale quantities and RCI quantities are not rewritten.
begin;

create table if not exists public.rr_customer_sales_map_v9745(
  id uuid primary key default gen_random_uuid(),
  source_kind text not null check(source_kind in('REDZED_CUSTOMER','DISTRIBUTOR_CUSTOMER')),
  customer_id uuid references public.rr_customers(id) on delete restrict,
  partner_customer_id uuid references public.rr_market_partner_customer_v67(id) on delete restrict,
  buyer_id uuid not null references public.rr_buyers_v787(id) on delete restrict,
  canonical_name text not null,
  canonical_mobile text,
  match_basis text not null check(match_basis in('CUSTOMER_ID','MOBILE','EXACT_NAME','CREATED')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check((source_kind='REDZED_CUSTOMER' and customer_id is not null and partner_customer_id is null)
     or (source_kind='DISTRIBUTOR_CUSTOMER' and partner_customer_id is not null and customer_id is null))
);

create unique index if not exists rr_customer_sales_map_customer_v9745
  on public.rr_customer_sales_map_v9745(customer_id) where customer_id is not null;
create unique index if not exists rr_customer_sales_map_partner_v9745
  on public.rr_customer_sales_map_v9745(partner_customer_id) where partner_customer_id is not null;
create index if not exists rr_customer_sales_map_buyer_v9745
  on public.rr_customer_sales_map_v9745(buyer_id,is_active);
create index if not exists rr_customer_sales_map_mobile_v9745
  on public.rr_customer_sales_map_v9745(canonical_mobile) where canonical_mobile is not null;

alter table public.rr_customer_sales_map_v9745 enable row level security;
revoke all on public.rr_customer_sales_map_v9745 from public,anon,authenticated;

create or replace function public.rr_customer_sales_map_sync_v9745(
  p_source_kind text,p_source_id uuid,p_name text,p_mobile text,p_active boolean default true
) returns uuid
language plpgsql security definer set search_path='public'
as $function$
declare
  v_kind text:=upper(trim(coalesce(p_source_kind,'')));
  v_name text:=trim(coalesce(p_name,''));
  v_mobile text:=right(regexp_replace(coalesce(p_mobile,''),'\D','','g'),10);
  v_buyer uuid; v_basis text;
begin
  if v_kind not in('REDZED_CUSTOMER','DISTRIBUTOR_CUSTOMER') or p_source_id is null or v_name='' then
    raise exception 'Canonical party source, id and name required.';
  end if;

  if v_kind='REDZED_CUSTOMER' then
    select buyer_id into v_buyer from public.rr_customer_sales_map_v9745 where customer_id=p_source_id;
  else
    select buyer_id into v_buyer from public.rr_customer_sales_map_v9745 where partner_customer_id=p_source_id;
  end if;
  if v_buyer is not null then v_basis:='CUSTOMER_ID'; end if;

  if v_buyer is null and length(v_mobile)=10 then
    select id into v_buyer from public.rr_buyers_v787
    where right(regexp_replace(coalesce(contact_no,''),'\D','','g'),10)=v_mobile
    order by active desc nulls last,id limit 1;
    if v_buyer is not null then v_basis:='MOBILE'; end if;
  end if;
  if v_buyer is null then
    select id into v_buyer from public.rr_buyers_v787
    where lower(trim(buyer_name))=lower(v_name)
    order by active desc nulls last,id limit 1;
    if v_buyer is not null then v_basis:='EXACT_NAME'; end if;
  end if;
  if v_buyer is null then
    insert into public.rr_buyers_v787(buyer_name,contact_no,discount_type,discount_value,active)
    values(v_name,nullif(p_mobile,''),'PER_PIECE',0,coalesce(p_active,true)) returning id into v_buyer;
    v_basis:='CREATED';
  else
    update public.rr_buyers_v787 set
      buyer_name=v_name,
      contact_no=coalesce(nullif(p_mobile,''),contact_no),
      active=coalesce(p_active,true)
    where id=v_buyer;
  end if;

  if v_kind='REDZED_CUSTOMER' then
    insert into public.rr_customer_sales_map_v9745(source_kind,customer_id,buyer_id,canonical_name,canonical_mobile,match_basis,is_active)
    values(v_kind,p_source_id,v_buyer,v_name,nullif(v_mobile,''),v_basis,coalesce(p_active,true))
    on conflict(customer_id) where customer_id is not null do update set
      buyer_id=excluded.buyer_id,canonical_name=excluded.canonical_name,canonical_mobile=excluded.canonical_mobile,
      match_basis=excluded.match_basis,is_active=excluded.is_active,updated_at=now();
  else
    insert into public.rr_customer_sales_map_v9745(source_kind,partner_customer_id,buyer_id,canonical_name,canonical_mobile,match_basis,is_active)
    values(v_kind,p_source_id,v_buyer,v_name,nullif(v_mobile,''),v_basis,coalesce(p_active,true))
    on conflict(partner_customer_id) where partner_customer_id is not null do update set
      buyer_id=excluded.buyer_id,canonical_name=excluded.canonical_name,canonical_mobile=excluded.canonical_mobile,
      match_basis=excluded.match_basis,is_active=excluded.is_active,updated_at=now();
  end if;
  return v_buyer;
end
$function$;

revoke all on function public.rr_customer_sales_map_sync_v9745(text,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.rr_customer_sales_map_sync_v9745(text,uuid,text,text,boolean) to service_role;
commit;
