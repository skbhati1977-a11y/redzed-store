begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
create temporary table first_advance_result(label text,result jsonb) on commit drop;
do $audit$ declare w uuid;p jsonb;r jsonb;r2 jsonb;k uuid:=gen_random_uuid();b bigint;a bigint;pay jsonb;begin
select x.worker_id into w from public.rr_worker_payroll_board_v777_3 x where x.data_mode='TEST' and x.payroll_profile_status='ACTIVE' and x.worker_category='SALARIED' and x.effective_from<=(now() at time zone 'Asia/Kolkata')::date and coalesce(x.effective_to,'9999-12-31')>=(now() at time zone 'Asia/Kolkata')::date and not exists(select 1 from public.rr_worker_advance_balance_v785 v where v.worker_id=x.worker_id and v.data_mode='TEST' and abs(v.total_advance_balance)>0.005) limit 1;
if w is null then raise exception 'Missing configured zero-balance rollback fixture';end if;
p:=public.rr_advance_payment_preview_v785('TEST','SALARIED',array[w],jsonb_build_array(jsonb_build_object('worker_id',w,'amount_paid',1)));
if (p->>'selected_worker_count')::integer<>1 or (p->>'new_advance_payment_total')::numeric<>1 then raise exception 'First advance not selected';end if;
insert into first_advance_result values('configured_zero_balance_first_issue_preview',jsonb_build_object('selected',1,'amount',1));
pay:=jsonb_build_object('p_data_mode','TEST','p_payroll_category_filter','SALARIED','p_worker_ids',jsonb_build_array(w),'p_worker_amounts',jsonb_build_array(jsonb_build_object('worker_id',w,'amount_paid',1)),'p_payment_date',(now() at time zone 'Asia/Kolkata')::date,'p_payment_mode','CASH','p_voucher_no','AUDIT-FIRST-'||k,'p_remarks','Rollback only');
select count(*) into b from public.rr_account_transactions_v805;
r:=public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',k,pay);
r2:=public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',k,pay);
if r->>'batch_id' is distinct from r2->>'batch_id' then raise exception 'Duplicate first advance';end if;
select count(*) into a from public.rr_account_transactions_v805;
if a-b<>1 then raise exception 'Expected exactly one advance journal, got %',a-b;end if;
insert into first_advance_result values('first_issue_retry',jsonb_build_object('same_batch',true,'accounts_journal_delta',a-b));
end $audit$;
select * from first_advance_result;
rollback;

begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
create temporary table advance_bridge_result(label text,result jsonb) on commit drop;
do $test$
declare w uuid;issued uuid;recovered uuid;rev uuid;asset uuid;k uuid:=gen_random_uuid();r jsonb;payload jsonb;before_n bigint;failed boolean:=false;balance numeric;
begin
select x.worker_id into w from public.rr_worker_payroll_board_v777_3 x where x.data_mode='TEST' and x.payroll_profile_status='ACTIVE' and x.worker_category='SALARIED' and x.effective_from<=(now() at time zone 'Asia/Kolkata')::date and coalesce(x.effective_to,'9999-12-31')>=(now() at time zone 'Asia/Kolkata')::date and not exists(select 1 from public.rr_worker_advance_balance_v785 v where v.worker_id=x.worker_id and v.data_mode='TEST' and abs(v.total_advance_balance)>0.005) limit 1;
if w is null then raise exception 'Missing zero balance fixture';end if;
payload:=jsonb_build_object('p_data_mode','TEST','p_payroll_category_filter','SALARIED','p_worker_ids',jsonb_build_array(w),'p_worker_amounts',jsonb_build_array(jsonb_build_object('worker_id',w,'amount_paid',10)),'p_payment_date',(now() at time zone 'Asia/Kolkata')::date,'p_payment_mode','CASH','p_voucher_no','ROLLBACK-ADV-'||k,'p_remarks','Rollback only');
r:=public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',k,payload);
select id into issued from public.rr_worker_advance_ledger_v785 where source_batch_id=(r->>'batch_id')::uuid;
select id into asset from public.rr_ledgers_v805 where ledger_code='ADV_TEST_'||w;
if not exists(select 1 from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id where t.source_module='WORKER_ADVANCE_TEST71' and t.source_record_id=issued::text and p.ledger_id=asset and p.dr_amount=10 and p.cr_amount=0) then raise exception 'Missing advance asset debit';end if;
insert into public.rr_worker_advance_ledger_v785(data_mode,worker_id,entry_date,entry_type,amount,balance_effect,created_by)
values('TEST',w,current_date,'ADVANCE_RECOVERY',4,-4,auth.uid()) returning id into recovered;
if not exists(select 1 from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id where t.source_module='WORKER_ADVANCE_TEST71' and t.source_record_id=recovered::text and p.ledger_id=asset and p.cr_amount=4) then raise exception 'Missing recovery asset credit';end if;
insert into public.rr_worker_advance_ledger_v785(data_mode,worker_id,entry_date,entry_type,amount,balance_effect,related_entry_id,created_by)
values('TEST',w,current_date,'ADVANCE_REVERSAL',4,4,recovered,auth.uid()) returning id into rev;
if not exists(select 1 from public.rr_account_transactions_v805 where source_module='WORKER_ADVANCE_TEST71' and source_record_id=recovered::text and status='REVERSED') then raise exception 'Missing linked recovery journal reversal';end if;
insert into advance_bridge_result values('issue_recovery_reversal',jsonb_build_object('asset_debit',10,'recovery_credit',4,'linked_reversal',true));
select count(*) into before_n from public.rr_advance_payment_batches_v785;
if exists(select 1 from public.rr_payroll_cash_bank_routes_test71 where data_mode='TEST' and payment_mode='BANK') then raise exception 'Expected unconfigured BANK test route';end if;
begin
perform public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',gen_random_uuid(),payload||jsonb_build_object('p_payment_mode','BANK','p_voucher_no','ROLLBACK-BANK-'||k));
exception when others then if sqlerrm not like '%Cash/Bank route%' then raise;end if;failed:=true;end;
if not failed or (select count(*) from public.rr_advance_payment_batches_v785)<>before_n then raise exception 'Missing bank route did not rollback payment';end if;
begin
update public.rr_worker_advance_ledger_v785 set amount=20,balance_effect=20 where id=issued;
raise exception 'Mutation unexpectedly allowed';
exception when others then if sqlerrm not like '%immutable%' then raise;end if;end;
update public.rr_worker_advance_ledger_v785 set status='VOID',void_reason='Rollback payment correction',voided_by=auth.uid(),voided_at=now() where id=issued;
if not exists(select 1 from public.rr_account_transactions_v805 where source_module='WORKER_ADVANCE_TEST71' and source_record_id=issued::text and status='REVERSED') then raise exception 'Missing payment void reversal';end if;
if exists(select 1 from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id where t.source_module like 'WORKER_ADVANCE_TEST71%' group by t.id having sum(p.dr_amount)<>sum(p.cr_amount)) then raise exception 'Unbalanced journal';end if;
insert into advance_bridge_result values('atomicity_immutability_void',jsonb_build_object('missing_bank_route_blocked',true,'financial_mutation_blocked',true,'payment_void_reversed',true,'journals_balanced',true));
end;$test$;
select * from advance_bridge_result;
rollback;