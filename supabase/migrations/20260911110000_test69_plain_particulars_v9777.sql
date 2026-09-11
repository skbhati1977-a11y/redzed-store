-- V9777: keep account particulars short and business-friendly.
create or replace function public.rr_accounts_plain_particular_v9777(p_transaction_type text,p_source_module text default null)
returns text language sql immutable security invoker set search_path=public as $$
  select case upper(coalesce(p_transaction_type,''))
    when 'SALE' then 'Sales' when 'SALES' then 'Sales' when 'SALES_RETURN' then 'Return'
    when 'RECEIPT' then 'Receipt' when 'PAYMENT' then 'Payment' when 'PURCHASE' then 'Purchase'
    when 'PURCHASE_RETURN' then 'Purchase Return' when 'JOURNAL' then 'Journal' when 'EXPENSE' then 'Expense'
    when 'REVERSAL' then case when coalesce(p_source_module,'') ilike 'RCI%REVERSAL' then 'Return Cancel' else 'Reversed' end
    when 'CHIT_INSTALLMENT' then 'Installment' when 'COMMITTEE_INSTALLMENT' then 'Installment' when 'CHIT_CONTRIBUTION' then 'Installment'
    when 'CHIT_PRIZE' then 'Prize' when 'COMMITTEE_PRIZE_RECEIPT' then 'Prize' when 'COMMITTEE_DIVIDEND' then 'Dividend'
    when 'LOAN_RECEIPT' then 'Loan' when 'LOAN_EMI' then 'Loan EMI' when 'DRAWING' then 'Drawing' when 'FIXED_ASSET' then 'Fixed Asset'
    else 'Entry' end
$$;

create or replace function public.rr_accounts_ledger_statement_v9777(p_ledger_id uuid,p_from_date date,p_to_date date,p_data_mode text default 'TEST')
returns table(entry_date date,particulars text,voucher_no text,voucher_type text,debit numeric,credit numeric,running_balance numeric,piece_qty numeric,pi_id uuid,pi_no text,cpi_no text,requirement_id uuid)
language plpgsql security definer set search_path=public as $$
declare v_open numeric;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select coalesce(l.opening_balance,0)*(case when l.opening_side='CR' then -1 else 1 end)+coalesce(sum(case when t.transaction_datetime::date<p_from_date then p.dr_amount-p.cr_amount else 0 end),0)
  into v_open from public.rr_ledgers_v805 l left join public.rr_account_postings_v805 p on p.ledger_id=l.id
  left join public.rr_account_transactions_v805 t on t.id=p.transaction_id and t.data_mode=upper(coalesce(p_data_mode,'TEST')) and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED')
  where l.id=p_ledger_id group by l.opening_balance,l.opening_side;
  return query select t.transaction_datetime::date,public.rr_accounts_plain_particular_v9777(t.transaction_type,t.source_module),
    coalesce(nullif(t.bill_no,''),t.voucher_no),public.rr_accounts_plain_particular_v9777(t.transaction_type,t.source_module),round(p.dr_amount,2),round(p.cr_amount,2),
    round(coalesce(v_open,0)+sum(p.dr_amount-p.cr_amount) over(order by t.transaction_datetime,p.id rows unbounded preceding),2),
    (pc.j->>'piece_qty')::numeric,(pc.j->>'pi_id')::uuid,pc.j->>'pi_no',pc.j->>'cpi_no',(pc.j->>'requirement_id')::uuid
  from public.rr_account_postings_v805 p join public.rr_account_transactions_v805 t on t.id=p.transaction_id
  cross join lateral (select public.rr_accounts_piece_context_v9775(t.id) j) pc
  where p.ledger_id=p_ledger_id and t.data_mode=upper(coalesce(p_data_mode,'TEST')) and t.transaction_datetime::date between p_from_date and p_to_date
    and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED') order by t.transaction_datetime,p.id;
end $$;

create or replace function public.rr_accounts_voucher_detail_v9777(p_voucher_no text,p_data_mode text default 'TEST')
returns table(transaction_id uuid,voucher_no text,entry_date date,voucher_type text,particulars text,ledger_name text,debit numeric,credit numeric,status text,voucher_piece_qty numeric,pi_id uuid,pi_no text,cpi_no text,requirement_id uuid,source_module text,source_record_id text)
language plpgsql security definer set search_path=public as $$
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  return query select t.id,coalesce(nullif(t.bill_no,''),t.voucher_no),t.transaction_datetime::date,public.rr_accounts_plain_particular_v9777(t.transaction_type,t.source_module),
    public.rr_accounts_plain_particular_v9777(t.transaction_type,t.source_module),l.ledger_name,round(p.dr_amount,2),round(p.cr_amount,2),t.status,
    (pc.j->>'piece_qty')::numeric,(pc.j->>'pi_id')::uuid,pc.j->>'pi_no',pc.j->>'cpi_no',(pc.j->>'requirement_id')::uuid,t.source_module,t.source_record_id
  from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id join public.rr_ledgers_v805 l on l.id=p.ledger_id
  cross join lateral (select public.rr_accounts_piece_context_v9775(t.id) j) pc
  where (t.voucher_no=trim(p_voucher_no) or t.bill_no=trim(p_voucher_no)) and t.data_mode=upper(coalesce(p_data_mode,'TEST')) order by p.created_at,p.id;
end $$;

revoke all on function public.rr_accounts_plain_particular_v9777(text,text),public.rr_accounts_ledger_statement_v9777(uuid,date,date,text),public.rr_accounts_voucher_detail_v9777(text,text) from public,anon;
grant execute on function public.rr_accounts_plain_particular_v9777(text,text),public.rr_accounts_ledger_statement_v9777(uuid,date,date,text),public.rr_accounts_voucher_detail_v9777(text,text) to authenticated,service_role;
