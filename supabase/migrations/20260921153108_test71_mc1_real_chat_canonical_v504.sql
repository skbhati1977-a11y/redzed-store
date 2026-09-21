-- TEST71 V504: MC1 / Matching Cloth canonical Real Chat integration.
-- Repairs the deployed V3 purchase contract against the current MC1 schema,
-- keeps purchase/stock/consumption/costing on the existing MC1 records, and
-- adds read projections plus an idempotent confirmation adapter for Real Chat.

alter table public.rr_mc1_purchases
  add column if not exists idempotency_key uuid;

create unique index if not exists rr_mc1_purchases_idempotency_key_uq
  on public.rr_mc1_purchases(idempotency_key)
  where idempotency_key is not null;

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
set search_path=public
as $$
declare
  v_account public.rr_mc1_account%rowtype;
  v_fabric public.rr_mc1_fabrics%rowtype;
  v_purchase public.rr_mc1_purchases%rowtype;
  v_name text:=trim(coalesce(p_fabric_name,''));
  v_norm text:=public.rr_normalize_mc_fabric_name_v1(p_fabric_name);
  v_supplier_ledger_id uuid;
  v_rate numeric(18,4);
  v_f_qty numeric(18,3); v_f_value numeric(18,2); v_f_avg numeric(18,4);
  v_p_qty numeric(18,3); v_p_value numeric(18,2); v_p_avg numeric(18,4);
begin
  perform public.rr_product_require_admin_v1();
  if p_fabric_id is null and (v_name='' or v_norm='') then raise exception 'Matching Fabric Name required.'; end if;
  if nullif(trim(p_vendor_name),'') is null then raise exception 'Vendor Name required.'; end if;
  if nullif(trim(p_bill_no),'') is null then raise exception 'Bill No required.'; end if;
  if coalesce(p_bill_qty,0)<=0 then raise exception 'Bill Qty must be greater than zero.'; end if;
  if coalesce(p_bill_value,0)<=0 then raise exception 'Bill Value must be greater than zero.'; end if;

  select * into v_account from public.rr_mc1_account where mc_no='MC1' for update;
  if not found then raise exception 'MC1 account not found.'; end if;

  if p_fabric_id is not null then
    select * into v_fabric from public.rr_mc1_fabrics
    where id=p_fabric_id and mc_account_id=v_account.id and is_active=true
    for update;
    if not found then raise exception 'Selected Matching Fabric not found.'; end if;
  else
    insert into public.rr_mc1_fabrics(mc_account_id,fabric_name,normalized_name)
    values(v_account.id,v_name,v_norm)
    on conflict(mc_account_id,normalized_name)
    do update set fabric_name=excluded.fabric_name,is_active=true,updated_at=now()
    returning * into v_fabric;
  end if;

  v_supplier_ledger_id:=public.rr_ensure_mc_supplier_ledger_v9135(p_vendor_name);
  v_rate:=round(p_bill_value/p_bill_qty,4);
  v_f_qty:=round(v_fabric.current_qty+p_bill_qty,3);
  v_f_value:=round(v_fabric.current_value+p_bill_value,2);
  v_f_avg:=case when v_f_qty>0 then round(v_f_value/v_f_qty,4) else 0 end;
  v_p_qty:=round(v_account.current_qty+p_bill_qty,3);
  v_p_value:=round(v_account.current_value+p_bill_value,2);
  v_p_avg:=case when v_p_qty>0 then round(v_p_value/v_p_qty,4) else 0 end;

  insert into public.rr_mc1_purchases(
    mc_account_id,fabric_id,fabric_name,supplier_ledger_id,vendor_name,bill_no,bill_date,
    bill_qty,bill_value,bill_rate,remarks,entry_kind,operation_status,created_by
  ) values(
    v_account.id,v_fabric.id,v_fabric.fabric_name,v_supplier_ledger_id,trim(p_vendor_name),upper(trim(p_bill_no)),
    coalesce(p_bill_date,current_date),round(p_bill_qty,3),round(p_bill_value,2),v_rate,
    nullif(trim(p_remarks),''),'PURCHASE','ACTIVE',auth.uid()
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
    fabric_balance_qty,fabric_balance_value,fabric_avg_rate_after,occurred_at,remarks,created_by
  ) values(
    v_account.id,v_fabric.id,'PURCHASE_IN',v_purchase.id,round(p_bill_qty,3),v_rate,round(p_bill_value,2),
    v_p_qty,v_p_value,v_p_avg,v_f_qty,v_f_value,v_f_avg,v_purchase.posted_at,
    concat(v_fabric.fabric_name,' · Vendor: ',trim(p_vendor_name),' · Bill: ',upper(trim(p_bill_no))),auth.uid()
  );

  return jsonb_build_object(
    'ok',true,'purchase_id',v_purchase.id,'fabric_id',v_fabric.id,'fabric_name',v_fabric.fabric_name,
    'supplier_ledger_id',v_supplier_ledger_id,'vendor_name',v_purchase.vendor_name,'bill_no',v_purchase.bill_no,
    'bill_qty',v_purchase.bill_qty,'bill_value',v_purchase.bill_value,'bill_rate',v_purchase.bill_rate,
    'current_qty',v_f_qty,'current_value',v_f_value,'avg_rate',v_f_avg
  );
end;
$$;

revoke all on function public.rr_post_mc_fabric_purchase_v3(uuid,text,text,text,numeric,numeric,date,text) from public,anon;
grant execute on function public.rr_post_mc_fabric_purchase_v3(uuid,text,text,text,numeric,numeric,date,text) to authenticated,service_role;

create or replace function public.rr_confirm_mc_purchase_v504(
  p_idempotency_key uuid,
  p_fabric_id uuid,
  p_fabric_name text,
  p_supplier_ledger_id uuid,
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
set search_path=public
as $$
declare
  v_existing public.rr_mc1_purchases%rowtype;
  v_vendor text:=trim(coalesce(p_vendor_name,''));
  v_result jsonb;
  v_purchase_id uuid;
begin
  perform public.rr_product_require_admin_v1();
  if p_idempotency_key is null then raise exception 'Confirmation key required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,504));

  select * into v_existing from public.rr_mc1_purchases
  where idempotency_key=p_idempotency_key;
  if found then
    return jsonb_build_object(
      'ok',true,'duplicate_blocked',true,'purchase_id',v_existing.id,'fabric_id',v_existing.fabric_id,
      'fabric_name',v_existing.fabric_name,'supplier_ledger_id',v_existing.supplier_ledger_id,
      'vendor_name',v_existing.vendor_name,'bill_no',v_existing.bill_no,'bill_qty',v_existing.bill_qty,
      'bill_value',v_existing.bill_value,'bill_rate',v_existing.bill_rate
    );
  end if;

  if p_supplier_ledger_id is not null then
    select ledger_name into v_vendor from public.rr_ledgers_v805
    where id=p_supplier_ledger_id and ledger_kind='SUPPLIER' and is_active=true;
    if not found then raise exception 'Mapped Supplier Ledger not found.'; end if;
  end if;

  v_result:=public.rr_post_mc_fabric_purchase_v3(
    p_fabric_id,p_fabric_name,v_vendor,p_bill_no,p_bill_qty,p_bill_value,p_bill_date,p_remarks
  );
  v_purchase_id:=(v_result->>'purchase_id')::uuid;
  update public.rr_mc1_purchases set idempotency_key=p_idempotency_key where id=v_purchase_id;
  return v_result||jsonb_build_object('idempotency_key',p_idempotency_key,'duplicate_blocked',false);
exception
  when unique_violation then
    select * into v_existing from public.rr_mc1_purchases where idempotency_key=p_idempotency_key;
    if found then
      return jsonb_build_object(
        'ok',true,'duplicate_blocked',true,'purchase_id',v_existing.id,'fabric_id',v_existing.fabric_id,
        'fabric_name',v_existing.fabric_name,'supplier_ledger_id',v_existing.supplier_ledger_id,
        'vendor_name',v_existing.vendor_name,'bill_no',v_existing.bill_no,'bill_qty',v_existing.bill_qty,
        'bill_value',v_existing.bill_value,'bill_rate',v_existing.bill_rate
      );
    end if;
    raise;
end;
$$;

revoke all on function public.rr_confirm_mc_purchase_v504(uuid,uuid,text,uuid,text,text,numeric,numeric,date,text) from public,anon;
grant execute on function public.rr_confirm_mc_purchase_v504(uuid,uuid,text,uuid,text,text,numeric,numeric,date,text) to authenticated,service_role;

create or replace function public.rr_mc1_sync_lot_cost_v504(
  p_lot_no text,p_fabric_id uuid,p_qty numeric,p_rate numeric,p_cost numeric
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_single integer:=0;v_multi integer:=0;
begin
  update public.rr_cutting_lots_v3
  set matching_qty=round(p_qty,3),
      matching_avg_cost=round(p_rate,4),matching_amount=round(p_cost,2),updated_at=now()
  where upper(trim(lot_no))=upper(trim(p_lot_no));
  get diagnostics v_single=row_count;

  update public.rr_production_lots
  set matching_qty=round(p_qty,3),
      matching_avg_cost=round(p_rate,4),matching_amount=round(p_cost,2),updated_at=now()
  where upper(trim(lot_no))=upper(trim(p_lot_no));
  get diagnostics v_multi=row_count;
  return jsonb_build_object('single_rows',v_single,'multi_rows',v_multi);
end;
$$;

revoke all on function public.rr_mc1_sync_lot_cost_v504(text,uuid,numeric,numeric,numeric) from public,anon,authenticated;
grant execute on function public.rr_mc1_sync_lot_cost_v504(text,uuid,numeric,numeric,numeric) to service_role;

create or replace function public.rr_confirm_lot_matching_v2(p_lot_no text,p_source_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_match public.rr_mc1_lot_matchings_v2%rowtype;
  v_fabric public.rr_mc1_fabrics%rowtype;
  v_account public.rr_mc1_account%rowtype;
  v_ledger public.rr_mc1_ledger%rowtype;
  v_fabric_qty numeric(18,3);v_fabric_value numeric(18,2);v_fabric_avg numeric(18,4);
  v_parent_qty numeric(18,3);v_parent_value numeric(18,2);v_parent_avg numeric(18,4);
  v_financial boolean:=public.rr_role_can_view_financials_v1();
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  select * into v_match from public.rr_mc1_lot_matchings_v2
  where lower(lot_no)=lower(trim(p_lot_no)) and status in('RESERVED','POSTED') for update;
  if not found then raise exception 'Matching reservation not found for Lot %.',p_lot_no; end if;

  if v_match.status='POSTED' then
    perform public.rr_mc1_sync_lot_cost_v504(v_match.lot_no,v_match.fabric_id,v_match.qty,v_match.avg_rate_snapshot,v_match.total_cost);
    return jsonb_build_object(
      'status','POSTED','duplicate_blocked',true,'lot_no',v_match.lot_no,'fabric_id',v_match.fabric_id,'qty',v_match.qty,
      'avg_rate_snapshot',case when v_financial then v_match.avg_rate_snapshot else 0 end,
      'total_cost',case when v_financial then v_match.total_cost else 0 end,'ledger_id',v_match.ledger_id
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

  update public.rr_mc1_fabrics set current_qty=v_fabric_qty,current_value=v_fabric_value,avg_rate=v_fabric_avg,
    total_consumption_qty=round(total_consumption_qty+v_match.qty,3),updated_at=now() where id=v_fabric.id;
  update public.rr_mc1_account set current_qty=v_parent_qty,current_value=v_parent_value,avg_rate=v_parent_avg,
    total_consumption_qty=round(total_consumption_qty+v_match.qty,3),updated_at=now() where id=v_account.id;

  insert into public.rr_mc1_ledger(
    mc_account_id,fabric_id,entry_type,reference_id,lot_no,qty_out,rate_snapshot,value_out,
    balance_qty,balance_value,avg_rate_after,fabric_balance_qty,fabric_balance_value,fabric_avg_rate_after,occurred_at,remarks,created_by
  ) values(
    v_account.id,v_fabric.id,'LOT_CONSUMPTION_OUT',coalesce(p_source_id,v_match.id),v_match.lot_no,
    v_match.qty,v_match.avg_rate_snapshot,v_match.total_cost,v_parent_qty,v_parent_value,v_parent_avg,
    v_fabric_qty,v_fabric_value,v_fabric_avg,now(),concat(v_fabric.fabric_name,' · Lot matching consumption'),auth.uid()
  ) returning * into v_ledger;

  update public.rr_mc1_lot_matchings_v2
  set status='POSTED',ledger_id=v_ledger.id,source_id=coalesce(p_source_id,source_id),posted_at=now()
  where id=v_match.id returning * into v_match;
  perform public.rr_mc1_sync_lot_cost_v504(v_match.lot_no,v_match.fabric_id,v_match.qty,v_match.avg_rate_snapshot,v_match.total_cost);

  return jsonb_build_object(
    'status','POSTED','duplicate_blocked',false,'lot_no',v_match.lot_no,'fabric_id',v_fabric.id,
    'fabric_name',v_fabric.fabric_name,'qty',v_match.qty,
    'avg_rate_snapshot',case when v_financial then v_match.avg_rate_snapshot else 0 end,
    'total_cost',case when v_financial then v_match.total_cost else 0 end,'ledger_id',v_ledger.id
  );
end;
$$;

create or replace function public.rr_mc1_real_chat_queue_v504(p_status text,p_search text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_status text:=upper(trim(coalesce(p_status,'OPEN')));
  v_search text:=lower(trim(coalesce(p_search,'')));
  v_financial boolean:=public.rr_role_can_view_financials_v1();
  v_role text:=lower(coalesce(public.rr_current_role(),''));
  v_cards jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_status not in('OPEN','WORKING','CLOSE') then raise exception 'Invalid MC1 view.'; end if;

  if v_status='OPEN' and v_financial then
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind','PURCHASE_IN','purchase_id',p.id,'fabric_id',p.fabric_id,'fabric_name',coalesce(p.fabric_name,f.fabric_name),
      'supplier_ledger_id',p.supplier_ledger_id,'vendor_name',p.vendor_name,'bill_no',p.bill_no,'bill_date',p.bill_date,
      'qty',p.bill_qty,'rate',p.bill_rate,'value',p.bill_value,'status',coalesce(p.operation_status,'ACTIVE'),
      'posted_at',p.posted_at,'purchase_account','Matching Cloth Purchase'
    ) order by p.posted_at desc),'[]'::jsonb) into v_cards
    from public.rr_mc1_purchases p left join public.rr_mc1_fabrics f on f.id=p.fabric_id
    where v_search='' or lower(concat_ws(' ',p.fabric_name,f.fabric_name,p.vendor_name,p.bill_no)) like '%'||v_search||'%';
  elsif v_status='WORKING' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.posted_at desc),'[]'::jsonb) into v_cards from(
      select 'LOT_CONSUMPTION'::text kind,m.lot_no,m.fabric_id,max(f.fabric_name) fabric_name,
        round(sum(m.qty),3) qty,
        case when v_financial then round(sum(m.total_cost)/nullif(sum(m.qty),0),4) else null end rate,
        case when v_financial then round(sum(m.total_cost),2) else null end value,
        'CONSUMPTION_RECORDED'::text status,max(m.posted_at) posted_at,count(*) movement_count,
        'MC1'::text source
      from public.rr_mc1_lot_matchings_v2 m join public.rr_mc1_fabrics f on f.id=m.fabric_id
      where m.status='POSTED' and (v_search='' or lower(concat_ws(' ',m.lot_no,f.fabric_name)) like '%'||v_search||'%')
      group by m.lot_no,m.fabric_id
    )x;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind','CLOSING_STOCK','fabric_id',f.fabric_id,'fabric_name',f.fabric_name,
      'total_purchase_in',f.total_purchase_qty,'total_consumption_out',f.total_consumption_qty,
      'gr_adjustment',coalesce(f.total_exchange_qty,0)-coalesce(f.total_gr_qty,0),
      'total_gr_qty',f.total_gr_qty,'total_exchange_qty',f.total_exchange_qty,
      'closing_qty',f.current_qty,'available_qty',f.available_qty,
      'avg_rate',case when v_financial then f.avg_cost else null end,
      'closing_value',case when v_financial then f.current_value else null end,
      'updated_at',f.updated_at
    ) order by lower(f.fabric_name)),'[]'::jsonb) into v_cards
    from public.rr_mc1_fabric_stock_v2 f
    where f.is_active and (v_search='' or lower(f.fabric_name) like '%'||v_search||'%');
  end if;

  return jsonb_build_object(
    'ok',true,'version','V504_MC1_REAL_CHAT','status',v_status,'cards',v_cards,
    'can_view_financials',v_financial,'can_operate',v_role in('owner','admin'),
    'purchase_restricted',v_status='OPEN' and not v_financial,
    'headings',jsonb_build_object('OPEN','Purchase / Stock IN','WORKING','Lot Consumption','CLOSE','Closing Stock')
  );
end;
$$;

revoke all on function public.rr_mc1_real_chat_queue_v504(text,text) from public,anon;
grant execute on function public.rr_mc1_real_chat_queue_v504(text,text) to authenticated,service_role;

create or replace function public.rr_mc1_real_chat_history_v504(p_fabric_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_financial boolean:=public.rr_role_can_view_financials_v1();v_rows jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'entry_type',l.entry_type,'date_time',l.occurred_at,'lot_no',l.lot_no,
    'bill_no',p.bill_no,'vendor_name',p.vendor_name,'qty_in',l.qty_in,'qty_out',l.qty_out,
    'rate',case when v_financial then l.rate_snapshot else null end,
    'value',case when v_financial then coalesce(l.value_in,l.value_out) else null end,
    'balance_qty',l.fabric_balance_qty,
    'balance_value',case when v_financial then l.fabric_balance_value else null end,
    'remarks',l.remarks
  ) order by l.occurred_at desc),'[]'::jsonb) into v_rows
  from public.rr_mc1_ledger l left join public.rr_mc1_purchases p on p.id=l.reference_id
  where l.fabric_id=p_fabric_id and l.reversed_at is null;
  return jsonb_build_object('ok',true,'can_view_financials',v_financial,'rows',v_rows);
end;
$$;

revoke all on function public.rr_mc1_real_chat_history_v504(uuid) from public,anon;
grant execute on function public.rr_mc1_real_chat_history_v504(uuid) to authenticated,service_role;

-- Deterministic repair: only mirror already-posted canonical MC1 cost snapshots into
-- their existing Lot rows. This does not create or alter any stock/ledger movement.
update public.rr_cutting_lots_v3 c
set matching_qty=m.qty,matching_avg_cost=m.avg_rate_snapshot,
    matching_amount=m.total_cost,updated_at=now()
from public.rr_mc1_lot_matchings_v2 m
where m.status='POSTED' and upper(trim(c.lot_no))=upper(trim(m.lot_no))
  and (coalesce(c.matching_qty,0)<>m.qty or coalesce(c.matching_amount,0)<>m.total_cost);

update public.rr_production_lots p
set matching_qty=m.qty,matching_avg_cost=m.avg_rate_snapshot,
    matching_amount=m.total_cost,updated_at=now()
from public.rr_mc1_lot_matchings_v2 m
where m.status='POSTED' and upper(trim(p.lot_no))=upper(trim(m.lot_no))
  and (coalesce(p.matching_qty,0)<>m.qty or coalesce(p.matching_amount,0)<>m.total_cost);
