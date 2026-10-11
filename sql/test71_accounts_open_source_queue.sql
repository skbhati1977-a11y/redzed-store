CREATE OR REPLACE FUNCTION public.rr_accounts_real_chat_home_v500(p_status text DEFAULT 'OPEN'::text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cats jsonb; cards jsonb; s text:=upper(coalesce(p_status,'OPEN'));
begin
  IF upper(coalesce(p_data_mode,'')) NOT IN('TEST','REAL') THEN RAISE EXCEPTION 'Explicit TEST / REAL data mode required.';END IF;
  if auth.uid() IS NULL OR not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  if s not in('OPEN','WORKING','CLOSE') then raise exception 'OPEN / WORKING / CLOSE required.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('code',x.code,'label',x.label,'count',x.n,'amount',x.amount) order by x.sort_no),'[]'::jsonb) into cats from (
    select 1 sort_no,'DEBTORS' code,'SUNDRY DEBTORS' label,count(*) n,coalesce(sum(outstanding_amount),0) amount from public.rr_account_bills_v500 where data_mode=upper(p_data_mode) and bill_kind='RECEIVABLE' and status<>'REVERSED'
    union all select 2,'CREDITORS','SUNDRY CREDITORS',count(*),coalesce(sum(outstanding_amount),0) from public.rr_account_bills_v500 where data_mode=upper(p_data_mode) and bill_kind='PAYABLE' and status<>'REVERSED'
    union all select 3,'SALES','SALES',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type in('SALE','SALES')
    union all select 4,'PURCHASE','PURCHASE',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='PURCHASE'
    union all select 5,'RECEIPTS','RECEIPTS',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='RECEIPT'
    union all select 6,'PAYMENTS','PAYMENTS',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='PAYMENT'
    union all select 7,'EXPENSES','EXPENSES',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='EXPENSE'
    union all select 8,'JOURNALS','JOURNALS',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='JOURNAL'
  ) x;
  if s='OPEN' then
    SELECT coalesce(jsonb_agg(x.card ORDER BY x.sort_at,x.card->>'id'),'[]'::jsonb) INTO cards FROM (
 SELECT b.created_at sort_at,jsonb_build_object('id',b.id,'kind',b.bill_kind,'reference_no',b.bill_no,'detail',coalesce(l.ledger_name,'Party')||' · '||coalesce(t.source_module,'ACCOUNTS'),'amount',b.outstanding_amount,'since',b.bill_date,'state','OPEN','party_ledger_id',b.party_ledger_id,'source_module',coalesce(t.source_module,'ACCOUNTS'),'source_id',b.id,'data_mode',b.data_mode,'next_action',CASE WHEN b.bill_kind='PAYABLE' THEN 'PAYMENT' ELSE 'RECEIPT' END,'action_url','real-accounts-v805.html') card
 FROM public.rr_account_bills_v500 b LEFT JOIN public.rr_account_transactions_v805 t ON t.id=b.source_transaction_id AND t.data_mode=b.data_mode LEFT JOIN public.rr_ledgers_v805 l ON l.id=b.party_ledger_id
 WHERE b.data_mode=upper(p_data_mode) AND b.status<>'REVERSED' AND b.outstanding_amount>0.005
 UNION ALL
 SELECT d.sort_at,jsonb_build_object('id',d.source_id,'kind',d.due_type,'reference_no',d.reference_no,'detail',d.reference_detail,'amount',d.due_amount,'since',d.due_since,'state','OPEN','source_module',d.module_code,'source_id',d.source_id,'data_mode','TEST','next_action',d.due_type,'action_url',null)
 FROM public.rr_accounts_due_v834 d WHERE upper(p_data_mode)='TEST' AND coalesce(d.due_state,'OPEN') NOT IN('CLOSE','CLOSED','POSTED') AND d.due_amount>0.005
 UNION ALL
 SELECT d.due_created_at,jsonb_build_object('id',d.due_entry_id,'kind','WORKER_SALARY_DUE','reference_no',d.due_reference,'detail',d.worker_name||' · '||d.department_code,'amount',d.balance_amount,'since',d.due_date,'state','OPEN','source_module',d.source_module,'source_id',d.due_entry_id,'data_mode',d.data_mode,'next_action','PAY SALARY','action_url','real-salary-home-v786.html')
 FROM public.rr_worker_salary_due_board_v781 d WHERE d.data_mode=upper(p_data_mode) AND d.balance_amount>0.005
 UNION ALL
 SELECT p.updated_at,jsonb_build_object('id',p.payroll_id,'kind','MONTHLY_SALARY_DUE','reference_no',to_char(p.payroll_month,'YYYY-MM'),'detail',coalesce(w.worker_name,p.worker_id::text)||' · Final settlement','amount',s.closing_balance,'since',p.payroll_month,'state','OPEN','source_module','MONTHLY_V779_TEST71','source_id',p.payroll_id,'data_mode',p.data_mode,'next_action','PAY MONTHLY SETTLEMENT','action_url','real-monthly-payroll-v779.html')
 FROM public.rr_monthly_payroll_v779_1 p JOIN public.rr_worker_settlements_v777_2 s ON s.settlement_id=p.settlement_id LEFT JOIN public.rr_worker_directory_unified_v1 w ON w.worker_id=p.worker_id
 WHERE p.data_mode=upper(p_data_mode) AND p.payroll_status='FINAL' AND s.closing_balance>0.005 AND EXISTS(SELECT 1 FROM public.rr_worker_salary_ledger_v781 l WHERE l.source_run_id=p.payroll_id AND l.source_module='MONTHLY_V779_TEST71' AND l.data_mode=p.data_mode AND l.status='POSTED')
 ) x;
  elsif s='WORKING' then
    select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'kind',w.action_kind,'reference_no',w.reference_no,'amount',w.amount,'since',w.accepted_at,'state',w.state,'party_ledger_id',w.party_ledger_id) order by w.accepted_at),'[]'::jsonb) into cards
    from public.rr_accounts_work_item_v500 w where w.data_mode=upper(p_data_mode) and w.state='WORKING';
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.transaction_type,'reference_no',t.voucher_no,'bill_no',t.bill_no,'amount',t.total_amount,'since',t.transaction_datetime,'state','CLOSE','party_ledger_id',t.party_ledger_id) order by t.transaction_datetime desc),'[]'::jsonb) into cards
    from (select * from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' order by transaction_datetime desc limit 80) t;
  end if;
  return jsonb_build_object('version','V500_CANONICAL_ACCOUNTS_CHAT','status',s,'categories',cats,'cards',cards,
    'day_book_rpc','rr_day_book_v806','ledger_rpc','rr_accounts_ledger_statement_v9785');
end $function$
;
REVOKE ALL ON FUNCTION public.rr_accounts_real_chat_home_v500(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_accounts_real_chat_home_v500(text,text) TO authenticated;