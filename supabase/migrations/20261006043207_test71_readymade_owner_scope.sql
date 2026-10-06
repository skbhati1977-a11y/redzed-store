create or replace function public.rr_rm_assert_operator_test71() returns void language plpgsql security definer set search_path=public as $$
begin
 perform public.rr_fg_assert_user_v787();
 if lower(coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','')) not in('owner','super_admin','superadmin','admin','accounts','account') then raise exception 'Readymade Purchase / Accounts permission required.'; end if;
end $$;
create or replace function public.rr_rm_costing_test71(p_lot_no text,p_data_mode text default 'TEST') returns jsonb language plpgsql stable security definer set search_path=public as $$
declare s record;h record;ps date;pe date;shared jsonb;ratio numeric;pcs numeric;oh numeric:=0;sal numeric:=0;rows jsonb;outj jsonb;private_ok boolean;
begin
 perform public.rr_fg_assert_user_v787();
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode=upper(p_data_mode);
 if not found then raise exception 'Readymade lot not found.'; end if;
 private_ok:=coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','') in('OWNER','SUPER_ADMIN');
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
create or replace function public.rr_rm_approve_rate_test71(p_lot_no text,p_final_rate numeric,p_reason text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare s record;j jsonb;r jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin','admin') then raise exception 'Owner / Admin rate approval required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(p_lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST' for update;
 if not found then raise exception 'Readymade lot not found.';end if;
 -- Freeze full private costing under owner scope; Admin can approve but cannot read it.
 if s.costing_snapshot_test71 is null then
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin') then raise exception 'Owner must finalize Readymade costing first.';end if;
 j:=public.rr_rm_costing_test71(s.lot_no,'TEST');
 if not coalesce((j->>'costing_complete')::boolean,false) then raise exception 'Monthly weighted allocation is pending.';end if;
 update public.rr_rm_stock_v849_2c6 set costing_snapshot_test71=j||jsonb_build_object('frozen',true,'frozen_at',now()) where stock_id=s.stock_id;
 end if;
 r:=public.rrq_apply_packing_rate_core_test71(s.lot_no,p_final_rate,'TEST',p_reason);
 update public.rr_rm_stock_v849_2c6 set target_sale_rate=p_final_rate,minimum_allowed_sale_rate=greatest(0,p_final_rate-max_customer_discount_per_pc),markup_mode='DEFAULT_22',markup_per_pc=22 where stock_id=s.stock_id;
 return r;
end $$;
create or replace function public.rr_rm_cards_test71(p_search text default '') returns jsonb language plpgsql stable security definer set search_path=public as $$
declare priv boolean;outj jsonb;
begin
 perform public.rr_fg_assert_user_v787();
 priv:=coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role','') in('OWNER','SUPER_ADMIN');
 select coalesce(jsonb_agg(jsonb_build_object('stock_id',s.stock_id,'lot_no',s.lot_no,'item_name',s.item_name,'received_qty',s.qty_received,'available_qty',s.available_qty,'image_url',s.final_image_url,'approved_rate',q.final_sale_rate,'approval_ready',q.dispatch_ready,'costing',public.rr_rm_costing_test71(s.lot_no,'TEST'))||case when priv then jsonb_build_object('purchase_rate',s.purchase_rate) else '{}'::jsonb end order by s.lot_no),'[]'::jsonb) into outj
 from public.rr_rm_stock_v849_2c6 s left join public.rrq_lot_rates_v9300 q on q.lot_no=s.lot_no and q.data_mode=s.data_mode where s.data_mode='TEST' and concat_ws(' ',s.lot_no,s.item_name) ilike '%'||coalesce(p_search,'')||'%';
 return outj;
end $$;
