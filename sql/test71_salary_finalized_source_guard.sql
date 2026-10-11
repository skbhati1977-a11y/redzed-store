CREATE OR REPLACE FUNCTION public.rr_salary_payment_post_v786(p_payroll_category text, p_period_start date, p_period_end date, p_data_mode text, p_payment_method text, p_payment_scope text, p_bulk_amount numeric, p_worker_ids uuid[], p_worker_amounts jsonb, p_payment_date date, p_payment_mode text, p_voucher_no text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_category text:=upper(trim(coalesce(p_payroll_category,'')));
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'TEST'));
  v_method text:=upper(trim(coalesce(p_payment_method,'')));
  v_scope text:=upper(trim(coalesce(p_payment_scope,'')));
  v_start date:=coalesce(p_period_start,current_date); v_end date:=coalesce(p_period_end,v_start);
  v_month date:=date_trunc('month',v_start)::date;
  v_paymode text:=upper(trim(coalesce(p_payment_mode,'')));
  v_prefix text; v_voucher text; v_next_voucher bigint;
  v_preview jsonb; v_actor text; v_batch uuid; v_line_id uuid; v_due uuid; v_pay uuid;
  v_adv_ledger uuid; v_salary_recovery uuid; v_dedicated_now numeric(16,2);
  r record; v_claim numeric(16,2); v_msg text;
begin
 PERFORM public.rr_financial_request_assert_test71(v_mode,ARRAY['rr_salary_payment_post_v786','rr_salary_payment_post_v785']);

  if not public.rr_worker_salary_can_pay_v781() then raise exception 'Salary payment permission required.'; end if;
  if p_payment_date is null then raise exception 'Payment Date required.'; end if;
  if v_paymode not in('CASH','BANK','UPI','CHEQUE','OTHER') then raise exception 'Valid Payment Mode required.'; end if;
  v_prefix:=case when v_category='PIECE_RATE' then 'PCSL' when v_category='SALARIED' then 'MSL' end;
  if v_prefix is null then raise exception 'Payroll Category must be PIECE_RATE or SALARIED.'; end if;

  IF v_mode='TEST' THEN PERFORM pg_advisory_xact_lock(hashtextextended('SALARY_SOURCE_TEST71',0));END IF;
  perform pg_advisory_xact_lock(hashtextextended(concat('SALARY_V786|',v_mode,'|',v_category),0));
  IF v_mode='TEST' AND v_category='SALARIED' AND EXISTS(
 SELECT 1 FROM public.rr_worker_salary_ledger_v781 l WHERE l.worker_id=ANY(p_worker_ids) AND l.data_mode='TEST' AND l.status='POSTED' AND l.source_module='MONTHLY_V779_TEST71'
 AND (l.period_month=v_month OR EXISTS(SELECT 1 FROM public.rr_monthly_payroll_v779_1 p JOIN public.rr_worker_settlements_v777_2 s ON s.settlement_id=p.settlement_id WHERE p.payroll_id=l.source_run_id AND s.closing_balance>0))
 ) THEN RAISE EXCEPTION 'Finalized V779 monthly salary must be paid through its mapped settlement; alternate salary route denied.';END IF;
  v_preview:=public.rr_salary_payment_preview_v786(v_category,v_start,v_end,v_mode,v_method,v_scope,
    p_bulk_amount,p_worker_ids,p_worker_amounts);
  IF v_mode='TEST' AND EXISTS(SELECT 1 FROM jsonb_array_elements(v_preview->'lines') z WHERE coalesce((z->>'payment_selected')::boolean,false) AND coalesce((z->>'legacy_advance_recovery')::numeric,0)>0) THEN RAISE EXCEPTION 'Legacy advance opening Accounts source mapping required before recovery.';END IF;
  IF v_mode='TEST' AND v_category='SALARIED' AND EXISTS(
 SELECT 1 FROM jsonb_array_elements(v_preview->'lines') z JOIN public.rr_worker_salary_ledger_v781 l ON l.worker_id=(z->>'worker_id')::uuid
 WHERE coalesce((z->>'payment_selected')::boolean,false) AND l.data_mode='TEST' AND l.status='POSTED' AND l.source_module='MONTHLY_V779_TEST71'
 AND (l.period_month=v_month OR EXISTS(SELECT 1 FROM public.rr_monthly_payroll_v779_1 p JOIN public.rr_worker_settlements_v777_2 s ON s.settlement_id=p.settlement_id WHERE p.payroll_id=l.source_run_id AND s.closing_balance>0))
 ) THEN RAISE EXCEPTION 'Finalized V779 monthly salary must be paid through its mapped settlement; alternate salary route denied.';END IF;
  if coalesce((v_preview->>'selected_worker_count')::int,0)<=0 then raise exception 'No eligible worker selected.'; end if;
  if (v_preview->>'bulk_amount_payment')::numeric<=0 then raise exception 'Payment amount must be greater than zero.'; end if;

  select coalesce(nullif(trim(p.full_name),''),'OWNER') into v_actor
  from public.rr_user_profiles p where p.auth_user_id=auth.uid() limit 1;

  perform pg_advisory_xact_lock(hashtextextended(concat('SALARY_VOUCHER_V786|',v_prefix),0));
  insert into public.rr_salary_voucher_sequence_v786(voucher_prefix,last_number,updated_at,updated_by)
  values(v_prefix,0,now(),auth.uid()) on conflict(voucher_prefix) do nothing;
  update public.rr_salary_voucher_sequence_v786 s
  set last_number=greatest(s.last_number,coalesce((select max(substring(upper(trim(b.voucher_no)) from length(v_prefix)+1)::bigint)
      from public.rr_salary_payment_batches_v785 b
      where upper(trim(coalesce(b.voucher_no,'')))~('^'||v_prefix||'[0-9]+$')),0))+1,
      updated_at=now(),updated_by=auth.uid()
  where s.voucher_prefix=v_prefix returning s.last_number into v_next_voucher;
  if v_next_voucher is null then raise exception 'Auto voucher sequence unavailable for %.',v_prefix; end if;
  v_voucher:=concat(v_prefix,v_next_voucher);

  insert into public.rr_salary_payment_batches_v785(
    data_mode,payroll_category,payment_method,payment_scope,period_start,period_end,period_month,
    payment_date,payment_mode,voucher_no,remarks,eligible_worker_count,selected_worker_count,advance_worker_count,
    total_previous_outstanding,total_current_period_payable,total_final_payable,selected_scope_payable,
    total_round_100_ready_payment,total_round_100_carry_forward,
    bulk_amount_payment,total_outstanding_payment,total_current_period_payment,total_new_outstanding,
    allocation_ratio,rounding_unit,total_gross_payable,total_advance_recovery,created_by,created_by_name
  ) values(
    v_mode,v_category,v_method,v_scope,v_start,v_end,v_month,p_payment_date,v_paymode,v_voucher,
    nullif(trim(coalesce(p_remarks,'')),''),(v_preview->>'eligible_worker_count')::int,
    (v_preview->>'selected_worker_count')::int,(v_preview->>'advance_worker_count')::int,
    (v_preview->>'total_previous_outstanding')::numeric,(v_preview->>'total_current_period_payable')::numeric,
    (v_preview->>'total_final_payable')::numeric,(v_preview->>'selected_scope_payable')::numeric,
    (v_preview->>'total_round_100_ready_payment')::numeric,(v_preview->>'total_round_100_carry_forward')::numeric,
    (v_preview->>'bulk_amount_payment')::numeric,(v_preview->>'total_outstanding_payment')::numeric,
    (v_preview->>'total_current_period_payment')::numeric,(v_preview->>'total_new_outstanding')::numeric,
    (v_preview->>'allocation_ratio')::numeric,(v_preview->>'rounding_unit')::numeric,
    (v_preview->>'total_gross_payable')::numeric,(v_preview->>'total_advance_recovery')::numeric,auth.uid(),v_actor
  ) returning id into v_batch;

  for r in select * from jsonb_to_recordset(v_preview->'lines') as x(
    worker_id uuid,worker_name text,worker_code text,department_code text,worker_status text,payment_selected boolean,
    gross_previous_outstanding numeric,gross_current_period_payable numeric,advance_opening_balance numeric,
    legacy_advance_recovery numeric,dedicated_advance_recovery numeric,advance_recovery_amount numeric,
    previous_outstanding numeric,current_period_payable numeric,unaccrued_current_amount numeric,
    final_total_payable numeric,scope_payable numeric,round_100_ready_payment numeric,
    round_100_carry_forward numeric,raw_allocation numeric,floor_allocation numeric,
    allocation_remainder numeric,amount_paid numeric,outstanding_payment numeric,current_period_payment numeric,
    new_previous_outstanding numeric,new_current_outstanding numeric,new_total_outstanding numeric,current_source text
  ) loop
    IF v_mode='TEST' AND NOT coalesce(r.payment_selected,false) THEN CONTINUE;END IF;
    insert into public.rr_salary_payment_batch_lines_v785(
      batch_id,worker_id,worker_name,worker_code,department_code,worker_status,payment_selected,
      gross_previous_outstanding,gross_current_period_payable,advance_opening_balance,
      legacy_advance_recovery,dedicated_advance_recovery,advance_recovery_amount,
      previous_outstanding,current_period_payable,unaccrued_current_amount,final_total_payable,scope_payable,
      round_100_ready_payment,round_100_carry_forward,
      raw_allocation,floor_allocation,allocation_remainder,amount_paid,outstanding_payment,current_period_payment,
      new_previous_outstanding,new_current_outstanding,new_total_outstanding,current_source
    ) values(
      v_batch,r.worker_id,r.worker_name,r.worker_code,r.department_code,r.worker_status,r.payment_selected,
      r.gross_previous_outstanding,r.gross_current_period_payable,r.advance_opening_balance,
      r.legacy_advance_recovery,r.dedicated_advance_recovery,r.advance_recovery_amount,
      r.previous_outstanding,r.current_period_payable,r.unaccrued_current_amount,r.final_total_payable,r.scope_payable,
      r.round_100_ready_payment,r.round_100_carry_forward,
      r.raw_allocation,r.floor_allocation,r.allocation_remainder,r.amount_paid,r.outstanding_payment,r.current_period_payment,
      r.new_previous_outstanding,r.new_current_outstanding,r.new_total_outstanding,r.current_source
    ) returning id into v_line_id;

    if not r.payment_selected then continue; end if;
    v_claim:=0; v_due:=null; v_pay:=null; v_adv_ledger:=null; v_salary_recovery:=null;

    if r.unaccrued_current_amount>0 then
      if v_category='PIECE_RATE' then
        insert into public.rr_salary_pcs_work_claims_v785(
          data_mode,work_key,work_date,assignment_id,canonical_lot_id,lot_no,department_code,
          worker_id,worker_name,worker_code,colour_code,colour_name,size_code,submitted_qty,payable_qty,actual_rate,salary_amount,
          batch_id,batch_line_id,created_by)
        select v_mode,w.work_key,w.work_date,w.assignment_id,w.canonical_lot_id,w.lot_no,w.department_code,
          w.worker_id,w.worker_name,w.worker_code,w.colour_code,w.colour_name,w.size_code,w.submitted_qty,w.payable_qty,w.actual_rate,w.salary_amount,
          v_batch,v_line_id,auth.uid()
        from public.rr_salary_pcs_unpaid_work_v785(v_start,v_end,v_mode,r.worker_id) w on conflict do nothing;
        select round(coalesce(sum(c.salary_amount),0),2) into v_claim
        from public.rr_salary_pcs_work_claims_v785 c where c.batch_line_id=v_line_id and c.status='POSTED';
        if abs(v_claim-r.unaccrued_current_amount)>0.01 then raise exception 'PCS work changed during posting for %. Reload Preview.',r.worker_name; end if;
      else v_claim:=round(r.unaccrued_current_amount,2); end if;

      insert into public.rr_salary_current_claims_v785(
        data_mode,payroll_category,worker_id,worker_name,worker_code,department_code,period_start,period_end,period_month,
        source_kind,claimed_amount,batch_id,batch_line_id,created_by)
      values(v_mode,v_category,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_start,v_end,v_month,
        r.current_source,v_claim,v_batch,v_line_id,auth.uid());

      insert into public.rr_worker_salary_ledger_v781(
        data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
        source_module,source_run_id,source_line_id,source_key,period_month,entry_date,entry_type,amount,balance_effect,
        earning_window_start,earning_window_end,reference_no,remarks,created_by,created_by_name)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_category,
        case when v_category='PIECE_RATE' then 'PCS_FLEX_V786' else 'MONTHLY_CURRENT_V786' end,
        v_batch,v_line_id,concat('CURRENT_DUE_V786|',v_batch,'|',r.worker_id),v_month,v_end,
        case when v_category='PIECE_RATE' then 'PCS_WINDOW_DUE' else 'MONTHLY_SALARY_DUE' end,
        v_claim,v_claim,v_start,v_end,concat(case when v_category='PIECE_RATE' then 'PCS-' else 'MONTHLY-' end,
        to_char(v_start,'YYYYMMDD'),'-',to_char(v_end,'YYYYMMDD')),
        concat('Current salary accrued Â· ',r.current_source),auth.uid(),v_actor)
      returning id into v_due;
      update public.rr_salary_payment_batch_lines_v785 set salary_due_ledger_entry_id=v_due where id=v_line_id;
    end if;

    if r.dedicated_advance_recovery>0 then
      perform pg_advisory_xact_lock(hashtextextended(concat('ADVANCE_WORKER_V786|',v_mode,'|',r.worker_id),0));
      select coalesce((select a.dedicated_advance_balance from public.rr_worker_advance_balance_v785 a
        where a.data_mode=v_mode and a.worker_id=r.worker_id),0) into v_dedicated_now;
      if v_dedicated_now+0.005<r.dedicated_advance_recovery then
        raise exception 'Advance balance changed for %. Reload Preview.',r.worker_name;
      end if;

      insert into public.rr_worker_advance_ledger_v785(
        data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
        entry_date,entry_type,amount,balance_effect,reference_no,remarks,
        source_batch_id,source_line_id,created_by,created_by_name)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_category,
        p_payment_date,'ADVANCE_RECOVERY',round(r.dedicated_advance_recovery,2),-round(r.dedicated_advance_recovery,2),
        v_voucher,'Automatic recovery from earned salary',v_batch,v_line_id,auth.uid(),v_actor)
      returning id into v_adv_ledger;

      insert into public.rr_worker_salary_ledger_v781(
        data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
        source_module,source_run_id,source_line_id,source_key,period_month,entry_date,entry_type,amount,balance_effect,
        reference_no,remarks,earning_window_start,earning_window_end,created_by,created_by_name)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_category,
        'ADVANCE_AUTO_RECOVERY_V786',v_batch,v_line_id,concat('ADVANCE_RECOVERY_V786|',v_line_id),
        v_month,p_payment_date,'MANUAL_DEBIT',round(r.dedicated_advance_recovery,2),-round(r.dedicated_advance_recovery,2),
        v_voucher,'Dedicated advance adjusted against earned salary',v_start,v_end,auth.uid(),v_actor)
      returning id into v_salary_recovery;

      update public.rr_salary_payment_batch_lines_v785
      set advance_recovery_ledger_entry_id=v_adv_ledger,advance_salary_ledger_entry_id=v_salary_recovery
      where id=v_line_id;
    end if;

    if r.amount_paid>0 then
      insert into public.rr_worker_salary_ledger_v781(
        data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
        source_module,source_run_id,source_line_id,source_key,period_month,entry_date,entry_type,amount,balance_effect,
        payment_mode,reference_no,remarks,earning_window_start,earning_window_end,created_by,created_by_name)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_category,
        'SALARY_PAYMENT_V786',v_batch,v_line_id,concat('PAYMENT_V786|',v_batch,'|',r.worker_id),v_month,
        p_payment_date,'BULK_PAYMENT',round(r.amount_paid,2),-round(r.amount_paid,2),v_paymode,v_voucher,
        nullif(trim(coalesce(p_remarks,'')),''),v_start,v_end,auth.uid(),v_actor)
      returning id into v_pay;
      update public.rr_salary_payment_batch_lines_v785 set payment_ledger_entry_id=v_pay where id=v_line_id;
    end if;

    v_msg:=concat(case when v_mode='TEST' then '[TEST] ' else '' end,
      case when v_category='PIECE_RATE' then 'PCS Salary Update' else 'Monthly Salary Update' end,
      E'\nPeriod: ',to_char(v_start,'DD-MM-YYYY'),' to ',to_char(v_end,'DD-MM-YYYY'),
      E'\nGross Payable: â‚¹',to_char(r.gross_previous_outstanding+r.gross_current_period_payable,'FM9999999990.00'),
      E'\nAdvance Adjusted: â‚¹',to_char(r.advance_recovery_amount,'FM9999999990.00'),
      E'\nNet Payable: â‚¹',to_char(r.final_total_payable,'FM9999999990.00'),
      E'\nâ‚¹100 Ready Pay: â‚¹',to_char(r.round_100_ready_payment,'FM9999999990.00'),
      E'\nCarry Forward: â‚¹',to_char(r.round_100_carry_forward,'FM9999999990.00'),
      E'\nAmount Paid: â‚¹',to_char(r.amount_paid,'FM9999999990.00'),
      E'\nNew Outstanding: â‚¹',to_char(r.new_total_outstanding,'FM9999999990.00'),
      E'\nPayment Date: ',to_char(p_payment_date,'DD-MM-YYYY'),E'\nMode: ',v_paymode,E'\nVoucher: ',v_voucher);
    begin
      insert into public.rr_worker_app_notifications_v785(data_mode,worker_id,worker_name,worker_code,event_type,title,message_body,source_type,source_id)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,'SALARY_PAYMENT',
        case when v_category='PIECE_RATE' then 'PCS Salary Payment' else 'Monthly Salary Payment' end,
        v_msg,'SALARY_PAYMENT_BATCH',v_batch);
      insert into public.rr_worker_message_outbox_v785(data_mode,worker_id,worker_name,worker_code,event_type,message_body,source_type,source_id,delivery_allowed,status)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,'SALARY_PAYMENT',v_msg,'SALARY_PAYMENT_BATCH',v_batch,
        v_mode='REAL',case when v_mode='REAL' then 'PENDING_ROUTING' else 'BLOCKED_TEST' end);
    exception when others then null; end;
  end loop;

  return jsonb_build_object('ok',true,'batch_id',v_batch,'voucher_no',v_voucher,
    'bulk_amount_payment',(v_preview->>'bulk_amount_payment')::numeric,
    'total_advance_recovery',(v_preview->>'total_advance_recovery')::numeric,
    'total_round_100_ready_payment',(v_preview->>'total_round_100_ready_payment')::numeric,
    'total_round_100_carry_forward',(v_preview->>'total_round_100_carry_forward')::numeric,
    'total_new_outstanding',(v_preview->>'total_new_outstanding')::numeric,'messages_queued',true);
end;
$function$
;