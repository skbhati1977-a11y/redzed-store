CREATE OR REPLACE FUNCTION public.rr_financial_request_assert_test71(p_data_mode text,p_operations text[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE ctx jsonb;
BEGIN
 IF upper(p_data_mode) IS DISTINCT FROM 'TEST' THEN RETURN;END IF;
 BEGIN ctx:=nullif(current_setting('rr.financial_request_context_test71',true),'')::jsonb;EXCEPTION WHEN others THEN ctx:=NULL;END;
 IF auth.uid() IS NULL OR ctx IS NULL OR NOT (ctx->>'operation'=ANY(p_operations)) OR NOT EXISTS(
 SELECT 1 FROM public.rr_financial_requests_test71 r WHERE r.actor_id=auth.uid() AND r.operation=ctx->>'operation' AND r.data_mode='TEST' AND r.request_id=(ctx->>'request_id')::uuid AND r.result IS NULL AND r.effective_identity=public.rr_upm_effective_identity_v200()
 ) THEN RAISE EXCEPTION 'Protected financial request required for TEST posting.' USING ERRCODE='42501';END IF;
END;$$;
REVOKE ALL ON FUNCTION public.rr_financial_request_assert_test71(text,text[]) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_accounts_post_payment_v805(p_against_ledger_id uuid, p_cash_bank_ledger_id uuid, p_amount numeric, p_ref_no text DEFAULT NULL::text, p_narration text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 PERFORM public.rr_financial_request_assert_test71(p_data_mode,ARRAY['rr_accounts_post_payment_v805']);

  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.' using errcode='42501'; end if;
  if p_against_ledger_id is null or p_against_ledger_id=p_cash_bank_ledger_id then raise exception 'Payment party and Cash/Bank must be different active ledgers.'; end if;
  if not exists(select 1 from public.rr_ledgers_v805 where id=p_cash_bank_ledger_id and is_active and upper(ledger_kind) in('CASH','BANK')) then raise exception 'Active Cash/Bank payment source required.'; end if;
  if not exists(select 1 from public.rr_ledgers_v805 where id=p_against_ledger_id and is_active and upper(ledger_kind) not in('CASH','BANK')) then raise exception 'Active party or expense ledger required.'; end if;

  return public.rr_accounts_post_v805(
    'PAYMENT',
    p_amount,
    jsonb_build_array(
      jsonb_build_object(
        'ledger_id', p_against_ledger_id,
        'dr', p_amount,
        'cr', 0,
        'narration', 'Payment / Expense'
      ),
      jsonb_build_object(
        'ledger_id', p_cash_bank_ledger_id,
        'dr', 0,
        'cr', p_amount,
        'narration', 'Paid From Cash / Bank'
      )
    ),
    'ACCOUNTS_TEMPLATE',
    gen_random_uuid()::text,
    p_against_ledger_id,
    p_ref_no,
    current_date,
    p_narration,
    p_data_mode
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_accounts_post_receipt_v805(p_party_ledger_id uuid, p_cash_bank_ledger_id uuid, p_amount numeric, p_ref_no text DEFAULT NULL::text, p_narration text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 PERFORM public.rr_financial_request_assert_test71(p_data_mode,ARRAY['rr_accounts_post_receipt_v805']);

  return public.rr_accounts_post_v805(
    'RECEIPT',
    p_amount,
    jsonb_build_array(
      jsonb_build_object(
        'ledger_id', p_cash_bank_ledger_id,
        'dr', p_amount,
        'cr', 0,
        'narration', 'Money Received'
      ),
      jsonb_build_object(
        'ledger_id', p_party_ledger_id,
        'dr', 0,
        'cr', p_amount,
        'narration', 'Received From Party'
      )
    ),
    'ACCOUNTS_TEMPLATE',
    gen_random_uuid()::text,
    p_party_ledger_id,
    p_ref_no,
    current_date,
    p_narration,
    p_data_mode
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_advance_payment_post_v785(p_data_mode text, p_payroll_category_filter text, p_worker_ids uuid[], p_worker_amounts jsonb, p_payment_date date, p_payment_mode text, p_voucher_no text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL')); v_cat text:=upper(coalesce(nullif(trim(p_payroll_category_filter),''),'ALL'));
  v_paymode text:=upper(trim(coalesce(p_payment_mode,''))); v_voucher text:=nullif(trim(coalesce(p_voucher_no,'')),'');
  v_preview jsonb; v_actor text; v_batch uuid; v_line uuid; v_ledger uuid; r record; v_msg text;
begin
 PERFORM public.rr_financial_request_assert_test71(v_mode,ARRAY['rr_advance_payment_post_v785']);

  if not public.rr_worker_salary_can_pay_v781() then raise exception 'Advance payment permission required.'; end if;
  if p_payment_date is null then raise exception 'Payment Date required.'; end if;
  if v_paymode not in('CASH','BANK','UPI','CHEQUE','OTHER') then raise exception 'Valid Payment Mode required.'; end if;
  if v_voucher is null then raise exception 'Voucher / Reference required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(concat('ADVANCE_V785|',v_mode),0));
  v_preview:=public.rr_advance_payment_preview_v785(v_mode,v_cat,p_worker_ids,p_worker_amounts);
  if (v_preview->>'new_advance_payment_total')::numeric<=0 then raise exception 'At least one New Advance Amount must be greater than zero.'; end if;
  select coalesce(nullif(trim(p.full_name),''),'OWNER') into v_actor from public.rr_user_profiles p where p.auth_user_id=auth.uid() limit 1;
  insert into public.rr_advance_payment_batches_v785(
    data_mode,payroll_category_filter,payment_date,payment_mode,voucher_no,remarks,worker_count,existing_advance_total,new_advance_payment_total,updated_advance_total,created_by,created_by_name
  ) values(
    v_mode,v_cat,p_payment_date,v_paymode,v_voucher,nullif(trim(coalesce(p_remarks,'')),''),(select count(*) from jsonb_to_recordset(v_preview->'lines') x(new_advance_amount numeric) where x.new_advance_amount>0),
    (v_preview->>'existing_advance_total')::numeric,(v_preview->>'new_advance_payment_total')::numeric,(v_preview->>'updated_advance_total')::numeric,auth.uid(),v_actor
  ) returning id into v_batch;
  for r in select * from jsonb_to_recordset(v_preview->'lines') as x(
    worker_id uuid,worker_name text,worker_code text,department_code text,payroll_category text,payment_selected boolean,
    existing_advance_balance numeric,new_advance_amount numeric,updated_advance_balance numeric
  ) loop
    if not r.payment_selected or r.new_advance_amount<=0 then continue; end if;
    insert into public.rr_advance_payment_batch_lines_v785(
      batch_id,worker_id,worker_name,worker_code,department_code,payroll_category,existing_advance_balance,new_advance_amount,updated_advance_balance
    ) values(v_batch,r.worker_id,r.worker_name,r.worker_code,r.department_code,r.payroll_category,r.existing_advance_balance,r.new_advance_amount,r.updated_advance_balance)
    returning id into v_line;
    insert into public.rr_worker_advance_ledger_v785(
      data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,entry_date,entry_type,amount,balance_effect,
      payment_mode,reference_no,remarks,source_batch_id,source_line_id,created_by,created_by_name
    ) values(v_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,r.payroll_category,p_payment_date,'ADVANCE_PAYMENT',r.new_advance_amount,r.new_advance_amount,
      v_paymode,v_voucher,nullif(trim(coalesce(p_remarks,'')),''),v_batch,v_line,auth.uid(),v_actor) returning id into v_ledger;
    update public.rr_advance_payment_batch_lines_v785 set advance_ledger_entry_id=v_ledger where id=v_line;
    v_msg:=concat(case when v_mode='TEST' then '[TEST] ' else '' end,'Advance Payment Update',
      E'\nExisting Advance Balance: â‚¹',to_char(r.existing_advance_balance,'FM9999999990.00'),
      E'\nNew Advance Payment: â‚¹',to_char(r.new_advance_amount,'FM9999999990.00'),
      E'\nUpdated Advance Balance: â‚¹',to_char(r.updated_advance_balance,'FM9999999990.00'),
      E'\nPayment Date: ',to_char(p_payment_date,'DD-MM-YYYY'),E'\nMode: ',v_paymode,E'\nVoucher: ',v_voucher);
    begin
      insert into public.rr_worker_app_notifications_v785(data_mode,worker_id,worker_name,worker_code,event_type,title,message_body,source_type,source_id)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,'ADVANCE_PAYMENT','Advance Payment',v_msg,'ADVANCE_PAYMENT_BATCH',v_batch);
      insert into public.rr_worker_message_outbox_v785(data_mode,worker_id,worker_name,worker_code,event_type,message_body,source_type,source_id,delivery_allowed,status)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,'ADVANCE_PAYMENT',v_msg,'ADVANCE_PAYMENT_BATCH',v_batch,v_mode='REAL',case when v_mode='REAL' then 'PENDING_ROUTING' else 'BLOCKED_TEST' end);
    exception when others then null;
    end;
  end loop;
  return jsonb_build_object('ok',true,'batch_id',v_batch,'voucher_no',v_voucher,
    'new_advance_payment_total',(v_preview->>'new_advance_payment_total')::numeric,
    'updated_advance_total',(v_preview->>'updated_advance_total')::numeric,'messages_queued',true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_committee_payment_post_v824(p_scheme_id uuid, p_month_no integer, p_amount numeric, p_payment_mode text, p_organizer_reference text DEFAULT NULL::text, p_bank_reference text DEFAULT NULL::text, p_payment_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    s public.rr_committee_schemes_v820%rowtype;
    m public.rr_committee_months_v820%rowtype;

    v_mode text;
    v_already numeric;
    v_balance numeric;

    v_no text;
    v_id uuid;
begin
 PERFORM public.rr_financial_request_assert_test71('TEST',ARRAY['rr_committee_payment_post_v824']);


    if not public.rr_acct_can_view_v805() then
      raise exception 'Accounts permission required.';
    end if;

    select *
    into s
    from public.rr_committee_schemes_v820
    where id=p_scheme_id;

    if not found then
      raise exception 'Committee scheme not found.';
    end if;

    if s.data_mode<>'TEST' then
      raise exception 'V824 TEST only.';
    end if;

    if not coalesce(s.member_side_only,false) then
      raise exception 'Member-side Committee required.';
    end if;

    if coalesce(p_amount,0)<=0 then
      raise exception 'Payment amount must be positive.';
    end if;

    v_mode:=upper(trim(coalesce(p_payment_mode,'')));

    if v_mode not in ('CASH','BANK') then
      raise exception 'Payment mode must be CASH or BANK.';
    end if;

    if v_mode='BANK'
       and nullif(trim(p_bank_reference),'') is null then
      raise exception 'Bank reference required.';
    end if;

    select *
    into m
    from public.rr_committee_months_v820
    where scheme_id=p_scheme_id
      and month_no=p_month_no
    for update;

    if not found then
      raise exception 'Committee month not found.';
    end if;

    select coalesce(sum(amount),0)
    into v_already
    from public.rr_committee_payments_v824
    where month_id=m.id
      and status='POSTED';

    v_balance:=round(m.our_net_installment-v_already,2);

    if v_balance<=0 then
      raise exception 'Month already fully paid.';
    end if;

    if round(p_amount,2)>v_balance then
      raise exception
        'Payment exceeds outstanding ₹%',
        v_balance;
    end if;

    v_no :=
      'TCPAY'||
      nextval('public.rr_committee_test_payment_seq_v824');

    insert into public.rr_committee_payments_v824(
      scheme_id,
      month_id,
      payment_no,
      payment_date,
      payment_mode,
      amount,
      organizer_reference,
      bank_reference,
      remarks,
      status,
      data_mode
    )
    values(
      s.id,
      m.id,
      v_no,
      coalesce(p_payment_date,current_date),
      v_mode,
      round(p_amount,2),
      nullif(trim(p_organizer_reference),''),
      nullif(trim(p_bank_reference),''),
      nullif(trim(p_remarks),''),
      'POSTED',
      'TEST'
    )
    returning id into v_id;

    v_already:=round(v_already+p_amount,2);

    update public.rr_committee_months_v820
    set
      our_paid_amount=v_already,
      our_payment_status=
        case
          when v_already>=our_net_installment
            then 'PAID'
          else 'PENDING'
        end,
      updated_at=now()
    where id=m.id;

    -- Cash/Bank and contribution asset post atomically with the payment.
    perform public.rr_committee_payment_accounts_post_v825(v_id);
    return jsonb_build_object(
      'PASS',true,
      'payment_id',v_id,
      'payment_no',v_no,
      'scheme_code',s.scheme_code,
      'month_no',m.month_no,
      'payment_mode',v_mode,
      'amount',round(p_amount,2),
      'total_paid',v_already,
      'outstanding',
        round(greatest(m.our_net_installment-v_already,0),2),
      'status',
        case
          when v_already>=m.our_net_installment
            then 'PAID'
          else 'PARTIAL'
        end
    );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_material_post_purchase_txn_v661(p_supplier_ledger_id uuid, p_material_id uuid, p_purchase_ledger_id uuid, p_purchase_qty numeric, p_purchase_unit text, p_purchase_to_consumption numeric, p_rate numeric, p_bill_no text, p_bill_date date, p_gst_amount numeric, p_payment_status text, p_paid_amount numeric, p_cash_bank_ledger_id uuid, p_data_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.rr_material_master_v805%rowtype;v_purchase_unit text:=upper(trim(coalesce(p_purchase_unit,'')));v_factor numeric;v_consumption_qty numeric;v_stock_qty numeric;v_result jsonb;
begin
 PERFORM public.rr_financial_request_assert_test71(p_data_mode,ARRAY['rr_material_post_purchase_txn_v661']);

 select * into m from public.rr_material_master_v805 where id=p_material_id and is_active;if not found then raise exception 'Active mapped Material not found.';end if;
 if coalesce(p_purchase_qty,0)<=0 then raise exception 'Purchase Qty required.';end if;
 if not exists(select 1 from public.rr_unit_master_v606 u where upper(u.unit_code)=v_purchase_unit and u.is_active) then raise exception 'Active Purchase Unit required.';end if;
 if v_purchase_unit=upper(m.consumption_unit) then v_factor:=1;else v_factor:=p_purchase_to_consumption;if coalesce(v_factor,0)<=0 then raise exception 'Purchase to Consumption conversion required when units differ.';end if;end if;
 v_consumption_qty:=round(p_purchase_qty*v_factor,6);
 if upper(m.base_stock_unit)=upper(m.consumption_unit) then v_stock_qty:=v_consumption_qty;elsif coalesce(m.consumption_to_base,0)>0 then v_stock_qty:=round(v_consumption_qty*m.consumption_to_base,6);else raise exception 'Saved Consumption to Stock conversion missing.';end if;
 select public.rr_material_post_purchase_v805_1(p_supplier_ledger_id,p_material_id,p_purchase_ledger_id,p_purchase_qty,v_purchase_unit,v_stock_qty,m.base_stock_unit,v_consumption_qty,m.consumption_unit,p_rate,p_bill_no,coalesce(p_bill_date,current_date),coalesce(p_gst_amount,0),coalesce(p_payment_status,'CREDIT'),coalesce(p_paid_amount,0),p_cash_bank_ledger_id,upper(coalesce(p_data_mode,'TEST'))) into v_result;
 if p_supplier_ledger_id is not null and m.preferred_supplier_ledger_id is null then update public.rr_material_master_v805 set preferred_supplier_ledger_id=p_supplier_ledger_id,updated_at=now() where id=m.id;end if;
 return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('purchase_unit',v_purchase_unit,'purchase_to_consumption',v_factor,'backend_stock_qty',v_stock_qty,'backend_stock_unit',m.base_stock_unit,'backend_consumption_qty',v_consumption_qty,'backend_consumption_unit',m.consumption_unit);
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_material_post_purchase_v805_1(p_supplier_ledger_id uuid, p_material_id uuid, p_purchase_ledger_id uuid, p_purchase_qty numeric, p_purchase_unit text, p_stock_qty numeric, p_stock_unit text, p_consumption_qty numeric, p_consumption_unit text, p_rate numeric, p_bill_no text, p_bill_date date, p_gst_amount numeric, p_payment_status text, p_paid_amount numeric, p_cash_bank_ledger_id uuid, p_data_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_m public.rr_material_master_v805%rowtype; v_source_id text:=gen_random_uuid()::text; v_result jsonb; v_purchase_id uuid;
        v_cost numeric; v_current_cost numeric; v_before numeric; v_after numeric; v_run_value numeric; v_run_qty numeric; v_run_avg numeric;
begin
 PERFORM public.rr_financial_request_assert_test71(p_data_mode,ARRAY['rr_material_post_purchase_v805_1','rr_material_post_purchase_txn_v661']);

  if p_material_id is null then raise exception 'Material required.'; end if;
  if coalesce(p_purchase_qty,0)<=0 or coalesce(p_stock_qty,0)<=0 or coalesce(p_consumption_qty,0)<=0 then raise exception 'Purchase Qty, Stock Qty and Consumption Qty must be greater than zero.'; end if;
  if coalesce(p_rate,0)<0 then raise exception 'Rate cannot be negative.'; end if;
  select * into v_m from public.rr_material_master_v805 where id=p_material_id and is_active;
  if not found then raise exception 'Active Material not found.'; end if;
  if upper(v_m.purchase_unit)<>upper(trim(p_purchase_unit)) or upper(v_m.base_stock_unit)<>upper(trim(p_stock_unit)) or upper(v_m.consumption_unit)<>upper(trim(p_consumption_unit)) then
    raise exception 'Units do not match saved Material setup.';
  end if;

  select coalesce(current_balance_stock_qty,0) into v_before from public.rr_material_stock_v805_1 where material_id=p_material_id and data_mode=upper(coalesce(p_data_mode,'TEST'));
  v_before:=coalesce(v_before,0); v_after:=v_before+p_stock_qty;

  update public.rr_material_master_v805 set purchase_to_base=p_stock_qty/p_purchase_qty,consumption_to_base=p_stock_qty/p_consumption_qty,updated_at=now() where id=p_material_id;
  v_cost:=round(p_purchase_qty*p_rate,2); v_current_cost:=round(v_cost/p_consumption_qty,6);

  select public.rr_accounts_post_material_purchase_v805(
    p_supplier_ledger_id,p_material_id,p_purchase_ledger_id,p_purchase_qty,p_rate,p_bill_no,coalesce(p_bill_date,current_date),coalesce(p_gst_amount,0),
    p_payment_status,coalesce(p_paid_amount,0),p_cash_bank_ledger_id,'MATERIAL_PURCHASE_V805_1',v_source_id,upper(coalesce(p_data_mode,'TEST'))
  ) into v_result;

  select id into v_purchase_id from public.rr_material_purchases_v805
   where source_module='MATERIAL_PURCHASE_V805_1' and source_record_id=v_source_id and data_mode=upper(coalesce(p_data_mode,'TEST')) order by created_at desc limit 1;
  if v_purchase_id is null then raise exception 'Accounts posted but Material Purchase row could not be resolved.'; end if;

  update public.rr_material_purchases_v805 set stock_qty=p_stock_qty,stock_unit=upper(trim(p_stock_unit)),
    consumption_equivalent_qty=p_consumption_qty,consumption_equivalent_unit=upper(trim(p_consumption_unit)),
    current_cost_per_consumption_unit=v_current_cost,costing_value=v_cost,base_qty=p_stock_qty,
    balance_before_purchase=v_before,balance_after_purchase=v_after where id=v_purchase_id;

  select running_purchase_value,running_consumption_qty,running_weighted_avg_cost_per_consumption_unit
    into v_run_value,v_run_qty,v_run_avg from public.rr_material_running_cost_v805_1
    where material_id=p_material_id and data_mode=upper(coalesce(p_data_mode,'TEST'));

  update public.rr_material_purchases_v805 set running_purchase_value=v_run_value,running_consumption_qty=v_run_qty,
    running_weighted_avg_cost_per_consumption_unit=v_run_avg where id=v_purchase_id;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('purchase_id',v_purchase_id,'current_cost_per_consumption_unit',v_current_cost,
    'running_purchase_value',v_run_value,'running_consumption_qty',v_run_qty,'running_weighted_avg_cost_per_consumption_unit',v_run_avg,
    'balance_before_purchase',v_before,'balance_after_purchase',v_after);
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_salary_payment_post_v785(p_payroll_category text, p_period_start date, p_period_end date, p_data_mode text, p_payment_method text, p_payment_scope text, p_bulk_amount numeric, p_worker_ids uuid[], p_worker_amounts jsonb, p_payment_date date, p_payment_mode text, p_voucher_no text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_category text:=upper(trim(coalesce(p_payroll_category,'')));
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL'));
  v_method text:=upper(trim(coalesce(p_payment_method,'')));
  v_scope text:=upper(trim(coalesce(p_payment_scope,'')));
  v_start date:=coalesce(p_period_start,current_date);
  v_end date:=coalesce(p_period_end,v_start);
  v_month date:=date_trunc('month',v_start)::date;
  v_paymode text:=upper(trim(coalesce(p_payment_mode,'')));
  v_prefix text;
  v_voucher text;
  v_next_voucher bigint;
  v_preview jsonb; v_actor text; v_batch uuid; v_line_id uuid; v_due uuid; v_pay uuid;
  r record; v_claim numeric(16,2); v_msg text;
begin
 PERFORM public.rr_financial_request_assert_test71(v_mode,ARRAY['rr_salary_payment_post_v785','rr_salary_payment_post_v786']);

  if not public.rr_worker_salary_can_pay_v781() then raise exception 'Salary payment permission required.'; end if;
  if p_payment_date is null then raise exception 'Payment Date required.'; end if;
  if v_paymode not in('CASH','BANK','UPI','CHEQUE','OTHER') then raise exception 'Valid Payment Mode required.'; end if;
  v_prefix:=case
    when v_category='PIECE_RATE' then 'PCSL'
    when v_category='SALARIED' then 'MSL'
    else null
  end;
  if v_prefix is null then raise exception 'Payroll Category must be PIECE_RATE or SALARIED.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(concat('SALARY_V785|',v_mode,'|',v_category),0));
  v_preview:=public.rr_salary_payment_preview_v785(v_category,v_start,v_end,v_mode,v_method,v_scope,p_bulk_amount,p_worker_ids,p_worker_amounts);
  if v_method<>'WORKER_LEDGER_WISE' and (v_preview->>'bulk_amount_payment')::numeric<=0 then raise exception 'Bulk Amount Payment must be greater than zero.'; end if;

  select coalesce(nullif(trim(p.full_name),''),'OWNER') into v_actor
  from public.rr_user_profiles p where p.auth_user_id=auth.uid() limit 1;

  -- Final voucher is allocated only after preview succeeds.
  -- The category-wide advisory lock prevents duplicates across devices/users.
  perform pg_advisory_xact_lock(
    hashtextextended(concat('SALARY_VOUCHER_V786|',v_prefix),0)
  );

  insert into public.rr_salary_voucher_sequence_v786(
    voucher_prefix,last_number,updated_at,updated_by
  )
  values(v_prefix,0,now(),auth.uid())
  on conflict(voucher_prefix) do nothing;

  update public.rr_salary_voucher_sequence_v786 s
  set last_number=
        greatest(
          s.last_number,
          coalesce((
            select max(
              substring(
                upper(trim(b.voucher_no))
                from length(v_prefix)+1
              )::bigint
            )
            from public.rr_salary_payment_batches_v785 b
            where upper(trim(coalesce(b.voucher_no,'')))
                  ~ ('^'||v_prefix||'[0-9]+$')
          ),0)
        )+1,
      updated_at=now(),
      updated_by=auth.uid()
  where s.voucher_prefix=v_prefix
  returning s.last_number into v_next_voucher;

  if v_next_voucher is null then
    raise exception 'Auto voucher sequence unavailable for %.',v_prefix;
  end if;

  v_voucher:=concat(v_prefix,v_next_voucher);

  insert into public.rr_salary_payment_batches_v785(
    data_mode,payroll_category,payment_method,payment_scope,period_start,period_end,period_month,
    payment_date,payment_mode,voucher_no,remarks,eligible_worker_count,selected_worker_count,advance_worker_count,
    total_previous_outstanding,total_current_period_payable,total_final_payable,selected_scope_payable,
    bulk_amount_payment,total_outstanding_payment,total_current_period_payment,total_new_outstanding,
    allocation_ratio,rounding_unit,created_by,created_by_name
  ) values(
    v_mode,v_category,v_method,v_scope,v_start,v_end,v_month,p_payment_date,v_paymode,v_voucher,nullif(trim(coalesce(p_remarks,'')),''),
    (v_preview->>'eligible_worker_count')::int,(v_preview->>'selected_worker_count')::int,(v_preview->>'advance_worker_count')::int,
    (v_preview->>'total_previous_outstanding')::numeric,(v_preview->>'total_current_period_payable')::numeric,
    (v_preview->>'total_final_payable')::numeric,(v_preview->>'selected_scope_payable')::numeric,
    (v_preview->>'bulk_amount_payment')::numeric,(v_preview->>'total_outstanding_payment')::numeric,
    (v_preview->>'total_current_period_payment')::numeric,(v_preview->>'total_new_outstanding')::numeric,
    (v_preview->>'allocation_ratio')::numeric,(v_preview->>'rounding_unit')::numeric,auth.uid(),v_actor
  ) returning id into v_batch;

  for r in select * from jsonb_to_recordset(v_preview->'lines') as x(
    worker_id uuid,worker_name text,worker_code text,department_code text,worker_status text,payment_selected boolean,
    previous_outstanding numeric,current_period_payable numeric,unaccrued_current_amount numeric,final_total_payable numeric,scope_payable numeric,
    raw_allocation numeric,floor_allocation numeric,allocation_remainder numeric,amount_paid numeric,
    outstanding_payment numeric,current_period_payment numeric,new_previous_outstanding numeric,new_current_outstanding numeric,new_total_outstanding numeric,current_source text
  ) loop
    insert into public.rr_salary_payment_batch_lines_v785(
      batch_id,worker_id,worker_name,worker_code,department_code,worker_status,payment_selected,
      previous_outstanding,current_period_payable,unaccrued_current_amount,final_total_payable,scope_payable,
      raw_allocation,floor_allocation,allocation_remainder,amount_paid,outstanding_payment,current_period_payment,
      new_previous_outstanding,new_current_outstanding,new_total_outstanding,current_source
    ) values(
      v_batch,r.worker_id,r.worker_name,r.worker_code,r.department_code,r.worker_status,r.payment_selected,
      r.previous_outstanding,r.current_period_payable,r.unaccrued_current_amount,r.final_total_payable,r.scope_payable,
      r.raw_allocation,r.floor_allocation,r.allocation_remainder,r.amount_paid,r.outstanding_payment,r.current_period_payment,
      r.new_previous_outstanding,r.new_current_outstanding,r.new_total_outstanding,r.current_source
    ) returning id into v_line_id;

    if not r.payment_selected then continue; end if;
    v_claim:=0;

    if r.unaccrued_current_amount>0 then
      if v_category='PIECE_RATE' then
        insert into public.rr_salary_pcs_work_claims_v785(
          data_mode,work_key,work_date,assignment_id,canonical_lot_id,lot_no,department_code,
          worker_id,worker_name,worker_code,colour_code,colour_name,size_code,submitted_qty,payable_qty,actual_rate,salary_amount,
          batch_id,batch_line_id,created_by
        )
        select v_mode,w.work_key,w.work_date,w.assignment_id,w.canonical_lot_id,w.lot_no,w.department_code,
          w.worker_id,w.worker_name,w.worker_code,w.colour_code,w.colour_name,w.size_code,w.submitted_qty,w.payable_qty,w.actual_rate,w.salary_amount,
          v_batch,v_line_id,auth.uid()
        from public.rr_salary_pcs_unpaid_work_v785(v_start,v_end,v_mode,r.worker_id) w
        on conflict do nothing;
        select round(coalesce(sum(c.salary_amount),0),2) into v_claim
        from public.rr_salary_pcs_work_claims_v785 c where c.batch_line_id=v_line_id and c.status='POSTED';
        if abs(v_claim-r.unaccrued_current_amount)>0.01 then raise exception 'PCS work changed during posting for %. Reload Preview.',r.worker_name; end if;
      else
        v_claim:=round(r.unaccrued_current_amount,2);
      end if;

      insert into public.rr_salary_current_claims_v785(
        data_mode,payroll_category,worker_id,worker_name,worker_code,department_code,period_start,period_end,period_month,
        source_kind,claimed_amount,batch_id,batch_line_id,created_by
      ) values(v_mode,v_category,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_start,v_end,v_month,r.current_source,v_claim,v_batch,v_line_id,auth.uid());

      insert into public.rr_worker_salary_ledger_v781(
        data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
        source_module,source_run_id,source_line_id,source_key,period_month,entry_date,entry_type,amount,balance_effect,
        earning_window_start,earning_window_end,reference_no,remarks,created_by,created_by_name
      ) values(
        v_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_category,
        case when v_category='PIECE_RATE' then 'PCS_FLEX_V785' else 'MONTHLY_CURRENT_V785' end,
        v_batch,v_line_id,concat('CURRENT_DUE_V785|',v_batch,'|',r.worker_id),v_month,v_end,
        case when v_category='PIECE_RATE' then 'PCS_WINDOW_DUE' else 'MONTHLY_SALARY_DUE' end,
        v_claim,v_claim,v_start,v_end,
        concat(case when v_category='PIECE_RATE' then 'PCS-' else 'MONTHLY-' end,to_char(v_start,'YYYYMMDD'),'-',to_char(v_end,'YYYYMMDD')),
        concat('Current period salary accrued Â· ',r.current_source),auth.uid(),v_actor
      ) returning id into v_due;
      update public.rr_salary_payment_batch_lines_v785 set salary_due_ledger_entry_id=v_due where id=v_line_id;
    end if;

    if r.amount_paid>0 then
      insert into public.rr_worker_salary_ledger_v781(
        data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
        source_module,source_run_id,source_line_id,source_key,period_month,entry_date,entry_type,amount,balance_effect,
        payment_mode,reference_no,remarks,earning_window_start,earning_window_end,created_by,created_by_name
      ) values(
        v_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,v_category,
        'SALARY_PAYMENT_V785',v_batch,v_line_id,concat('PAYMENT_V785|',v_batch,'|',r.worker_id),v_month,p_payment_date,'BULK_PAYMENT',
        round(r.amount_paid,2),-round(r.amount_paid,2),v_paymode,v_voucher,nullif(trim(coalesce(p_remarks,'')),''),v_start,v_end,auth.uid(),v_actor
      ) returning id into v_pay;
      update public.rr_salary_payment_batch_lines_v785 set payment_ledger_entry_id=v_pay where id=v_line_id;
    end if;

    v_msg:=concat(
      case when v_mode='TEST' then '[TEST] ' else '' end,
      case when v_category='PIECE_RATE' then 'PCS Salary Update' else 'Monthly Salary Update' end,
      E'\nPeriod: ',to_char(v_start,'DD-MM-YYYY'),' to ',to_char(v_end,'DD-MM-YYYY'),
      E'\nPrevious Outstanding: â‚¹',to_char(r.previous_outstanding,'FM9999999990.00'),
      E'\nCurrent Period Payable: â‚¹',to_char(r.current_period_payable,'FM9999999990.00'),
      E'\nFinal Total Payable: â‚¹',to_char(r.final_total_payable,'FM9999999990.00'),
      E'\nAmount Paid: â‚¹',to_char(r.amount_paid,'FM9999999990.00'),
      E'\nOutstanding Payment: â‚¹',to_char(r.outstanding_payment,'FM9999999990.00'),
      E'\nCurrent Period Payment: â‚¹',to_char(r.current_period_payment,'FM9999999990.00'),
      E'\nNew Outstanding: â‚¹',to_char(r.new_total_outstanding,'FM9999999990.00'),
      E'\nMethod: ',replace(v_method,'_',' '),E'\nScope: ',replace(v_scope,'_',' '),
      E'\nPayment Date: ',to_char(p_payment_date,'DD-MM-YYYY'),E'\nMode: ',v_paymode,E'\nVoucher: ',v_voucher
    );
    begin
      insert into public.rr_worker_app_notifications_v785(data_mode,worker_id,worker_name,worker_code,event_type,title,message_body,source_type,source_id)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,'SALARY_PAYMENT',case when v_category='PIECE_RATE' then 'PCS Salary Payment' else 'Monthly Salary Payment' end,v_msg,'SALARY_PAYMENT_BATCH',v_batch);
      insert into public.rr_worker_message_outbox_v785(data_mode,worker_id,worker_name,worker_code,event_type,message_body,source_type,source_id,delivery_allowed,status)
      values(v_mode,r.worker_id,r.worker_name,r.worker_code,'SALARY_PAYMENT',v_msg,'SALARY_PAYMENT_BATCH',v_batch,v_mode='REAL',case when v_mode='REAL' then 'PENDING_ROUTING' else 'BLOCKED_TEST' end);
    exception when others then null;
    end;
  end loop;

  return jsonb_build_object('ok',true,'batch_id',v_batch,'voucher_no',v_voucher,
    'bulk_amount_payment',(v_preview->>'bulk_amount_payment')::numeric,
    'total_new_outstanding',(v_preview->>'total_new_outstanding')::numeric,
    'zero_payment_batch',((v_preview->>'bulk_amount_payment')::numeric<=0),'messages_queued',true);
end;
$function$
;
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
 PERFORM public.rr_financial_request_assert_test71(v_mode,ARRAY['rr_salary_payment_post_v786']);

  if not public.rr_worker_salary_can_pay_v781() then raise exception 'Salary payment permission required.'; end if;
  if p_payment_date is null then raise exception 'Payment Date required.'; end if;
  if v_paymode not in('CASH','BANK','UPI','CHEQUE','OTHER') then raise exception 'Valid Payment Mode required.'; end if;
  v_prefix:=case when v_category='PIECE_RATE' then 'PCSL' when v_category='SALARIED' then 'MSL' end;
  if v_prefix is null then raise exception 'Payroll Category must be PIECE_RATE or SALARIED.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(concat('SALARY_V786|',v_mode,'|',v_category),0));
  v_preview:=public.rr_salary_payment_preview_v786(v_category,v_start,v_end,v_mode,v_method,v_scope,
    p_bulk_amount,p_worker_ids,p_worker_amounts);
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
CREATE OR REPLACE FUNCTION public.rr_worker_salary_payment_post_v781(p_due_entry_id uuid, p_amount numeric, p_payment_date date, p_payment_mode text, p_reference_no text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_due public.rr_worker_salary_ledger_v781%rowtype;
  v_amount numeric(16,2);
  v_mode text;
  v_reference text;
  v_paid numeric(16,2):=0;
  v_balance numeric(16,2):=0;
  v_actor_name text;
  v_payment_id uuid;
  v_run_result jsonb;
begin
 PERFORM public.rr_financial_request_assert_test71((SELECT data_mode FROM public.rr_worker_salary_ledger_v781 WHERE id=p_due_entry_id),ARRAY['rr_worker_salary_payment_post_v781']);

  if not public.rr_worker_salary_can_pay_v781() then
    raise exception 'Worker salary payment permission required.';
  end if;

  v_amount:=round(coalesce(p_amount,0),2);
  if v_amount<=0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  if p_payment_date is null then
    raise exception 'Payment date required.';
  end if;

  v_mode:=upper(trim(coalesce(p_payment_mode,'')));
  if v_mode not in(
    'CASH','BANK','UPI','CHEQUE','OTHER'
  ) then
    raise exception 'Valid payment mode required.';
  end if;

  v_reference:=nullif(trim(coalesce(p_reference_no,'')),'');
  if v_reference is null then
    raise exception 'Payment voucher / reference required.';
  end if;

  select *
  into v_due
  from public.rr_worker_salary_ledger_v781
  where id=p_due_entry_id
    and status='POSTED'
    and entry_type='SALARY_DUE'
  for update;

  if not found then
    raise exception 'Active salary due entry not found.';
  end if;

  select
    coalesce(sum(
      case
        when entry_type='PAYMENT'
          then amount
        when entry_type='PAYMENT_REVERSAL'
          then -amount
        else 0
      end
    ),0)
  into v_paid
  from public.rr_worker_salary_ledger_v781
  where due_entry_id=v_due.id
    and status='POSTED'
    and entry_type in(
      'PAYMENT',
      'PAYMENT_REVERSAL'
    );

  v_balance:=round(v_due.amount-v_paid,2);

  if v_balance<=0.005 then
    raise exception 'This salary due is already fully paid.';
  end if;

  if v_amount>v_balance+0.005 then
    raise exception
      'Payment exceeds balance. Current balance is â‚¹%.',
      v_balance;
  end if;

  select coalesce(
    nullif(trim(p.full_name),''),
    p.role_code,
    'AUTHORIZED USER'
  )
  into v_actor_name
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid()
  limit 1;

  insert into public.rr_worker_salary_ledger_v781(
    data_mode,
    worker_id,
    worker_name,
    worker_code,
    department_code,
    payroll_category,
    source_module,
    source_run_id,
    source_line_id,
    period_month,
    entry_date,
    entry_type,
    amount,
    balance_effect,
    due_entry_id,
    payment_mode,
    reference_no,
    remarks,
    created_by,
    created_by_name
  )
  values(
    v_due.data_mode,
    v_due.worker_id,
    v_due.worker_name,
    v_due.worker_code,
    v_due.department_code,
    v_due.payroll_category,
    v_due.source_module,
    v_due.source_run_id,
    v_due.source_line_id,
    v_due.period_month,
    p_payment_date,
    'PAYMENT',
    v_amount,
    -v_amount,
    v_due.id,
    v_mode,
    v_reference,
    nullif(trim(coalesce(p_remarks,'')),''),
    auth.uid(),
    v_actor_name
  )
  returning id into v_payment_id;

  if v_due.source_module='PCS_V779'
     and v_due.source_run_id is not null then
    v_run_result:=
      public.rr_worker_salary_sync_piece_run_v781(
        v_due.source_run_id
      );
  end if;

  return jsonb_build_object(
    'ok',true,
    'payment_id',v_payment_id,
    'due_entry_id',v_due.id,
    'worker_id',v_due.worker_id,
    'worker_name',v_due.worker_name,
    'payment_amount',v_amount,
    'previous_balance',v_balance,
    'new_balance',greatest(v_balance-v_amount,0),
    'run_result',v_run_result
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_material_post_purchase_v805_2(p_supplier_ledger_id uuid, p_material_id uuid, p_purchase_ledger_id uuid, p_purchase_qty numeric, p_purchase_unit text, p_stock_qty numeric, p_stock_unit text, p_consumption_qty numeric, p_consumption_unit text, p_rate numeric, p_rate_basis text, p_bill_no text, p_bill_date date, p_gst_amount numeric, p_payment_status text, p_paid_amount numeric, p_cash_bank_ledger_id uuid, p_data_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.rr_material_master_v805%rowtype; typ text; src text:=gen_random_uuid()::text;
 val numeric; eff numeric; cur numeric; before_bal numeric; after_bal numeric; res jsonb; pid uuid; rc record;
begin
 PERFORM public.rr_financial_request_assert_test71(p_data_mode,ARRAY['rr_material_post_purchase_v805_2']);

 select mm.* into m
 from public.rr_material_master_v805 mm
 where mm.id=p_material_id and mm.is_active;

 if not found then
   raise exception 'Active material not found.';
 end if;

 select mt.type_code into typ
 from public.rr_material_types_v805 mt
 where mt.id=m.material_type_id;
 if typ='REGULAR_CLOTH' then raise exception 'Regular Cloth purchase only from CB New / CB Purchase.'; end if;
 if typ in('MATCHING_CLOTH','STICKER','METAL_ID') then raise exception '% purchase remains in its dedicated source module.',replace(typ,'_',' '); end if;
 if coalesce(p_purchase_qty,0)<=0 or coalesce(p_stock_qty,0)<=0 or coalesce(p_consumption_qty,0)<=0
 then raise exception 'Purchase Qty, Stock Qty and Consumption Qty must be greater than zero.'; end if;
 if upper(m.purchase_unit)<>upper(p_purchase_unit) or upper(m.base_stock_unit)<>upper(p_stock_unit) or upper(m.consumption_unit)<>upper(p_consumption_unit)
 then raise exception 'Units do not match saved material setup.'; end if;
 select coalesce(current_balance_qty,0) into before_bal from public.rr_material_stock_v805_2
 where material_id=p_material_id and data_mode=upper(coalesce(p_data_mode,'TEST'));
 if upper(coalesce(p_rate_basis,'PURCHASE'))='STOCK' then
   val:=round(p_stock_qty*p_rate,2); eff:=val/p_purchase_qty;
 else val:=round(p_purchase_qty*p_rate,2); eff:=p_rate; end if;
 cur:=round(val/p_consumption_qty,6);
 update public.rr_material_master_v805 set purchase_to_base=p_stock_qty/p_purchase_qty,
 consumption_to_base=p_stock_qty/p_consumption_qty,updated_at=now() where id=p_material_id;
 select public.rr_accounts_post_material_purchase_v805(
   p_supplier_ledger_id,p_material_id,p_purchase_ledger_id,p_purchase_qty,eff,p_bill_no,coalesce(p_bill_date,current_date),
   coalesce(p_gst_amount,0),p_payment_status,coalesce(p_paid_amount,0),p_cash_bank_ledger_id,'MATERIAL_PURCHASE_V805_2',src,
   upper(coalesce(p_data_mode,'TEST'))) into res;
 select id into pid from public.rr_material_purchases_v805
 where source_module='MATERIAL_PURCHASE_V805_2' and source_record_id=src order by created_at desc limit 1;
 if pid is null then raise exception 'Material purchase row not resolved after accounts posting.'; end if;
 after_bal:=before_bal+p_stock_qty;
 update public.rr_material_purchases_v805 set stock_qty=p_stock_qty,stock_unit=upper(p_stock_unit),
 consumption_equivalent_qty=p_consumption_qty,consumption_equivalent_unit=upper(p_consumption_unit),
 current_cost_per_consumption_unit=cur,costing_value=val,base_qty=p_stock_qty,
 balance_before_purchase=before_bal,balance_after_purchase=after_bal where id=pid;
 select * into rc from public.rr_material_running_cost_v805_2 where material_id=p_material_id and data_mode=upper(coalesce(p_data_mode,'TEST'));
 perform public.rr_material_reorder_check_v805_2(p_material_id,p_data_mode,'PURCHASE',pid::text);
 return coalesce(res,'{}'::jsonb)||jsonb_build_object('purchase_id',pid,'balance_before',before_bal,'balance_after',after_bal,
 'current_cost_per_consumption_unit',cur,'running_weighted_avg_cost_per_consumption_unit',rc.running_weighted_avg_cost_per_consumption_unit);
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_financial_request_post_test71(p_operation text, p_data_mode text, p_request_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_actor uuid:=auth.uid();v_mode text:=upper(p_data_mode);v_existing public.rr_financial_requests_test71%rowtype;v_result jsonb;v_identity jsonb;v_previous_request_context text:=current_setting('rr.financial_request_context_test71',true);
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'Login required.' USING ERRCODE='42501';END IF;
 IF p_operation NOT IN('rr_accounts_post_payment_v805','rr_accounts_post_receipt_v805','rr_committee_payment_post_v824','rr_material_post_purchase_v805_1','rr_worker_salary_payment_post_v781','rr_advance_payment_post_v785','rr_material_post_purchase_txn_v661','rr_salary_payment_post_v785','rr_salary_payment_post_v786','rr_post_mc_purchase_accounts_test71','rr_monthly_salary_payment_post_test71','rr_material_post_purchase_v805_2') THEN RAISE EXCEPTION 'Unsupported financial operation.';END IF;
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
 PERFORM set_config('rr.financial_request_context_test71',jsonb_build_object('operation',p_operation,'request_id',p_request_id)::text,true);
 CASE p_operation
 WHEN 'rr_material_post_purchase_v805_2' THEN
 SELECT public.rr_material_post_purchase_v805_2(x.p_supplier_ledger_id,x.p_material_id,x.p_purchase_ledger_id,x.p_purchase_qty,x.p_purchase_unit,x.p_stock_qty,x.p_stock_unit,x.p_consumption_qty,x.p_consumption_unit,x.p_rate,x.p_rate_basis,x.p_bill_no,x.p_bill_date,x.p_gst_amount,x.p_payment_status,x.p_paid_amount,x.p_cash_bank_ledger_id,x.p_data_mode) INTO v_result FROM jsonb_to_record(p_payload) AS x(p_supplier_ledger_id uuid,p_material_id uuid,p_purchase_ledger_id uuid,p_purchase_qty numeric,p_purchase_unit text,p_stock_qty numeric,p_stock_unit text,p_consumption_qty numeric,p_consumption_unit text,p_rate numeric,p_rate_basis text,p_bill_no text,p_bill_date date,p_gst_amount numeric,p_payment_status text,p_paid_amount numeric,p_cash_bank_ledger_id uuid,p_data_mode text);
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
 PERFORM set_config('rr.financial_request_context_test71',coalesce(v_previous_request_context,''),true);
 RETURN v_result || jsonb_build_object('request_id',p_request_id,'already_processed',false);
EXCEPTION WHEN others THEN
 PERFORM set_config('rr.financial_request_context_test71',coalesce(v_previous_request_context,''),true);
 RAISE;
END;$function$
;
