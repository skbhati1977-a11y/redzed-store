create or replace function public.rr_rm_costing_test71(p_lot_no text,p_data_mode text default 'TEST') returns jsonb language plpgsql stable security definer set search_path=public as $$
declare s record;h record;ps date;pe date;shared jsonb;ratio numeric;pcs numeric;oh numeric:=0;sal numeric:=0;rows jsonb;salaryheads jsonb;outj jsonb;private_ok boolean;
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
 select coalesce(jsonb_agg(jsonb_build_object('head',head,'monthly_salary',amount,'readymade_share',round(amount*coalesce(ratio,0),2),'per_pc',round(amount*coalesce(ratio,0)/nullif(pcs,0),6))),'[]'::jsonb) into salaryheads from (
 select case when upper(coalesce(role_code,'')) in('ACCOUNT','ACCOUNTS') or public.rr_costing_canonical_department_v760(department_code)='ACCOUNTS' then 'ACCOUNTS_SALARY' when upper(coalesce(role_code,'')) in('SALESMAN','SALES') or public.rr_costing_canonical_department_v760(department_code)='SALES' then 'SALES_SALARY' else 'ADMIN_SALARY' end head,sum(monthly_salary) amount
 from public.rr_salaried_profile_canonical_v294 where upper(data_mode)=upper(p_data_mode) and effective_from<=pe and(effective_to is null or effective_to>=ps) and(public.rr_costing_canonical_department_v760(department_code) in('ADMIN','ACCOUNTS','SALES') or upper(coalesce(role_code,'')) in('ADMIN','ACCOUNT','ACCOUNTS','SALESMAN','SALES')) group by 1) a;
 with pool as (
 select case upper(expense_code) when 'ELECTRICITY' then 'ELECTRICITY_EXPENSE' when 'WATER' then 'WATER_EXPENSE' when 'RENT' then 'RENT_EXPENSE' else upper(expense_code) end code,expense_name label,business_stream, sum(amount*greatest(0,least(period_end,pe)-greatest(period_start,ps)+1)::numeric/greatest(1,period_end-period_start+1)) amount
 from public.rr_cost_expense_pool_v850 where data_mode=upper(p_data_mode) and is_active and period_start<=pe and period_end>=ps
 and (upper(business_stream) in('ALL','TRADING','READYMADE','COMMON_BUSINESS','COMMON_SALES') or upper(expense_code) in('ELECTRICITY','ELECTRICITY_EXPENSE','WATER','WATER_EXPENSE','RENT','RENT_EXPENSE')) and upper(expense_code) not like '%SALARY%'
 group by upper(expense_code),expense_name,business_stream
 ),acct as (
 select c.category_code code,c.category_name label,'ALL'::text business_stream,sum(p.dr_amount-p.cr_amount) amount
 from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id
 join public.rr_ledgers_v805 l on l.id=p.ledger_id join public.rr_account_categories_v805 c on c.id=l.category_id
 where t.data_mode=upper(p_data_mode) and t.status='POSTED' and coalesce(t.bill_date,t.transaction_datetime::date) between ps and pe
 and c.category_code in('ELECTRICITY_EXPENSE','WATER_EXPENSE','RENT_EXPENSE','TELEPHONE_INTERNET','STATIONERY_EXPENSE','ADMIN_OFFICE_EXPENSE','SELLING_DISTRIBUTION','BANK_CHARGES','PROFESSIONAL_FEES','REPAIR_MAINTENANCE','OTHER_EXPENSE')
 and not exists(select 1 from pool e where e.code=c.category_code) group by c.category_code,c.category_name
 ),fixed as(
 select case upper(cost_code) when 'ELECTRICITY' then 'ELECTRICITY_EXPENSE' when 'WATER' then 'WATER_EXPENSE' when 'RENT' then 'RENT_EXPENSE' else upper(cost_code) end code,cost_name label,'ALL'::text business_stream,
 coalesce(monthly_amount,annual_amount/12,rate_per_pc*pcs,0) amount
 from public.rr_cost_fixed_rule_v850 f where data_mode=upper(p_data_mode) and is_active and effective_from<=pe and (effective_to is null or effective_to>=ps)
 and (upper(business_stream) in('ALL','COMMON_BUSINESS','COMMON_SALES','TRADING','READYMADE') or upper(cost_code) in('ELECTRICITY','WATER','RENT'))
 and upper(cost_code) not like '%SALARY%' and upper(cost_code) not like '%MARGIN%'
 and not exists(select 1 from pool e where e.code=case upper(f.cost_code) when 'ELECTRICITY' then 'ELECTRICITY_EXPENSE' when 'WATER' then 'WATER_EXPENSE' when 'RENT' then 'RENT_EXPENSE' else upper(f.cost_code) end)
 and not exists(select 1 from acct e where e.code=upper(f.cost_code))
 ),allheads as(select * from pool union all select * from acct union all select * from fixed),a as(
 select *,amount*case when upper(business_stream) not in('READYMADE','TRADING') then coalesce(ratio,0) else 1 end/nullif(pcs,0) per_pc from allheads)
 select coalesce(jsonb_agg(jsonb_build_object('head',code,'label',label,'period_amount',amount,'business_stream',business_stream,'per_pc',round(per_pc,6)) order by code),'[]'::jsonb),coalesce(sum(per_pc),0) into rows,oh from a;
 outj:=jsonb_build_object('ok',pcs>0 and shared->>'state'='READY','costing_complete',pcs>0 and shared->>'state'='READY','version','TEST71_READYMADE','path','READYMADE_WEIGHTED_COST_TEST71','lot_no',s.lot_no,'qty',s.qty_received,'period_start',ps,'period_end',pe,'purchase_cost_per_pc',s.purchase_rate,'owner_margin_per_pc',22,'salary_per_pc',sal,'overhead_per_pc',oh,'overhead_heads',rows,'salary_allocation',shared,'salary_heads',salaryheads,'total_cost_per_pc',s.purchase_rate+sal+oh,'source_rate',round(s.purchase_rate+sal+oh+22,0),'calculated_sale_rate',s.purchase_rate+sal+oh+22,'frozen',false);
 end if;
 if private_ok then return outj||jsonb_build_object('qty',s.available_qty); end if;
 return jsonb_build_object('ok',outj->'ok','costing_complete',outj->'costing_complete','lot_no',s.lot_no,'qty',s.available_qty,'source_rate',outj->'source_rate','calculated_sale_rate',outj->'source_rate','path',outj->'path','frozen',outj->'frozen');
end $$;