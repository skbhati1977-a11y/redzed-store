CREATE OR REPLACE FUNCTION public.rr_finalize_monthly_payroll_v779_2(p_payroll_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payroll public.rr_monthly_payroll_v779_1%rowtype;
  v_settlement public.rr_worker_settlements_v777_2%rowtype;
  v_claim record;
  v_advance record;
  v_incentive record;
  v_applied jsonb;
  v_prior_balance numeric;v_due_amount numeric;
begin
  if auth.uid() IS NULL OR (public.rr_payroll_actor_role_v779_1() not in('owner','admin') AND lower(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code',''))<>'super_admin') then
    raise exception 'Final settlement Owner/Admin only.';
  end if;

  select *
  into v_payroll
  from public.rr_monthly_payroll_v779_1
  where payroll_id=p_payroll_id
  for update;

  if not found then raise exception 'Payroll nahi mila.'; end if;

  IF v_payroll.data_mode<>'TEST' AND public.rr_payroll_actor_role_v779_1() not in('owner','admin') THEN RAISE EXCEPTION 'Final settlement Owner/Admin only.';END IF;
  IF v_payroll.data_mode='TEST' AND (v_payroll.calculation_snapshot->'source_snapshot_test71') IS DISTINCT FROM public.rr_monthly_payroll_sources_test71(v_payroll.worker_id,v_payroll.payroll_month) THEN RAISE EXCEPTION 'Payroll sources changed after posting; reviewed recalculation required before finalization.';END IF;
  if v_payroll.payroll_status not in('POSTED','UNDER_REVIEW') then
    raise exception 'Payroll POSTED/UNDER_REVIEW hona chahiye.';
  end if;

  if v_payroll.settlement_id is null then
    raise exception 'Settlement link missing hai.';
  end if;

  select *
  into v_settlement
  from public.rr_worker_settlements_v777_2
  where settlement_id=v_payroll.settlement_id
  for update;

  if not found or v_settlement.settlement_status<>'CALCULATED' then
    raise exception 'CALCULATED settlement required hai.';
  end if;

  IF v_payroll.data_mode='TEST' THEN
   IF v_payroll.approved_claim_amount>0 OR v_payroll.advance_recovery_amount>0 OR EXISTS(SELECT 1 FROM public.rr_worker_advance_balance_v785 b WHERE b.worker_id=v_payroll.worker_id AND b.data_mode='TEST' AND b.total_advance_balance>0) THEN RAISE EXCEPTION 'Approved claim/advance recovery Accounts source mapping required before finalization.';END IF;
   IF EXISTS(SELECT 1 FROM public.rr_worker_salary_ledger_v781 l WHERE l.worker_id=v_payroll.worker_id AND l.data_mode='TEST' AND l.payroll_category='SALARIED' AND l.period_month=v_payroll.payroll_month AND l.status='POSTED' AND l.entry_type IN('MONTHLY_SALARY_DUE','MONTHLY_FINAL_ADJUSTMENT')) THEN RAISE EXCEPTION 'Existing monthly salary accrual must be reconciled before V779 finalization.';END IF;
   SELECT coalesce(sum(l.balance_effect),0) INTO v_prior_balance FROM public.rr_worker_salary_ledger_v781 l WHERE l.worker_id=v_payroll.worker_id AND l.data_mode='TEST' AND l.payroll_category='SALARIED' AND l.status='POSTED';
   IF v_prior_balance IS DISTINCT FROM v_settlement.opening_balance THEN RAISE EXCEPTION 'Approved opening salary ledger differs from settlement opening.';END IF;
   v_due_amount:=round(v_payroll.monthly_salary_amount+v_payroll.incentive_amount+v_payroll.net_extra_work_amount,2);
   IF v_due_amount>0 THEN
    INSERT INTO public.rr_worker_salary_ledger_v781(data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,source_module,source_run_id,source_line_id,period_month,entry_date,entry_type,amount,balance_effect,remarks,created_by,source_key)
    SELECT 'TEST',v_payroll.worker_id,w.worker_name,w.worker_code,w.department_code,'SALARIED','MONTHLY_V779_TEST71',p_payroll_id,v_payroll.settlement_id,v_payroll.payroll_month,v_payroll.posting_date,'MONTHLY_SALARY_DUE',v_due_amount,v_due_amount,coalesce(p_reason,'Approved monthly salary accrual'),auth.uid(),'MONTHLY_V779|'||p_payroll_id::text
    FROM public.rr_worker_directory_unified_v1 w WHERE w.worker_id=v_payroll.worker_id LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Worker identity required for monthly salary accrual.';END IF;
   END IF;
  END IF;

  -- Claims: exact status and settlement link.
  for v_claim in
    select c.*
    from public.rr_worker_claims_v777_2 c
    where c.worker_id=v_payroll.worker_id
      and c.data_mode=v_payroll.data_mode
      and c.claim_status='APPROVED_PENDING_SETTLEMENT'
      and c.reversed_at is null
      and c.approved_amount>0
      and not exists(
        select 1
        from public.rr_payroll_source_applications_v779_1 a
        where a.source_type='CLAIM'
          and a.source_id=c.claim_id
          and a.data_mode=v_payroll.data_mode
          and a.reversed_at is null
      )
    for update
  loop
    insert into public.rr_payroll_source_applications_v779_1(
      payroll_id,worker_id,source_type,source_id,
      applied_amount,data_mode,applied_by
    )
    values(
      p_payroll_id,v_payroll.worker_id,'CLAIM',v_claim.claim_id,
      v_claim.approved_amount,v_payroll.data_mode,auth.uid()
    );

    update public.rr_worker_claims_v777_2
    set claim_status='DEBIT_POSTED',
        debit_settlement_id=v_payroll.settlement_id,
        debit_posted_at=now()
    where claim_id=v_claim.claim_id;
  end loop;

  -- Advances: source application prevents reuse.
  for v_advance in
    select a.*
    from public.rr_worker_advances_v777_2 a
    where a.worker_id=v_payroll.worker_id
      and a.data_mode=v_payroll.data_mode
      and not a.is_reversed
      and a.advance_date<=(
        v_payroll.payroll_month+interval '1 month' - interval '1 day'
      )::date
      and not exists(
        select 1
        from public.rr_payroll_source_applications_v779_1 x
        where x.source_type='ADVANCE'
          and x.source_id=a.advance_id
          and x.data_mode=v_payroll.data_mode
          and x.reversed_at is null
      )
    for update
  loop
    insert into public.rr_payroll_source_applications_v779_1(
      payroll_id,worker_id,source_type,source_id,
      applied_amount,data_mode,applied_by
    )
    values(
      p_payroll_id,v_payroll.worker_id,'ADVANCE',v_advance.advance_id,
      v_advance.advance_amount,v_payroll.data_mode,auth.uid()
    );
  end loop;

  -- Approved incentives: consume exactly once.
  for v_incentive in
    select i.*
    from public.rr_payroll_incentives_v779_1 i
    where i.worker_id=v_payroll.worker_id
      and i.payroll_month=v_payroll.payroll_month
      and i.data_mode=v_payroll.data_mode
      and i.incentive_status='APPROVED'
      and not exists(
        select 1
        from public.rr_payroll_source_applications_v779_1 x
        where x.source_type='INCENTIVE'
          and x.source_id=i.incentive_id
          and x.data_mode=v_payroll.data_mode
          and x.reversed_at is null
      )
    for update
  loop
    insert into public.rr_payroll_source_applications_v779_1(
      payroll_id,worker_id,source_type,source_id,
      applied_amount,data_mode,applied_by
    )
    values(
      p_payroll_id,v_payroll.worker_id,'INCENTIVE',
      v_incentive.incentive_id,v_incentive.incentive_amount,
      v_payroll.data_mode,auth.uid()
    );
  end loop;

  IF v_payroll.data_mode='TEST' THEN
   SELECT coalesce(jsonb_agg(jsonb_build_object('type',a.source_type,'id',a.source_id,'amount',a.applied_amount) ORDER BY a.source_type,a.source_id),'[]'::jsonb) INTO v_applied FROM public.rr_payroll_source_applications_v779_1 a WHERE a.payroll_id=p_payroll_id AND a.data_mode='TEST' AND a.reversed_at IS NULL;
   IF v_applied IS DISTINCT FROM v_payroll.calculation_snapshot->'source_snapshot_test71' THEN RAISE EXCEPTION 'Payroll source applications differ from approved snapshot; finalization rolled back.';END IF;
  END IF;
  update public.rr_worker_settlements_v777_2
  set settlement_status='APPROVED',
      claim_debit_applied=
        (v_payroll.approved_claim_amount>0),
      approved_at=now(),
      approved_by=auth.uid()
  where settlement_id=v_payroll.settlement_id;

  update public.rr_monthly_payroll_v779_1
  set payroll_status='FINAL',
      finalized_at=now(),
      finalized_by=auth.uid(),
      updated_at=now()
  where payroll_id=p_payroll_id;

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,
    old_snapshot,new_snapshot,reason,data_mode
  )
  values(
    p_payroll_id,v_payroll.worker_id,v_payroll.payroll_month,
    'PAYROLL_FINALIZED',to_jsonb(v_payroll),
    jsonb_build_object(
      'payroll_status','FINAL',
      'settlement_status','APPROVED',
      'settlement_id',v_payroll.settlement_id
    ),
    p_reason,v_payroll.data_mode
  );

  return jsonb_build_object(
    'ok',true,
    'version','V779_2_PAYROLL_POSTING_SETTLEMENT_ENGINE',
    'payroll_id',p_payroll_id,
    'settlement_id',v_payroll.settlement_id,
    'payroll_status','FINAL',
    'settlement_status','APPROVED',
    'net_payable_salary',v_payroll.net_payable_salary
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_record_monthly_salary_payment_v779_2(p_payroll_id uuid, p_payment_amount numeric, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payroll public.rr_monthly_payroll_v779_1%rowtype;
  v_settlement public.rr_worker_settlements_v777_2%rowtype;
  v_new_paid numeric;
  v_new_closing numeric;
  v_status text;
begin
  IF EXISTS(SELECT 1 FROM public.rr_monthly_payroll_v779_1 WHERE payroll_id=p_payroll_id AND data_mode='TEST') THEN RAISE EXCEPTION 'Use protected monthly payment with Cash/Bank mode and voucher reference.';END IF;
  if public.rr_payroll_actor_role_v779_1() not in('owner','admin') then
    raise exception 'Salary payment Owner/Admin only.';
  end if;

  if coalesce(p_payment_amount,0)<=0 then
    raise exception 'Payment amount positive hona chahiye.';
  end if;

  select *
  into v_payroll
  from public.rr_monthly_payroll_v779_1
  where payroll_id=p_payroll_id
  for update;

  if not found or v_payroll.payroll_status not in('FINAL','PAID') then
    raise exception 'FINAL payroll required hai.';
  end if;

  select *
  into v_settlement
  from public.rr_worker_settlements_v777_2
  where settlement_id=v_payroll.settlement_id
  for update;

  if not found or v_settlement.settlement_status not in('APPROVED','PAID') then
    raise exception 'APPROVED settlement required hai.';
  end if;

  v_new_paid:=v_settlement.payment_amount+p_payment_amount;

  if v_new_paid>v_settlement.opening_balance
      +v_settlement.earnings_amount
      +v_settlement.incentive_amount
      +v_settlement.overtime_amount
      +v_settlement.holiday_amount
      -v_settlement.advance_recovery_amount
      -v_settlement.approved_claim_debit_amount
  then
    raise exception 'Payment payable balance se zyada hai.';
  end if;

  v_new_closing:=
      v_settlement.opening_balance
    + v_settlement.earnings_amount
    + v_settlement.incentive_amount
    + v_settlement.overtime_amount
    + v_settlement.holiday_amount
    - v_settlement.advance_recovery_amount
    - v_settlement.approved_claim_debit_amount
    - v_new_paid;

  v_status:=case when v_new_closing=0 then 'PAID' else 'APPROVED' end;

  update public.rr_worker_settlements_v777_2
  set payment_amount=v_new_paid,
      closing_balance=v_new_closing,
      settlement_status=v_status,
      closed_at=case when v_new_closing=0 then now() else closed_at end
  where settlement_id=v_payroll.settlement_id;

  update public.rr_monthly_payroll_v779_1
  set payroll_status=case when v_new_closing=0 then 'PAID' else 'FINAL' end,
      updated_at=now()
  where payroll_id=p_payroll_id;

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,
    old_snapshot,new_snapshot,reason,data_mode
  )
  values(
    p_payroll_id,v_payroll.worker_id,v_payroll.payroll_month,
    'SALARY_PAYMENT_RECORDED',
    to_jsonb(v_settlement),
    jsonb_build_object(
      'payment_added',p_payment_amount,
      'total_payment',v_new_paid,
      'closing_balance',v_new_closing,
      'settlement_status',v_status
    ),
    p_reason,v_payroll.data_mode
  );

  return jsonb_build_object(
    'ok',true,
    'payroll_id',p_payroll_id,
    'settlement_id',v_payroll.settlement_id,
    'payment_added',p_payment_amount,
    'total_payment',v_new_paid,
    'closing_balance',v_new_closing,
    'payroll_status',case when v_new_closing=0 then 'PAID' else 'FINAL' end,
    'settlement_status',v_status
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_monthly_salary_payment_sync_test71()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE p public.rr_monthly_payroll_v779_1%rowtype;s public.rr_worker_settlements_v777_2%rowtype;paid numeric;due_total numeric;
BEGIN
 IF NEW.data_mode<>'TEST' OR NEW.source_module<>'MONTHLY_V779_TEST71' OR NEW.entry_type NOT IN('PAYMENT','PAYMENT_REVERSAL') OR NEW.status<>'POSTED' THEN RETURN NEW;END IF;
 IF auth.uid() IS NULL OR NOT (public.rr_worker_salary_can_pay_v781() OR public.rr_worker_salary_can_reverse_v781()) THEN RAISE EXCEPTION 'Monthly salary settlement permission required.' USING ERRCODE='42501';END IF;
 SELECT * INTO p FROM public.rr_monthly_payroll_v779_1 WHERE payroll_id=NEW.source_run_id AND worker_id=NEW.worker_id AND data_mode='TEST' FOR UPDATE;
 IF p.payroll_id IS NULL OR p.payroll_status NOT IN('FINAL','PAID') THEN RAISE EXCEPTION 'Final mapped monthly payroll required.';END IF;
 SELECT * INTO s FROM public.rr_worker_settlements_v777_2 WHERE settlement_id=p.settlement_id FOR UPDATE;
 IF s.settlement_id IS NULL OR s.settlement_status NOT IN('APPROVED','PAID') THEN RAISE EXCEPTION 'Approved mapped settlement required.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_worker_salary_ledger_v781 d WHERE d.id=NEW.due_entry_id AND d.source_module='MONTHLY_V779_TEST71' AND d.source_run_id=p.payroll_id AND d.worker_id=NEW.worker_id AND d.data_mode='TEST' AND d.entry_type='MONTHLY_SALARY_DUE' AND d.status='POSTED') THEN RAISE EXCEPTION 'Monthly payment due identity mismatch.';END IF;
 IF NEW.entry_type='PAYMENT_REVERSAL' AND NOT EXISTS(SELECT 1 FROM public.rr_worker_salary_ledger_v781 r WHERE r.id=NEW.related_entry_id AND r.due_entry_id=NEW.due_entry_id AND r.entry_type='PAYMENT' AND r.status='POSTED' AND r.amount=NEW.amount AND r.worker_id=NEW.worker_id AND r.data_mode='TEST') THEN RAISE EXCEPTION 'Monthly reversal identity mismatch.';END IF;
 SELECT coalesce(sum(CASE WHEN l.entry_type='PAYMENT' THEN l.amount ELSE -l.amount END),0) INTO paid FROM public.rr_worker_salary_ledger_v781 l WHERE l.due_entry_id=NEW.due_entry_id AND l.status='POSTED' AND l.entry_type IN('PAYMENT','PAYMENT_REVERSAL');
 due_total:=s.opening_balance+s.earnings_amount+s.incentive_amount+s.overtime_amount+s.holiday_amount-s.advance_recovery_amount-s.approved_claim_debit_amount;
 IF paid<0 OR paid>due_total THEN RAISE EXCEPTION 'Monthly payment exceeds approved settlement payable.';END IF;
 UPDATE public.rr_worker_settlements_v777_2 SET payment_amount=paid,closing_balance=due_total-paid,settlement_status=CASE WHEN paid=due_total THEN 'PAID' ELSE 'APPROVED' END,closed_at=CASE WHEN paid=due_total THEN now() ELSE NULL END WHERE settlement_id=p.settlement_id;
 UPDATE public.rr_monthly_payroll_v779_1 SET payroll_status=CASE WHEN paid=due_total THEN 'PAID' ELSE 'FINAL' END,updated_at=now() WHERE payroll_id=p.payroll_id;
 INSERT INTO public.rr_payroll_events_v779_1(payroll_id,worker_id,payroll_month,event_type,old_snapshot,new_snapshot,reason,data_mode)
 VALUES(p.payroll_id,p.worker_id,p.payroll_month,CASE WHEN NEW.entry_type='PAYMENT' THEN 'SALARY_PAYMENT_RECORDED' ELSE 'SALARY_PAYMENT_REVERSED' END,to_jsonb(s),jsonb_build_object('salary_ledger_entry_id',NEW.id,'total_payment',paid,'closing_balance',due_total-paid),NEW.remarks,'TEST');
 RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION public.rr_monthly_salary_payment_sync_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_monthly_salary_payment_sync_test71 AFTER INSERT ON public.rr_worker_salary_ledger_v781 FOR EACH ROW EXECUTE FUNCTION public.rr_monthly_salary_payment_sync_test71();

CREATE OR REPLACE FUNCTION public.rr_monthly_salary_payment_post_test71(p_payroll_id uuid,p_payment_amount numeric,p_payment_date date,p_payment_mode text,p_reference_no text,p_reason text,p_data_mode text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE p public.rr_monthly_payroll_v779_1%rowtype;d public.rr_worker_salary_ledger_v781%rowtype;s public.rr_worker_settlements_v777_2%rowtype;amount numeric:=round(p_payment_amount,2);eid uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT public.rr_worker_salary_can_pay_v781() THEN RAISE EXCEPTION 'Monthly salary payment permission required.' USING ERRCODE='42501';END IF;
 IF upper(trim(p_data_mode)) IS DISTINCT FROM 'TEST' THEN RAISE EXCEPTION 'TEST monthly payment only.';END IF;
 PERFORM public.rr_app_data_mode_assert_v786('TEST');
 IF amount IS NULL OR amount<=0 OR p_payment_date IS NULL OR p_payment_date>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Positive amount and non-future payment date required.';END IF;
 IF upper(trim(p_payment_mode)) NOT IN('CASH','BANK','UPI','CHEQUE','OTHER') OR nullif(trim(p_payment_mode),'') IS NULL OR nullif(trim(p_reference_no),'') IS NULL THEN RAISE EXCEPTION 'Payment mode and voucher/reference required.';END IF;
 SELECT * INTO p FROM public.rr_monthly_payroll_v779_1 WHERE payroll_id=p_payroll_id AND data_mode='TEST' FOR UPDATE;
 IF p.payroll_id IS NULL OR p.payroll_status NOT IN('FINAL','PAID') OR p_payment_date<p.posting_date THEN RAISE EXCEPTION 'Final payroll and payment date on/after posting required.';END IF;
 SELECT * INTO s FROM public.rr_worker_settlements_v777_2 WHERE settlement_id=p.settlement_id FOR UPDATE;
 IF s.settlement_id IS NULL OR s.settlement_status NOT IN('APPROVED','PAID') OR amount>s.closing_balance THEN RAISE EXCEPTION 'Payment exceeds approved settlement balance.';END IF;
 SELECT * INTO d FROM public.rr_worker_salary_ledger_v781 WHERE source_module='MONTHLY_V779_TEST71' AND source_run_id=p.payroll_id AND entry_type='MONTHLY_SALARY_DUE' AND status='POSTED' AND data_mode='TEST' FOR UPDATE;
 IF d.id IS NULL THEN RAISE EXCEPTION 'Mapped monthly salary ledger accrual required.';END IF;
 INSERT INTO public.rr_worker_salary_ledger_v781(data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,source_module,source_run_id,source_line_id,period_month,entry_date,entry_type,amount,balance_effect,due_entry_id,payment_mode,reference_no,remarks,created_by)
 VALUES('TEST',d.worker_id,d.worker_name,d.worker_code,d.department_code,'SALARIED',d.source_module,d.source_run_id,d.source_line_id,d.period_month,p_payment_date,'PAYMENT',amount,-amount,d.id,upper(trim(p_payment_mode)),trim(p_reference_no),p_reason,auth.uid()) RETURNING id INTO eid;
 SELECT * INTO s FROM public.rr_worker_settlements_v777_2 WHERE settlement_id=p.settlement_id;
 RETURN jsonb_build_object('ok',true,'payroll_id',p.payroll_id,'payment_id',eid,'settlement_id',s.settlement_id,'payment_added',amount,'total_payment',s.payment_amount,'closing_balance',s.closing_balance,'data_mode','TEST');
END;$$;
REVOKE ALL ON FUNCTION public.rr_monthly_salary_payment_post_test71(uuid,numeric,date,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_monthly_salary_payment_post_test71(uuid,numeric,date,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_financial_request_post_test71(p_operation text, p_data_mode text, p_request_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_actor uuid:=auth.uid();v_mode text:=upper(p_data_mode);v_existing public.rr_financial_requests_test71%rowtype;v_result jsonb;v_identity jsonb;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'Login required.' USING ERRCODE='42501';END IF;
 IF p_operation NOT IN('rr_accounts_post_payment_v805','rr_accounts_post_receipt_v805','rr_committee_payment_post_v824','rr_material_post_purchase_v805_1','rr_worker_salary_payment_post_v781','rr_advance_payment_post_v785','rr_material_post_purchase_txn_v661','rr_salary_payment_post_v785','rr_salary_payment_post_v786','rr_post_mc_purchase_accounts_test71','rr_monthly_salary_payment_post_test71') THEN RAISE EXCEPTION 'Unsupported financial operation.';END IF;
 IF p_operation IN('rr_worker_salary_payment_post_v781','rr_salary_payment_post_v785','rr_salary_payment_post_v786','rr_advance_payment_post_v785','rr_monthly_salary_payment_post_test71') THEN
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
 WHEN 'rr_monthly_salary_payment_post_test71' THEN
 SELECT public.rr_monthly_salary_payment_post_test71(x.p_payroll_id,x.p_payment_amount,x.p_payment_date,x.p_payment_mode,x.p_reference_no,x.p_reason,x.p_data_mode) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_payroll_id uuid,p_payment_amount numeric,p_payment_date date,p_payment_mode text,p_reference_no text,p_reason text,p_data_mode text);
 WHEN 'rr_post_mc_purchase_accounts_test71' THEN
 SELECT public.rr_post_mc_purchase_accounts_test71(x.p_fabric_id,x.p_fabric_name,x.p_vendor_name,x.p_bill_no,x.p_bill_qty,x.p_bill_value,x.p_bill_date,x.p_remarks,x.p_data_mode,x.p_supplier_ledger_id)
 INTO v_result FROM jsonb_to_record(p_payload) AS x(p_fabric_id uuid,p_fabric_name text,p_vendor_name text,p_bill_no text,p_bill_qty numeric,p_bill_value numeric,p_bill_date date,p_remarks text,p_data_mode text,p_supplier_ledger_id uuid);
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
END;$function$
;
