-- V9768: concise business particulars; technical narration remains in voucher audit detail.
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
    case
      when t.transaction_type='REVERSAL' and t.source_module ilike 'RCI%REVERSAL' then 'Return Cancel'
      when t.transaction_type='REVERSAL' then 'Entry Reversed'
      when t.transaction_type in('SALE','SALES') then 'Sale'
      when t.transaction_type='SALES_RETURN' then 'Customer Return'
      when t.transaction_type='RECEIPT' then 'Received'
      when t.transaction_type='PAYMENT' then 'Paid'
      when t.transaction_type='PURCHASE' then 'Purchase'
      when t.transaction_type='PURCHASE_RETURN' then 'Purchase Return'
      when t.transaction_type='JOURNAL' then 'Journal'
      when t.transaction_type='EXPENSE' then 'Expense'
      when t.transaction_type in('CHIT_INSTALLMENT','COMMITTEE_INSTALLMENT','CHIT_CONTRIBUTION') then 'Installment'
      when t.transaction_type in('CHIT_PRIZE','COMMITTEE_PRIZE_RECEIPT') then 'Prize Received'
      when t.transaction_type='COMMITTEE_DIVIDEND' then 'Dividend'
      when t.transaction_type='LOAN_RECEIPT' then 'Loan Received'
      when t.transaction_type='LOAN_EMI' then 'Loan EMI'
      when t.transaction_type='DRAWING' then 'Drawing'
      when t.transaction_type='FIXED_ASSET' then 'Fixed Asset'
      else replace(initcap(t.transaction_type),'_',' ')
    end,
    coalesce(nullif(t.bill_no,''),t.voucher_no),replace(initcap(t.transaction_type),'_',' '),round(p.dr_amount,2),round(p.cr_amount,2),
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
  return query select coalesce(nullif(t.bill_no,''),t.voucher_no),t.transaction_datetime::date,replace(initcap(t.transaction_type),'_',' '),
    coalesce(nullif(p.line_narration,''),nullif(t.narration,''),'—'),l.ledger_name,round(p.dr_amount,2),round(p.cr_amount,2),t.status
  from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id join public.rr_ledgers_v805 l on l.id=p.ledger_id
  where (t.voucher_no=trim(p_voucher_no) or t.bill_no=trim(p_voucher_no)) and t.data_mode=upper(coalesce(p_data_mode,'TEST')) order by p.created_at,p.id;
end $$;

revoke all on function public.rr_accounts_ledger_statement_v9767(uuid,date,date,text),public.rr_accounts_voucher_detail_v9767(text,text) from public,anon;
grant execute on function public.rr_accounts_ledger_statement_v9767(uuid,date,date,text),public.rr_accounts_voucher_detail_v9767(text,text) to authenticated,service_role;
