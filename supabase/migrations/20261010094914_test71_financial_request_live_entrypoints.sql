BEGIN;
CREATE OR REPLACE FUNCTION public.rr_financial_request_post_test71(p_operation text,p_data_mode text,p_request_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $f$
DECLARE v_actor uuid:=auth.uid();v_mode text:=upper(p_data_mode);v_existing public.rr_financial_requests_test71%rowtype;v_result jsonb;v_identity jsonb;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'Login required.' USING ERRCODE='42501';END IF;
 IF p_operation NOT IN('rr_accounts_post_payment_v805','rr_accounts_post_receipt_v805','rr_committee_payment_post_v824','rr_material_post_purchase_v805_1','rr_worker_salary_payment_post_v781','rr_advance_payment_post_v785','rr_material_post_purchase_txn_v661','rr_salary_payment_post_v785','rr_salary_payment_post_v786') THEN RAISE EXCEPTION 'Unsupported financial operation.';END IF;
 IF p_operation IN('rr_worker_salary_payment_post_v781','rr_salary_payment_post_v785','rr_salary_payment_post_v786','rr_advance_payment_post_v785') THEN
  IF NOT public.rr_worker_salary_can_pay_v781() THEN RAISE EXCEPTION 'Salary payment permission required.' USING ERRCODE='42501';END IF;
 ELSE
  PERFORM public.rr_accounts_report_access_assert_test71();
 END IF;
 IF p_request_id IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' THEN RAISE EXCEPTION 'Request ID and object payload required.';END IF;
 IF v_mode NOT IN('TEST','REAL') OR v_mode IS NULL THEN RAISE EXCEPTION 'TEST/REAL mode required.';END IF;
 PERFORM public.rr_app_data_mode_assert_v786(v_mode);
 IF p_operation NOT IN('rr_worker_salary_payment_post_v781','rr_committee_payment_post_v824') AND upper(p_payload->>'p_data_mode') IS DISTINCT FROM v_mode THEN RAISE EXCEPTION 'Request and payload data modes differ.';END IF;
 IF p_operation='rr_worker_salary_payment_post_v781' AND NOT EXISTS(
 SELECT 1 FROM public.rr_worker_salary_ledger_v781 WHERE id=(p_payload->>'p_due_entry_id')::uuid AND data_mode=v_mode
 ) THEN RAISE EXCEPTION 'Salary due is not in requested data mode.';END IF;
 IF p_operation='rr_committee_payment_post_v824' AND v_mode<>'TEST' THEN RAISE EXCEPTION 'Committee V824 is TEST only.';END IF;
 v_identity:=public.rr_upm_effective_identity_v200();
 PERFORM pg_advisory_xact_lock(hashtextextended(concat(v_actor,'|',p_operation,'|',v_mode,'|',p_request_id),0));
 SELECT * INTO v_existing FROM public.rr_financial_requests_test71 WHERE actor_id=v_actor AND operation=p_operation AND data_mode=v_mode AND request_id=p_request_id FOR UPDATE;
 IF FOUND THEN
  IF v_existing.payload IS DISTINCT FROM p_payload OR v_existing.effective_identity IS DISTINCT FROM v_identity THEN RAISE EXCEPTION 'Request ID already used with different payload or actor identity.';END IF;
  IF v_existing.result IS NULL THEN RAISE EXCEPTION 'Financial request is incomplete.';END IF;
  RETURN v_existing.result || jsonb_build_object('request_id',p_request_id,'already_processed',true);
 END IF;
 INSERT INTO public.rr_financial_requests_test71(actor_id,operation,data_mode,request_id,payload,effective_identity)
 VALUES(v_actor,p_operation,v_mode,p_request_id,p_payload,v_identity);
 CASE p_operation
 WHEN 'rr_accounts_post_payment_v805' THEN
 SELECT public.rr_accounts_post_payment_v805(x.p_against_ledger_id,x.p_cash_bank_ledger_id,x.p_amount,x.p_ref_no,x.p_narration,x.p_data_mode) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_against_ledger_id uuid,p_cash_bank_ledger_id uuid,p_amount numeric,p_ref_no text,p_narration text,p_data_mode text);
WHEN 'rr_accounts_post_receipt_v805' THEN
 SELECT public.rr_accounts_post_receipt_v805(x.p_party_ledger_id,x.p_cash_bank_ledger_id,x.p_amount,x.p_ref_no,x.p_narration,x.p_data_mode) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_party_ledger_id uuid,p_cash_bank_ledger_id uuid,p_amount numeric,p_ref_no text,p_narration text,p_data_mode text);
WHEN 'rr_committee_payment_post_v824' THEN
 SELECT public.rr_committee_payment_post_v824(x.p_scheme_id,x.p_month_no,x.p_amount,x.p_payment_mode,x.p_organizer_reference,x.p_bank_reference,x.p_payment_date,x.p_remarks) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_scheme_id uuid,p_month_no integer,p_amount numeric,p_payment_mode text,p_organizer_reference text,p_bank_reference text,p_payment_date date,p_remarks text);
WHEN 'rr_material_post_purchase_v805_1' THEN
 SELECT public.rr_material_post_purchase_v805_1(x.p_supplier_ledger_id,x.p_material_id,x.p_purchase_ledger_id,x.p_purchase_qty,x.p_purchase_unit,x.p_stock_qty,x.p_stock_unit,x.p_consumption_qty,x.p_consumption_unit,x.p_rate,x.p_bill_no,x.p_bill_date,x.p_gst_amount,x.p_payment_status,x.p_paid_amount,x.p_cash_bank_ledger_id,x.p_data_mode) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_supplier_ledger_id uuid,p_material_id uuid,p_purchase_ledger_id uuid,p_purchase_qty numeric,p_purchase_unit text,p_stock_qty numeric,p_stock_unit text,p_consumption_qty numeric,p_consumption_unit text,p_rate numeric,p_bill_no text,p_bill_date date,p_gst_amount numeric,p_payment_status text,p_paid_amount numeric,p_cash_bank_ledger_id uuid,p_data_mode text);
WHEN 'rr_worker_salary_payment_post_v781' THEN
 SELECT public.rr_worker_salary_payment_post_v781(x.p_due_entry_id,x.p_amount,x.p_payment_date,x.p_payment_mode,x.p_reference_no,x.p_remarks) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_due_entry_id uuid,p_amount numeric,p_payment_date date,p_payment_mode text,p_reference_no text,p_remarks text);

WHEN 'rr_advance_payment_post_v785' THEN
 SELECT public.rr_advance_payment_post_v785(x.p_data_mode,x.p_payroll_category_filter,x.p_worker_ids,x.p_worker_amounts,x.p_payment_date,x.p_payment_mode,x.p_voucher_no,x.p_remarks) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_data_mode text,p_payroll_category_filter text,p_worker_ids uuid[],p_worker_amounts jsonb,p_payment_date date,p_payment_mode text,p_voucher_no text,p_remarks text);
WHEN 'rr_material_post_purchase_txn_v661' THEN
 SELECT public.rr_material_post_purchase_txn_v661(x.p_supplier_ledger_id,x.p_material_id,x.p_purchase_ledger_id,x.p_purchase_qty,x.p_purchase_unit,x.p_purchase_to_consumption,x.p_rate,x.p_bill_no,x.p_bill_date,x.p_gst_amount,x.p_payment_status,x.p_paid_amount,x.p_cash_bank_ledger_id,x.p_data_mode) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_supplier_ledger_id uuid,p_material_id uuid,p_purchase_ledger_id uuid,p_purchase_qty numeric,p_purchase_unit text,p_purchase_to_consumption numeric,p_rate numeric,p_bill_no text,p_bill_date date,p_gst_amount numeric,p_payment_status text,p_paid_amount numeric,p_cash_bank_ledger_id uuid,p_data_mode text);
WHEN 'rr_salary_payment_post_v785' THEN
 SELECT public.rr_salary_payment_post_v785(x.p_payroll_category,x.p_period_start,x.p_period_end,x.p_data_mode,x.p_payment_method,x.p_payment_scope,x.p_bulk_amount,x.p_worker_ids,x.p_worker_amounts,x.p_payment_date,x.p_payment_mode,x.p_voucher_no,x.p_remarks) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_payroll_category text,p_period_start date,p_period_end date,p_data_mode text,p_payment_method text,p_payment_scope text,p_bulk_amount numeric,p_worker_ids uuid[],p_worker_amounts jsonb,p_payment_date date,p_payment_mode text,p_voucher_no text,p_remarks text);
WHEN 'rr_salary_payment_post_v786' THEN
 SELECT public.rr_salary_payment_post_v786(x.p_payroll_category,x.p_period_start,x.p_period_end,x.p_data_mode,x.p_payment_method,x.p_payment_scope,x.p_bulk_amount,x.p_worker_ids,x.p_worker_amounts,x.p_payment_date,x.p_payment_mode,x.p_voucher_no,x.p_remarks) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_payroll_category text,p_period_start date,p_period_end date,p_data_mode text,p_payment_method text,p_payment_scope text,p_bulk_amount numeric,p_worker_ids uuid[],p_worker_amounts jsonb,p_payment_date date,p_payment_mode text,p_voucher_no text,p_remarks text);
 END CASE;
 IF v_result IS NULL THEN RAISE EXCEPTION 'Financial operation returned no result.';END IF;
 UPDATE public.rr_financial_requests_test71 SET result=v_result WHERE actor_id=v_actor AND operation=p_operation AND data_mode=v_mode AND request_id=p_request_id;
 RETURN v_result || jsonb_build_object('request_id',p_request_id,'already_processed',false);
END;$f$;
;
COMMIT;
