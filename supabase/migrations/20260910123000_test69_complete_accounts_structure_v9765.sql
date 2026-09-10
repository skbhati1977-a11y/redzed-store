-- V9765: complete, zero-visible chart of accounts for the TEST69 easy Accounts Hub.
begin;

insert into public.rr_account_categories_v805(category_code,category_name,group_id,is_active)
select x.code,x.name,g.id,true
from (values
 ('LOANS_ADVANCES_ASSET','Loans & Advances (Asset)','ASSET'),
 ('STAFF_ADVANCE','Staff Advances','ASSET'),
 ('SUPPLIER_ADVANCE','Advance to Suppliers','ASSET'),
 ('SECURITY_DEPOSIT','Security Deposits','ASSET'),
 ('INVENTORY_STOCK','Inventory / Closing Stock','ASSET'),
 ('RAW_MATERIAL_STOCK','Raw Material Stock','ASSET'),
 ('WORK_IN_PROGRESS','Work in Progress (WIP)','ASSET'),
 ('FINISHED_GOODS_STOCK','Finished Goods Stock','ASSET'),
 ('PREPAID_EXPENSE','Prepaid Expenses','ASSET'),
 ('ADVANCE_TAX','Advance Tax / TDS Receivable','ASSET'),
 ('LOANS_PAYABLE','Loans Payable','LIABILITY'),
 ('SECURED_LOANS','Secured Loans','LIABILITY'),
 ('UNSECURED_LOANS','Unsecured Loans','LIABILITY'),
 ('SALARY_PAYABLE','Salary & Wages Payable','LIABILITY'),
 ('EXPENSE_PAYABLE','Outstanding Expenses','LIABILITY'),
 ('CUSTOMER_ADVANCE','Advance from Customers','LIABILITY'),
 ('CAPITAL_ACCOUNT','Capital Account','EQUITY'),
 ('RESERVES_SURPLUS','Reserves & Surplus','EQUITY'),
 ('DIRECT_MATERIAL_CONSUMPTION','Direct Material Consumption','PURCHASE'),
 ('PURCHASE_RETURN_MFG','Purchase Returns / Debit Notes','PURCHASE'),
 ('DIRECT_LABOUR','Direct Labour / Production Wages','SALARY'),
 ('SALARY_ADMIN','Administrative Salary','SALARY'),
 ('SALARY_SALES','Sales Salary','SALARY'),
 ('BONUS_INCENTIVE','Bonus & Incentives','SALARY'),
 ('EMPLOYER_CONTRIBUTION','Employer PF / ESI Contribution','SALARY'),
 ('FACTORY_OVERHEAD','Factory Overheads','EXPENSE'),
 ('POWER_FUEL','Power & Fuel','EXPENSE'),
 ('JOB_WORK_CHARGES','Job Work Charges','EXPENSE'),
 ('QUALITY_REJECTION_LOSS','Quality / Rejection Loss','EXPENSE'),
 ('STOCK_ADJUSTMENT_LOSS','Stock Adjustment Loss','EXPENSE'),
 ('DEPRECIATION','Depreciation','EXPENSE'),
 ('SELLING_DISTRIBUTION','Selling & Distribution Expense','EXPENSE'),
 ('ADMIN_OFFICE_EXPENSE','Administrative & Office Expense','EXPENSE'),
 ('INTEREST_FINANCE_COST','Interest & Finance Cost','EXPENSE'),
 ('BAD_DEBTS','Bad Debts','EXPENSE'),
 ('SCRAP_SALE','Scrap Sale','INCOME'),
 ('JOB_WORK_INCOME','Job Work Income','INCOME'),
 ('INTEREST_INCOME','Interest Income','INCOME'),
 ('STOCK_ADJUSTMENT_GAIN','Stock Adjustment Gain','INCOME'),
 ('TDS_PAYABLE','TDS Payable','TAX'),
 ('PF_ESI_PAYABLE','PF / ESI Payable','TAX')
) x(code,name,group_code)
join public.rr_account_groups_v805 g on g.group_code=x.group_code and g.is_active
on conflict(category_code) do update set category_name=excluded.category_name,group_id=excluded.group_id,is_active=true;

create or replace function public.rr_accounts_structure_v9765(p_search text default '',p_group_code text default null,p_data_mode text default 'TEST')
returns table(group_code text,group_name text,category_id uuid,category_code text,category_name text,ledger_id uuid,ledger_code text,ledger_name text,ledger_kind text,debit_balance numeric,credit_balance numeric,net_balance numeric,entry_count bigint)
language plpgsql stable security definer set search_path='public' as $function$
declare v_q text:=lower(trim(coalesce(p_search,'')));v_role text;
begin
 select lower(role_code) into v_role from public.rr_user_profiles where auth_user_id=auth.uid() and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
 if v_role not in('owner','super_admin','superadmin','admin','sales','account','accounts') then raise exception 'Owner/Admin/Sales/Accounts access required.'; end if;
 return query
 with totals as(
  select b.ledger_id,sum(coalesce(b.dr_amount,0)) dr,sum(coalesce(b.cr_amount,0)) cr,count(*) entries
  from public.rr_account_reporting_base_v806 b
  where b.data_mode=upper(coalesce(p_data_mode,'TEST')) and coalesce(b.transaction_status,'POSTED') not in('VOIDED','CANCELLED')
  group by b.ledger_id
 )
 select g.group_code,g.group_name,c.id,c.category_code,c.category_name,l.id,l.ledger_code,l.ledger_name,l.ledger_kind,
 round(greatest(coalesce(t.dr,0)-coalesce(t.cr,0),0),2),round(greatest(coalesce(t.cr,0)-coalesce(t.dr,0),0),2),round(coalesce(t.dr,0)-coalesce(t.cr,0),2),coalesce(t.entries,0)
 from public.rr_account_groups_v805 g
 join public.rr_account_categories_v805 c on c.group_id=g.id and c.is_active
 left join public.rr_ledgers_v805 l on l.category_id=c.id and l.is_active
 left join totals t on t.ledger_id=l.id
 where g.is_active
 and (nullif(trim(coalesce(p_group_code,'')),'') is null or g.group_code=upper(trim(p_group_code)))
 and (v_q='' or lower(g.group_name) like '%'||v_q||'%' or lower(c.category_name) like '%'||v_q||'%' or lower(coalesce(l.ledger_name,'')) like '%'||v_q||'%' or lower(coalesce(l.ledger_code,'')) like '%'||v_q||'%')
 order by g.group_name,c.category_name,lower(coalesce(l.ledger_name,''));
end $function$;

revoke all on function public.rr_accounts_structure_v9765(text,text,text) from public,anon;
grant execute on function public.rr_accounts_structure_v9765(text,text,text) to authenticated,service_role;
commit;
