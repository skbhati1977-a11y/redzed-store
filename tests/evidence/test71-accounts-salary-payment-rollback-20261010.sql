begin;select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
do $audit$ declare due uuid;j jsonb;j2 jsonb;rev jsonb;payment uuid;outj jsonb:='{}';n0 int;n1 int;ref text:='SALARY-AUDIT-'||gen_random_uuid()::text;begin
select d.id into due from rr_worker_salary_ledger_v781 d where d.status='POSTED' and d.entry_type='SALARY_DUE' and d.data_mode='TEST'
and d.amount-coalesce((select sum(case when p.entry_type='PAYMENT' then p.amount else -p.amount end) from rr_worker_salary_ledger_v781 p where p.due_entry_id=d.id and p.status='POSTED' and p.entry_type in('PAYMENT','PAYMENT_REVERSAL')),0)>0.05 limit 1;
if due is null then raise exception 'positive salary due fixture missing';end if;
select count(*) into n0 from rr_account_transactions_v805;
j:=rr_worker_salary_payment_post_v781(due,0.01,current_date,'CASH',ref,'Rollback audit');payment:=(j->>'payment_id')::uuid;
j2:=rr_worker_salary_payment_post_v781(due,0.01,current_date,'CASH',ref,'Repeat identical audit');
select count(*) into n1 from rr_account_transactions_v805;
outj:=outj||jsonb_build_object('payment_posted',j->>'ok','same_reference_second_payment_created',payment<>(j2->>'payment_id')::uuid,'general_accounts_transaction_delta',n1-n0);
rev:=rr_worker_salary_payment_reverse_v781(payment,'Rollback audit reversal');
outj:=outj||jsonb_build_object('salary_reversal',rev->>'ok');
begin perform rr_worker_salary_payment_reverse_v781(payment,'Repeat reversal audit');outj:=outj||jsonb_build_object('repeat_reversal_blocked',false);exception when others then outj:=outj||jsonb_build_object('repeat_reversal_blocked',true,'repeat_reversal_reason',sqlerrm);end;
begin perform rr_worker_salary_payment_post_v781(due,999999999,current_date,'CASH',ref||'-OVER','Overpay audit');outj:=outj||jsonb_build_object('overpay_blocked',false);exception when others then outj:=outj||jsonb_build_object('overpay_blocked',true);end;
perform set_config('audit.salary.payment',outj::text,true);end $audit$;
select current_setting('audit.salary.payment')::jsonb result;rollback;
