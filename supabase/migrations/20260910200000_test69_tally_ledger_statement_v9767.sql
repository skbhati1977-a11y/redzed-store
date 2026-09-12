-- V9767: focused Tally-style summaries, statements and voucher drill-down.
create or replace function public.rr_accounts_ledger_summary_v9767(
  p_scope text default 'ALL', p_search text default '', p_from_date date default date_trunc('month',current_date)::date,
  p_to_date date default current_date, p_data_mode text default 'TEST'
) returns table(ledger_id uuid, ledger_name text, opening_balance numeric, total_debit numeric, total_credit numeric, closing_balance numeric)
language plpgsql security definer set search_path=public as $$
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  return query
  with eligible as (
    select l.id,l.ledger_name,l.opening_balance,l.opening_side,l.ledger_kind,c.category_code,g.group_code
    from public.rr_ledgers_v805 l
    left join public.rr_account_categories_v805 c on c.id=l.category_id
    left join public.rr_account_groups_v805 g on g.id=c.group_id
    where l.is_active and (coalesce(trim(p_search),'')='' or l.ledger_name ilike '%'||trim(p_search)||'%' or l.ledger_code ilike '%'||trim(p_search)||'%')
      and case upper(coalesce(p_scope,'ALL'))
        when 'DEBTORS' then l.ledger_kind='CUSTOMER'
        when 'CREDITORS' then l.ledger_kind='SUPPLIER'
        when 'SALARY' then g.group_code='SALARY' or c.category_code ilike '%SALARY%' or c.category_code ilike '%WAGE%'
        when 'EXPENSE' then g.group_code in('EXPENSE','SALARY')
        when 'CASH_BANK' then l.ledger_kind in('CASH','BANK')
        when 'LOAN_ADVANCE' then l.ledger_kind='LOAN' or c.category_code ilike '%LOAN%' or c.category_code ilike '%ADVANCE%'
        else true end
  ), movement as (
    select e.id,
      coalesce(e.opening_balance,0)*(case when e.opening_side='CR' then -1 else 1 end)
        +coalesce(sum(case when t.transaction_datetime::date<p_from_date then p.dr_amount-p.cr_amount else 0 end),0) opening,
      coalesce(sum(case when t.transaction_datetime::date between p_from_date and p_to_date then p.dr_amount else 0 end),0) dr,
      coalesce(sum(case when t.transaction_datetime::date between p_from_date and p_to_date then p.cr_amount else 0 end),0) cr
    from eligible e left join public.rr_account_postings_v805 p on p.ledger_id=e.id
    left join public.rr_account_transactions_v805 t on t.id=p.transaction_id and t.data_mode=upper(coalesce(p_data_mode,'TEST')) and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED')
    group by e.id,e.opening_balance,e.opening_side
  )
  select e.id,e.ledger_name,round(m.opening,2),round(m.dr,2),round(m.cr,2),round(m.opening+m.dr-m.cr,2)
  from eligible e join movement m on m.id=e.id order by e.ledger_name;
end $$;

create or replace function public.rr_accounts_ledger_statement_v9767(
  p_ledger_id uuid, p_from_date date, p_to_date date, p_data_mode text default 'TEST'
) returns table(entry_date date, particulars text, voucher_no text, voucher_type text, debit numeric, credit numeric, running_balance numeric)
language plpgsql security definer set search_path=public as $$
declare v_open numeric;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select coalesce(l.opening_balance,0)*(case when l.opening_side='CR' then -1 else 1 end)
    +coalesce(sum(case when t.transaction_datetime::date<p_from_date then p.dr_amount-p.cr_amount else 0 end),0)
  into v_open from public.rr_ledgers_v805 l
  left join public.rr_account_postings_v805 p on p.ledger_id=l.id
  left join public.rr_account_transactions_v805 t on t.id=p.transaction_id and t.data_mode=upper(coalesce(p_data_mode,'TEST')) and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED')
  where l.id=p_ledger_id group by l.opening_balance,l.opening_side;
  return query
  select t.transaction_datetime::date,
    coalesce(nullif(p.line_narration,''),nullif(t.narration,''),replace(initcap(t.transaction_type),'_',' ')),
    t.voucher_no,replace(initcap(t.transaction_type),'_',' '),round(p.dr_amount,2),round(p.cr_amount,2),
    round(coalesce(v_open,0)+sum(p.dr_amount-p.cr_amount) over(order by t.transaction_datetime,p.id rows unbounded preceding),2)
  from public.rr_account_postings_v805 p join public.rr_account_transactions_v805 t on t.id=p.transaction_id
  where p.ledger_id=p_ledger_id and t.data_mode=upper(coalesce(p_data_mode,'TEST'))
    and t.transaction_datetime::date between p_from_date and p_to_date and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED')
  order by t.transaction_datetime,p.id;
end $$;

create or replace function public.rr_accounts_voucher_detail_v9767(p_voucher_no text,p_data_mode text default 'TEST')
returns table(voucher_no text,entry_date date,voucher_type text,particulars text,ledger_name text,debit numeric,credit numeric,status text)
language plpgsql security definer set search_path=public as $$
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  return query select t.voucher_no,t.transaction_datetime::date,replace(initcap(t.transaction_type),'_',' '),
    coalesce(nullif(p.line_narration,''),nullif(t.narration,''),'—'),l.ledger_name,round(p.dr_amount,2),round(p.cr_amount,2),t.status
  from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id join public.rr_ledgers_v805 l on l.id=p.ledger_id
  where t.voucher_no=trim(p_voucher_no) and t.data_mode=upper(coalesce(p_data_mode,'TEST')) order by p.created_at,p.id;
end $$;

revoke all on function public.rr_accounts_ledger_summary_v9767(text,text,date,date,text),public.rr_accounts_ledger_statement_v9767(uuid,date,date,text),public.rr_accounts_voucher_detail_v9767(text,text) from public,anon;
grant execute on function public.rr_accounts_ledger_summary_v9767(text,text,date,date,text),public.rr_accounts_ledger_statement_v9767(uuid,date,date,text),public.rr_accounts_voucher_detail_v9767(text,text) to authenticated,service_role;
