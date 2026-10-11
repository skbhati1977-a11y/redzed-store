CREATE OR REPLACE FUNCTION public.rr_salary_earned_preview_test71(p_worker_id uuid,p_cutoff_date date)
RETURNS TABLE(worker_id uuid,worker_name text,worker_code text,department_code text,monthly_salary numeric,earned_to_cutoff numeric,eligibility_status text,eligibility_reason text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.rr_worker_salary_can_view_v781() THEN RAISE EXCEPTION 'Salary view permission required.' USING ERRCODE='42501';END IF;
 BEGIN
  RETURN QUERY SELECT e.worker_id,e.worker_name,e.worker_code,e.department_code,e.monthly_salary,e.earned_to_cutoff,'ELIGIBLE'::text,NULL::text FROM public.rr_salary_monthly_earned_v782(p_worker_id,p_cutoff_date,'TEST') e;
 EXCEPTION WHEN others THEN
  IF sqlerrm NOT LIKE 'Attendance incomplete:%' AND sqlerrm NOT LIKE 'Salary contract changes within month%' THEN RAISE;END IF;
  RETURN QUERY SELECT w.worker_id,w.worker_name,w.worker_code,w.department_code,p.monthly_salary,NULL::numeric,
   CASE WHEN sqlerrm LIKE 'Attendance incomplete:%' THEN 'WAITING_FOR_ATTENDANCE' ELSE 'CONTRACT_REVIEW_REQUIRED' END,sqlerrm
   FROM public.rr_worker_directory_unified_v1 w
   CROSS JOIN LATERAL public.rr_active_payroll_profile_v778_2(p_worker_id,least(p_cutoff_date,(date_trunc('month',p_cutoff_date)+interval '1 month'-interval '1 day')::date),'TEST') p
   WHERE w.worker_id=p_worker_id;
 END;
END;$$;
REVOKE ALL ON FUNCTION public.rr_salary_earned_preview_test71(uuid,date) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_salary_current_board_v785(p_payroll_category text, p_period_start date, p_period_end date, p_data_mode text)
 RETURNS TABLE(worker_id uuid, worker_name text, worker_code text, department_code text, worker_status text, previous_outstanding numeric, current_period_payable numeric, unaccrued_current_amount numeric, final_total_payable numeric, current_source text, total_advance_balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_category text:=upper(trim(coalesce(p_payroll_category,'')));
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL'));
  v_start date:=coalesce(p_period_start,current_date);
  v_end date:=coalesce(p_period_end,v_start);
  v_month date:=date_trunc('month',v_start)::date;
begin
  if not public.rr_worker_salary_can_view_v781() then raise exception 'Salary payment view permission required.'; end if;
  if v_category not in('PIECE_RATE','SALARIED') then raise exception 'Invalid Salary Module.'; end if;
  if v_mode not in('TEST','REAL') then raise exception 'Invalid Data Mode.'; end if;
  if v_end<v_start then raise exception 'Period End cannot be before Period Start.'; end if;
  if v_end>(now() at time zone 'Asia/Kolkata')::date then raise exception 'Future period date is not allowed.'; end if;

  if v_category='PIECE_RATE' then
    return query
    with w as(
      select x.worker_id,max(x.worker_name) worker_name,max(x.worker_code) worker_code,max(x.department_code) department_code,
             sum(x.salary_amount)::numeric(16,2) current_amount
      from public.rr_salary_pcs_unpaid_work_v785(v_start,v_end,v_mode,null) x
      group by x.worker_id
    )
    select
      w.worker_id,w.worker_name,w.worker_code,w.department_code,'ACTIVE'::text,
      greatest(coalesce(b.outstanding_amount,0),0)::numeric(16,2),
      round(w.current_amount,2)::numeric(16,2),
      round(w.current_amount,2)::numeric(16,2),
      round(greatest(coalesce(b.outstanding_amount,0),0)+w.current_amount,2)::numeric(16,2),
      'PCS_UNPAID_WORK'::text,
      coalesce(a.total_advance_balance,0)::numeric(16,2)
    from w
    left join public.rr_salary_worker_balance_v782 b on b.data_mode=v_mode and b.worker_id=w.worker_id
    left join public.rr_worker_advance_balance_v785 a on a.data_mode=v_mode and a.worker_id=w.worker_id
    where w.current_amount>0;
    return;
  end if;

  if date_trunc('month',v_end)::date<>v_month then raise exception 'Monthly period must remain inside one month.'; end if;

  IF v_mode='TEST' THEN
  return query
  with profiles as(
    select distinct on(p.worker_id) p.worker_id,p.worker_name,p.worker_code,p.department_code
    from public.rr_worker_payroll_board_v777_3 p
    where upper(coalesce(p.data_mode,'TEST'))=v_mode
      and upper(coalesce(p.worker_category,''))='SALARIED'
      and coalesce(p.effective_from,v_end)<=v_end
      and coalesce(p.effective_to,v_end)>=v_start
    order by p.worker_id,p.effective_from desc nulls last
  ),
  target as(
    select p.worker_id,p.worker_name,p.worker_code,p.department_code,
      e.earned_to_cutoff::numeric(16,2) target_amount,
      case when e.eligibility_status='ELIGIBLE' then 'MONTHLY_EARNED_CANONICAL_TO_CUTOFF' else e.eligibility_status end::text current_source
    from profiles p
    left join lateral public.rr_salary_earned_preview_test71(p.worker_id,v_end) e on true
  ),
  accrued as(
    select l.worker_id,coalesce(sum(l.balance_effect),0)::numeric(16,2) amount
    from public.rr_worker_salary_ledger_v781 l
    where l.data_mode=v_mode and l.payroll_category='SALARIED' and l.period_month=v_month and l.status='POSTED'
      and l.entry_type in('MONTHLY_SALARY_DUE','MONTHLY_FINAL_ADJUSTMENT')
    group by l.worker_id
  ),
  paid_v785 as(
    select x.worker_id,coalesce(sum(x.current_period_payment),0)::numeric(16,2) amount
    from public.rr_salary_payment_batch_lines_v785 x
    join public.rr_salary_payment_batches_v785 b on b.id=x.batch_id
    where b.data_mode=v_mode and b.payroll_category='SALARIED' and b.period_month=v_month and b.status='POSTED'
    group by x.worker_id
  ),
  paid_v782 as(
    select x.worker_id,coalesce(sum(greatest(x.allocated_amount-least(x.allocated_amount,x.previous_outstanding),0)),0)::numeric(16,2) amount
    from public.rr_salary_bulk_batch_lines_v782 x
    join public.rr_salary_bulk_batches_v782 b on b.id=x.batch_id
    where b.data_mode=v_mode and b.payroll_category='SALARIED' and b.period_month=v_month and b.status='POSTED'
    group by x.worker_id
  ),
  calc as(
    select t.*,
      greatest(coalesce(a.amount,0),0)::numeric(16,2) accrued_amount,
      greatest(coalesce(p5.amount,0)+coalesce(p2.amount,0),0)::numeric(16,2) paid_amount,
      greatest(coalesce(sb.outstanding_amount,0),0)::numeric(16,2) ledger_outstanding,
      coalesce(ab.total_advance_balance,0)::numeric(16,2) advance_balance
    from target t
    left join accrued a on a.worker_id=t.worker_id
    left join paid_v785 p5 on p5.worker_id=t.worker_id
    left join paid_v782 p2 on p2.worker_id=t.worker_id
    left join public.rr_salary_worker_balance_v782 sb on sb.data_mode=v_mode and sb.worker_id=t.worker_id
    left join public.rr_worker_advance_balance_v785 ab on ab.data_mode=v_mode and ab.worker_id=t.worker_id
  )
  select
    c.worker_id,c.worker_name,c.worker_code,c.department_code,'ACTIVE'::text,
    greatest(c.ledger_outstanding-greatest(c.accrued_amount-c.paid_amount,0),0)::numeric(16,2) previous_outstanding,
    case when c.target_amount is null then null else greatest(c.target_amount-c.paid_amount,0) end::numeric(16,2) current_period_payable,
    case when c.target_amount is null then null else greatest(c.target_amount-c.accrued_amount,0) end::numeric(16,2) unaccrued_current_amount,
    case when c.target_amount is null then null else round(greatest(c.ledger_outstanding-greatest(c.accrued_amount-c.paid_amount,0),0)+greatest(c.target_amount-c.paid_amount,0),2) end::numeric(16,2) final_total_payable,
    c.current_source,
    c.advance_balance
  from calc c
  where (c.target_amount is null or greatest(c.target_amount-c.paid_amount,0)>0)
 and not exists(select 1 from public.rr_worker_salary_ledger_v781 z where z.worker_id=c.worker_id and z.data_mode='TEST' and z.period_month=v_month and z.source_module='MONTHLY_V779_TEST71' and z.status='POSTED' and z.entry_type='MONTHLY_SALARY_DUE');
  RETURN;
  END IF;

  return query
  with profiles as(
    select distinct on(p.worker_id) p.worker_id,p.worker_name,p.worker_code,p.department_code
    from public.rr_worker_payroll_board_v777_3 p
    where upper(coalesce(p.data_mode,'TEST'))=v_mode
      and upper(coalesce(p.worker_category,''))='SALARIED'
      and coalesce(p.effective_from,v_end)<=v_end
      and coalesce(p.effective_to,v_end)>=v_start
    order by p.worker_id,p.effective_from desc nulls last
  ),
  approved_run as(
    select r.* from public.rr_payroll_runs_v778 r
    where r.data_mode=v_mode and r.period_month=v_month
      and r.status in('APPROVED','PARTIALLY_PAID','PAID')
    order by r.updated_at desc limit 1
  ),
  target as(
    select p.worker_id,p.worker_name,p.worker_code,p.department_code,
      case when ar.id is not null and v_end>=ar.period_end then coalesce(l.net_pay,0) else coalesce(e.earned_to_cutoff,0) end::numeric(16,2) target_amount,
      case when ar.id is not null and v_end>=ar.period_end then 'MONTHLY_APPROVED_NET_PAY' else 'MONTHLY_EARNED_TO_CUTOFF' end::text current_source
    from profiles p
    left join approved_run ar on true
    left join public.rr_payroll_run_lines_v778 l on l.payroll_run_id=ar.id and l.worker_id=p.worker_id
    left join lateral public.rr_salary_monthly_earned_v782(p.worker_id,v_end,v_mode) e on true
  ),
  accrued as(
    select l.worker_id,coalesce(sum(l.balance_effect),0)::numeric(16,2) amount
    from public.rr_worker_salary_ledger_v781 l
    where l.data_mode=v_mode and l.payroll_category='SALARIED' and l.period_month=v_month and l.status='POSTED'
      and l.entry_type in('MONTHLY_SALARY_DUE','MONTHLY_FINAL_ADJUSTMENT')
    group by l.worker_id
  ),
  paid_v785 as(
    select x.worker_id,coalesce(sum(x.current_period_payment),0)::numeric(16,2) amount
    from public.rr_salary_payment_batch_lines_v785 x
    join public.rr_salary_payment_batches_v785 b on b.id=x.batch_id
    where b.data_mode=v_mode and b.payroll_category='SALARIED' and b.period_month=v_month and b.status='POSTED'
    group by x.worker_id
  ),
  paid_v782 as(
    select x.worker_id,coalesce(sum(greatest(x.allocated_amount-least(x.allocated_amount,x.previous_outstanding),0)),0)::numeric(16,2) amount
    from public.rr_salary_bulk_batch_lines_v782 x
    join public.rr_salary_bulk_batches_v782 b on b.id=x.batch_id
    where b.data_mode=v_mode and b.payroll_category='SALARIED' and b.period_month=v_month and b.status='POSTED'
    group by x.worker_id
  ),
  calc as(
    select t.*,
      greatest(coalesce(a.amount,0),0)::numeric(16,2) accrued_amount,
      greatest(coalesce(p5.amount,0)+coalesce(p2.amount,0),0)::numeric(16,2) paid_amount,
      greatest(coalesce(sb.outstanding_amount,0),0)::numeric(16,2) ledger_outstanding,
      coalesce(ab.total_advance_balance,0)::numeric(16,2) advance_balance
    from target t
    left join accrued a on a.worker_id=t.worker_id
    left join paid_v785 p5 on p5.worker_id=t.worker_id
    left join paid_v782 p2 on p2.worker_id=t.worker_id
    left join public.rr_salary_worker_balance_v782 sb on sb.data_mode=v_mode and sb.worker_id=t.worker_id
    left join public.rr_worker_advance_balance_v785 ab on ab.data_mode=v_mode and ab.worker_id=t.worker_id
  )
  select
    c.worker_id,c.worker_name,c.worker_code,c.department_code,'ACTIVE'::text,
    greatest(c.ledger_outstanding-greatest(c.accrued_amount-c.paid_amount,0),0)::numeric(16,2) previous_outstanding,
    greatest(c.target_amount-c.paid_amount,0)::numeric(16,2) current_period_payable,
    greatest(c.target_amount-c.accrued_amount,0)::numeric(16,2) unaccrued_current_amount,
    round(greatest(c.ledger_outstanding-greatest(c.accrued_amount-c.paid_amount,0),0)+greatest(c.target_amount-c.paid_amount,0),2)::numeric(16,2) final_total_payable,
    c.current_source,
    c.advance_balance
  from calc c
  where greatest(c.target_amount-c.paid_amount,0)>0;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_salary_payment_preview_v785(p_payroll_category text, p_period_start date, p_period_end date, p_data_mode text, p_payment_method text, p_payment_scope text, p_bulk_amount numeric DEFAULT 0, p_worker_ids uuid[] DEFAULT NULL::uuid[], p_worker_amounts jsonb DEFAULT '[]'::jsonb)
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
  v_owner numeric(16,2):=round(greatest(coalesce(p_bulk_amount,0),0),2);
  v_rounding numeric(14,2):=100;
  v_selected_scope numeric(16,2):=0;
  v_ratio numeric(18,10):=0;
  v_floor_total numeric(16,2):=0;
  v_remaining numeric(16,2):=0;
  v_worker uuid;
begin
 IF v_mode='TEST' THEN RETURN public.rr_salary_payment_preview_v786(p_payroll_category,p_period_start,p_period_end,p_data_mode,p_payment_method,p_payment_scope,p_bulk_amount,p_worker_ids,p_worker_amounts);END IF;

  if not public.rr_worker_salary_can_view_v781() then raise exception 'Salary payment view permission required.'; end if;
  if v_method not in('PARTIAL_RATIO','WORKER_LEDGER_WISE','FULL_PAYMENT') then raise exception 'Invalid Payment Method.'; end if;
  if v_scope not in('OUTSTANDING_ONLY','CURRENT_PERIOD_ONLY','FULL_AND_FINAL') then raise exception 'Invalid Payment Scope.'; end if;

  create temporary table if not exists rr_salary_preview_tmp_v785(
    worker_id uuid primary key,worker_name text,worker_code text,department_code text,worker_status text,
    payment_selected boolean,previous_outstanding numeric(16,2),current_period_payable numeric(16,2),
    unaccrued_current_amount numeric(16,2),final_total_payable numeric(16,2),scope_payable numeric(16,2),
    raw_allocation numeric(16,6),floor_allocation numeric(16,2),allocation_remainder numeric(16,6),
    amount_paid numeric(16,2),outstanding_payment numeric(16,2),current_period_payment numeric(16,2),
    new_previous_outstanding numeric(16,2),new_current_outstanding numeric(16,2),new_total_outstanding numeric(16,2),current_source text
  ) on commit drop;
  truncate rr_salary_preview_tmp_v785;

  -- Current-period workers.
  insert into rr_salary_preview_tmp_v785(
    worker_id,worker_name,worker_code,department_code,worker_status,payment_selected,
    previous_outstanding,current_period_payable,unaccrued_current_amount,final_total_payable,scope_payable,
    new_previous_outstanding,new_current_outstanding,new_total_outstanding,current_source
  )
  select c.worker_id,c.worker_name,c.worker_code,c.department_code,c.worker_status,
    (p_worker_ids is null or c.worker_id=any(p_worker_ids)),
    c.previous_outstanding,c.current_period_payable,c.unaccrued_current_amount,c.final_total_payable,
    case when v_scope='OUTSTANDING_ONLY' then c.previous_outstanding
         when v_scope='CURRENT_PERIOD_ONLY' then c.current_period_payable
         else c.final_total_payable end,
    c.previous_outstanding,c.current_period_payable,c.final_total_payable,c.current_source
  from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c
  where c.final_total_payable>0
    and coalesce(c.total_advance_balance,0)<=0.005
    and (
      (v_scope='CURRENT_PERIOD_ONLY' and c.current_period_payable>0)
      or
      (v_scope='OUTSTANDING_ONLY' and c.previous_outstanding>0)
      or
      (v_scope='FULL_AND_FINAL' and c.final_total_payable>0)
    );

  -- Ledger-only outstanding workers were previously hidden because
  -- rr_salary_current_board_v785 returns PCS/monthly rows only when
  -- current-period payable is positive. OUTSTANDING_ONLY and
  -- FULL_AND_FINAL must also allow an existing positive salary ledger
  -- balance even when current-period payable is zero.
  if v_scope in('OUTSTANDING_ONLY','FULL_AND_FINAL') then
    insert into rr_salary_preview_tmp_v785(
      worker_id,worker_name,worker_code,department_code,worker_status,payment_selected,
      previous_outstanding,current_period_payable,unaccrued_current_amount,final_total_payable,scope_payable,
      new_previous_outstanding,new_current_outstanding,new_total_outstanding,current_source
    )
    select
      b.worker_id,
      coalesce(nullif(trim(b.worker_name),''),nullif(trim(m.worker_name),''),b.worker_id::text),
      coalesce(nullif(trim(b.worker_code),''),nullif(trim(m.worker_code),'')),
      coalesce(nullif(trim(b.department_code),''),nullif(trim(m.department_code),'')),
      'ACTIVE'::text,
      (p_worker_ids is null or b.worker_id=any(p_worker_ids)),
      greatest(coalesce(b.outstanding_amount,0),0)::numeric(16,2),
      0::numeric(16,2),
      0::numeric(16,2),
      greatest(coalesce(b.outstanding_amount,0),0)::numeric(16,2),
      greatest(coalesce(b.outstanding_amount,0),0)::numeric(16,2),
      greatest(coalesce(b.outstanding_amount,0),0)::numeric(16,2),
      0::numeric(16,2),
      greatest(coalesce(b.outstanding_amount,0),0)::numeric(16,2),
      'LEDGER_OUTSTANDING'::text
    from public.rr_salary_worker_balance_v782 b
    join lateral(
      select
        l.worker_name,
        l.worker_code,
        l.department_code,
        upper(coalesce(l.payroll_category,'')) as payroll_category
      from public.rr_worker_salary_ledger_v781 l
      where l.data_mode=v_mode
        and l.worker_id=b.worker_id
        and l.status='POSTED'
      order by l.created_at desc
      limit 1
    ) m on true
    left join public.rr_worker_advance_balance_v785 a
      on a.data_mode=v_mode
     and a.worker_id=b.worker_id
    where b.data_mode=v_mode
      and greatest(coalesce(b.outstanding_amount,0),0)>0
      and m.payroll_category=v_category
      and coalesce(a.total_advance_balance,0)<=0.005
      and not exists(
        select 1
        from rr_salary_preview_tmp_v785 t
        where t.worker_id=b.worker_id
      );
  end if;

  delete from rr_salary_preview_tmp_v785 where scope_payable<=0;
  if not exists(select 1 from rr_salary_preview_tmp_v785) then
    raise exception 'No eligible worker for selected scope. OLD OUTSTANDING requires previous outstanding; CURRENT WORK requires current payable; FINAL TOTAL accepts either. Advance workers are excluded.';
  end if;

  select coalesce(sum(scope_payable) filter(where payment_selected),0) into v_selected_scope from rr_salary_preview_tmp_v785;
  if v_selected_scope<=0 then raise exception 'No selected worker has a positive payable amount for this scope.'; end if;

  -- All allocation columns must be non-null for every batch line.
  update rr_salary_preview_tmp_v785
  set raw_allocation=0,
      floor_allocation=0,
      allocation_remainder=0,
      amount_paid=0
  where worker_id is not null;

  if v_method='PARTIAL_RATIO' then
    if v_owner<=0 then
      null;
    elsif v_owner>v_selected_scope+0.005 then
      raise exception 'Bulk Amount Payment exceeds Selected Workers Payable.';
    elsif mod(v_owner,v_rounding)<>0 then
      raise exception 'Ratio Division Payment amount must be a multiple of â‚¹100.';
    else
      v_ratio:=v_owner/v_selected_scope;

      update rr_salary_preview_tmp_v785
      set raw_allocation=round(scope_payable*v_ratio,6),
          floor_allocation=floor(scope_payable*v_ratio/v_rounding)*v_rounding
      where payment_selected;

      update rr_salary_preview_tmp_v785
      set allocation_remainder=raw_allocation-floor_allocation,
          amount_paid=floor_allocation
      where payment_selected;

      select coalesce(sum(amount_paid),0)
      into v_floor_total
      from rr_salary_preview_tmp_v785
      where payment_selected;

      v_remaining:=round(v_owner-v_floor_total,2);

      while v_remaining>=v_rounding-0.005 loop
        select t.worker_id
        into v_worker
        from rr_salary_preview_tmp_v785 t
        where t.payment_selected
          and t.amount_paid+v_rounding<=t.scope_payable+0.005
        order by
          t.allocation_remainder desc,
          t.scope_payable desc,
          t.worker_id
        limit 1;

        if v_worker is null then
          raise exception 'â‚¹100 ratio cannot exactly match this Bulk Amount.';
        end if;

        update rr_salary_preview_tmp_v785
        set amount_paid=amount_paid+v_rounding,
            floor_allocation=amount_paid+v_rounding,
            allocation_remainder=-1
        where worker_id=v_worker;

        v_remaining:=round(v_remaining-v_rounding,2);
        v_worker:=null;
      end loop;

      if abs(v_remaining)>0.005 then
        raise exception 'Unallocated remainder. Use a compatible â‚¹100 amount.';
      end if;
    end if;
  end if;

  if v_method='FULL_PAYMENT' then
    v_ratio:=1;

    update rr_salary_preview_tmp_v785
    set raw_allocation=scope_payable,
        floor_allocation=floor(scope_payable/v_rounding)*v_rounding,
        allocation_remainder=scope_payable-(floor(scope_payable/v_rounding)*v_rounding),
        amount_paid=floor(scope_payable/v_rounding)*v_rounding
    where payment_selected;

    select coalesce(sum(amount_paid),0)
    into v_owner
    from rr_salary_preview_tmp_v785
    where payment_selected;
  end if;

  if v_method='WORKER_LEDGER_WISE' then
    update rr_salary_preview_tmp_v785 t
    set amount_paid=round(greatest(coalesce(x.amount_paid,0),0),2)
    from jsonb_to_recordset(coalesce(p_worker_amounts,'[]'::jsonb))
      x(worker_id uuid,amount_paid numeric)
    where t.worker_id=x.worker_id
      and t.payment_selected;

    if exists(
      select 1
      from rr_salary_preview_tmp_v785
      where amount_paid>scope_payable+0.005
    ) then
      raise exception 'Worker Amount Paid cannot exceed Selected Scope Payable.';
    end if;

    if exists(
      select 1
      from rr_salary_preview_tmp_v785
      where payment_selected
        and amount_paid>0
        and mod(amount_paid,v_rounding)<>0
    ) then
      raise exception 'Selected Worker Payment amount must be a multiple of â‚¹100.';
    end if;

    update rr_salary_preview_tmp_v785
    set raw_allocation=amount_paid,
        floor_allocation=amount_paid,
        allocation_remainder=0
    where payment_selected;

    select coalesce(sum(amount_paid),0)
    into v_owner
    from rr_salary_preview_tmp_v785
    where payment_selected;
  end if;

  update rr_salary_preview_tmp_v785
  set outstanding_payment=case when not payment_selected or v_scope='CURRENT_PERIOD_ONLY' then 0 else least(amount_paid,previous_outstanding) end,
      current_period_payment=case when not payment_selected or v_scope='OUTSTANDING_ONLY' then 0
        when v_scope='CURRENT_PERIOD_ONLY' then least(amount_paid,current_period_payable)
        else greatest(amount_paid-least(amount_paid,previous_outstanding),0) end
  where worker_id is not null;

  update rr_salary_preview_tmp_v785
  set new_previous_outstanding=greatest(previous_outstanding-outstanding_payment,0),
      new_current_outstanding=greatest(current_period_payable-current_period_payment,0),
      new_total_outstanding=greatest(previous_outstanding-outstanding_payment,0)+greatest(current_period_payable-current_period_payment,0)
  where worker_id is not null;

  return jsonb_build_object(
    'ok',true,'data_mode',v_mode,'payroll_category',v_category,'payment_method',v_method,'payment_scope',v_scope,
    'period_start',v_start,'period_end',v_end,'period_month',v_month,
    'eligible_worker_count',(select count(*) from rr_salary_preview_tmp_v785),
    'selected_worker_count',(select count(*) from rr_salary_preview_tmp_v785 where payment_selected),
    'advance_worker_count',(select count(*) from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c where c.final_total_payable>0 and c.total_advance_balance>0.005),
    'advance_worker_amount',(select round(coalesce(sum(c.total_advance_balance),0),2) from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c where c.final_total_payable>0 and c.total_advance_balance>0.005),
    'total_previous_outstanding',(select round(coalesce(sum(previous_outstanding),0),2) from rr_salary_preview_tmp_v785),
    'total_current_period_payable',(select round(coalesce(sum(current_period_payable),0),2) from rr_salary_preview_tmp_v785),
    'total_final_payable',(select round(coalesce(sum(final_total_payable),0),2) from rr_salary_preview_tmp_v785),
    'selected_scope_payable',round(v_selected_scope,2),'bulk_amount_payment',round(v_owner,2),
    'total_outstanding_payment',(select round(coalesce(sum(outstanding_payment),0),2) from rr_salary_preview_tmp_v785),
    'total_current_period_payment',(select round(coalesce(sum(current_period_payment),0),2) from rr_salary_preview_tmp_v785),
    'total_new_outstanding',(select round(coalesce(sum(new_total_outstanding),0),2) from rr_salary_preview_tmp_v785),
    'allocation_ratio',round(v_ratio,10),'rounding_unit',v_rounding,
    'advance_workers',coalesce((select jsonb_agg(to_jsonb(c) order by c.total_advance_balance desc,c.worker_name)
      from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c
      where c.final_total_payable>0 and c.total_advance_balance>0.005),'[]'::jsonb),
    'lines',coalesce((select jsonb_agg(to_jsonb(t) order by t.final_total_payable desc,t.worker_name,t.worker_id) from rr_salary_preview_tmp_v785 t),'[]'::jsonb)
  );
end;
$function$
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

 IF v_mode='TEST' THEN RETURN public.rr_salary_payment_post_v786(p_payroll_category,p_period_start,p_period_end,p_data_mode,p_payment_method,p_payment_scope,p_bulk_amount,p_worker_ids,p_worker_amounts,p_payment_date,p_payment_mode,p_voucher_no,p_remarks);END IF;
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
 PERFORM public.rr_financial_request_assert_test71(v_mode,ARRAY['rr_salary_payment_post_v786','rr_salary_payment_post_v785']);

  if not public.rr_worker_salary_can_pay_v781() then raise exception 'Salary payment permission required.'; end if;
  if p_payment_date is null then raise exception 'Payment Date required.'; end if;
  if v_paymode not in('CASH','BANK','UPI','CHEQUE','OTHER') then raise exception 'Valid Payment Mode required.'; end if;
  v_prefix:=case when v_category='PIECE_RATE' then 'PCSL' when v_category='SALARIED' then 'MSL' end;
  if v_prefix is null then raise exception 'Payroll Category must be PIECE_RATE or SALARIED.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(concat('SALARY_V786|',v_mode,'|',v_category),0));
  v_preview:=public.rr_salary_payment_preview_v786(v_category,v_start,v_end,v_mode,v_method,v_scope,
    p_bulk_amount,p_worker_ids,p_worker_amounts);
  IF v_mode='TEST' AND EXISTS(SELECT 1 FROM jsonb_array_elements(v_preview->'lines') z WHERE coalesce((z->>'payment_selected')::boolean,false) AND coalesce((z->>'legacy_advance_recovery')::numeric,0)>0) THEN RAISE EXCEPTION 'Legacy advance opening Accounts source mapping required before recovery.';END IF;
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
