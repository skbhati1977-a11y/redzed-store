-- REAL FACTORY V9076
-- MC NEW Matching Cloth Purchase -> exact Matching Fabric + Vendor purchase account mapping.
-- Run after REDZED_V72036_MC_FABRIC_LEDGER_PATCH.sql.

begin;

create or replace function public.rr_post_mc_fabric_purchase_v3(
  p_fabric_id uuid,
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
  v_name text := trim(coalesce(p_fabric_name, ''));
  v_norm text := public.rr_normalize_mc_fabric_name_v1(p_fabric_name);
  v_rate numeric(18,4);
  v_f_qty numeric(18,3);
  v_f_value numeric(18,2);
  v_f_avg numeric(18,4);
  v_p_qty numeric(18,3);
  v_p_value numeric(18,2);
  v_p_avg numeric(18,4);
begin
  perform public.rr_product_require_admin_v1();

  if nullif(trim(p_vendor_name), '') is null then
    raise exception 'Vendor Name required.';
  end if;
  if nullif(trim(p_bill_no), '') is null then
    raise exception 'Bill No required.';
  end if;
  if coalesce(p_bill_qty, 0) <= 0 then
    raise exception 'Bill Qty must be greater than zero.';
  end if;
  if coalesce(p_bill_value, 0) <= 0 then
    raise exception 'Bill Value must be greater than zero.';
  end if;

  select * into v_account
  from public.rr_mc1_account
  where mc_no = 'MC1'
  for update;

  if not found then
    raise exception 'MC1 account not found.';
  end if;

  if p_fabric_id is not null then
    select * into v_fabric
    from public.rr_mc1_fabrics
    where id = p_fabric_id
      and mc_account_id = v_account.id
      and is_active = true
    for update;

    if not found then
      raise exception 'Selected Matching Fabric account not found.';
    end if;

    v_name := v_fabric.fabric_name;
    v_norm := v_fabric.normalized_name;
  else
    if v_name = '' or v_norm = '' then
      raise exception 'Matching Fabric Name required.';
    end if;

    insert into public.rr_mc1_fabrics(mc_account_id, fabric_name, normalized_name)
    values(v_account.id, v_name, v_norm)
    on conflict(mc_account_id, normalized_name)
    do update set fabric_name = excluded.fabric_name, is_active = true, updated_at = now()
    returning * into v_fabric;
  end if;

  v_rate := round(p_bill_value / p_bill_qty, 4);
  v_f_qty := round(v_fabric.current_qty + p_bill_qty, 3);
  v_f_value := round(v_fabric.current_value + p_bill_value, 2);
  v_f_avg := case when v_f_qty > 0 then round(v_f_value / v_f_qty, 4) else 0 end;
  v_p_qty := round(v_account.current_qty + p_bill_qty, 3);
  v_p_value := round(v_account.current_value + p_bill_value, 2);
  v_p_avg := case when v_p_qty > 0 then round(v_p_value / v_p_qty, 4) else 0 end;

  insert into public.rr_mc1_purchases(
    mc_account_id, fabric_id, fabric_name, vendor_name, bill_no, bill_date,
    bill_qty, bill_value, bill_rate, remarks, entry_kind, operation_status
  ) values (
    v_account.id, v_fabric.id, v_fabric.fabric_name, trim(p_vendor_name), upper(trim(p_bill_no)),
    coalesce(p_bill_date, current_date), round(p_bill_qty, 3), round(p_bill_value, 2), v_rate,
    nullif(trim(p_remarks), ''), 'PURCHASE', 'ACTIVE'
  ) returning * into v_purchase;

  update public.rr_mc1_fabrics
  set current_qty = v_f_qty,
      current_value = v_f_value,
      avg_rate = v_f_avg,
      total_purchase_qty = round(total_purchase_qty + p_bill_qty, 3),
      updated_at = now()
  where id = v_fabric.id;

  update public.rr_mc1_account
  set current_qty = v_p_qty,
      current_value = v_p_value,
      avg_rate = v_p_avg,
      total_purchase_qty = round(total_purchase_qty + p_bill_qty, 3),
      updated_at = now()
  where id = v_account.id;

  insert into public.rr_mc1_ledger(
    mc_account_id, fabric_id, entry_type, reference_id, qty_in, rate_snapshot, value_in,
    balance_qty, balance_value, avg_rate_after,
    fabric_balance_qty, fabric_balance_value, fabric_avg_rate_after, occurred_at, remarks
  ) values (
    v_account.id, v_fabric.id, 'PURCHASE_IN', v_purchase.id, round(p_bill_qty, 3), v_rate, round(p_bill_value, 2),
    v_p_qty, v_p_value, v_p_avg,
    v_f_qty, v_f_value, v_f_avg, v_purchase.posted_at,
    concat(v_fabric.fabric_name, ' · Vendor: ', trim(p_vendor_name), ' · Bill: ', upper(trim(p_bill_no)))
  );

  return jsonb_build_object(
    'purchase_id', v_purchase.id,
    'purchase_account', 'Matching Cloth Purchase',
    'fabric_id', v_fabric.id,
    'matching_fabric_name', v_fabric.fabric_name,
    'vendor_name', v_purchase.vendor_name,
    'bill_no', v_purchase.bill_no,
    'bill_qty', v_purchase.bill_qty,
    'bill_value', v_purchase.bill_value,
    'bill_rate', v_purchase.bill_rate,
    'status', v_purchase.operation_status
  );
end;
$$;

create or replace function public.rr_get_mc1_purchase_account_v9076()
returns table(
  source_type text,
  purchase_account text,
  purchase_id uuid,
  fabric_id uuid,
  matching_fabric_name text,
  vendor_name text,
  bill_no text,
  bill_date date,
  qty numeric,
  rate numeric,
  amount numeric,
  status text,
  posted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.rr_role_can_view_financials_v1() then
    raise exception 'Accounts permission required.';
  end if;

  return query
  select
    'MC1_MATCHING_PURCHASE'::text as source_type,
    'Matching Cloth Purchase'::text as purchase_account,
    p.id as purchase_id,
    p.fabric_id,
    coalesce(p.fabric_name, f.fabric_name, 'Matching Cloth') as matching_fabric_name,
    p.vendor_name,
    p.bill_no,
    p.bill_date,
    p.bill_qty as qty,
    p.bill_rate as rate,
    p.bill_value as amount,
    coalesce(p.operation_status, p.entry_kind, 'ACTIVE') as status,
    p.posted_at
  from public.rr_mc1_purchases p
  left join public.rr_mc1_fabrics f on f.id = p.fabric_id
  order by p.posted_at desc;
end;
$$;

grant execute on function public.rr_post_mc_fabric_purchase_v3(uuid,text,text,text,numeric,numeric,date,text) to authenticated;
grant execute on function public.rr_get_mc1_purchase_account_v9076() to authenticated;

commit;
