-- TEST71 Readymade only. Existing stock, Accounts, overhead pools and RRQ authorities.
-- REAL rollout remains gated by existing RM schema constraints.
create or replace function public.rr_rm_assert_operator_test71() returns void language plpgsql security definer set search_path=public as $$
begin
 perform public.rr_fg_assert_user_v787();
 if lower(coalesce(public.rr_current_role(),'')) not in('owner','super_admin','superadmin','admin','accounts','account') then raise exception 'Readymade Purchase / Accounts permission required.'; end if;
end $$;
revoke all on function public.rr_rm_assert_operator_test71() from public,anon;
grant execute on function public.rr_rm_assert_operator_test71() to authenticated;

alter table public.rr_rm_stock_v849_2c6 add column if not exists costing_snapshot_test71 jsonb;
alter table public.rr_rm_purchase_header_v849_2c6 add column if not exists supplier_ledger_id_test71 uuid references public.rr_ledgers_v805(id);
alter table public.rr_rm_purchase_header_v849_2c6 add column if not exists bill_no_test71 text;
alter table public.rr_rm_purchase_header_v849_2c6 add column if not exists account_transaction_id_test71 uuid references public.rr_account_transactions_v805(id);

create or replace function public.rr_rm_purchase_save_test71(p_purchase_id uuid,p_supplier_name text,p_bill_no text,p_purchase_date date,p_lines jsonb,p_post boolean default false) returns jsonb language plpgsql security definer set search_path=public as $$
declare pid uuid;res jsonb;h record;
begin
 perform public.rr_rm_assert_operator_test71();
 if nullif(trim(p_bill_no),'') is null then raise exception 'Supplier Bill No. required.';end if;
 if p_purchase_id is null then
 perform pg_advisory_xact_lock(hashtextextended('RM-BILL:'||public.rr_name_normalize_v805(p_supplier_name)||':'||trim(p_bill_no),0));
 select purchase_id into pid from public.rr_rm_purchase_header_v849_2c6 where public.rr_name_normalize_v805(supplier_name)=public.rr_name_normalize_v805(p_supplier_name) and bill_no_test71=trim(p_bill_no) and data_mode='TEST';
 if found then raise exception 'Supplier bill already exists. Open its saved purchase.';end if;
 res:=public.rr_rm_purchase_create_v849_2c6(p_supplier_name,p_purchase_date,null);pid:=(res->>'purchase_id')::uuid;
 else pid:=p_purchase_id;end if;
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=pid for update;
 if h.status='POSTED' then return jsonb_build_object('ok',true,'purchase_id',pid,'status','POSTED','duplicate_blocked',true);end if;
 if h.status<>'DRAFT' or h.data_mode<>'TEST' then raise exception 'TEST Readymade draft required.';end if;
 update public.rr_rm_purchase_header_v849_2c6 set supplier_name=trim(p_supplier_name),bill_no_test71=trim(p_bill_no),purchase_date=p_purchase_date where purchase_id=pid;
 res:=public.rr_rm_purchase_replace_lines_v849_2c6(pid,p_lines);
 if p_post then res:=public.rr_rm_purchase_post_v849_2c6(pid);end if;
 return res||jsonb_build_object('purchase_id',pid);
end $$;
revoke all on function public.rr_rm_purchase_save_test71(uuid,text,text,date,jsonb,boolean) from public,anon;
grant execute on function public.rr_rm_purchase_save_test71(uuid,text,text,date,jsonb,boolean) to authenticated;

create or replace function public.rr_rm_overhead_save_test71(p_head text,p_month date,p_amount numeric,p_stream text default 'ALL') returns jsonb language plpgsql security definer set search_path=public as $$
declare eid uuid;ps date:=date_trunc('month',p_month)::date;pe date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
begin
 perform public.rr_rm_assert_operator_test71();
 if upper(p_head) not in('ELECTRICITY_EXPENSE','WATER_EXPENSE','RENT_EXPENSE','TELEPHONE_INTERNET','STATIONERY_EXPENSE','ADMIN_OFFICE_EXPENSE','SELLING_DISTRIBUTION','BANK_CHARGES','PROFESSIONAL_FEES','REPAIR_MAINTENANCE','OTHER_EXPENSE') then raise exception 'Select a shared business overhead head.';end if;
 if upper(p_stream) not in('ALL','READYMADE') or coalesce(p_amount,-1)<0 or p_amount::text in('NaN','Infinity','-Infinity') then raise exception 'Valid overhead amount and stream required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM-OH:'||upper(p_head)||':'||ps::text||':'||upper(p_stream),0));
 select expense_id into eid from public.rr_cost_expense_pool_v850 where expense_code=upper(p_head) and period_start=ps and period_end=pe and upper(business_stream)=upper(p_stream) and data_mode='TEST' and source_type='RM_HEAD_TEST71' for update;
 if eid is null then
 insert into public.rr_cost_expense_pool_v850(expense_code,expense_name,business_stream,allocation_driver,period_start,period_end,amount,source_type,data_mode,created_by)
 values(upper(p_head),initcap(replace(p_head,'_',' ')),upper(p_stream),'VALUE_RATIO',ps,pe,p_amount,'RM_HEAD_TEST71','TEST',auth.uid()) returning expense_id into eid;
 else update public.rr_cost_expense_pool_v850 set amount=p_amount,is_active=true where expense_id=eid;end if;
 return jsonb_build_object('ok',true,'expense_id',eid);
end $$;
revoke all on function public.rr_rm_overhead_save_test71(text,date,numeric,text) from public,anon;
grant execute on function public.rr_rm_overhead_save_test71(text,date,numeric,text) to authenticated;

create or replace function public.rr_rm_costing_test71(p_lot_no text,p_data_mode text default 'TEST') returns jsonb language plpgsql stable security definer set search_path=public as $$
declare s record;h record;ps date;pe date;shared jsonb;ratio numeric;pcs numeric;oh numeric:=0;sal numeric:=0;rows jsonb;outj jsonb;private_ok boolean;
begin
 perform public.rr_fg_assert_user_v787();
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode=upper(p_data_mode);
 if not found then raise exception 'Readymade lot not found.'; end if;
 private_ok:=coalesce((public.rr_costing_user_scope_v760(null)->>'can_view_private_cost')::boolean,false);
 if s.costing_snapshot_test71 is not null then outj:=s.costing_snapshot_test71;
 else
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=s.source_purchase_id;
 ps:=date_trunc('month',h.purchase_date)::date;pe:=(ps+interval '1 month - 1 day')::date;
 shared:=public.rr_shared_business_allocation_v669(ps,pe,p_data_mode);
 pcs:=coalesce((shared->>'readymade_inward_pcs')::numeric,0);
 ratio:=coalesce((shared->>'readymade_inward_value')::numeric,0)/nullif(coalesce((shared->>'manufacturing_stock_in_value')::numeric,0)+coalesce((shared->>'readymade_inward_value')::numeric,0),0);
 sal:=coalesce((shared->>'readymade_salary_per_pc')::numeric,0);
 -- Heads retain their identity; salary is sourced ONLY from canonical salary profiles.
 -- Actual Accounts entries are used only when no corresponding expense-pool head exists.
 with pool as (
 select upper(expense_code) code,expense_name label,business_stream, sum(amount*greatest(0,least(period_end,pe)-greatest(period_start,ps)+1)::numeric/greatest(1,period_end-period_start+1)) amount
 from public.rr_cost_expense_pool_v850 where data_mode=upper(p_data_mode) and is_active and period_start<=pe and period_end>=ps
 and upper(business_stream) in('ALL','TRADING','READYMADE') and upper(expense_code) not like '%SALARY%'
 group by upper(expense_code),expense_name,business_stream
 ),acct as (
 select c.category_code code,c.category_name label,'ALL'::text business_stream,sum(p.dr_amount-p.cr_amount) amount
 from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id
 join public.rr_ledgers_v805 l on l.id=p.ledger_id join public.rr_account_categories_v805 c on c.id=l.category_id
 where t.data_mode=upper(p_data_mode) and t.status='POSTED' and coalesce(t.bill_date,t.transaction_datetime::date) between ps and pe
 and c.category_code in('ELECTRICITY_EXPENSE','WATER_EXPENSE','RENT_EXPENSE','TELEPHONE_INTERNET','STATIONERY_EXPENSE','ADMIN_OFFICE_EXPENSE','SELLING_DISTRIBUTION','BANK_CHARGES','PROFESSIONAL_FEES','REPAIR_MAINTENANCE','OTHER_EXPENSE')
 and not exists(select 1 from pool e where e.code=c.category_code) group by c.category_code,c.category_name
 ),allheads as(select * from pool union all select * from acct),a as(
 select *,amount*case when upper(business_stream)='ALL' then coalesce(ratio,0) else 1 end/nullif(pcs,0) per_pc from allheads)
 select coalesce(jsonb_agg(jsonb_build_object('head',code,'label',label,'period_amount',amount,'business_stream',business_stream,'per_pc',round(per_pc,6)) order by code),'[]'::jsonb),coalesce(sum(per_pc),0) into rows,oh from a;
 outj:=jsonb_build_object('ok',pcs>0 and shared->>'state'='READY','costing_complete',pcs>0 and shared->>'state'='READY','version','TEST71_READYMADE','path','READYMADE_WEIGHTED_COST_TEST71','lot_no',s.lot_no,'qty',s.qty_received,'period_start',ps,'period_end',pe,'purchase_cost_per_pc',s.purchase_rate,'owner_margin_per_pc',22,'salary_per_pc',sal,'overhead_per_pc',oh,'overhead_heads',rows,'salary_allocation',shared,'total_cost_per_pc',s.purchase_rate+sal+oh,'source_rate',round(s.purchase_rate+sal+oh+22,0),'calculated_sale_rate',s.purchase_rate+sal+oh+22,'frozen',false);
 end if;
 if private_ok then return outj; end if;
 return jsonb_build_object('ok',outj->'ok','costing_complete',outj->'costing_complete','lot_no',s.lot_no,'qty',outj->'qty','source_rate',outj->'source_rate','calculated_sale_rate',outj->'source_rate','path',outj->'path','frozen',outj->'frozen');
end $$;
revoke all on function public.rr_rm_costing_test71(text,text) from public,anon;
grant execute on function public.rr_rm_costing_test71(text,text) to authenticated;

create or replace function public.rr_rm_finish_purchase_test71(p_purchase_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare h record;s record;party uuid;purchase_ledger uuid;tx jsonb;costj jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id for update;
 if not found or h.data_mode<>'TEST' then raise exception 'TEST Readymade purchase required.'; end if;
 party:=public.rr_supplier_ledger_resolve_v806(h.supplier_name);
 select l.id into purchase_ledger from public.rr_ledgers_v805 l join public.rr_account_categories_v805 c on c.id=l.category_id where c.category_code='OTHER_MATERIAL_PURCHASE' and l.is_active order by l.created_at limit 1;
 if purchase_ledger is null then raise exception 'Readymade Purchase account mapping required.'; end if;
 for s in select * from public.rr_rm_stock_v849_2c6 where source_purchase_id=p_purchase_id order by lot_no loop
 perform public.rr_rm_sync_trade_stock_to_fg_v849(s.stock_id);
 insert into public.rr_fg_products_v787(lot_no,full_item_name,short_item_name,sale_rate,image_url,active)
 values(s.lot_no,s.item_name,s.item_name,s.purchase_rate+22,s.final_image_url,true)
 on conflict(lot_no) do update set full_item_name=excluded.full_item_name,short_item_name=excluded.short_item_name,image_url=excluded.image_url;
 end loop;
 if not exists(select 1 from public.rr_account_transactions_v805 where source_module='READYMADE_PURCHASE' and source_record_id=p_purchase_id::text and data_mode=h.data_mode and status<>'REVERSED') then
 tx:=public.rr_accounts_mirror_post_v806('PURCHASE',h.total_purchase_amount,jsonb_build_array(jsonb_build_object('ledger_id',purchase_ledger,'dr',h.total_purchase_amount,'cr',0),jsonb_build_object('ledger_id',party,'dr',0,'cr',h.total_purchase_amount)),'READYMADE_PURCHASE',p_purchase_id::text,party,coalesce(h.bill_no_test71,h.purchase_no),h.purchase_date,'Readymade garments purchase',h.data_mode);
 update public.rr_rm_purchase_header_v849_2c6 set supplier_ledger_id_test71=party,account_transaction_id_test71=(tx->>'transaction_id')::uuid where purchase_id=p_purchase_id;
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.rr_rm_finish_purchase_test71(uuid) from public,anon,authenticated;

-- Use the existing purchased-stock sync, eliminating its hard-coded actor fallback.
create or replace function public.rr_rm_sync_trade_stock_to_fg_v849(p_stock_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare s record;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into s from public.rr_rm_stock_v849_2c6 where stock_id=p_stock_id for update;
 if not found or s.data_mode<>'TEST' then raise exception 'TEST Readymade stock required.';end if;
 if not exists(select 1 from public.rr_fg_stock_ledger_v787 where ref_type='RM_STOCK' and ref_id=s.stock_id and txn_type='READYMADE_PURCHASE_IN' and data_mode=s.data_mode) then
 insert into public.rr_fg_stock_ledger_v787(txn_type,ref_type,ref_id,lot_no,stock_type,qty_delta,rate,data_mode,created_by,created_at,meta)
 select 'READYMADE_PURCHASE_IN','RM_STOCK',s.stock_id,s.lot_no,'TRADED',s.qty_received::integer,s.purchase_rate,s.data_mode,auth.uid(),h.purchase_date::timestamptz,jsonb_build_object('source','READYMADE_PURCHASE','purchase_id',s.source_purchase_id)
 from public.rr_rm_purchase_header_v849_2c6 h where h.purchase_id=s.source_purchase_id;
 end if;
 return jsonb_build_object('ok',true,'stock_id',s.stock_id);
end $$;

create or replace function public.rr_pack_rate_context_universal_v9405(p_lot_no text,p_data_mode text default 'TEST') returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if upper(p_data_mode)='TEST' and exists(select 1 from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode=upper(p_data_mode)) then return public.rr_rm_costing_test71(p_lot_no,p_data_mode);end if;
 return public.rr_pack_rate_context_v309(p_lot_no,p_data_mode)||jsonb_build_object('compat_entrypoint','V9405');
end $$;

create or replace function public.rr_rm_approve_rate_test71(p_lot_no text,p_final_rate numeric,p_reason text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare s record;j jsonb;r jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 if lower(public.rr_current_role()) not in('owner','super_admin','superadmin','admin') then raise exception 'Owner / Admin rate approval required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(p_lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST' for update;
 if not found then raise exception 'Readymade lot not found.';end if;
 -- Freeze full private costing under owner scope; Admin can approve but cannot read it.
 if s.costing_snapshot_test71 is null then
 if lower(public.rr_current_role()) not in('owner','super_admin','superadmin') then raise exception 'Owner must finalize Readymade costing first.';end if;
 j:=public.rr_rm_costing_test71(s.lot_no,'TEST');
 if not coalesce((j->>'costing_complete')::boolean,false) then raise exception 'Monthly weighted allocation is pending.';end if;
 update public.rr_rm_stock_v849_2c6 set costing_snapshot_test71=j||jsonb_build_object('frozen',true,'frozen_at',now()) where stock_id=s.stock_id;
 end if;
 r:=public.rrq_apply_packing_rate_core_test71(s.lot_no,p_final_rate,'TEST',p_reason);
 update public.rr_rm_stock_v849_2c6 set target_sale_rate=p_final_rate,minimum_allowed_sale_rate=greatest(0,p_final_rate-max_customer_discount_per_pc),markup_mode='DEFAULT_22',markup_per_pc=22 where stock_id=s.stock_id;
 return r;
end $$;
revoke all on function public.rr_rm_approve_rate_test71(text,numeric,text) from public,anon;
grant execute on function public.rr_rm_approve_rate_test71(text,numeric,text) to authenticated;

create or replace function public.rr_rm_purchase_return_test71(p_stock_id uuid,p_qty numeric,p_reason text,p_return_date date default current_date,p_remarks text default null,p_idempotency_key text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare s record;h record;rid uuid;party uuid;tx jsonb;avail numeric;already numeric;key text:=nullif(trim(p_idempotency_key),'');
begin
 perform public.rr_rm_assert_operator_test71();
 if key is null then raise exception 'Return request reference required.';end if;
 if coalesce(p_qty,0)<=0 or p_qty<>trunc(p_qty) or nullif(trim(p_reason),'') is null then raise exception 'Whole PCS and return reason required.';end if;
 select * into s from public.rr_rm_stock_v849_2c6 where stock_id=p_stock_id for update;
 if not found or s.data_mode<>'TEST' then raise exception 'TEST Readymade stock required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(s.lot_no))||':TEST',0));
 select id into rid from public.rr_purchase_returns_v806 where source_module='READYMADE' and source_purchase_id=s.stock_id and source_after->>'idempotency_key'=key and data_mode=s.data_mode;
 if found then return jsonb_build_object('ok',true,'return_id',rid,'duplicate_blocked',true);end if;
 select coalesce(sum(qty_delta),0) into avail from public.rr_fg_stock_ledger_v787 where lot_no=s.lot_no and stock_type='TRADED' and data_mode=s.data_mode;
 select coalesce(sum(return_qty),0) into already from public.rr_purchase_returns_v806 where source_module='READYMADE' and source_purchase_id=s.stock_id and status='POSTED' and data_mode=s.data_mode;
 if p_qty>avail or p_qty>s.qty_received-already then raise exception 'Return exceeds available purchased stock.';end if;
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=s.source_purchase_id;
 party:=public.rr_supplier_ledger_resolve_v806(h.supplier_name);
 insert into public.rr_purchase_returns_v806(source_module,source_purchase_id,return_qty,rate_snapshot,return_value,supplier_ledger_id,bill_no,return_date,reason,remarks,data_mode,status,source_before,source_after,created_by)
 values('READYMADE',s.stock_id,p_qty,s.purchase_rate,p_qty*s.purchase_rate,party,coalesce(h.bill_no_test71,h.purchase_no),p_return_date,p_reason,p_remarks,s.data_mode,'POSTED',to_jsonb(s),jsonb_build_object('idempotency_key',key,'lot_no',s.lot_no),auth.uid()) returning id into rid;
 tx:=public.rr_accounts_post_purchase_return_v806('READYMADE_RETURN',rid::text,party,p_qty*s.purchase_rate,coalesce(h.bill_no_test71,h.purchase_no),p_return_date,p_reason,s.data_mode);
 update public.rr_purchase_returns_v806 set account_transaction_id=(tx->>'transaction_id')::uuid where id=rid;
 insert into public.rr_fg_stock_ledger_v787(txn_type,ref_type,ref_id,lot_no,stock_type,qty_delta,rate,data_mode,created_by,meta)
 values('READYMADE_PURCHASE_RETURN','PURCHASE_RETURN',rid,s.lot_no,'TRADED',-p_qty::integer,s.purchase_rate,s.data_mode,auth.uid(),jsonb_build_object('purchase_id',h.purchase_id,'reason',p_reason));
 return jsonb_build_object('ok',true,'return_id',rid,'qty',p_qty,'amount',p_qty*s.purchase_rate,'duplicate_blocked',false);
end $$;
revoke all on function public.rr_rm_purchase_return_test71(uuid,numeric,text,date,text,text) from public,anon;
grant execute on function public.rr_rm_purchase_return_test71(uuid,numeric,text,date,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.rrq_apply_packing_rate_core_test71(p_lot_no text, p_admin_final_rate numeric, p_data_mode text DEFAULT 'TEST'::text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_mode text:=upper(coalesce(p_data_mode,'TEST'));
  v_ctx jsonb;
  v_base numeric;
  v_qty numeric;
  v_old numeric;
  v_delta_pc numeric;
  v_quota_delta numeric;
  v_balance numeric;
  v_canonical text;
  v_id uuid;
  v_ready boolean;
begin
  v_role:=lower(coalesce(public.rr_current_role(),''));
  if v_role not in ('owner','admin','super_admin') then
    raise exception 'Only Admin/Owner/Super Admin can decide RRQ sale rate.';
  end if;
  if p_admin_final_rate is null or p_admin_final_rate<0 or p_admin_final_rate<>round(p_admin_final_rate,0) then
    raise exception 'RRQ final sale rate must be a whole rupee.';
  end if;

  v_ctx:=public.rr_pack_rate_context_universal_v9405(trim(p_lot_no),v_mode);
  v_canonical:=nullif(v_ctx->>'canonical_lot_id','');
  v_base:=round(coalesce((v_ctx->>'source_rate')::numeric,0),0);
  v_qty:=coalesce((v_ctx->>'qty')::numeric,0);
  if coalesce((v_ctx->>'ok')::boolean,false) is not true or v_base<=0 or v_qty<=0 then
    raise exception 'Final costing or lot quantity missing.';
  end if;

  select id,final_sale_rate,dispatch_ready into v_id,v_old,v_ready
  from public.rrq_lot_rates_v9300
  where data_mode=v_mode and lot_no=trim(p_lot_no)
  for update;
  if found and v_ready and v_old=p_admin_final_rate then
    select balance into v_balance from public.rrq_balance_v9300 where data_mode=v_mode;
    return jsonb_build_object(
      'lot_no',trim(p_lot_no),'base_sale_rate',v_base,'final_sale_rate',p_admin_final_rate,
      'rrq_adjustment_per_pc',p_admin_final_rate-v_base,'quota_delta',0,
      'rrq_balance',coalesce(v_balance,0),'dispatch_ready',true,
      'mapping_path',v_ctx->>'path','duplicate_blocked',true
    );
  end if;

  v_old:=coalesce(v_old,v_base);
  v_delta_pc:=p_admin_final_rate-v_old;
  v_quota_delta:=v_delta_pc*v_qty;
  insert into public.rrq_balance_v9300(data_mode,balance) values(v_mode,0) on conflict do nothing;
  update public.rrq_balance_v9300 set balance=balance+v_quota_delta,updated_at=now()
  where data_mode=v_mode returning balance into v_balance;
  insert into public.rrq_lot_rates_v9300(
    data_mode,lot_no,canonical_lot_id,qty_snapshot,base_sale_rate,rrq_adjustment_per_pc,
    final_sale_rate,dispatch_ready,decided_by,decided_at,updated_at
  ) values(
    v_mode,trim(p_lot_no),v_canonical,v_qty,v_base,p_admin_final_rate-v_base,
    p_admin_final_rate,true,auth.uid(),now(),now()
  ) on conflict(data_mode,lot_no) do update set
    canonical_lot_id=coalesce(excluded.canonical_lot_id,public.rrq_lot_rates_v9300.canonical_lot_id),
    qty_snapshot=excluded.qty_snapshot,base_sale_rate=excluded.base_sale_rate,
    rrq_adjustment_per_pc=excluded.rrq_adjustment_per_pc,final_sale_rate=excluded.final_sale_rate,
    dispatch_ready=true,decided_by=auth.uid(),decided_at=now(),updated_at=now();
  insert into public.rrq_rate_ledger_v9300(
    data_mode,lot_no,event_type,qty,previous_rate,new_rate,delta_per_pc,quota_delta,balance_after,reason
  ) values(
    v_mode,trim(p_lot_no),'PACKING_ADMIN',v_qty,v_old,p_admin_final_rate,
    v_delta_pc,v_quota_delta,v_balance,coalesce(p_reason,'Admin RRQ decision')
  );
  update public.rr_fg_products_v787 set sale_rate=p_admin_final_rate where lot_no=trim(p_lot_no);
  return jsonb_build_object(
    'lot_no',trim(p_lot_no),'base_sale_rate',v_base,'final_sale_rate',p_admin_final_rate,
    'rrq_adjustment_per_pc',p_admin_final_rate-v_base,'quota_delta',v_quota_delta,
    'rrq_balance',v_balance,'dispatch_ready',true,'mapping_path',v_ctx->>'path',
    'duplicate_blocked',false
  );
end $function$
;
revoke all on function public.rrq_apply_packing_rate_core_test71(text,numeric,text,text) from public,anon,authenticated;

create or replace function public.rrq_apply_packing_rate_v9300(p_lot_no text,p_admin_final_rate numeric,p_data_mode text default 'TEST',p_reason text default null) returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if upper(p_data_mode)='TEST' and exists(select 1 from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST') then return public.rr_rm_approve_rate_test71(p_lot_no,p_admin_final_rate,p_reason);end if;
 return public.rrq_apply_packing_rate_core_test71(p_lot_no,p_admin_final_rate,p_data_mode,p_reason);
end $$;

CREATE OR REPLACE FUNCTION public.rr_rm_purchase_create_v849_2c6(p_supplier_name text, p_purchase_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

declare
    v_purchase_id uuid;

    v_purchase_no text;

begin
    perform public.rr_rm_assert_operator_test71();

    if nullif(
         trim(
           coalesce(
             p_supplier_name,
             ''
           )
         ),
         ''
       ) is null
    then
      raise exception
        'Supplier Name required.';
    end if;


    v_purchase_no :=
      public.rr_rm_next_purchase_no_v849_2c6();


    insert into public.rr_rm_purchase_header_v849_2c6
    (
      purchase_no,
      purchase_date,
      supplier_name,
      status,
      source_type,
      data_mode,
      notes
    )
    values
    (
      v_purchase_no,
      coalesce(
        p_purchase_date,
        current_date
      ),
      trim(p_supplier_name),
      'DRAFT',
      'TRADED',
      'TEST',
      p_notes
    )

    returning purchase_id
    into v_purchase_id;


    insert into public.rr_rm_purchase_audit_v849_2c6
    (
      purchase_id,
      purchase_no,
      action_code,
      details
    )
    values
    (
      v_purchase_id,
      v_purchase_no,
      'DRAFT_CREATED',

      jsonb_build_object(
        'supplier',
        trim(p_supplier_name)
      )
    );


    return jsonb_build_object(
      'ok',true,
      'purchase_id',v_purchase_id,
      'purchase_no',v_purchase_no,
      'status','DRAFT'
    );

end;
$function$
;

CREATE OR REPLACE FUNCTION public.rr_rm_purchase_replace_lines_v849_2c6(p_purchase_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

declare
    v_header record;

    v_json_line jsonb;

    v_lot_no text;

    v_item_name text;

    v_qty numeric;

    v_purchase_rate numeric;

    v_markup_mode text;

    v_markup numeric;

    v_image text;

    v_line_count integer:=0;

begin
    perform public.rr_rm_assert_operator_test71();

    select *
    into v_header

    from public.rr_rm_purchase_header_v849_2c6

    where purchase_id=p_purchase_id

    for update;


    if not found then
      raise exception
        'ReadyMade purchase not found.';
    end if;


    if v_header.status<>'DRAFT' then
      raise exception
        'Only DRAFT purchase can be edited.';
    end if;


    if p_lines is null
       or jsonb_typeof(p_lines)<>'array'
    then
      raise exception
        'Lines JSON array required.';
    end if;


    delete from public.rr_rm_purchase_lines_v849_2c6

    where purchase_id=p_purchase_id;


    for v_json_line in

      select value

      from jsonb_array_elements(p_lines)

    loop

      v_lot_no :=
        nullif(
          trim(
            coalesce(
              v_json_line->>'lot_no',
              ''
            )
          ),
          ''
        );


      v_item_name :=
        nullif(
          trim(
            coalesce(
              v_json_line->>'item_name',
              ''
            )
          ),
          ''
        );


      v_qty :=
        nullif(
          v_json_line->>'qty',
          ''
        )::numeric;


      v_purchase_rate :=
        nullif(
          v_json_line->>'purchase_rate',
          ''
        )::numeric;


      v_markup_mode :=
        upper(
          trim(
            coalesce(
              v_json_line->>'markup_mode',
              'DEFAULT_22'
            )
          )
        );


      v_image :=
        nullif(
          trim(
            coalesce(
              v_json_line->>'final_image_url',
              ''
            )
          ),
          ''
        );


      if v_lot_no is null then
        raise exception
          'Lot No required.';
      end if;


      if v_item_name is null then
        raise exception
          'Item Name required for Lot %.',
          v_lot_no;
      end if;


      if coalesce(v_qty,0)<=0 then
        raise exception
          'Positive Qty required for Lot %.',
          v_lot_no;
      end if;


      if coalesce(v_purchase_rate,0)<=0 then
        raise exception
          'Positive Purchase Rate required for Lot %.',
          v_lot_no;
      end if;


      v_markup_mode:='DEFAULT_22'; v_markup:=22;
      if v_qty<>trunc(v_qty) then raise exception 'Readymade quantity must be whole PCS.'; end if;

      insert into public.rr_rm_purchase_lines_v849_2c6
      (
        purchase_id,
        lot_no,
        item_name,
        qty,
        purchase_rate,
        markup_mode,
        markup_per_pc,
        max_customer_discount_per_pc,
        final_image_url,
        source_type
      )
      values
      (
        p_purchase_id,
        v_lot_no,
        v_item_name,
        v_qty,
        v_purchase_rate,
        v_markup_mode,
        v_markup,
        10,
        v_image,
        'TRADED'
      );


      v_line_count :=
        v_line_count+1;

    end loop;


    update public.rr_rm_purchase_header_v849_2c6 h

    set
      total_qty=
        (
          select coalesce(
                   sum(pl.qty),
                   0
                 )

          from public.rr_rm_purchase_lines_v849_2c6 pl

          where pl.purchase_id=p_purchase_id
        ),

      total_purchase_amount=
        (
          select coalesce(
                   sum(
                     pl.qty
                     *
                     pl.purchase_rate
                   ),
                   0
                 )

          from public.rr_rm_purchase_lines_v849_2c6 pl

          where pl.purchase_id=p_purchase_id
        ),

      updated_at=now()

    where h.purchase_id=p_purchase_id;


    insert into public.rr_rm_purchase_audit_v849_2c6
    (
      purchase_id,
      purchase_no,
      action_code,
      details
    )
    values
    (
      p_purchase_id,
      v_header.purchase_no,
      'DRAFT_LINES_REPLACED',

      jsonb_build_object(
        'line_count',
        v_line_count
      )
    );


    return jsonb_build_object(
      'ok',true,
      'purchase_id',p_purchase_id,
      'status','DRAFT',
      'line_count',v_line_count
    );

end;
$function$
;

CREATE OR REPLACE FUNCTION public.rr_rm_purchase_post_v849_2c6(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

declare
    v_header record;

    v_line record;

    v_line_count integer;

begin
    perform public.rr_rm_assert_operator_test71();

    select *
    into v_header

    from public.rr_rm_purchase_header_v849_2c6

    where purchase_id=p_purchase_id

    for update;


    if not found
    then
      raise exception
        'ReadyMade purchase not found.';
    end if;


    if v_header.status='POSTED'
    then

      return jsonb_build_object(

        'ok',true,

        'purchase_id',
          v_header.purchase_id,

        'purchase_no',
          v_header.purchase_no,

        'status',
          'POSTED',

        'stock_effect_applied',
          false,

        'reason',
          'ALREADY_POSTED'

      );

    end if;


    if v_header.status<>'DRAFT'
    then
      raise exception
        'Only DRAFT purchase may be posted.';
    end if;


    select count(*)
    into v_line_count

    from public.rr_rm_purchase_lines_v849_2c6 pl

    where pl.purchase_id=p_purchase_id;


    if v_line_count<=0
    then
      raise exception
        'At least one purchase line required.';
    end if;


    if exists(

      select 1

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id

        and (
             pl.qty<=0
          or pl.purchase_rate<=0
          or pl.markup_per_pc<>22
          or pl.max_customer_discount_per_pc<>10
          or pl.final_image_url is null
        )

    )
    then
      raise exception
        'ReadyMade Qty / Rate / Markup / Final Image validation failed.';
    end if;


    -- --------------------------------------------------------
    -- GLOBAL LOT COLLISION CHECK
    -- --------------------------------------------------------

    for v_line in

      select pl.*

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id

      order by pl.lot_no

    loop

      perform
        public.rr_rm_assert_lot_available_v849(
          v_line.lot_no
        );

    end loop;


    -- --------------------------------------------------------
    -- CREATE TRADED STOCK
    -- --------------------------------------------------------

    for v_line in

      select pl.*

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id

      order by pl.lot_no

    loop

      insert into public.rr_rm_stock_v849_2c6
      (
        lot_no,
        source_purchase_id,
        source_purchase_line_id,
        item_name,
        source_type,
        purchase_rate,
        markup_mode,
        markup_per_pc,
        max_customer_discount_per_pc,
        target_sale_rate,
        minimum_allowed_sale_rate,
        qty_received,
        qty_sold,
        final_image_url,
        sale_ready,
        data_mode
      )
      values
      (
        v_line.lot_no,
        p_purchase_id,
        v_line.purchase_line_id,
        v_line.item_name,
        'TRADED',
        v_line.purchase_rate,
        v_line.markup_mode,
        v_line.markup_per_pc,
        v_line.max_customer_discount_per_pc,
        v_line.target_sale_rate,
        v_line.minimum_allowed_sale_rate,
        v_line.qty,
        0,
        v_line.final_image_url,
        true,
        'TEST'
      );

    end loop;


    -- --------------------------------------------------------
    -- STOCK RECONCILIATION
    -- --------------------------------------------------------

    if
    (
      select coalesce(
               sum(st.qty_received),
               0
             )

      from public.rr_rm_stock_v849_2c6 st

      where st.source_purchase_id=p_purchase_id
    )
    <>
    (
      select coalesce(
               sum(pl.qty),
               0
             )

      from public.rr_rm_purchase_lines_v849_2c6 pl

      where pl.purchase_id=p_purchase_id
    )
    then

      raise exception
        'ReadyMade stock reconciliation failed.';

    end if;


    -- --------------------------------------------------------
    -- REGISTER UNIVERSAL LOT IDENTITY
    -- --------------------------------------------------------

    insert into public.rr_universal_lot_registry_v849
    (
      lot_no,
      normalized_lot_no,
      source_type,
      source_internal_id,
      data_mode
    )

    select
        st.lot_no,

        upper(
          trim(
            st.lot_no
          )
        ),

        'TRADED',

        st.stock_id::text,

        st.data_mode

    from public.rr_rm_stock_v849_2c6 st

    where st.source_purchase_id=p_purchase_id

    on conflict(
      normalized_lot_no,
      data_mode
    )

    do update set
      lot_no=excluded.lot_no,
      source_type='TRADED',
      source_internal_id=excluded.source_internal_id,
      updated_at=now();


    -- --------------------------------------------------------
    -- FINAL POST
    -- --------------------------------------------------------

    perform public.rr_rm_finish_purchase_test71(p_purchase_id);

    update public.rr_rm_purchase_header_v849_2c6 h

    set
      status='POSTED',
      posted_at=now(),
      updated_at=now()

    where h.purchase_id=p_purchase_id;


    insert into public.rr_rm_purchase_audit_v849_2c6
    (
      purchase_id,
      purchase_no,
      action_code,
      details
    )
    values
    (
      p_purchase_id,

      v_header.purchase_no,

      'POSTED_TO_TRADED_STOCK',

      jsonb_build_object(
        'line_count',
          v_line_count,

        'universal_lot_identity_registered',
          true
      )
    );


    return jsonb_build_object(

      'ok',true,

      'purchase_id',
        p_purchase_id,

      'purchase_no',
        v_header.purchase_no,

      'status',
        'POSTED',

      'stock_effect_applied',
        true,

      'universal_lot_identity_registered',
        true

    );

end;
$function$
;

CREATE OR REPLACE FUNCTION public.rr_fg_save_pi_v787(p_pi_id uuid, p_buyer_name text, p_dispatch_details text, p_lines jsonb, p_value_added_pct numeric DEFAULT 0, p_packing_other numeric DEFAULT 0, p_finalize boolean DEFAULT false, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    pid uuid;
    bid uuid;
    pi text;
    cpi text;
    ver int;
    sub numeric;
    raw numeric;
    grand numeric;
    ln jsonb;
    avail int;
    v_rate numeric;
    v_trade jsonb;
    v_actor uuid;
    v_serial integer:=0;
    v_party_discount numeric;
begin

    perform rr_fg_assert_user_v787();

    v_actor:=coalesce(
      auth.uid(),
      'af915a18-3823-48df-b039-1e4c7a88479b'::uuid
    );

    if p_packing_other<0
       or jsonb_typeof(p_lines)<>'array'
       or jsonb_array_length(p_lines)=0
    then
        raise exception 'Valid PI lines required';
    end if;

    select id
    into bid
    from rr_buyers_v787
    where lower(buyer_name)=lower(trim(p_buyer_name));

    if bid is null then
        insert into rr_buyers_v787(buyer_name)
        values(trim(p_buyer_name))
        returning id into bid;
    end if;

    if p_pi_id is null then

        pi:=rr_fg_next_no_v787(
          'PI',
          p_data_mode,
          case when p_data_mode='TEST' then 'TPI' else 'PI' end
        );

        insert into rr_fg_pi_v787
        (
            pi_no,
            buyer_id,
            buyer_snapshot,
            dispatch_details,
            data_mode
        )
        select
            pi,
            b.id,
            jsonb_build_object(
                'buyer_name',b.buyer_name,
                'contact_no',b.contact_no,
                'address',b.address,
                'gst_no',b.gst_no
            ),
            p_dispatch_details,
            p_data_mode
        from rr_buyers_v787 b
        where b.id=bid
        returning id into pid;

    else

        select id,version_no
        into pid,ver
        from rr_fg_pi_v787
        where id=p_pi_id
          and status='DRAFT'
          and data_mode=p_data_mode
        for update;

        if pid is null then
            raise exception 'Editable PI not found';
        end if;

        update rr_fg_pi_v787
        set
            version_no=version_no+1,
            buyer_id=bid,
            dispatch_details=p_dispatch_details,
            updated_at=now()
        where id=pid;

        delete from rr_fg_pi_lines_v787
        where pi_id=pid;

    end if;


    if upper(p_data_mode)='TEST' then
      perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(x->>'lot_no'))||':'||p_data_mode,0))
      from jsonb_array_elements(p_lines) x where x->>'stock_type'='TRADED' order by upper(trim(x->>'lot_no'));
      if p_finalize and exists(select 1 from jsonb_array_elements(p_lines) x where x->>'stock_type'='TRADED'
        group by upper(trim(x->>'lot_no')) having sum((x->>'qty')::integer)>
        coalesce((select sum(b.available_qty) from public.rr_fg_stock_balance_v787 b
        where upper(trim(b.lot_no))=upper(trim(x->>'lot_no')) and b.stock_type='TRADED' and b.data_mode=p_data_mode),0))
      then raise exception 'Readymade quantity exceeds available stock.'; end if;
    end if;

    for ln in
        select *
        from jsonb_array_elements(p_lines)
    loop

        if (ln->>'stock_type') not in(
            'REGULAR',
            'ASST',
            'TRADED'
        )
        or (ln->>'qty')::int<=0
        then
            raise exception 'Invalid PI line';
        end if;


        select coalesce(sum(available_qty),0)
        into avail
        from rr_fg_stock_balance_v787
        where upper(trim(lot_no))=
              upper(trim(ln->>'lot_no'))
          and stock_type=ln->>'stock_type'
          and data_mode=p_data_mode;


        if p_finalize
           and avail<(ln->>'qty')::int
        then
            raise exception 'Insufficient stock';
        end if;


        if ln->>'stock_type'='TRADED' then

            v_trade :=
              public.rr_trade_effective_rate_v849(
                ln->>'lot_no',
                p_buyer_name,
                p_data_mode
              );

            v_rate:=(v_trade->>'final_rate')::numeric;
            -- TEST71 party billing uses one flat party discount, including traded items.
            -- Read the default on the server; never authorize a discount from line JSON.
            if upper(p_data_mode)='TEST' and ln ? 'party_discount_per_piece' then
                select coalesce(allowed_discount_per_piece,0) into v_party_discount
                from public.rr_customers
                where lower(customer_name)=lower(trim(p_buyer_name)) and is_active is true
                order by updated_at desc limit 1;
                if v_party_discount is null or v_party_discount<0 or v_party_discount>10 then
                    raise exception 'Invalid customer flat discount.';
                end if;
                if coalesce((ln->>'gross_rate')::numeric,-1)<0 or (ln->>'gross_rate')::numeric::text in ('NaN','Infinity','-Infinity') then raise exception 'Valid Readymade bill rate required.'; end if;
                v_rate:=greatest(0,(ln->>'gross_rate')::numeric-v_party_discount);
            end if;

        else

            v_rate:=(ln->>'rate')::numeric;

        end if;


        v_serial:=v_serial+1;
        insert into rr_fg_pi_lines_v787
        (
            pi_id,
            lot_no,
            short_item_name,
            stock_type,
            qty,
            original_rate,
            final_rate,
            amount,
            serial_no
        )
        values
        (
            pid,
            ln->>'lot_no',
            coalesce(
              nullif(ln->>'short_item_name',''),
              ln->>'lot_no'
            ),
            ln->>'stock_type',
            (ln->>'qty')::int,
            v_rate,
            v_rate,
            (ln->>'qty')::int*v_rate,
            v_serial
        );

    end loop;


    select coalesce(sum(amount),0)
    into sub
    from rr_fg_pi_lines_v787
    where pi_id=pid;

    raw:=
      sub+
      (sub*p_value_added_pct/100)+
      p_packing_other;

    grand:=round(raw/10)*10;


    update rr_fg_pi_v787
    set
        value_added_pct=p_value_added_pct,
        packing_other=p_packing_other,
        sub_total=sub,
        round_off=grand-raw,
        grand_total=grand,
        updated_at=now()
    where id=pid;


    select version_no
    into ver
    from rr_fg_pi_v787
    where id=pid;


    insert into rr_fg_pi_versions_v787
    (
        pi_id,
        version_no,
        snapshot
    )
    select
        pid,
        ver,
        jsonb_build_object(
            'header',to_jsonb(p),
            'lines',
            (
                select jsonb_agg(to_jsonb(l))
                from rr_fg_pi_lines_v787 l
                where l.pi_id=pid
            )
        )
    from rr_fg_pi_v787 p
    where p.id=pid
    on conflict do nothing;


    if p_finalize then

        cpi:=rr_fg_next_no_v787(
          'CPI',
          p_data_mode,
          case when p_data_mode='TEST' then 'TCI' else 'CI' end
        );


        for ln in
            select to_jsonb(l)
            from rr_fg_pi_lines_v787 l
            where l.pi_id=pid
        loop

            insert into rr_fg_stock_ledger_v787
            (
                txn_type,
                ref_type,
                ref_id,
                lot_no,
                stock_type,
                location_code,
                qty_delta,
                rate,
                data_mode,
                created_by,
                meta
            )
            values
            (
                'CI_SALE',
                'CI_LINE',
                (ln->>'id')::uuid,
                ln->>'lot_no',
                ln->>'stock_type',
                null,
                -(ln->>'qty')::int,
                (ln->>'final_rate')::numeric,
                p_data_mode,
                v_actor,
                jsonb_build_object(
                    'pi_id',pid,
                    'source_type',
                    case
                      when ln->>'stock_type'='TRADED'
                      then 'TRADED'
                      else 'MANUFACTURED'
                    end
                )
            );

        end loop;


        update rr_fg_pi_v787
        set
            status='CI_FINAL',
            cpi_no=cpi,
            finalized_by=v_actor,
            finalized_at=now()
        where id=pid;

    end if;


    select pi_no
    into pi
    from rr_fg_pi_v787
    where id=pid;


    return jsonb_build_object(
        'pi_id',pid,
        'pi_no',pi,
        'cpi_no',cpi,
        'grand_total',grand
    );

end
$function$
;

CREATE OR REPLACE FUNCTION public.rr_purchase_return_post_universal_v806(p_source_type text, p_purchase_id uuid, p_return_qty numeric, p_reason text, p_data_mode text DEFAULT 'TEST'::text, p_return_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text, p_options jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_type text:=upper(trim(coalesce(p_source_type,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_roll_id uuid;
  v_division_id uuid;
  v_result jsonb;
begin
  if v_type in ('READYMADE','TRADED') then return public.rr_rm_purchase_return_test71(p_purchase_id,p_return_qty,p_reason,coalesce(p_return_date,current_date),p_remarks,nullif(p_options->>'idempotency_key','')); end if;
  if v_type not in(
    'REGULAR_CLOTH',
    'MATCHING_CLOTH',
    'STICKER',
    'METAL_ID',
    'GENERIC_MATERIAL'
  ) then
    raise exception 'Unsupported Purchase Return source type: %',v_type;
  end if;

  if p_purchase_id is null then
    raise exception 'Purchase ID required.';
  end if;

  if coalesce(p_return_qty,0)<=0 then
    raise exception 'Return Qty must be greater than zero.';
  end if;

  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Purchase Return reason required.';
  end if;

  if v_mode not in('TEST','REAL') then
    raise exception 'Data Mode must be TEST or REAL.';
  end if;

  perform public.rr_app_data_mode_assert_v786(v_mode);

  if v_type='REGULAR_CLOTH' then

    begin
      v_roll_id:=nullif(p_options->>'roll_id','')::uuid;
      v_division_id:=nullif(p_options->>'division_id','')::uuid;
    exception when others then
      raise exception 'Invalid Regular Cloth roll/division option.';
    end;

    v_result:=public.rr_cb_purchase_return_v806(
      p_purchase_id,
      p_return_qty,
      v_mode,
      p_reason,
      v_roll_id,
      v_division_id,
      coalesce(p_return_date,current_date),
      p_remarks
    );

  elsif v_type='MATCHING_CLOTH' then

    v_result:=public.rr_mc_purchase_return_v806(
      p_purchase_id,
      p_return_qty,
      v_mode,
      p_reason,
      coalesce(p_return_date,current_date),
      p_remarks
    );

  elsif v_type in('STICKER','METAL_ID') then

    if not exists(
      select 1
      from public.rr_accessory_purchase_ledger_v804 a
      where a.id=p_purchase_id
        and a.entry_type='PURCHASE'
        and a.item_type=v_type
        and a.data_mode=v_mode
    ) then
      raise exception '% Purchase record not found for selected Data Mode.',
        replace(v_type,'_',' ');
    end if;

    v_result:=public.rr_accessory_purchase_return_v806(
      p_purchase_id,
      p_return_qty,
      p_reason,
      coalesce(p_return_date,current_date),
      p_remarks
    );

  elsif v_type='GENERIC_MATERIAL' then

    v_result:=public.rr_material_purchase_return_v806(
      p_purchase_id,
      p_return_qty,
      p_reason,
      coalesce(p_return_date,current_date),
      p_remarks
    );

  end if;

  return coalesce(v_result,'{}'::jsonb)
    || jsonb_build_object(
         'universal_source_type',v_type,
         'universal_data_mode',v_mode
       );
end $function$
;
-- One traded stock event = one RRQ event. PI drafts never consume RRQ.
create or replace function public.rr_rm_stock_event_test71() returns trigger language plpgsql security definer set search_path=public as $$
declare s record;q record;orig record;lineid uuid;delta numeric:=0;base numeric;approved numeric;balancej numeric;
begin
 if new.stock_type<>'TRADED' or new.data_mode<>'TEST' then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(new.lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where lot_no=new.lot_no and data_mode=new.data_mode for update;
 if not found then raise exception 'Readymade source stock missing.';end if;
 if new.txn_type='CI_SALE' then
 select * into q from public.rrq_lot_rates_v9300 where lot_no=new.lot_no and data_mode=new.data_mode and dispatch_ready;
 if not found or s.costing_snapshot_test71 is null then raise exception 'Readymade costing and final rate approval required before CI.';end if;
 approved:=q.final_sale_rate;
 delta:=(new.rate-approved)*abs(new.qty_delta);
 new.meta:=coalesce(new.meta,'{}'::jsonb)||jsonb_build_object('approved_rate_snapshot',approved,'bill_rrq_per_pc',new.rate-approved);
 elsif new.txn_type in('SALES_RETURN','RCI_IN') then
 if new.ref_type='RETURN' then select cpi_line_id into lineid from public.rr_fg_returns_v787 where id=new.ref_id;
 else lineid:=nullif(new.meta->>'source_ci_line_id','')::uuid;end if;
 select * into orig from public.rr_fg_stock_ledger_v787 where ref_type='CI_LINE' and ref_id=lineid and stock_type='TRADED' and txn_type='CI_SALE' and data_mode=new.data_mode order by created_at limit 1;
 if found then delta:=-coalesce((orig.meta->>'bill_rrq_per_pc')::numeric,0)*new.qty_delta;end if;
 new.meta:=coalesce(new.meta,'{}'::jsonb)||jsonb_build_object('returned_invoice_line',lineid,'invoice_rate',new.rate);
 new.rate:=s.purchase_rate; -- inventory value is purchase cost, customer credit stays invoice rate.
 elsif new.txn_type='READYMADE_PURCHASE_RETURN' then
 select * into q from public.rrq_lot_rates_v9300 where lot_no=new.lot_no and data_mode=new.data_mode and dispatch_ready;
 if found then delta:=-(q.final_sale_rate-q.base_sale_rate)*abs(new.qty_delta);end if;
 end if;
 if new.txn_type in('CI_SALE','SALES_RETURN','RCI_IN','READYMADE_PURCHASE_RETURN') then
 if exists(select 1 from public.rrq_rate_ledger_v9300 where ref_type='RM_STOCK_EVENT' and ref_id=new.id and data_mode=new.data_mode) then raise exception 'Readymade stock event already applied.';end if;
 insert into public.rrq_balance_v9300(data_mode,balance) values(new.data_mode,0) on conflict do nothing;
 update public.rrq_balance_v9300 set balance=balance+delta,updated_at=now() where data_mode=new.data_mode returning balance into balancej;
 insert into public.rrq_rate_ledger_v9300(data_mode,lot_no,event_type,ref_type,ref_id,qty,previous_rate,new_rate,delta_per_pc,quota_delta,balance_after,reason)
 values(new.data_mode,new.lot_no,new.txn_type,'RM_STOCK_EVENT',new.id,abs(new.qty_delta),coalesce(approved,0),new.rate,delta/nullif(abs(new.qty_delta),0),delta,balancej,'Readymade stock-event RRQ');
 end if;
 return new;
end $$;
revoke all on function public.rr_rm_stock_event_test71() from public,anon,authenticated;
create trigger rr_rm_stock_event_test71 before insert on public.rr_fg_stock_ledger_v787 for each row when(new.stock_type='TRADED' and new.data_mode='TEST') execute function public.rr_rm_stock_event_test71();

create or replace function public.rr_rm_stock_balance_refresh_test71() returns trigger language plpgsql security definer set search_path=public as $$
declare available numeric;
begin
 if new.stock_type<>'TRADED' or new.data_mode<>'TEST' then return new;end if;
 select coalesce(sum(qty_delta),0) into available from public.rr_fg_stock_ledger_v787 where lot_no=new.lot_no and stock_type='TRADED' and data_mode=new.data_mode;
 update public.rr_rm_stock_v849_2c6 set qty_sold=qty_received-available,updated_at=now() where lot_no=new.lot_no and data_mode=new.data_mode;
 return new;
end $$;
revoke all on function public.rr_rm_stock_balance_refresh_test71() from public,anon,authenticated;
create trigger rr_rm_stock_balance_refresh_test71 after insert on public.rr_fg_stock_ledger_v787 for each row when(new.stock_type='TRADED' and new.data_mode='TEST') execute function public.rr_rm_stock_balance_refresh_test71();

-- Legacy known sales return reuses the existing Accounts posting engine.
create or replace function public.rr_rm_sales_return_accounts_test71() returns trigger language plpgsql security definer set search_path=public as $$
declare buyer uuid;party uuid;ledger uuid;
begin
 if new.stock_type<>'TRADED' or new.data_mode<>'TEST' or new.mode<>'KNOWN' then return new;end if;
 select p.buyer_id into buyer from public.rr_fg_pi_lines_v787 l join public.rr_fg_pi_v787 p on p.id=l.pi_id where l.id=new.cpi_line_id and p.status='CI_FINAL' and p.data_mode=new.data_mode;
 if buyer is null then raise exception 'Readymade return requires final CI in the same mode.';end if;
 party:=public.rr_accounts_ensure_buyer_ledger_v9754(buyer);
 select l.id into ledger from public.rr_ledgers_v805 l join public.rr_account_categories_v805 c on c.id=l.category_id where c.category_code='SALES_RETURN' and l.is_active order by l.created_at limit 1;
 if ledger is null then raise exception 'Sales Return account mapping required.';end if;
 perform public.rr_accounts_mirror_post_v806('SALES_RETURN',new.amount,jsonb_build_array(jsonb_build_object('ledger_id',ledger,'dr',new.amount,'cr',0),jsonb_build_object('ledger_id',party,'dr',0,'cr',new.amount)),'READYMADE_SALES_RETURN',new.id::text,party,new.return_no,current_date,'Readymade sales return',new.data_mode);
 return new;
end $$;
revoke all on function public.rr_rm_sales_return_accounts_test71() from public,anon,authenticated;
create trigger rr_rm_sales_return_accounts_test71 after insert on public.rr_fg_returns_v787 for each row when(new.stock_type='TRADED' and new.data_mode='TEST') execute function public.rr_rm_sales_return_accounts_test71();

-- READ API returns role-safe columns; never query raw purchase cost from a Sales screen.
create or replace function public.rr_rm_cards_test71(p_search text default '') returns jsonb language plpgsql stable security definer set search_path=public as $$
declare priv boolean;outj jsonb;
begin
 perform public.rr_fg_assert_user_v787();
 priv:=coalesce((public.rr_costing_user_scope_v760(null)->>'can_view_private_cost')::boolean,false);
 select coalesce(jsonb_agg(jsonb_build_object('stock_id',s.stock_id,'lot_no',s.lot_no,'item_name',s.item_name,'received_qty',s.qty_received,'available_qty',s.available_qty,'image_url',s.final_image_url,'approved_rate',q.final_sale_rate,'approval_ready',q.dispatch_ready,'costing',public.rr_rm_costing_test71(s.lot_no,'TEST'))||case when priv then jsonb_build_object('purchase_rate',s.purchase_rate) else '{}'::jsonb end order by s.lot_no),'[]'::jsonb) into outj
 from public.rr_rm_stock_v849_2c6 s left join public.rrq_lot_rates_v9300 q on q.lot_no=s.lot_no and q.data_mode=s.data_mode where s.data_mode='TEST' and concat_ws(' ',s.lot_no,s.item_name) ilike '%'||coalesce(p_search,'')||'%';
 return outj;
end $$;
revoke all on function public.rr_rm_cards_test71(text) from public,anon;
grant execute on function public.rr_rm_cards_test71(text) to authenticated;

-- Public traded pricing follows approved RRQ rate; private purchase costs removed.
create or replace function public.rr_trade_effective_rate_v849(p_lot_no text,p_party_name text,p_data_mode text default 'TEST') returns jsonb language plpgsql security definer set search_path=public as $$
declare s record;target numeric;party numeric:=0;offer numeric:=0;disc numeric;ratej jsonb;
begin
 perform public.rr_fg_assert_user_v787();
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode=upper(p_data_mode) and sale_ready;
 if not found then raise exception 'Readymade lot not found.';end if;
 select final_sale_rate into target from public.rrq_lot_rates_v9300 where lot_no=s.lot_no and data_mode=s.data_mode and dispatch_ready;
 if target is null then ratej:=public.rr_rm_costing_test71(s.lot_no,p_data_mode);target:=(ratej->>'source_rate')::numeric;end if;
 select coalesce(max(discount_per_pc),0) into party from public.rr_trade_party_discount_v849 where upper(trim(party_name))=upper(trim(p_party_name)) and data_mode=s.data_mode and is_active;
 select coalesce(max(discount_per_pc),0) into offer from public.rr_trade_special_offer_v849 where data_mode=s.data_mode and is_active and (lot_no is null or upper(trim(lot_no))=upper(trim(p_lot_no))) and (party_name is null or upper(trim(party_name))=upper(trim(p_party_name))) and (valid_from is null or current_date>=valid_from) and (valid_to is null or current_date<=valid_to);
 disc:=least(greatest(party+offer,0),s.max_customer_discount_per_pc);
 return jsonb_build_object('ok',true,'lot_no',s.lot_no,'source_type','TRADED','target_sale_rate',target,'party_discount',party,'special_offer_discount',offer,'applied_discount',disc,'maximum_discount',s.max_customer_discount_per_pc,'minimum_allowed_sale_rate',greatest(0,target-s.max_customer_discount_per_pc),'final_rate',greatest(0,target-disc));
end $$;

-- Strict grants on all RM mutations, including the existing unauthenticated endpoints.
revoke all on function public.rr_rm_purchase_create_v849_2c6(text,date,text),public.rr_rm_purchase_replace_lines_v849_2c6(uuid,jsonb),public.rr_rm_purchase_post_v849_2c6(uuid),public.rr_rm_sync_trade_stock_to_fg_v849(uuid),public.rr_trade_effective_rate_v849(text,text,text) from public,anon;
grant execute on function public.rr_rm_purchase_create_v849_2c6(text,date,text),public.rr_rm_purchase_replace_lines_v849_2c6(uuid,jsonb),public.rr_rm_purchase_post_v849_2c6(uuid),public.rr_rm_sync_trade_stock_to_fg_v849(uuid),public.rr_trade_effective_rate_v849(text,text,text) to authenticated;

