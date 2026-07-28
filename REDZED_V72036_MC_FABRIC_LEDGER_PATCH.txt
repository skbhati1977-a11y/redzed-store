-- REDZED REAL — V720.36
-- MC1 fabric-name consolidated stock + drill-down ledger + lot reservation bridge
-- Run once AFTER the existing V720.35 / V720.3 Product Master SQL.
--
-- Locked architecture:
--   MC1 remains one parent card.
--   Stock is consolidated by a stable Matching Fabric ID/name.
--   Bills remain separate in the purchase ledger.
--   Cutting selects Fabric Name · Available Qty · Weighted Avg Rate.
--   Lot matching is reserved before release and confirmed after release.
--   Old purchase/bill history is never overwritten.

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Role / permission foundation
-- ---------------------------------------------------------------------------
create or replace function public.rr_role_can_view_financials_v1()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(public.rr_current_role(), '')) in (
    'owner','admin','account','accounts'
  );
$$;

grant execute on function public.rr_role_can_view_financials_v1() to authenticated;

-- ---------------------------------------------------------------------------
-- Stable Matching Fabric Name master
-- ---------------------------------------------------------------------------
create or replace function public.rr_normalize_mc_fabric_name_v1(p_name text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(p_name,'')), '[^[:alnum:]]+', '', 'g'));
$$;

create table if not exists public.rr_mc1_fabrics (
  id uuid primary key default gen_random_uuid(),
  mc_account_id uuid not null references public.rr_mc1_account(id),
  fabric_name text not null,
  normalized_name text not null,
  current_qty numeric(18,3) not null default 0 check (current_qty >= 0),
  current_value numeric(18,2) not null default 0 check (current_value >= 0),
  avg_rate numeric(18,4) not null default 0 check (avg_rate >= 0),
  total_purchase_qty numeric(18,3) not null default 0 check (total_purchase_qty >= 0),
  total_consumption_qty numeric(18,3) not null default 0 check (total_consumption_qty >= 0),
  total_gr_qty numeric(18,3) not null default 0 check (total_gr_qty >= 0),
  total_exchange_qty numeric(18,3) not null default 0 check (total_exchange_qty >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (mc_account_id, normalized_name)
);

create index if not exists rr_mc1_fabrics_name_idx
  on public.rr_mc1_fabrics(normalized_name);

alter table public.rr_mc1_purchases
  add column if not exists fabric_id uuid references public.rr_mc1_fabrics(id);
alter table public.rr_mc1_purchases
  add column if not exists fabric_name text;

alter table public.rr_mc1_ledger
  add column if not exists fabric_id uuid references public.rr_mc1_fabrics(id);
alter table public.rr_mc1_ledger
  add column if not exists fabric_balance_qty numeric(18,3);
alter table public.rr_mc1_ledger
  add column if not exists fabric_balance_value numeric(18,2);
alter table public.rr_mc1_ledger
  add column if not exists fabric_avg_rate_after numeric(18,4);

-- Backfill old MC1 purchases. If an older patch already stored a name, preserve it.
update public.rr_mc1_purchases
set fabric_name = coalesce(nullif(trim(fabric_name), ''), 'Legacy Matching Cloth')
where fabric_name is null or trim(fabric_name) = '';

insert into public.rr_mc1_fabrics (
  mc_account_id, fabric_name, normalized_name
)
select distinct
  p.mc_account_id,
  p.fabric_name,
  public.rr_normalize_mc_fabric_name_v1(p.fabric_name)
from public.rr_mc1_purchases p
where public.rr_normalize_mc_fabric_name_v1(p.fabric_name) <> ''
on conflict (mc_account_id, normalized_name) do nothing;

update public.rr_mc1_purchases p
set fabric_id = f.id,
    fabric_name = f.fabric_name
from public.rr_mc1_fabrics f
where p.fabric_id is null
  and f.mc_account_id = p.mc_account_id
  and f.normalized_name = public.rr_normalize_mc_fabric_name_v1(p.fabric_name);

-- Purchase/Exchange ledger rows can be linked directly through reference purchase.
update public.rr_mc1_ledger l
set fabric_id = p.fabric_id
from public.rr_mc1_purchases p
where l.fabric_id is null
  and l.reference_id = p.id
  and p.fabric_id is not null;

-- Any still-unassigned legacy movement is kept in one explicit legacy pool.
do $backfill_legacy_mc$
declare
  v_account public.rr_mc1_account%rowtype;
  v_legacy_id uuid;
begin
  select * into v_account
  from public.rr_mc1_account
  where mc_no = 'MC1'
  limit 1;

  if not found then
    return;
  end if;

  insert into public.rr_mc1_fabrics (
    mc_account_id, fabric_name, normalized_name
  ) values (
    v_account.id,
    'Legacy Matching Cloth',
    public.rr_normalize_mc_fabric_name_v1('Legacy Matching Cloth')
  )
  on conflict (mc_account_id, normalized_name)
  do update set fabric_name = excluded.fabric_name
  returning id into v_legacy_id;

  update public.rr_mc1_ledger
  set fabric_id = v_legacy_id
  where fabric_id is null
    and mc_account_id = v_account.id;

  update public.rr_mc1_purchases
  set fabric_id = v_legacy_id,
      fabric_name = 'Legacy Matching Cloth'
  where fabric_id is null
    and mc_account_id = v_account.id;
end
$backfill_legacy_mc$;

-- Rebuild fabric totals from the permanent ledger.
with totals as (
  select
    f.id as fabric_id,
    coalesce(sum(l.qty_in),0)::numeric(18,3) as qty_in,
    coalesce(sum(l.qty_out),0)::numeric(18,3) as qty_out,
    coalesce(sum(l.value_in),0)::numeric(18,2) as value_in,
    coalesce(sum(l.value_out),0)::numeric(18,2) as value_out,
    coalesce(sum(case when l.entry_type in ('PURCHASE_IN','EXCHANGE_IN') then l.qty_in else 0 end),0)::numeric(18,3) as purchase_qty,
    coalesce(sum(case when l.entry_type = 'LOT_CONSUMPTION_OUT' and l.reversed_at is null then l.qty_out else 0 end),0)::numeric(18,3) as consumption_qty,
    coalesce(sum(case when l.entry_type = 'PURCHASE_GR_OUT' then l.qty_out else 0 end),0)::numeric(18,3) as gr_qty,
    coalesce(sum(case when l.entry_type = 'EXCHANGE_IN' then l.qty_in else 0 end),0)::numeric(18,3) as exchange_qty
  from public.rr_mc1_fabrics f
  left join public.rr_mc1_ledger l on l.fabric_id = f.id
  group by f.id
)
update public.rr_mc1_fabrics f
set current_qty = greatest(0, round(t.qty_in - t.qty_out, 3)),
    current_value = greatest(0, round(t.value_in - t.value_out, 2)),
    avg_rate = case when round(t.qty_in - t.qty_out,3) > 0
      then round(greatest(0,t.value_in-t.value_out) / round(t.qty_in-t.qty_out,3),4)
      else 0 end,
    total_purchase_qty = t.purchase_qty,
    total_consumption_qty = t.consumption_qty,
    total_gr_qty = t.gr_qty,
    total_exchange_qty = t.exchange_qty,
    updated_at = now()
from totals t
where t.fabric_id = f.id;

-- If old parent balance has a small legacy difference, preserve it in Legacy pool.
do $balance_parent_difference$
declare
  v_account public.rr_mc1_account%rowtype;
  v_sum_qty numeric(18,3);
  v_sum_value numeric(18,2);
  v_legacy public.rr_mc1_fabrics%rowtype;
  v_diff_qty numeric(18,3);
  v_diff_value numeric(18,2);
begin
  select * into v_account from public.rr_mc1_account where mc_no='MC1' limit 1;
  if not found then return; end if;

  select coalesce(sum(current_qty),0), coalesce(sum(current_value),0)
  into v_sum_qty, v_sum_value
  from public.rr_mc1_fabrics
  where mc_account_id = v_account.id;

  v_diff_qty := round(v_account.current_qty - v_sum_qty,3);
  v_diff_value := round(v_account.current_value - v_sum_value,2);

  if abs(v_diff_qty) > 0.0005 or abs(v_diff_value) > 0.01 then
    select * into v_legacy
    from public.rr_mc1_fabrics
    where mc_account_id=v_account.id
      and normalized_name=public.rr_normalize_mc_fabric_name_v1('Legacy Matching Cloth')
    for update;

    update public.rr_mc1_fabrics
    set current_qty = greatest(0,round(current_qty+v_diff_qty,3)),
        current_value = greatest(0,round(current_value+v_diff_value,2)),
        avg_rate = case when greatest(0,round(current_qty+v_diff_qty,3)) > 0
          then round(greatest(0,round(current_value+v_diff_value,2)) /
                     greatest(0,round(current_qty+v_diff_qty,3)),4)
          else 0 end,
        updated_at=now()
    where id=v_legacy.id;
  end if;
end
$balance_parent_difference$;

-- ---------------------------------------------------------------------------
-- Lot matching reservation / posting bridge
-- ---------------------------------------------------------------------------
create table if not exists public.rr_mc1_lot_matchings_v2 (
  id uuid primary key default gen_random_uuid(),
  fabric_id uuid not null references public.rr_mc1_fabrics(id),
  lot_no text not null,
  qty numeric(18,3) not null check (qty > 0),
  avg_rate_snapshot numeric(18,4) not null check (avg_rate_snapshot >= 0),
  total_cost numeric(18,2) not null check (total_cost >= 0),
  status text not null default 'RESERVED' check (status in ('RESERVED','POSTED','CANCELLED','REVERSED')),
  expires_at timestamptz,
  ledger_id uuid references public.rr_mc1_ledger(id),
  source_id uuid,
  source_kind text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  posted_at timestamptz,
  cancelled_at timestamptz,
  remarks text
);

create unique index if not exists rr_mc1_lot_matching_active_uq
  on public.rr_mc1_lot_matchings_v2(lower(lot_no))
  where status in ('RESERVED','POSTED');

create index if not exists rr_mc1_lot_matching_fabric_idx
  on public.rr_mc1_lot_matchings_v2(fabric_id,status,expires_at);

create or replace function public.rr_lot_exists_v2(p_lot_no text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_exists boolean := false;
begin
  if to_regclass('public.rr_cutting_lots_v3') is not null then
    execute 'select exists(select 1 from public.rr_cutting_lots_v3 where upper(trim(lot_no))=upper(trim($1)))'
      into v_exists using p_lot_no;
    if v_exists then return true; end if;
  end if;

  if to_regclass('public.rr_production_lots') is not null then
    execute 'select exists(select 1 from public.rr_production_lots where upper(trim(lot_no))=upper(trim($1)))'
      into v_exists using p_lot_no;
  end if;

  return coalesce(v_exists,false);
end;
$$;

create or replace function public.rr_reserve_lot_matching_v2(
  p_fabric_id uuid,
  p_lot_no text,
  p_qty numeric,
  p_source_kind text default 'CUTTING_MASTER',
  p_remarks text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fabric public.rr_mc1_fabrics%rowtype;
  v_existing public.rr_mc1_lot_matchings_v2%rowtype;
  v_reserved numeric(18,3);
  v_qty numeric(18,3) := round(coalesce(p_qty,0),3);
  v_lot text := upper(trim(coalesce(p_lot_no,'')));
  v_cost numeric(18,2);
  v_financial boolean := public.rr_role_can_view_financials_v1();
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_lot='' then raise exception 'Lot No required.'; end if;
  if v_qty<=0 then raise exception 'Matching Qty must be greater than zero.'; end if;

  update public.rr_mc1_lot_matchings_v2
  set status='CANCELLED', cancelled_at=now(), remarks=coalesce(remarks,'')||' · Reservation expired'
  where status='RESERVED' and expires_at < now();

  select * into v_existing
  from public.rr_mc1_lot_matchings_v2
  where lower(lot_no)=lower(v_lot)
    and status in ('RESERVED','POSTED')
  for update;

  if found then
    if v_existing.status='POSTED' then
      raise exception 'Matching Cloth is already posted for Lot %.',v_lot;
    end if;
    if v_existing.fabric_id<>p_fabric_id then
      raise exception 'Lot % already has another Matching Fabric reservation.',v_lot;
    end if;
  end if;

  select * into v_fabric
  from public.rr_mc1_fabrics
  where id=p_fabric_id and is_active=true
  for update;
  if not found then raise exception 'Matching Fabric stock item not found.'; end if;

  select coalesce(sum(qty),0) into v_reserved
  from public.rr_mc1_lot_matchings_v2
  where fabric_id=p_fabric_id
    and status='RESERVED'
    and expires_at>=now()
    and lower(lot_no)<>lower(v_lot);

  if v_qty > v_fabric.current_qty-v_reserved+0.0005 then
    raise exception '% balance is % kg; available after reservations is % kg.',
      v_fabric.fabric_name,v_fabric.current_qty,round(v_fabric.current_qty-v_reserved,3);
  end if;

  v_cost:=round(v_qty*v_fabric.avg_rate,2);

  if v_existing.id is not null then
    update public.rr_mc1_lot_matchings_v2
    set qty=v_qty,avg_rate_snapshot=v_fabric.avg_rate,total_cost=v_cost,
        expires_at=now()+interval '30 minutes',source_kind=coalesce(p_source_kind,'CUTTING_MASTER'),
        remarks=nullif(trim(p_remarks),''),created_by=auth.uid()
    where id=v_existing.id
    returning * into v_existing;
  else
    insert into public.rr_mc1_lot_matchings_v2(
      fabric_id,lot_no,qty,avg_rate_snapshot,total_cost,status,expires_at,
      source_kind,remarks
    ) values (
      p_fabric_id,v_lot,v_qty,v_fabric.avg_rate,v_cost,'RESERVED',now()+interval '30 minutes',
      coalesce(p_source_kind,'CUTTING_MASTER'),nullif(trim(p_remarks),'')
    ) returning * into v_existing;
  end if;

  return jsonb_build_object(
    'reservation_id',v_existing.id,
    'matching_item_id',v_fabric.id,
    'fabric_name',v_fabric.fabric_name,
    'qty',v_existing.qty,
    'avg_rate_snapshot',case when v_financial then v_existing.avg_rate_snapshot else 0 end,
    'total_cost',case when v_financial then v_existing.total_cost else 0 end,
    'expires_at',v_existing.expires_at,
    'status',v_existing.status
  );
end;
$$;

create or replace function public.rr_confirm_lot_matching_v2(
  p_lot_no text,
  p_source_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.rr_mc1_lot_matchings_v2%rowtype;
  v_fabric public.rr_mc1_fabrics%rowtype;
  v_account public.rr_mc1_account%rowtype;
  v_ledger public.rr_mc1_ledger%rowtype;
  v_fabric_qty numeric(18,3);
  v_fabric_value numeric(18,2);
  v_fabric_avg numeric(18,4);
  v_parent_qty numeric(18,3);
  v_parent_value numeric(18,2);
  v_parent_avg numeric(18,4);
  v_financial boolean := public.rr_role_can_view_financials_v1();
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;

  select * into v_match
  from public.rr_mc1_lot_matchings_v2
  where lower(lot_no)=lower(trim(p_lot_no))
    and status in ('RESERVED','POSTED')
  for update;
  if not found then raise exception 'Matching reservation not found for Lot %.',p_lot_no; end if;

  if v_match.status='POSTED' then
    return jsonb_build_object(
      'status','POSTED','lot_no',v_match.lot_no,'fabric_id',v_match.fabric_id,
      'qty',v_match.qty,
      'avg_rate_snapshot',case when v_financial then v_match.avg_rate_snapshot else 0 end,
      'total_cost',case when v_financial then v_match.total_cost else 0 end,
      'ledger_id',v_match.ledger_id
    );
  end if;

  if not public.rr_lot_exists_v2(v_match.lot_no) then
    raise exception 'Released Lot % not found yet. Reservation remains pending.',v_match.lot_no;
  end if;

  select * into v_fabric from public.rr_mc1_fabrics where id=v_match.fabric_id for update;
  if not found then raise exception 'Matching Fabric stock item not found.'; end if;
  select * into v_account from public.rr_mc1_account where id=v_fabric.mc_account_id for update;

  if v_match.qty>v_fabric.current_qty+0.0005 then
    raise exception '% balance is % kg; reserved Qty is % kg.',v_fabric.fabric_name,v_fabric.current_qty,v_match.qty;
  end if;

  v_fabric_qty:=round(v_fabric.current_qty-v_match.qty,3);
  v_fabric_value:=greatest(0,round(v_fabric.current_value-v_match.total_cost,2));
  v_fabric_avg:=case when v_fabric_qty>0 then round(v_fabric_value/v_fabric_qty,4) else 0 end;
  v_parent_qty:=round(v_account.current_qty-v_match.qty,3);
  v_parent_value:=greatest(0,round(v_account.current_value-v_match.total_cost,2));
  v_parent_avg:=case when v_parent_qty>0 then round(v_parent_value/v_parent_qty,4) else 0 end;

  update public.rr_mc1_fabrics
  set current_qty=v_fabric_qty,current_value=v_fabric_value,avg_rate=v_fabric_avg,
      total_consumption_qty=round(total_consumption_qty+v_match.qty,3),updated_at=now()
  where id=v_fabric.id;

  update public.rr_mc1_account
  set current_qty=v_parent_qty,current_value=v_parent_value,avg_rate=v_parent_avg,
      total_consumption_qty=round(total_consumption_qty+v_match.qty,3),updated_at=now()
  where id=v_account.id;

  insert into public.rr_mc1_ledger(
    mc_account_id,fabric_id,entry_type,reference_id,lot_no,
    qty_out,rate_snapshot,value_out,balance_qty,balance_value,avg_rate_after,
    fabric_balance_qty,fabric_balance_value,fabric_avg_rate_after,occurred_at,remarks
  ) values (
    v_account.id,v_fabric.id,'LOT_CONSUMPTION_OUT',coalesce(p_source_id,v_match.id),v_match.lot_no,
    v_match.qty,v_match.avg_rate_snapshot,v_match.total_cost,
    v_parent_qty,v_parent_value,v_parent_avg,
    v_fabric_qty,v_fabric_value,v_fabric_avg,now(),
    concat(v_fabric.fabric_name,' · Lot matching consumption')
  ) returning * into v_ledger;

  update public.rr_mc1_lot_matchings_v2
  set status='POSTED',ledger_id=v_ledger.id,source_id=coalesce(p_source_id,source_id),posted_at=now()
  where id=v_match.id
  returning * into v_match;

  return jsonb_build_object(
    'status','POSTED','lot_no',v_match.lot_no,'fabric_id',v_fabric.id,
    'fabric_name',v_fabric.fabric_name,'qty',v_match.qty,
    'avg_rate_snapshot',case when v_financial then v_match.avg_rate_snapshot else 0 end,
    'total_cost',case when v_financial then v_match.total_cost else 0 end,
    'ledger_id',v_ledger.id
  );
end;
$$;

create or replace function public.rr_cancel_lot_matching_v2(
  p_lot_no text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_match public.rr_mc1_lot_matchings_v2%rowtype;
begin
  select * into v_match
  from public.rr_mc1_lot_matchings_v2
  where lower(lot_no)=lower(trim(p_lot_no)) and status='RESERVED'
  for update;
  if not found then return jsonb_build_object('status','NOTHING_TO_CANCEL','lot_no',upper(trim(p_lot_no))); end if;

  update public.rr_mc1_lot_matchings_v2
  set status='CANCELLED',cancelled_at=now(),remarks=coalesce(remarks,'')||
    case when nullif(trim(p_reason),'') is null then '' else ' · '||trim(p_reason) end
  where id=v_match.id;
  return jsonb_build_object('status','CANCELLED','lot_no',v_match.lot_no);
end;
$$;

create or replace function public.rr_recover_lot_matching_v2()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r record; v_result jsonb; v_count integer:=0;
begin
  for r in
    select lot_no from public.rr_mc1_lot_matchings_v2
    where status='RESERVED' and expires_at>=now()
      and public.rr_lot_exists_v2(lot_no)
  loop
    v_result:=public.rr_confirm_lot_matching_v2(r.lot_no,null);
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('confirmed',v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- Name-wise purchase posting
-- ---------------------------------------------------------------------------
create or replace function public.rr_post_mc_fabric_purchase_v2(
  p_fabric_name text,
  p_vendor_name text,
  p_bill_no text,
  p_bill_qty numeric,
  p_bill_value numeric,
  p_bill_date date default current_date,
  p_remarks text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.rr_mc1_account%rowtype;
  v_fabric public.rr_mc1_fabrics%rowtype;
  v_purchase public.rr_mc1_purchases%rowtype;
  v_name text:=trim(coalesce(p_fabric_name,''));
  v_norm text:=public.rr_normalize_mc_fabric_name_v1(p_fabric_name);
  v_rate numeric(18,4);
  v_f_qty numeric(18,3); v_f_value numeric(18,2); v_f_avg numeric(18,4);
  v_p_qty numeric(18,3); v_p_value numeric(18,2); v_p_avg numeric(18,4);
begin
  perform public.rr_product_require_admin_v1();
  if v_name='' or v_norm='' then raise exception 'Matching Fabric Name required.'; end if;
  if nullif(trim(p_vendor_name),'') is null then raise exception 'Vendor Name required.'; end if;
  if nullif(trim(p_bill_no),'') is null then raise exception 'Bill No required.'; end if;
  if coalesce(p_bill_qty,0)<=0 then raise exception 'Bill Qty must be greater than zero.'; end if;
  if coalesce(p_bill_value,0)<=0 then raise exception 'Bill Value must be greater than zero.'; end if;

  select * into v_account from public.rr_mc1_account where mc_no='MC1' for update;

  insert into public.rr_mc1_fabrics(mc_account_id,fabric_name,normalized_name)
  values(v_account.id,v_name,v_norm)
  on conflict(mc_account_id,normalized_name)
  do update set fabric_name=excluded.fabric_name,is_active=true,updated_at=now()
  returning * into v_fabric;

  v_rate:=round(p_bill_value/p_bill_qty,4);
  v_f_qty:=round(v_fabric.current_qty+p_bill_qty,3);
  v_f_value:=round(v_fabric.current_value+p_bill_value,2);
  v_f_avg:=case when v_f_qty>0 then round(v_f_value/v_f_qty,4) else 0 end;
  v_p_qty:=round(v_account.current_qty+p_bill_qty,3);
  v_p_value:=round(v_account.current_value+p_bill_value,2);
  v_p_avg:=case when v_p_qty>0 then round(v_p_value/v_p_qty,4) else 0 end;

  insert into public.rr_mc1_purchases(
    mc_account_id,fabric_id,fabric_name,vendor_name,bill_no,bill_date,
    bill_qty,bill_value,bill_rate,remarks,entry_kind,operation_status
  ) values(
    v_account.id,v_fabric.id,v_fabric.fabric_name,trim(p_vendor_name),upper(trim(p_bill_no)),
    coalesce(p_bill_date,current_date),round(p_bill_qty,3),round(p_bill_value,2),v_rate,
    nullif(trim(p_remarks),''),'PURCHASE','ACTIVE'
  ) returning * into v_purchase;

  update public.rr_mc1_fabrics
  set current_qty=v_f_qty,current_value=v_f_value,avg_rate=v_f_avg,
      total_purchase_qty=round(total_purchase_qty+p_bill_qty,3),updated_at=now()
  where id=v_fabric.id;

  update public.rr_mc1_account
  set current_qty=v_p_qty,current_value=v_p_value,avg_rate=v_p_avg,
      total_purchase_qty=round(total_purchase_qty+p_bill_qty,3),updated_at=now()
  where id=v_account.id;

  insert into public.rr_mc1_ledger(
    mc_account_id,fabric_id,entry_type,reference_id,qty_in,rate_snapshot,value_in,
    balance_qty,balance_value,avg_rate_after,
    fabric_balance_qty,fabric_balance_value,fabric_avg_rate_after,occurred_at,remarks
  ) values(
    v_account.id,v_fabric.id,'PURCHASE_IN',v_purchase.id,round(p_bill_qty,3),v_rate,round(p_bill_value,2),
    v_p_qty,v_p_value,v_p_avg,v_f_qty,v_f_value,v_f_avg,v_purchase.posted_at,
    concat(v_fabric.fabric_name,' · Vendor: ',trim(p_vendor_name),' · Bill: ',upper(trim(p_bill_no)))
  );

  return jsonb_build_object('purchase',to_jsonb(v_purchase),'fabric',to_jsonb(v_fabric),
    'card',(select to_jsonb(a) from public.rr_mc1_account a where a.id=v_account.id));
end;
$$;

-- Keep the legacy purchase RPC functional by routing it to an explicit legacy pool.
create or replace function public.rr_post_mc_purchase_v1(
  p_vendor_name text,
  p_bill_no text,
  p_bill_qty numeric,
  p_bill_value numeric,
  p_bill_date date default current_date,
  p_remarks text default null
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.rr_post_mc_fabric_purchase_v2(
    'Legacy Matching Cloth',p_vendor_name,p_bill_no,p_bill_qty,p_bill_value,p_bill_date,p_remarks
  );
$$;

-- ---------------------------------------------------------------------------
-- Name-aware MC GR and Exchange overrides (same public signatures)
-- ---------------------------------------------------------------------------
create or replace function public.rr_post_mc_gr_v1(
  p_mc_purchase_id uuid,
  p_gr_mode text,
  p_qty numeric default null,
  p_gr_date date default current_date,
  p_reason text default null,
  p_remarks text default null,
  p_exchange_expected boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_purchase public.rr_mc1_purchases%rowtype;
  v_fabric public.rr_mc1_fabrics%rowtype;
  v_account public.rr_mc1_account%rowtype;
  v_mode text:=upper(trim(coalesce(p_gr_mode,'')));
  v_prior_gr numeric(18,3); v_returnable numeric(18,3); v_qty numeric(18,3); v_value numeric(18,2);
  v_f_qty numeric(18,3); v_f_value numeric(18,2); v_f_avg numeric(18,4);
  v_p_qty numeric(18,3); v_p_value numeric(18,2); v_p_avg numeric(18,4);
  v_gr public.rr_product_gr_entries%rowtype;
begin
  perform public.rr_product_require_admin_v1();
  if v_mode not in('PARTIAL','FULL') then raise exception 'GR mode must be PARTIAL or FULL.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'GR reason is required.'; end if;

  select * into v_purchase from public.rr_mc1_purchases where id=p_mc_purchase_id for update;
  if not found then raise exception 'MC1 purchase not found.'; end if;
  select * into v_fabric from public.rr_mc1_fabrics where id=v_purchase.fabric_id for update;
  if not found then raise exception 'Matching Fabric pool not found for this bill.'; end if;
  select * into v_account from public.rr_mc1_account where id=v_purchase.mc_account_id for update;

  select coalesce(sum(gr_qty),0) into v_prior_gr from public.rr_product_gr_entries
  where source_type='MC1' and mc_purchase_id=p_mc_purchase_id and status<>'REVERSED';
  v_returnable:=round(v_purchase.bill_qty-v_prior_gr,3);
  v_qty:=case when v_mode='FULL' then v_returnable else round(coalesce(p_qty,0),3) end;
  if v_qty<=0 then raise exception 'No returnable quantity remains on this MC1 bill.'; end if;
  if v_qty>v_returnable then raise exception 'Maximum returnable quantity is % kg.',v_returnable; end if;

  v_value:=round(v_qty*v_purchase.bill_rate,2);
  if v_qty>v_fabric.current_qty+0.0005 then raise exception '% current balance is % kg.',v_fabric.fabric_name,v_fabric.current_qty; end if;
  if v_value>v_fabric.current_value+0.01 then raise exception '% current stock value is insufficient for bill-rate GR.',v_fabric.fabric_name; end if;

  v_f_qty:=round(v_fabric.current_qty-v_qty,3); v_f_value:=greatest(0,round(v_fabric.current_value-v_value,2));
  v_f_avg:=case when v_f_qty>0 then round(v_f_value/v_f_qty,4) else 0 end;
  v_p_qty:=round(v_account.current_qty-v_qty,3); v_p_value:=greatest(0,round(v_account.current_value-v_value,2));
  v_p_avg:=case when v_p_qty>0 then round(v_p_value/v_p_qty,4) else 0 end;

  update public.rr_mc1_fabrics set current_qty=v_f_qty,current_value=v_f_value,avg_rate=v_f_avg,
    total_gr_qty=round(total_gr_qty+v_qty,3),updated_at=now() where id=v_fabric.id;
  update public.rr_mc1_account set current_qty=v_p_qty,current_value=v_p_value,avg_rate=v_p_avg,updated_at=now() where id=v_account.id;

  insert into public.rr_product_gr_entries(source_type,mc_purchase_id,gr_mode,gr_qty,gr_rate,gr_value,
    gr_date,reason,remarks,exchange_expected,status)
  values('MC1',p_mc_purchase_id,v_mode,v_qty,v_purchase.bill_rate,v_value,coalesce(p_gr_date,current_date),
    trim(p_reason),nullif(trim(p_remarks),''),coalesce(p_exchange_expected,false),
    case when coalesce(p_exchange_expected,false) then 'AWAITING_EXCHANGE' else 'CLOSED' end)
  returning * into v_gr;

  insert into public.rr_mc1_ledger(mc_account_id,fabric_id,entry_type,reference_id,qty_out,rate_snapshot,value_out,
    balance_qty,balance_value,avg_rate_after,fabric_balance_qty,fabric_balance_value,fabric_avg_rate_after,occurred_at,remarks)
  values(v_account.id,v_fabric.id,'PURCHASE_GR_OUT',v_gr.id,v_qty,v_purchase.bill_rate,v_value,
    v_p_qty,v_p_value,v_p_avg,v_f_qty,v_f_value,v_f_avg,now(),
    concat(v_fabric.fabric_name,' · GR against Vendor ',v_purchase.vendor_name,' · Bill ',v_purchase.bill_no));

  update public.rr_mc1_purchases set operation_status=case when v_qty=v_returnable then 'FULL_GR' else 'PARTIAL_GR' end
  where id=p_mc_purchase_id;

  return jsonb_build_object('gr',to_jsonb(v_gr),'fabric',(select to_jsonb(f) from public.rr_mc1_fabrics f where f.id=v_fabric.id),
    'card',(select to_jsonb(a) from public.rr_mc1_account a where a.id=v_account.id));
end;
$$;

create or replace function public.rr_post_mc_exchange_v1(
  p_gr_id uuid,
  p_received_qty numeric,
  p_received_rate numeric,
  p_challan_bill_no text,
  p_received_date date default current_date,
  p_remarks text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gr public.rr_product_gr_entries%rowtype; v_old public.rr_mc1_purchases%rowtype;
  v_fabric public.rr_mc1_fabrics%rowtype; v_account public.rr_mc1_account%rowtype;
  v_received_before numeric(18,3); v_qty numeric(18,3):=round(coalesce(p_received_qty,0),3);
  v_rate numeric(18,4); v_value numeric(18,2);
  v_f_qty numeric(18,3); v_f_value numeric(18,2); v_f_avg numeric(18,4);
  v_p_qty numeric(18,3); v_p_value numeric(18,2); v_p_avg numeric(18,4);
  v_purchase public.rr_mc1_purchases%rowtype; v_exchange public.rr_product_exchange_entries%rowtype; v_status text;
begin
  perform public.rr_product_require_admin_v1();
  if v_qty<=0 then raise exception 'Exchange received quantity must be greater than zero.'; end if;
  if nullif(trim(p_challan_bill_no),'') is null then raise exception 'Exchange Challan / Bill No. is required.'; end if;
  select * into v_gr from public.rr_product_gr_entries where id=p_gr_id and source_type='MC1' for update;
  if not found then raise exception 'MC1 GR record not found.'; end if;
  select * into v_old from public.rr_mc1_purchases where id=v_gr.mc_purchase_id;
  if not found then raise exception 'Original MC1 purchase not found.'; end if;
  select * into v_fabric from public.rr_mc1_fabrics where id=v_old.fabric_id for update;
  select * into v_account from public.rr_mc1_account where id=v_old.mc_account_id for update;

  select coalesce(sum(received_qty),0) into v_received_before from public.rr_product_exchange_entries where gr_id=p_gr_id;
  if v_received_before+v_qty>v_gr.gr_qty+0.0005 then raise exception 'Remaining exchange quantity is % kg.',round(v_gr.gr_qty-v_received_before,3); end if;
  v_rate:=round(coalesce(nullif(p_received_rate,0),v_gr.gr_rate),4); v_value:=round(v_qty*v_rate,2);
  v_f_qty:=round(v_fabric.current_qty+v_qty,3); v_f_value:=round(v_fabric.current_value+v_value,2);
  v_f_avg:=case when v_f_qty>0 then round(v_f_value/v_f_qty,4) else 0 end;
  v_p_qty:=round(v_account.current_qty+v_qty,3); v_p_value:=round(v_account.current_value+v_value,2);
  v_p_avg:=case when v_p_qty>0 then round(v_p_value/v_p_qty,4) else 0 end;

  insert into public.rr_mc1_purchases(mc_account_id,fabric_id,fabric_name,vendor_name,bill_no,bill_date,bill_qty,bill_value,bill_rate,
    remarks,entry_kind,source_gr_id,operation_status)
  values(v_account.id,v_fabric.id,v_fabric.fabric_name,v_old.vendor_name,upper(trim(p_challan_bill_no)),coalesce(p_received_date,current_date),
    v_qty,v_value,v_rate,concat('EXCHANGE IN against GR #',v_gr.gr_no,coalesce(' · '||nullif(trim(p_remarks),''),'')),
    'EXCHANGE',v_gr.id,'ACTIVE') returning * into v_purchase;

  update public.rr_mc1_fabrics set current_qty=v_f_qty,current_value=v_f_value,avg_rate=v_f_avg,
    total_purchase_qty=round(total_purchase_qty+v_qty,3),total_exchange_qty=round(total_exchange_qty+v_qty,3),updated_at=now()
  where id=v_fabric.id;
  update public.rr_mc1_account set current_qty=v_p_qty,current_value=v_p_value,avg_rate=v_p_avg,
    total_purchase_qty=round(total_purchase_qty+v_qty,3),updated_at=now() where id=v_account.id;

  insert into public.rr_product_exchange_entries(gr_id,source_type,received_qty,received_rate,received_value,
    challan_bill_no,received_date,new_mc_purchase_id,remarks)
  values(v_gr.id,'MC1',v_qty,v_rate,v_value,upper(trim(p_challan_bill_no)),coalesce(p_received_date,current_date),v_purchase.id,
    nullif(trim(p_remarks),'')) returning * into v_exchange;

  insert into public.rr_mc1_ledger(mc_account_id,fabric_id,entry_type,reference_id,qty_in,rate_snapshot,value_in,
    balance_qty,balance_value,avg_rate_after,fabric_balance_qty,fabric_balance_value,fabric_avg_rate_after,occurred_at,remarks)
  values(v_account.id,v_fabric.id,'EXCHANGE_IN',v_exchange.id,v_qty,v_rate,v_value,
    v_p_qty,v_p_value,v_p_avg,v_f_qty,v_f_value,v_f_avg,now(),concat(v_fabric.fabric_name,' · Exchange against GR #',v_gr.gr_no));

  v_status:=case when v_received_before+v_qty>=v_gr.gr_qty-0.0005 then 'EXCHANGE_RECEIVED' else 'PART_EXCHANGE_RECEIVED' end;
  update public.rr_product_gr_entries set status=v_status,exchange_expected=true,
    closed_at=case when v_status='EXCHANGE_RECEIVED' then now() else null end,
    closed_by=case when v_status='EXCHANGE_RECEIVED' then auth.uid() else null end where id=v_gr.id;

  return jsonb_build_object('exchange',to_jsonb(v_exchange),'purchase',to_jsonb(v_purchase),'gr_status',v_status,
    'fabric',(select to_jsonb(f) from public.rr_mc1_fabrics f where f.id=v_fabric.id),
    'card',(select to_jsonb(a) from public.rr_mc1_account a where a.id=v_account.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Read models
-- ---------------------------------------------------------------------------
create or replace view public.rr_mc1_fabric_stock_v2 as
select
  f.id as matching_item_id,
  f.id as fabric_id,
  f.fabric_name,
  greatest(0,round(f.current_qty-coalesce(r.reserved_qty,0),3))::numeric(18,3) as available_qty,
  f.current_qty,
  f.current_value,
  f.avg_rate as avg_cost,
  f.total_purchase_qty,
  f.total_consumption_qty,
  f.total_gr_qty,
  f.total_exchange_qty,
  f.is_active,
  f.updated_at
from public.rr_mc1_fabrics f
left join (
  select fabric_id,sum(qty)::numeric(18,3) as reserved_qty
  from public.rr_mc1_lot_matchings_v2
  where status='RESERVED' and expires_at>=now()
  group by fabric_id
) r on r.fabric_id=f.id;

create or replace view public.rr_mc1_lot_matching_details_v2 as
select m.*, f.fabric_name
from public.rr_mc1_lot_matchings_v2 m
join public.rr_mc1_fabrics f on f.id=m.fabric_id;

create or replace function public.rr_get_matching_cloth_stock_v2()
returns table(
  matching_item_id uuid,
  fabric_name text,
  available_qty numeric,
  avg_cost numeric,
  current_value numeric,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    matching_item_id,
    fabric_name,
    available_qty,
    case when public.rr_role_can_view_financials_v1() then avg_cost else 0 end as avg_cost,
    case when public.rr_role_can_view_financials_v1() then current_value else 0 end as current_value,
    updated_at
  from public.rr_mc1_fabric_stock_v2
  where is_active=true and available_qty>0
  order by fabric_name;
$$;

create or replace function public.rr_get_mc1_lot_matchings_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_financial boolean := public.rr_role_can_view_financials_v1();
begin
  return coalesce((
    select jsonb_agg(
      case when v_financial then to_jsonb(m)
      else jsonb_build_object(
        'id',m.id,
        'fabric_id',m.fabric_id,
        'fabric_name',m.fabric_name,
        'lot_no',m.lot_no,
        'qty',m.qty,
        'status',m.status,
        'source_id',m.source_id,
        'source_kind',m.source_kind,
        'created_at',m.created_at,
        'posted_at',m.posted_at
      ) end
      order by m.created_at desc
    )
    from public.rr_mc1_lot_matching_details_v2 m
    where m.status in ('RESERVED','POSTED')
  ),'[]'::jsonb);
end;
$$;

create or replace function public.rr_get_mc1_card_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_financial boolean:=public.rr_role_can_view_financials_v1();
begin
  return (
    select jsonb_build_object(
      'card',case when v_financial then to_jsonb(a) else jsonb_build_object(
        'id',a.id,'mc_no',a.mc_no,'current_qty',a.current_qty,
        'total_purchase_qty',a.total_purchase_qty,'total_consumption_qty',a.total_consumption_qty,
        'created_at',a.created_at,'updated_at',a.updated_at
      ) end,
      'can_view_financials',v_financial,
      'fabrics',coalesce((
        select jsonb_agg(
          case when v_financial then to_jsonb(f)
          else jsonb_build_object(
            'id',f.id,'matching_item_id',f.matching_item_id,'fabric_name',f.fabric_name,
            'available_qty',f.available_qty,'current_qty',f.current_qty,
            'total_purchase_qty',f.total_purchase_qty,'total_consumption_qty',f.total_consumption_qty,
            'total_gr_qty',f.total_gr_qty,'total_exchange_qty',f.total_exchange_qty,'is_active',f.is_active,'updated_at',f.updated_at
          ) end order by f.fabric_name
        ) from public.rr_mc1_fabric_stock_v2 f
      ),'[]'::jsonb),
      'purchases',case when v_financial then coalesce((
        select jsonb_agg(to_jsonb(p) order by p.posted_at desc) from public.rr_mc1_purchases p where p.mc_account_id=a.id
      ),'[]'::jsonb) else '[]'::jsonb end,
      'ledger',case when v_financial then coalesce((
        select jsonb_agg(to_jsonb(l) order by l.occurred_at desc) from public.rr_mc1_ledger l where l.mc_account_id=a.id
      ),'[]'::jsonb) else '[]'::jsonb end,
      'lot_matchings',coalesce((
        select jsonb_agg(
          case when v_financial then to_jsonb(m)
          else jsonb_build_object(
            'id',m.id,'fabric_id',m.fabric_id,'fabric_name',m.fabric_name,
            'lot_no',m.lot_no,'qty',m.qty,'status',m.status,
            'source_id',m.source_id,'source_kind',m.source_kind,
            'created_at',m.created_at,'posted_at',m.posted_at
          ) end
          order by m.created_at desc
        )
        from public.rr_mc1_lot_matching_details_v2 m where m.status in ('RESERVED','POSTED')
      ),'[]'::jsonb)
    )
    from public.rr_mc1_account a where a.mc_no='MC1'
  );
end;
$$;

alter table public.rr_mc1_account enable row level security;
alter table public.rr_mc1_purchases enable row level security;
alter table public.rr_mc1_ledger enable row level security;
alter table public.rr_mc1_fabrics enable row level security;
alter table public.rr_mc1_lot_matchings_v2 enable row level security;

-- Financial columns are never exposed through direct table/view SELECT.
-- Authenticated screens must use the role-aware SECURITY DEFINER RPCs below.
drop policy if exists rr_mc1_fabrics_read on public.rr_mc1_fabrics;
drop policy if exists rr_mc1_lot_matchings_read on public.rr_mc1_lot_matchings_v2;
revoke all on public.rr_mc1_account,public.rr_mc1_purchases,public.rr_mc1_ledger,
  public.rr_mc1_fabrics,public.rr_mc1_lot_matchings_v2 from anon,authenticated;
revoke all on public.rr_mc1_fabric_stock_v2,public.rr_mc1_lot_matching_details_v2 from anon,authenticated;

grant execute on function public.rr_post_mc_fabric_purchase_v2(text,text,text,numeric,numeric,date,text) to authenticated;
grant execute on function public.rr_get_mc1_card_v2() to authenticated;
grant execute on function public.rr_get_matching_cloth_stock_v2() to authenticated;
grant execute on function public.rr_get_mc1_lot_matchings_v2() to authenticated;
grant execute on function public.rr_reserve_lot_matching_v2(uuid,text,numeric,text,text) to authenticated;
grant execute on function public.rr_confirm_lot_matching_v2(text,uuid) to authenticated;
grant execute on function public.rr_cancel_lot_matching_v2(text,text) to authenticated;
grant execute on function public.rr_recover_lot_matching_v2() to authenticated;
grant execute on function public.rr_lot_exists_v2(text) to authenticated;

commit;

-- CHECKS AFTER RUNNING:
-- select * from public.rr_mc1_fabric_stock_v2 order by fabric_name;
-- select public.rr_get_mc1_card_v2();
