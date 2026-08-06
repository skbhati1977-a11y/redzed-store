-- REAL FACTORY THREE PAYMENT METHODS STRICT FIX V786.3.9
--
-- ONLY THESE RULES ARE CHANGED:
-- 1. Selected Workers Partial Payment maps only to WORKER_LEDGER_WISE.
-- 2. Ratio Division Payment maps only to PARTIAL_RATIO.
-- 3. Complete Payment maps only to FULL_PAYMENT and is always selectable.
-- 4. Every actual payment is a ₹100 multiple.
-- 5. Allocation fields are never null.
--
-- Complete Payment pays the maximum safe ₹100 amount per worker.
-- Any balance below ₹100 remains in Current Outstanding.
--
-- No salary work, production work, payment history or worker data is
-- updated/deleted by this SQL. Only the preview function is replaced.

do $$
begin
  if to_regprocedure(
    'public.rr_salary_payment_preview_v785(text,date,date,text,text,text,numeric,uuid[],jsonb)'
  ) is null then
    raise exception 'Prerequisite missing: rr_salary_payment_preview_v785.';
  end if;
end;
$$;

create or replace function public.rr_salary_payment_preview_v785(
  p_payroll_category text,p_period_start date,p_period_end date,p_data_mode text,
  p_payment_method text,p_payment_scope text,p_bulk_amount numeric default 0,
  p_worker_ids uuid[] default null,p_worker_amounts jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer set search_path=public as $$
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
      amount_paid=0;

  if v_method='PARTIAL_RATIO' then
    if v_owner<=0 then
      null;
    elsif v_owner>v_selected_scope+0.005 then
      raise exception 'Bulk Amount Payment exceeds Selected Workers Payable.';
    elsif mod(v_owner,v_rounding)<>0 then
      raise exception 'Ratio Division Payment amount must be a multiple of ₹100.';
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
          raise exception '₹100 ratio cannot exactly match this Bulk Amount.';
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
        raise exception 'Unallocated remainder. Use a compatible ₹100 amount.';
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
      raise exception 'Selected Worker Payment amount must be a multiple of ₹100.';
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
$$;

grant execute
on function public.rr_salary_payment_preview_v785(
  text,date,date,text,text,text,numeric,uuid[],jsonb
)
to authenticated;

notify pgrst,'reload schema';

select
  case
    when position(
      'Ratio Division Payment amount must be a multiple of ₹100.'
      in pg_get_functiondef(
        'public.rr_salary_payment_preview_v785(text,date,date,text,text,text,numeric,uuid[],jsonb)'::regprocedure
      )
    )>0
    and position(
      'Selected Worker Payment amount must be a multiple of ₹100.'
      in pg_get_functiondef(
        'public.rr_salary_payment_preview_v785(text,date,date,text,text,text,numeric,uuid[],jsonb)'::regprocedure
      )
    )>0
    and position(
      'set raw_allocation=amount_paid'
      in pg_get_functiondef(
        'public.rr_salary_payment_preview_v785(text,date,date,text,text,text,numeric,uuid[],jsonb)'::regprocedure
      )
    )>0
    then 'PASS'
    else 'FAIL'
  end as three_payment_methods_round100_v786_3_9_result,

  position(
    'v_rounding numeric(14,2):=100'
    in replace(
      pg_get_functiondef(
        'public.rr_salary_payment_preview_v785(text,date,date,text,text,text,numeric,uuid[],jsonb)'::regprocedure
      ),
      ' ',
      ''
    )
  )>0 as round100_ready,

  position(
    'set raw_allocation=amount_paid'
    in pg_get_functiondef(
      'public.rr_salary_payment_preview_v785(text,date,date,text,text,text,numeric,uuid[],jsonb)'::regprocedure
    )
  )>0 as manual_allocation_not_null_ready,

  position(
    'floor(scope_payable/v_rounding)*v_rounding'
    in pg_get_functiondef(
      'public.rr_salary_payment_preview_v785(text,date,date,text,text,text,numeric,uuid[],jsonb)'::regprocedure
    )
  )>0 as complete_payment_round100_ready;
