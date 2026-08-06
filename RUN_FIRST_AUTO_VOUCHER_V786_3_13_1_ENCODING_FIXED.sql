-- REAL FACTORY AUTO LOAD + AUTO VOUCHER V786.3.13
-- RUN THIS FILE ONCE IN SUPABASE SQL EDITOR.
--
-- Backend change:
--   PIECE_RATE payment voucher: PCSL1, PCSL2, PCSL3...
--   SALARIED payment voucher:   MSL1, MSL2, MSL3...
-- Voucher is allocated atomically only during successful payment posting.
-- Existing payment rows, ledgers and vouchers are not rewritten.

begin;

create table if not exists public.rr_salary_voucher_sequence_v786(
  voucher_prefix text primary key
    check(voucher_prefix in('PCSL','MSL')),
  last_number bigint not null default 0
    check(last_number>=0),
  updated_at timestamptz not null default now(),
  updated_by uuid null
);

revoke all on table public.rr_salary_voucher_sequence_v786
from anon,authenticated;

create or replace function public.rr_salary_payment_post_v785(
  p_payroll_category text,p_period_start date,p_period_end date,p_data_mode text,
  p_payment_method text,p_payment_scope text,p_bulk_amount numeric,p_worker_ids uuid[],p_worker_amounts jsonb,
  p_payment_date date,p_payment_mode text,p_voucher_no text,p_remarks text default null
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
  v_paymode text:=upper(trim(coalesce(p_payment_mode,'')));
  v_prefix text;
  v_voucher text;
  v_next_voucher bigint;
  v_preview jsonb; v_actor text; v_batch uuid; v_line_id uuid; v_due uuid; v_pay uuid;
  r record; v_claim numeric(16,2); v_msg text;
begin
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
        concat('Current period salary accrued · ',r.current_source),auth.uid(),v_actor
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
      E'\nPrevious Outstanding: ₹',to_char(r.previous_outstanding,'FM9999999990.00'),
      E'\nCurrent Period Payable: ₹',to_char(r.current_period_payable,'FM9999999990.00'),
      E'\nFinal Total Payable: ₹',to_char(r.final_total_payable,'FM9999999990.00'),
      E'\nAmount Paid: ₹',to_char(r.amount_paid,'FM9999999990.00'),
      E'\nOutstanding Payment: ₹',to_char(r.outstanding_payment,'FM9999999990.00'),
      E'\nCurrent Period Payment: ₹',to_char(r.current_period_payment,'FM9999999990.00'),
      E'\nNew Outstanding: ₹',to_char(r.new_total_outstanding,'FM9999999990.00'),
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
$$;

-- =========================================================
-- 10. NORMAL PAYMENT VOID
-- =========================================================

commit;

-- INSTALLATION VERIFICATION
with fn as (
  select regexp_replace(
    pg_get_functiondef(
      'public.rr_salary_payment_post_v785(text,date,date,text,text,text,numeric,uuid[],jsonb,date,text,text,text)'::regprocedure
    ),
    '\s+','','g'
  ) as d
),
checks as (
  select
    to_regclass('public.rr_salary_voucher_sequence_v786') is not null
      as sequence_table_ready,
    position('whenv_category=''PIECE_RATE''then''PCSL''' in d)>0
      as pcsl_rule_ready,
    position('whenv_category=''SALARIED''then''MSL''' in d)>0
      as msl_rule_ready,
    position('SALARY_VOUCHER_V786' in d)>0
      as atomic_lock_ready,
    position('rr_salary_voucher_sequence_v786' in d)>0
      as sequence_usage_ready,
    position('Voucher/Referencerequired.' in d)=0
      as manual_voucher_requirement_removed,
    position('v_voucher:=concat(v_prefix,v_next_voucher)' in d)>0
      as final_voucher_generation_ready
  from fn
)
select
  case when
    sequence_table_ready
    and pcsl_rule_ready
    and msl_rule_ready
    and atomic_lock_ready
    and sequence_usage_ready
    and manual_voucher_requirement_removed
    and final_voucher_generation_ready
  then 'PASS' else 'FAIL' end
    as autoload_auto_voucher_v786_3_13_result,
  *
from checks;
