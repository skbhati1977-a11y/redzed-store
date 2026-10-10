begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
do $audit$
declare party uuid; cash uuid; other uuid; r jsonb; rev jsonb; tid uuid; dup1 uuid;dup2 uuid;bad jsonb; results jsonb:='{}';n int; ref text:='AUDIT-'||gen_random_uuid()::text;
begin
select id into party from rr_ledgers_v805 where is_active and ledger_kind='SUPPLIER' order by created_at limit 1;
select id into cash from rr_ledgers_v805 where is_active and upper(ledger_kind) in('CASH','BANK') order by created_at limit 1;
select id into other from rr_ledgers_v805 where is_active and id<>party and id<>cash order by created_at limit 1;
if cash is null then raise exception 'cash fixture missing';end if;
r:=rr_accounts_post_payment_v805(party,cash,1.23,ref,'Rollback audit','TEST');tid:=(r->>'transaction_id')::uuid;
select count(*) into n from rr_account_postings_v805 where transaction_id=tid;
if n<>2 then raise exception 'payment posting lines missing';end if;
rev:=rr_accounts_reverse_transaction_v9761(tid,'Rollback audit reversal');
if (select status from rr_account_transactions_v805 where id=tid)<>'REVERSED' then raise exception 'reverse original status failed';end if;
if (select sum(dr_amount-cr_amount) from rr_account_postings_v805 where transaction_id in(tid,(rev->>'reversal_transaction_id')::uuid))<>0 then raise exception 'reversal balance failed';end if;
results:=results||jsonb_build_object('payment_and_reversal','PASS');
r:=rr_accounts_post_receipt_v805(party,cash,1.23,ref||'-R','Rollback audit','TEST');perform rr_accounts_reverse_transaction_v9761((r->>'transaction_id')::uuid,'Rollback audit');
r:=rr_accounts_post_journal_v9763(party,other,1.23,ref||'-J','Rollback audit','TEST');perform rr_accounts_reverse_transaction_v9761((r->>'transaction_id')::uuid,'Rollback audit');
results:=results||jsonb_build_object('receipt_and_journal_reversal','PASS');
r:=rr_accounts_post_payment_v805(party,cash,0.01,ref||'-REPEAT','Repeat audit','TEST');dup1:=(r->>'transaction_id')::uuid;
r:=rr_accounts_post_payment_v805(party,cash,0.01,ref||'-REPEAT','Repeat audit','TEST');dup2:=(r->>'transaction_id')::uuid;
results:=results||jsonb_build_object('same_payment_reference_duplicate_created',dup1<>dup2);
begin bad:=rr_accounts_post_payment_v805(party,party,0.01,ref||'-SAME','Invalid cash mapping audit','TEST');results:=results||jsonb_build_object('same_ledger_payment_accepted',true);exception when others then results:=results||jsonb_build_object('same_ledger_payment_accepted',false,'same_ledger_denial',sqlerrm);end;
begin bad:=rr_accounts_post_payment_v805(party,other,0.01,ref||'-NONCASH','Invalid cash mapping audit','TEST');results:=results||jsonb_build_object('non_cash_payment_source_accepted',true);exception when others then results:=results||jsonb_build_object('non_cash_payment_source_accepted',false,'non_cash_denial',sqlerrm);end;
perform set_config('audit.remaining.payments',results::text,true);
end $audit$;
select current_setting('audit.remaining.payments')::jsonb result;
rollback;
