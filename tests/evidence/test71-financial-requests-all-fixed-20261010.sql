begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
do $t$
declare payload jsonb;r jsonb;s jsonb;k uuid;m rr_material_master_v805%rowtype;vendor uuid;pl uuid;cash uuid;due uuid;cid uuid;mid uuid;pid uuid;before_n int;outj jsonb:='[]';
begin
select * into m from rr_material_master_v805 where id='77c61feb-f81d-4baa-abb9-b0d8d7eed1b7';
select id into vendor from rr_ledgers_v805 where ledger_code='TST-CREDITOR-V818';
select id into pl from rr_ledgers_v805 where ledger_kind='PURCHASE' and ledger_code is distinct from 'PUR_RETURN' and is_active limit 1;
select id into cash from rr_ledgers_v805 where ledger_code='CASH_MAIN';
payload:=jsonb_build_object('p_supplier_ledger_id',vendor,'p_material_id',m.id,'p_purchase_ledger_id',pl,'p_purchase_qty',10,'p_purchase_unit',m.purchase_unit,'p_purchase_to_consumption',m.purchase_to_base/nullif(m.consumption_to_base,0),'p_rate',2,'p_bill_no','IDEM-MAT-AUDIT','p_bill_date',current_date,'p_gst_amount',0,'p_payment_status','CREDIT','p_paid_amount',0,'p_cash_bank_ledger_id',cash,'p_data_mode','TEST');
k:=gen_random_uuid();r:=rr_financial_request_post_test71('rr_material_post_purchase_txn_v661','TEST',k,payload);s:=rr_financial_request_post_test71('rr_material_post_purchase_txn_v661','TEST',k,payload);
if r->>'purchase_id'<>s->>'purchase_id' then raise exception 'material duplicate';end if;
outj:=outj||jsonb_build_array(jsonb_build_object('operation','material_live_v661','same_purchase',true));
payload:=jsonb_build_object('p_scheme_id','3b32ab0d-4e98-4c23-9e7b-7ee62a6036ff','p_month_no',1,'p_amount',1,'p_payment_mode','CASH','p_organizer_reference','IDEM-COM-AUDIT','p_bank_reference',null,'p_payment_date',current_date,'p_remarks','rollback');
k:=gen_random_uuid();r:=rr_financial_request_post_test71('rr_committee_payment_post_v824','TEST',k,payload);s:=rr_financial_request_post_test71('rr_committee_payment_post_v824','TEST',k,payload);
pid:=(r->>'payment_id')::uuid;
if r->>'payment_id'<>s->>'payment_id' or (select accounts_transaction_id from rr_committee_payments_v824 where id=pid) is null then raise exception 'committee duplicate or missing atomic journal';end if;
perform rr_committee_payment_reverse_v824(pid,'Rollback audit');
outj:=outj||jsonb_build_array(jsonb_build_object('operation','committee','one_payment_and_atomic_journal',true));
select d.id into due from rr_worker_salary_ledger_v781 d where d.status='POSTED' and d.entry_type='SALARY_DUE' and d.data_mode='TEST' and d.amount-coalesce((select sum(case when p.entry_type='PAYMENT' then p.amount else -p.amount end) from rr_worker_salary_ledger_v781 p where p.due_entry_id=d.id and p.status='POSTED' and p.entry_type in('PAYMENT','PAYMENT_REVERSAL')),0)>0.05 limit 1;
payload:=jsonb_build_object('p_due_entry_id',due,'p_amount',0.01,'p_payment_date',current_date,'p_payment_mode','CASH','p_reference_no','IDEM-SAL-AUDIT','p_remarks','rollback');
k:=gen_random_uuid();r:=rr_financial_request_post_test71('rr_worker_salary_payment_post_v781','TEST',k,payload);s:=rr_financial_request_post_test71('rr_worker_salary_payment_post_v781','TEST',k,payload);
if r->>'payment_id'<>s->>'payment_id' then raise exception 'salary duplicate';end if;
outj:=outj||jsonb_build_array(jsonb_build_object('operation','salary_individual','one_payment',true,'accounts_bridge','still pending'));
perform set_config('audit.requests.all',outj::text,true);
end;$t$;
select current_setting('audit.requests.all')::jsonb result;rollback;
