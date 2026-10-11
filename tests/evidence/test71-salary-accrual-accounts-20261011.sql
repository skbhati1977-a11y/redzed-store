begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
create temporary table salary_accrual_result(label text,result boolean) on commit drop;
do $test$
declare eid uuid;tx uuid;expense uuid;payable uuid;blocked boolean:=false;
begin
select id into expense from public.rr_ledgers_v805 where ledger_code='EXP_MONTHLY_SALARY';
payable:=public.rr_worker_accounts_ledger_resolve_test71('038f2ef4-ca5d-4ed0-a3da-264e2d727ac4');
insert into public.rr_worker_salary_ledger_v781(data_mode,worker_id,payroll_category,source_module,period_month,entry_date,entry_type,amount,balance_effect,remarks,created_by)
values('TEST','038f2ef4-ca5d-4ed0-a3da-264e2d727ac4','SALARIED','TEST71_ROLLBACK_ACCRUAL','2026-09-01',current_date,'MONTHLY_SALARY_DUE',10,10,'Rollback accrual proof',auth.uid()) returning id into eid;
select id into tx from public.rr_account_transactions_v805 where source_module='WORKER_SALARY_ACCRUAL_TEST71' and source_record_id=eid::text and data_mode='TEST' and status='POSTED';
if tx is null or (select count(*) from public.rr_account_postings_v805 where transaction_id=tx)<>2 then raise exception 'Missing exact accrual journal';end if;
if not exists(select 1 from public.rr_account_postings_v805 where transaction_id=tx and ledger_id=expense and dr_amount=10 and cr_amount=0) or not exists(select 1 from public.rr_account_postings_v805 where transaction_id=tx and ledger_id=payable and cr_amount=10 and dr_amount=0) then raise exception 'Wrong accrual mapping';end if;
insert into salary_accrual_result values('expense_debit_worker_payable_credit',true);
begin update public.rr_worker_salary_ledger_v781 set amount=11,balance_effect=11 where id=eid;exception when others then if sqlerrm not like '%immutable%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'Accrual mutated';end if;
insert into salary_accrual_result values('financial_mutation_blocked',true);
blocked:=false;
begin update public.rr_worker_salary_ledger_v781 set data_mode='REAL' where id=eid;exception when others then if sqlerrm not like '%immutable%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'Accrual mode changed';end if;
insert into salary_accrual_result values('mode_mutation_blocked',true);
update public.rr_worker_salary_ledger_v781 set status='VOID',voided_by=auth.uid(),voided_at=now(),void_reason='Rollback void' where id=eid;
if exists(select 1 from public.rr_account_source_links_v806 where source_module='WORKER_SALARY_ACCRUAL_TEST71' and source_record_id=eid::text and status='ACTIVE') then raise exception 'Active journal remained after void';end if;
insert into salary_accrual_result values('void_reverses_accounts_source',true);
blocked:=false;
begin update public.rr_worker_salary_ledger_v781 set status='POSTED' where id=eid;exception when others then if sqlerrm not like '%transition denied%' then raise;end if;blocked:=true;end;
if not blocked then raise exception 'Voided accrual revived';end if;
insert into salary_accrual_result values('void_reactivation_blocked',true);
insert into public.rr_worker_salary_ledger_v781(data_mode,worker_id,payroll_category,source_module,period_month,entry_date,entry_type,amount,balance_effect,remarks,created_by)
values('TEST','038f2ef4-ca5d-4ed0-a3da-264e2d727ac4','SALARIED','TEST71_ROLLBACK_ACCRUAL','2026-09-01',current_date,'MONTHLY_FINAL_ADJUSTMENT',3,-3,'Rollback adjustment proof',auth.uid()) returning id into eid;
select id into tx from public.rr_account_transactions_v805 where source_module='WORKER_SALARY_ACCRUAL_TEST71' and source_record_id=eid::text and data_mode='TEST' and status='POSTED';
if tx is null or not exists(select 1 from public.rr_account_postings_v805 where transaction_id=tx and ledger_id=expense and cr_amount=3 and dr_amount=0) or not exists(select 1 from public.rr_account_postings_v805 where transaction_id=tx and ledger_id=payable and dr_amount=3 and cr_amount=0) then raise exception 'Wrong final adjustment mapping';end if;
insert into salary_accrual_result values('final_adjustment_payable_debit_expense_credit',true);
end;$test$;
select * from salary_accrual_result;
rollback;