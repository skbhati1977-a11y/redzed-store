CREATE OR REPLACE FUNCTION public.rr_salary_batch_reverse_test71(p_batch_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b public.rr_salary_payment_batches_v785%rowtype;l public.rr_salary_payment_batch_lines_v785%rowtype;
s public.rr_worker_salary_ledger_v781%rowtype;a public.rr_worker_advance_ledger_v785%rowtype;
actor text;reason text:=nullif(btrim(p_reason),'');n int:=0;
BEGIN
IF auth.uid() IS NULL OR NOT public.rr_worker_salary_can_reverse_v781() THEN RAISE EXCEPTION 'Salary reversal permission required.' USING ERRCODE='42501';END IF;
PERFORM pg_advisory_xact_lock(hashtextextended('SALARY_SOURCE_TEST71',0));
IF reason IS NULL OR length(reason)<5 THEN RAISE EXCEPTION 'Reversal reason minimum 5 characters required.';END IF;
SELECT * INTO b FROM public.rr_salary_payment_batches_v785 WHERE id=p_batch_id AND data_mode='TEST' AND payroll_category='SALARIED' AND status='POSTED' FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'Active TEST salaried batch required; already reversed or unsupported.';END IF;
SELECT coalesce(full_name,role_code,'AUTHORIZED USER') INTO actor FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() LIMIT 1;
FOR l IN SELECT * FROM public.rr_salary_payment_batch_lines_v785 WHERE batch_id=b.id ORDER BY worker_id FOR UPDATE LOOP
IF NOT l.payment_selected OR l.legacy_advance_recovery>0 THEN RAISE EXCEPTION 'Only selected canonical advance recovery batches can be reversed.';END IF;
IF l.payment_ledger_entry_id IS NOT NULL THEN
SELECT * INTO s FROM public.rr_worker_salary_ledger_v781 WHERE id=l.payment_ledger_entry_id AND status='POSTED' AND data_mode='TEST' AND source_module='SALARY_PAYMENT_V786' AND entry_type='BULK_PAYMENT' FOR UPDATE;
IF NOT FOUND OR EXISTS(SELECT 1 FROM public.rr_worker_salary_ledger_v781 WHERE related_entry_id=s.id AND status='POSTED') THEN RAISE EXCEPTION 'Canonical payment missing or previously reversed.';END IF;
INSERT INTO public.rr_worker_salary_ledger_v781(data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,source_module,source_run_id,source_line_id,period_month,entry_date,entry_type,amount,balance_effect,related_entry_id,payment_mode,reference_no,remarks,created_by,created_by_name)
VALUES('TEST',s.worker_id,s.worker_name,s.worker_code,s.department_code,s.payroll_category,s.source_module,s.source_run_id,s.source_line_id,s.period_month,(now() AT TIME ZONE 'Asia/Kolkata')::date,'BULK_PAYMENT_REVERSAL',s.amount,s.amount,s.id,s.payment_mode,'REVERSAL · '||coalesce(s.reference_no,s.id::text),reason,auth.uid(),actor);
END IF;
IF l.advance_recovery_ledger_entry_id IS NOT NULL THEN
SELECT * INTO a FROM public.rr_worker_advance_ledger_v785 WHERE id=l.advance_recovery_ledger_entry_id AND status='POSTED' AND data_mode='TEST' AND entry_type='ADVANCE_RECOVERY' FOR UPDATE;
IF NOT FOUND OR EXISTS(SELECT 1 FROM public.rr_worker_advance_ledger_v785 WHERE related_entry_id=a.id AND status='POSTED') THEN RAISE EXCEPTION 'Advance recovery missing or previously reversed.';END IF;
INSERT INTO public.rr_worker_advance_ledger_v785(data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,entry_date,entry_type,amount,balance_effect,source_batch_id,source_line_id,related_entry_id,reference_no,remarks,created_by,created_by_name)
VALUES('TEST',a.worker_id,a.worker_name,a.worker_code,a.department_code,a.payroll_category,(now() AT TIME ZONE 'Asia/Kolkata')::date,'ADVANCE_REVERSAL',a.amount,a.amount,b.id,l.id,a.id,'REVERSAL · '||coalesce(a.reference_no,a.id::text),reason,auth.uid(),actor);
UPDATE public.rr_worker_salary_ledger_v781 SET status='VOID',voided_by=auth.uid(),voided_by_name=actor,voided_at=now(),void_reason=reason
WHERE id=l.advance_salary_ledger_entry_id AND data_mode='TEST' AND source_module='ADVANCE_AUTO_RECOVERY_V786' AND status='POSTED';
IF NOT FOUND THEN RAISE EXCEPTION 'Mapped salary recovery missing.';END IF;
END IF;
IF l.salary_due_ledger_entry_id IS NOT NULL THEN
UPDATE public.rr_worker_salary_ledger_v781 SET status='VOID',voided_by=auth.uid(),voided_by_name=actor,voided_at=now(),void_reason=reason
WHERE id=l.salary_due_ledger_entry_id AND data_mode='TEST' AND source_module='MONTHLY_CURRENT_V786' AND entry_type='MONTHLY_SALARY_DUE' AND status='POSTED';
IF NOT FOUND THEN RAISE EXCEPTION 'Canonical monthly accrual missing.';END IF;
END IF;
n:=n+1;
END LOOP;
IF n=0 THEN RAISE EXCEPTION 'Empty batch reversal denied.';END IF;
UPDATE public.rr_salary_current_claims_v785 SET status='VOID',voided_by=auth.uid(),voided_at=now(),void_reason=reason WHERE batch_id=b.id AND data_mode='TEST' AND status='POSTED';
UPDATE public.rr_salary_payment_batches_v785 SET status='VOID',voided_by=auth.uid(),voided_by_name=actor,voided_at=now(),void_reason=reason WHERE id=b.id;
RETURN jsonb_build_object('ok',true,'batch_id',b.id,'reversed_workers',n,'status','VOID');
END;$$;
REVOKE ALL ON FUNCTION public.rr_salary_batch_reverse_test71(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_salary_batch_reverse_test71(uuid,text) TO authenticated;