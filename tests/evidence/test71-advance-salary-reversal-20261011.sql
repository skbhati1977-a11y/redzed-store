BEGIN;
SELECT set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
CREATE TEMP TABLE advance_payroll_result(label text,result jsonb) ON COMMIT DROP;
DO $test$
DECLARE w uuid:='038f2ef4-ca5d-4ed0-a3da-264e2d727ac4';d date;p jsonb;r jsonb;s jsonb;k uuid;advance_batch uuid;salary_batch uuid;rec uuid;due uuid;cash_pay uuid;actual numeric;
BEGIN
FOR d IN SELECT generate_series('2026-09-01'::date,'2026-09-30'::date,interval '1 day')::date LOOP
 PERFORM public.rr_attendance_save_v778(w,d,(d+time '10:00') AT TIME ZONE 'Asia/Kolkata',(d+time '20:00') AT TIME ZONE 'Asia/Kolkata','AUTO',false,'MANUAL',null,'Rollback approved recovery','TEST');
END LOOP;
p:=jsonb_build_object('p_data_mode','TEST','p_payroll_category_filter','SALARIED','p_worker_ids',jsonb_build_array(w),'p_worker_amounts',jsonb_build_array(jsonb_build_object('worker_id',w,'amount_paid',100)),'p_payment_date',current_date,'p_payment_mode','CASH','p_voucher_no','ROLLBACK-ADV-APPROVED-SALARY','p_remarks','Rollback only');
k:=gen_random_uuid();r:=public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',k,p);advance_batch:=(r->>'batch_id')::uuid;
IF public.rr_financial_request_post_test71('rr_advance_payment_post_v785','TEST',k,p)->>'batch_id'<>r->>'batch_id' THEN RAISE EXCEPTION 'Advance retry duplicate';END IF;
SELECT dedicated_advance_balance INTO actual FROM public.rr_worker_advance_balance_v785 WHERE worker_id=w AND data_mode='TEST';
IF actual<>100 THEN RAISE EXCEPTION 'Advance outstanding incorrect %',actual;END IF;
INSERT INTO advance_payroll_result VALUES('protected_first_advance_balance_100','true');
p:=jsonb_build_object('p_payroll_category','SALARIED','p_period_start','2026-09-01','p_period_end','2026-09-30','p_data_mode','TEST','p_payment_method','FULL_PAYMENT','p_payment_scope','FULL_AND_FINAL','p_bulk_amount',0,'p_worker_ids',jsonb_build_array(w),'p_worker_amounts','[]'::jsonb,'p_payment_date',current_date,'p_payment_mode','CASH','p_voucher_no','ROLLBACK-SALARY-RECOVERY','p_remarks','Rollback only');
k:=gen_random_uuid();r:=public.rr_financial_request_post_test71('rr_salary_payment_post_v785','TEST',k,p);salary_batch:=(r->>'batch_id')::uuid;
s:=public.rr_financial_request_post_test71('rr_salary_payment_post_v785','TEST',k,p);
IF s->>'batch_id'<>r->>'batch_id' OR (r->>'total_advance_recovery')::numeric<>100 OR (r->>'bulk_amount_payment')::numeric<>14900 THEN RAISE EXCEPTION 'Salary recovery redirect incorrect %',r;END IF;
SELECT salary_due_ledger_entry_id,advance_recovery_ledger_entry_id,payment_ledger_entry_id INTO due,rec,cash_pay FROM public.rr_salary_payment_batch_lines_v785 WHERE batch_id=salary_batch AND worker_id=w;
IF due IS NULL OR rec IS NULL OR cash_pay IS NULL OR (SELECT count(*) FROM public.rr_salary_payment_batch_lines_v785 WHERE batch_id=salary_batch)<>1 THEN RAISE EXCEPTION 'Selected worker mapping incorrect';END IF;
SELECT dedicated_advance_balance INTO actual FROM public.rr_worker_advance_balance_v785 WHERE worker_id=w AND data_mode='TEST';
IF actual<>0 THEN RAISE EXCEPTION 'Recovery did not clear advance';END IF;
SELECT coalesce(sum(balance_effect),0) INTO actual FROM public.rr_worker_salary_ledger_v781 WHERE worker_id=w AND data_mode='TEST' AND status='POSTED';
IF actual<>0 THEN RAISE EXCEPTION 'Salary payable did not clear %',actual;END IF;
INSERT INTO advance_payroll_result VALUES('approved_salary_accrual_15000_recovery_100_cash_14900',r);
IF (SELECT count(*) FROM public.rr_account_transactions_v805 WHERE source_module='WORKER_SALARY_ACCRUAL_TEST71' AND source_record_id=due::text AND data_mode='TEST' AND status='POSTED')<>1 OR
 (SELECT count(*) FROM public.rr_account_transactions_v805 WHERE source_module='WORKER_SALARY_PAYMENT_TEST71' AND source_record_id=cash_pay::text AND data_mode='TEST' AND status='POSTED')<>1 THEN RAISE EXCEPTION 'Salary cash/accrual journals not atomic';END IF;
INSERT INTO advance_payroll_result VALUES('salary_accrual_cash_journal_exactly_one','true');
PERFORM public.rr_salary_batch_reverse_test71(salary_batch,'Rollback reversal proof');
SELECT dedicated_advance_balance INTO actual FROM public.rr_worker_advance_balance_v785 WHERE worker_id=w AND data_mode='TEST';
IF actual<>100 THEN RAISE EXCEPTION 'Reversal advance incorrect %',actual;END IF;
SELECT coalesce(sum(balance_effect),0) INTO actual FROM public.rr_worker_salary_ledger_v781 WHERE worker_id=w AND data_mode='TEST' AND status='POSTED';
IF actual<>0 THEN RAISE EXCEPTION 'Reversal salary balance incorrect %',actual;END IF;
INSERT INTO advance_payroll_result VALUES('reversal_restores_advance_100_salary_zero','true');
IF (SELECT count(*) FROM public.rr_account_mirror_lifecycle_v806 WHERE source_module IN('WORKER_ADVANCE_TEST71','WORKER_SALARY_PAYMENT_TEST71','WORKER_SALARY_ACCRUAL_TEST71') AND source_record_id IN(rec::text,cash_pay::text,due::text) AND action_type='REVERSE')<>3 THEN RAISE EXCEPTION 'Three financial sources not reversed atomically';END IF;
IF EXISTS(SELECT 1 FROM public.rr_account_source_links_v806 WHERE source_record_id IN(rec::text,cash_pay::text,due::text) AND status='ACTIVE') THEN RAISE EXCEPTION 'Reversed source remains active';END IF;
INSERT INTO advance_payroll_result VALUES('all_three_accounts_sources_audited_reversed','true');
BEGIN
PERFORM public.rr_salary_batch_reverse_test71(salary_batch,'Second reversal blocked');
RAISE EXCEPTION 'Duplicate reversal unexpectedly accepted';
EXCEPTION WHEN OTHERS THEN IF SQLERRM='Duplicate reversal unexpectedly accepted' THEN RAISE;END IF; END;
INSERT INTO advance_payroll_result VALUES('duplicate_reversal_blocked','true');
END;$test$;
SELECT * FROM advance_payroll_result;ROLLBACK;