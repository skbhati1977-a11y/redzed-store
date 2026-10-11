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

  PERFORM pg_advisory_xact_lock(hashtextextended('SALARY_SOURCE_TEST71',0));
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
   IF v_prior_balance<>0 THEN RAISE EXCEPTION 'Nonzero opening salary requires approved due allocation mapping before finalization.';END IF;
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
CREATE OR REPLACE FUNCTION public.rr_salary_bulk_post_v782(p_cycle_type text, p_period_month date, p_window_start date, p_window_end date, p_data_mode text, p_owner_amount numeric, p_worker_ids uuid[], p_payment_date date, p_payment_mode text, p_voucher_no text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_preview jsonb;
  v_cycle text:=upper(trim(coalesce(p_cycle_type,'')));
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL'));
  v_payment_mode text:=upper(trim(coalesce(p_payment_mode,'')));
  v_voucher text:=nullif(trim(coalesce(p_voucher_no,'')),'');
  v_actor_name text;
  v_batch_id uuid;
  v_line_id uuid;
  v_due_id uuid;
  v_payment_id uuid;
  v_line record;
  v_period_month date:=date_trunc(
    'month',
    coalesce(p_period_month,p_payment_date)
  )::date;
  v_parent_batch_id uuid;
begin
 IF v_mode='TEST' THEN RAISE EXCEPTION 'Legacy TEST bulk salary writer retired; use protected canonical salary payment.';END IF;
  if not public.rr_salary_bulk_is_owner_v782() then
    raise exception 'Only OWNER can post bulk salary payment.';
  end if;

  if p_payment_date is null then
    raise exception 'Payment date required.';
  end if;

  if v_payment_mode not in(
    'CASH','BANK','UPI','CHEQUE','OTHER'
  ) then
    raise exception 'Valid payment mode required.';
  end if;

  if v_voucher is null then
    raise exception 'One bulk voucher/reference required.';
  end if;

  v_preview:=public.rr_salary_bulk_preview_v782(
    v_cycle,
    v_period_month,
    p_window_start,
    p_window_end,
    v_mode,
    p_owner_amount,
    p_worker_ids
  );

  if coalesce(
    (v_preview->>'owner_payment_amount')::numeric,
    0
  )<=0 then
    raise exception 'Owner payment amount must be greater than zero.';
  end if;

  select coalesce(
    nullif(trim(p.full_name),''),
    'OWNER'
  )
  into v_actor_name
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid()
  limit 1;

  v_parent_batch_id:=
    nullif(
      v_preview->>'parent_batch_id',
      ''
    )::uuid;

  insert into public.rr_salary_bulk_batches_v782(
    data_mode,
    cycle_type,
    payroll_category,
    period_month,
    earning_window_start,
    earning_window_end,
    payment_date,
    payment_mode,
    voucher_no,
    owner_payment_amount,
    eligible_total,
    liability_total,
    allocation_ratio,
    rounding_unit,
    worker_count,
    full_eligible_payment,
    parent_batch_id,
    status,
    remarks,
    created_by,
    created_by_name
  )
  values(
    v_mode,
    v_cycle,
    case
      when v_cycle like 'MONTHLY_%'
        then 'SALARIED'
      else 'PIECE_RATE'
    end,
    v_period_month,
    p_window_start,
    p_window_end,
    p_payment_date,
    v_payment_mode,
    v_voucher,
    (v_preview->>'owner_payment_amount')::numeric,
    (v_preview->>'eligible_total')::numeric,
    (v_preview->>'liability_total')::numeric,
    (v_preview->>'allocation_ratio')::numeric,
    (v_preview->>'rounding_unit')::numeric,
    jsonb_array_length(v_preview->'lines'),
    coalesce(
      (v_preview->>'full_eligible_payment')::boolean,
      false
    ),
    v_parent_batch_id,
    'POSTED',
    nullif(trim(coalesce(p_remarks,'')),''),
    auth.uid(),
    v_actor_name
  )
  returning id into v_batch_id;

  for v_line in
    select *
    from jsonb_to_recordset(v_preview->'lines') as x(
      worker_id uuid,
      worker_name text,
      worker_code text,
      department_code text,

      previous_outstanding numeric,
      monthly_salary numeric,
      earned_to_cutoff numeric,
      first_week_earning numeric,
      next_week_earning numeric,
      eligible_current_amount numeric,
      eligible_part_payment numeric,
      part_payment numeric,
      balance_after_part_payment numeric,
      final_payable numeric,
      final_payment numeric,
      new_outstanding numeric,

      allocation_eligible numeric,
      raw_allocation numeric,
      floor_allocation numeric,
      allocation_remainder numeric,
      allocated_amount numeric,

      payable_pcs numeric,
      missing_rate_rows integer,
      missing_cap_rows integer
    )
  loop
    insert into public.rr_salary_bulk_batch_lines_v782(
      batch_id,
      worker_id,
      worker_name,
      worker_code,
      department_code,
      previous_outstanding,
      monthly_salary,
      earned_to_cutoff,
      first_week_earning,
      next_week_earning,
      eligible_current_amount,
      eligible_part_payment,
      part_payment,
      balance_after_part_payment,
      final_payable,
      final_payment,
      new_outstanding,
      allocation_eligible,
      raw_allocation,
      floor_allocation,
      allocation_remainder,
      allocated_amount,
      payable_pcs,
      missing_rate_rows,
      missing_cap_rows
    )
    values(
      v_batch_id,
      v_line.worker_id,
      v_line.worker_name,
      v_line.worker_code,
      v_line.department_code,
      v_line.previous_outstanding,
      v_line.monthly_salary,
      v_line.earned_to_cutoff,
      v_line.first_week_earning,
      v_line.next_week_earning,
      v_line.eligible_current_amount,
      v_line.eligible_part_payment,
      v_line.part_payment,
      v_line.balance_after_part_payment,
      v_line.final_payable,
      v_line.final_payment,
      v_line.new_outstanding,
      v_line.allocation_eligible,
      v_line.raw_allocation,
      v_line.floor_allocation,
      v_line.allocation_remainder,
      v_line.allocated_amount,
      v_line.payable_pcs,
      v_line.missing_rate_rows,
      v_line.missing_cap_rows
    )
    returning id into v_line_id;

    -- PCS completed week becomes a full salary liability.
    if v_cycle in('PCS_WEEK_PART','PCS_WEEK_FINAL') then
      insert into public.rr_worker_salary_ledger_v781(
        data_mode,
        worker_id,
        worker_name,
        worker_code,
        department_code,
        payroll_category,
        source_module,
        source_key,
        period_month,
        entry_date,
        entry_type,
        amount,
        balance_effect,
        bulk_batch_id,
        bulk_line_id,
        earning_window_start,
        earning_window_end,
        reference_no,
        remarks,
        created_by,
        created_by_name
      )
      values(
        v_mode,
        v_line.worker_id,
        v_line.worker_name,
        v_line.worker_code,
        v_line.department_code,
        'PIECE_RATE',
        'PCS_WEEK_V782',
        concat(
          'PCS_WEEK_V782|',
          v_mode,
          '|',
          p_window_start,
          '|',
          p_window_end,
          '|',
          v_line.worker_id
        ),
        date_trunc('month',p_window_end)::date,
        p_window_end,
        'WEEKLY_PCS_DUE',
        round(
          case
            when v_cycle='PCS_WEEK_PART'
              then v_line.first_week_earning
            else v_line.next_week_earning
          end,
          2
        ),
        round(
          case
            when v_cycle='PCS_WEEK_PART'
              then v_line.first_week_earning
            else v_line.next_week_earning
          end,
          2
        ),
        v_batch_id,
        v_line_id,
        p_window_start,
        p_window_end,
        concat(
          'PCS-WEEK-',
          to_char(p_window_start,'YYYYMMDD'),
          '-',
          to_char(p_window_end,'YYYYMMDD')
        ),
        'Completed 7-day PCS salary Â· Actual Assignment Rate only',
        auth.uid(),
        v_actor_name
      )
      returning id into v_due_id;

      update public.rr_salary_bulk_batch_lines_v782
      set salary_due_ledger_entry_id=v_due_id
      where id=v_line_id;
    end if;

    insert into public.rr_worker_salary_ledger_v781(
      data_mode,
      worker_id,
      worker_name,
      worker_code,
      department_code,
      payroll_category,
      source_module,
      source_key,
      period_month,
      entry_date,
      entry_type,
      amount,
      balance_effect,
      payment_mode,
      reference_no,
      remarks,
      bulk_batch_id,
      bulk_line_id,
      earning_window_start,
      earning_window_end,
      created_by,
      created_by_name
    )
    values(
      v_mode,
      v_line.worker_id,
      v_line.worker_name,
      v_line.worker_code,
      v_line.department_code,
      case
        when v_cycle like 'MONTHLY_%'
          then 'SALARIED'
        else 'PIECE_RATE'
      end,
      'BULK_V782',
      concat(
        'BULK_V782|',
        v_batch_id,
        '|',
        v_line.worker_id
      ),
      v_period_month,
      p_payment_date,
      'BULK_PAYMENT',
      round(v_line.allocated_amount,2),
      -round(v_line.allocated_amount,2),
      v_payment_mode,
      v_voucher,
      nullif(trim(coalesce(p_remarks,'')),''),
      v_batch_id,
      v_line_id,
      p_window_start,
      p_window_end,
      auth.uid(),
      v_actor_name
    )
    returning id into v_payment_id;

    update public.rr_salary_bulk_batch_lines_v782
    set payment_ledger_entry_id=v_payment_id
    where id=v_line_id;
  end loop;

  -- Monthly final run status follows actual remaining balances.
  if v_cycle='MONTHLY_FINAL' then
    update public.rr_payroll_runs_v778 r
    set
      status=case
        when not exists(
          select 1
          from public.rr_payroll_run_lines_v778 l

          left join public.rr_salary_worker_balance_v782 b
            on b.data_mode=r.data_mode
           and b.worker_id=l.worker_id

          where l.payroll_run_id=r.id
            and greatest(
              coalesce(b.outstanding_amount,0),
              0
            )>0.005
        )
          then 'PAID'
        else 'PARTIALLY_PAID'
      end,

      paid_by=case
        when not exists(
          select 1
          from public.rr_payroll_run_lines_v778 l

          left join public.rr_salary_worker_balance_v782 b
            on b.data_mode=r.data_mode
           and b.worker_id=l.worker_id

          where l.payroll_run_id=r.id
            and greatest(
              coalesce(b.outstanding_amount,0),
              0
            )>0.005
        )
          then auth.uid()
        else null
      end,

      paid_at=case
        when not exists(
          select 1
          from public.rr_payroll_run_lines_v778 l

          left join public.rr_salary_worker_balance_v782 b
            on b.data_mode=r.data_mode
           and b.worker_id=l.worker_id

          where l.payroll_run_id=r.id
            and greatest(
              coalesce(b.outstanding_amount,0),
              0
            )>0.005
        )
          then now()
        else null
      end,

      payment_reference=v_voucher,
      updated_at=now()

    where r.period_month=v_period_month
      and r.data_mode=v_mode
      and r.status in(
        'APPROVED',
        'PARTIALLY_PAID',
        'PAID'
      );
  end if;

  return jsonb_build_object(
    'ok',true,
    'batch_id',v_batch_id,
    'cycle_type',v_cycle,
    'voucher_no',v_voucher,
    'owner_payment_amount',
      (v_preview->>'owner_payment_amount')::numeric,
    'worker_count',
      jsonb_array_length(v_preview->'lines'),
    'new_outstanding_total',
      (
        select coalesce(sum(new_outstanding),0)
        from public.rr_salary_bulk_batch_lines_v782
        where batch_id=v_batch_id
      )
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_salary_bulk_post_v782_2(p_cycle_type text, p_period_month date, p_window_start date, p_window_end date, p_data_mode text, p_owner_amount numeric, p_worker_ids uuid[], p_payment_date date, p_payment_mode text, p_voucher_no text, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cycle text:=upper(trim(coalesce(p_cycle_type,'')));
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL'));
  v_payment_mode text:=upper(trim(coalesce(p_payment_mode,'')));
  v_voucher text:=nullif(trim(coalesce(p_voucher_no,'')),'');
  v_preview jsonb;
  v_actor_name text;
  v_batch_id uuid;
  v_line_id uuid;
  v_due_id uuid;
  v_payment_id uuid;
  v_line record;
  v_period_month date;
  v_anchor_before date;
begin
 IF v_mode='TEST' THEN RAISE EXCEPTION 'Legacy TEST bulk salary writer retired; use protected canonical salary payment.';END IF;
  if v_cycle in('MONTHLY_PART','MONTHLY_FINAL') then
    return public.rr_salary_bulk_post_v782(
      v_cycle,
      p_period_month,
      p_window_start,
      p_window_end,
      v_mode,
      p_owner_amount,
      p_worker_ids,
      p_payment_date,
      v_payment_mode,
      v_voucher,
      p_remarks
    );
  end if;

  if not public.rr_salary_bulk_is_owner_v782() then
    raise exception 'Only OWNER can post bulk salary payment.';
  end if;

  if p_payment_date is null then
    raise exception 'Payment date required.';
  end if;

  if v_payment_mode not in(
    'CASH','BANK','UPI','CHEQUE','OTHER'
  ) then
    raise exception 'Valid payment mode required.';
  end if;

  if v_voucher is null then
    raise exception 'One bulk voucher/reference required.';
  end if;

  v_preview:=public.rr_salary_bulk_preview_v782_2(
    v_cycle,
    p_period_month,
    p_window_start,
    p_window_end,
    v_mode,
    p_owner_amount,
    p_worker_ids
  );

  if coalesce(
    (v_preview->>'owner_payment_amount')::numeric,
    0
  )<=0 then
    raise exception 'Owner payment amount must be greater than zero.';
  end if;

  select coalesce(
    nullif(trim(p.full_name),''),
    'OWNER'
  )
  into v_actor_name
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid()
  limit 1;

  select min(l.earning_window_start)
  into v_anchor_before
  from public.rr_worker_salary_ledger_v781 l
  where l.data_mode=v_mode
    and l.entry_type in('WEEKLY_PCS_DUE','PCS_WINDOW_DUE')
    and l.status='POSTED'
    and l.earning_window_start is not null;

  v_period_month:=date_trunc(
    'month',
    p_window_end
  )::date;

  insert into public.rr_salary_bulk_batches_v782(
    data_mode,
    cycle_type,
    payroll_category,
    period_month,
    earning_window_start,
    earning_window_end,
    payment_date,
    payment_mode,
    voucher_no,
    owner_payment_amount,
    eligible_total,
    liability_total,
    allocation_ratio,
    rounding_unit,
    worker_count,
    full_eligible_payment,
    status,
    remarks,
    created_by,
    created_by_name
  )
  values(
    v_mode,
    v_cycle,
    'PIECE_RATE',
    v_period_month,
    p_window_start,
    p_window_end,
    p_payment_date,
    v_payment_mode,
    v_voucher,
    (v_preview->>'owner_payment_amount')::numeric,
    (v_preview->>'eligible_total')::numeric,
    (v_preview->>'liability_total')::numeric,
    (v_preview->>'allocation_ratio')::numeric,
    (v_preview->>'rounding_unit')::numeric,
    jsonb_array_length(v_preview->'lines'),
    coalesce(
      (v_preview->>'full_eligible_payment')::boolean,
      false
    ),
    'POSTED',
    nullif(trim(coalesce(p_remarks,'')),''),
    auth.uid(),
    v_actor_name
  )
  returning id into v_batch_id;

  for v_line in
    select *
    from jsonb_to_recordset(v_preview->'lines') as x(
      worker_id uuid,
      worker_name text,
      worker_code text,
      department_code text,

      payment_selected boolean,
      previous_outstanding numeric,
      monthly_salary numeric,
      earned_to_cutoff numeric,

      first_week_earning numeric,
      next_week_earning numeric,
      pcs_window_days integer,
      pcs_window_earning numeric,

      eligible_current_amount numeric,
      eligible_part_payment numeric,
      part_payment numeric,
      balance_after_part_payment numeric,
      final_payable numeric,
      final_payment numeric,
      new_outstanding numeric,

      allocation_eligible numeric,
      raw_allocation numeric,
      floor_allocation numeric,
      allocation_remainder numeric,
      allocated_amount numeric,

      payable_pcs numeric,
      missing_rate_rows integer,
      missing_cap_rows integer
    )
  loop
    insert into public.rr_salary_bulk_batch_lines_v782(
      batch_id,
      worker_id,
      worker_name,
      worker_code,
      department_code,
      payment_selected,
      previous_outstanding,
      monthly_salary,
      earned_to_cutoff,
      first_week_earning,
      next_week_earning,
      pcs_window_days,
      pcs_window_earning,
      eligible_current_amount,
      eligible_part_payment,
      part_payment,
      balance_after_part_payment,
      final_payable,
      final_payment,
      new_outstanding,
      allocation_eligible,
      raw_allocation,
      floor_allocation,
      allocation_remainder,
      allocated_amount,
      payable_pcs,
      missing_rate_rows,
      missing_cap_rows
    )
    values(
      v_batch_id,
      v_line.worker_id,
      v_line.worker_name,
      v_line.worker_code,
      v_line.department_code,
      v_line.payment_selected,
      v_line.previous_outstanding,
      0,
      0,
      v_line.first_week_earning,
      v_line.next_week_earning,
      v_line.pcs_window_days,
      v_line.pcs_window_earning,
      v_line.eligible_current_amount,
      v_line.eligible_part_payment,
      v_line.part_payment,
      v_line.balance_after_part_payment,
      v_line.final_payable,
      v_line.final_payment,
      v_line.new_outstanding,
      v_line.allocation_eligible,
      v_line.raw_allocation,
      v_line.floor_allocation,
      v_line.allocation_remainder,
      v_line.allocated_amount,
      v_line.payable_pcs,
      v_line.missing_rate_rows,
      v_line.missing_cap_rows
    )
    returning id into v_line_id;

    -- Salary due is posted for every worker with completed-window work,
    -- even when that worker was not selected for payment.
    insert into public.rr_worker_salary_ledger_v781(
      data_mode,
      worker_id,
      worker_name,
      worker_code,
      department_code,
      payroll_category,
      source_module,
      source_key,
      period_month,
      entry_date,
      entry_type,
      amount,
      balance_effect,
      bulk_batch_id,
      bulk_line_id,
      earning_window_start,
      earning_window_end,
      reference_no,
      remarks,
      created_by,
      created_by_name
    )
    values(
      v_mode,
      v_line.worker_id,
      v_line.worker_name,
      v_line.worker_code,
      v_line.department_code,
      'PIECE_RATE',
      'PCS_WINDOW_V782_2',
      concat(
        'PCS_WINDOW_V782_2|',
        v_mode,
        '|',
        p_window_start,
        '|',
        p_window_end,
        '|',
        v_line.worker_id
      ),
      v_period_month,
      p_window_end,
      'PCS_WINDOW_DUE',
      round(v_line.pcs_window_earning,2),
      round(v_line.pcs_window_earning,2),
      v_batch_id,
      v_line_id,
      p_window_start,
      p_window_end,
      concat(
        'PCS-',
        v_line.pcs_window_days,
        'D-',
        to_char(p_window_start,'YYYYMMDD'),
        '-',
        to_char(p_window_end,'YYYYMMDD')
      ),
      'Completed PCS work window Â· Exact Assignment Actual Rate only',
      auth.uid(),
      v_actor_name
    )
    returning id into v_due_id;

    update public.rr_salary_bulk_batch_lines_v782
    set salary_due_ledger_entry_id=v_due_id
    where id=v_line_id;

    if coalesce(v_line.allocated_amount,0)>0 then
      insert into public.rr_worker_salary_ledger_v781(
        data_mode,
        worker_id,
        worker_name,
        worker_code,
        department_code,
        payroll_category,
        source_module,
        source_key,
        period_month,
        entry_date,
        entry_type,
        amount,
        balance_effect,
        payment_mode,
        reference_no,
        remarks,
        bulk_batch_id,
        bulk_line_id,
        earning_window_start,
        earning_window_end,
        created_by,
        created_by_name
      )
      values(
        v_mode,
        v_line.worker_id,
        v_line.worker_name,
        v_line.worker_code,
        v_line.department_code,
        'PIECE_RATE',
        'BULK_V782_2',
        concat(
          'BULK_V782_2|',
          v_batch_id,
          '|',
          v_line.worker_id
        ),
        v_period_month,
        p_payment_date,
        'BULK_PAYMENT',
        round(v_line.allocated_amount,2),
        -round(v_line.allocated_amount,2),
        v_payment_mode,
        v_voucher,
        nullif(trim(coalesce(p_remarks,'')),''),
        v_batch_id,
        v_line_id,
        p_window_start,
        p_window_end,
        auth.uid(),
        v_actor_name
      )
      returning id into v_payment_id;

      update public.rr_salary_bulk_batch_lines_v782
      set payment_ledger_entry_id=v_payment_id
      where id=v_line_id;
    end if;
  end loop;

  if v_anchor_before is null then
    update public.rr_salary_bulk_rules_v782
    set
      pcs_week_anchor_date=p_window_start,
      pcs_anchor_locked_by_batch_id=v_batch_id,
      pcs_anchor_locked_at=now(),
      updated_by=auth.uid(),
      updated_at=now()
    where data_mode=v_mode;
  end if;

  return jsonb_build_object(
    'ok',true,
    'batch_id',v_batch_id,
    'cycle_type',v_cycle,
    'window_start',p_window_start,
    'window_end',p_window_end,
    'window_days',
      (v_preview->>'window_days')::integer,
    'voucher_no',v_voucher,
    'owner_payment_amount',
      (v_preview->>'owner_payment_amount')::numeric,
    'worker_count',
      jsonb_array_length(v_preview->'lines'),
    'anchor_locked_now',
      v_anchor_before is null,
    'expected_next_start',
      p_window_end+1,
    'new_outstanding_total',
      (
        select coalesce(sum(new_outstanding),0)
        from public.rr_salary_bulk_batch_lines_v782
        where batch_id=v_batch_id
      )
  );
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
 PERFORM public.rr_financial_request_assert_test71(v_mode,ARRAY['rr_salary_payment_post_v786','rr_salary_payment_post_v785']);

  if not public.rr_worker_salary_can_pay_v781() then raise exception 'Salary payment permission required.'; end if;
  if p_payment_date is null then raise exception 'Payment Date required.'; end if;
  if v_paymode not in('CASH','BANK','UPI','CHEQUE','OTHER') then raise exception 'Valid Payment Mode required.'; end if;
  v_prefix:=case when v_category='PIECE_RATE' then 'PCSL' when v_category='SALARIED' then 'MSL' end;
  if v_prefix is null then raise exception 'Payroll Category must be PIECE_RATE or SALARIED.'; end if;

  IF v_mode='TEST' THEN PERFORM pg_advisory_xact_lock(hashtextextended('SALARY_SOURCE_TEST71',0));END IF;
  perform pg_advisory_xact_lock(hashtextextended(concat('SALARY_V786|',v_mode,'|',v_category),0));
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