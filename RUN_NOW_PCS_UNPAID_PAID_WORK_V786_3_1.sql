
-- =====================================================================
-- REAL FACTORY PCS UNPAID / SALARY-ADDED / PAYMENT AUDIT V786.3.1
--
-- PURPOSE
-- One exact work-level RPC for:
--   UNPAID_WORK
--   SALARY_ADDED
--   PAYMENT_POSTED
--   ALL
--
-- IMPORTANT ACCOUNTING MEANING
-- Work claim proves that work salary was added to the worker ledger.
-- A worker payment may clear previous outstanding first, therefore a
-- partial payment cannot truthfully mark one exact lot/colour/size row
-- as fully paid. The RPC shows:
--   1. exact claimed work
--   2. linked batch/worker-line payment status and amount
--
-- DATA SAFETY
-- CREATE OR REPLACE only. No production, salary, payment or worker data
-- is updated, deleted, moved or converted.
-- =====================================================================

do $$
begin
  if to_regprocedure(
    'public.rr_pcs_unpaid_work_v784(date,date,text,uuid)'
  ) is null then
    raise exception
      'Prerequisite missing: rr_pcs_unpaid_work_v784.';
  end if;

  if to_regclass(
    'public.rr_pcs_work_claims_v784'
  ) is null then
    raise exception
      'Prerequisite missing: rr_pcs_work_claims_v784.';
  end if;

  if to_regclass(
    'public.rr_pcs_payment_batches_v784'
  ) is null then
    raise exception
      'Prerequisite missing: rr_pcs_payment_batches_v784.';
  end if;

  if to_regclass(
    'public.rr_pcs_payment_batch_lines_v784'
  ) is null then
    raise exception
      'Prerequisite missing: rr_pcs_payment_batch_lines_v784.';
  end if;
end;
$$;


create or replace function public.rr_pcs_work_payment_audit_v786_3_1(
  p_from_date date,
  p_to_date date,
  p_data_mode text default 'TEST',
  p_show text default 'UNPAID_WORK',
  p_search text default null
)
returns table(
  record_source text,
  work_status text,
  worker_batch_payment_status text,

  work_key text,
  work_date date,
  assignment_id uuid,
  canonical_lot_id text,
  lot_no text,
  department_code text,

  worker_id uuid,
  worker_name text,
  worker_code text,

  colour_code text,
  colour_name text,
  size_code text,

  submitted_qty numeric,
  payable_qty numeric,
  actual_rate numeric,
  salary_amount numeric,

  first_submit_at timestamptz,
  last_submit_at timestamptz,

  batch_id uuid,
  batch_line_id uuid,
  payment_type text,
  payment_date date,
  payment_mode text,
  voucher_no text,

  worker_previous_outstanding numeric,
  worker_period_work_salary numeric,
  worker_total_payable numeric,
  worker_amount_paid numeric,
  worker_new_outstanding numeric,

  batch_created_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_from date:=p_from_date;
  v_to date:=p_to_date;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_show text:=upper(trim(coalesce(p_show,'UNPAID_WORK')));
  v_search text:=lower(nullif(trim(coalesce(p_search,'')),''));
  v_allowed boolean:=false;
begin
  if v_from is null or v_to is null then
    raise exception 'From Date and To Date are required.';
  end if;

  if v_to<v_from then
    raise exception 'To Date cannot be before From Date.';
  end if;

  if v_mode not in('TEST','REAL') then
    raise exception 'Data Mode must be TEST or REAL.';
  end if;

  if v_show not in(
    'UNPAID_WORK',
    'SALARY_ADDED',
    'PAYMENT_POSTED',
    'ALL'
  ) then
    raise exception
      'Show must be UNPAID_WORK, SALARY_ADDED, PAYMENT_POSTED or ALL.';
  end if;

  if to_regprocedure(
    'public.rr_worker_salary_can_view_v781()'
  ) is not null then
    begin
      execute
        'select public.rr_worker_salary_can_view_v781()'
      into v_allowed;
    exception when others then
      v_allowed:=false;
    end;
  end if;

  if not coalesce(v_allowed,false)
     and to_regprocedure(
       'public.rr_salary_bulk_can_view_v782()'
     ) is not null then
    begin
      execute
        'select public.rr_salary_bulk_can_view_v782()'
      into v_allowed;
    exception when others then
      v_allowed:=false;
    end;
  end if;

  if not coalesce(v_allowed,false) then
    select exists(
      select 1
      from public.rr_user_profiles p
      where p.auth_user_id=auth.uid()
        and coalesce(p.is_active,false)
        and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
        and lower(coalesce(p.role_code,'')) in(
          'owner','admin','account','accounts',
          'payroll','manager','hr'
        )
    )
    into v_allowed;
  end if;

  if not coalesce(v_allowed,false) then
    raise exception 'PCS salary view permission required.';
  end if;

  return query
  with unpaid as(
    select
      'UNPAID'::text as record_source,
      'UNPAID_WORK'::text as work_status,
      'NOT_IN_SALARY_LEDGER'::text
        as worker_batch_payment_status,

      u.work_key,
      u.work_date,
      u.assignment_id,
      u.canonical_lot_id,
      u.lot_no,
      u.department_code,

      u.worker_id,
      u.worker_name,
      u.worker_code,

      u.colour_code,
      u.colour_name,
      u.size_code,

      u.submitted_qty,
      u.payable_qty,
      u.actual_rate,
      u.salary_amount,

      u.first_submit_at,
      u.last_submit_at,

      null::uuid as batch_id,
      null::uuid as batch_line_id,
      null::text as payment_type,
      null::date as payment_date,
      null::text as payment_mode,
      null::text as voucher_no,

      0::numeric as worker_previous_outstanding,
      u.salary_amount::numeric as worker_period_work_salary,
      u.salary_amount::numeric as worker_total_payable,
      0::numeric as worker_amount_paid,
      u.salary_amount::numeric as worker_new_outstanding,

      null::timestamptz as batch_created_at

    from public.rr_pcs_unpaid_work_v784(
      v_from,
      v_to,
      v_mode,
      null
    ) u
  ),
  claimed as(
    select
      'CLAIMED'::text as record_source,

      case
        when coalesce(l.amount_paid,0)<=0.005
          then 'SALARY_ADDED_PAYMENT_PENDING'
        when coalesce(l.new_outstanding,0)<=0.005
          then 'BATCH_LINE_FULLY_SETTLED'
        else 'BATCH_LINE_PARTIALLY_PAID'
      end::text as work_status,

      case
        when coalesce(l.amount_paid,0)<=0.005
          then 'PAYMENT_PENDING'
        when coalesce(l.new_outstanding,0)<=0.005
          then 'FULL_PAYMENT_POSTED'
        else 'PARTIAL_PAYMENT_POSTED'
      end::text as worker_batch_payment_status,

      c.work_key,
      c.work_date,
      c.assignment_id,
      c.canonical_lot_id,
      c.lot_no,
      c.department_code,

      c.worker_id,
      c.worker_name,
      c.worker_code,

      c.colour_code,
      c.colour_name,
      c.size_code,

      c.submitted_qty,
      c.payable_qty,
      c.actual_rate,
      c.salary_amount,

      c.first_submit_at,
      c.last_submit_at,

      c.batch_id,
      c.batch_line_id,
      b.payment_type,
      b.payment_date,
      b.payment_mode,
      b.voucher_no,

      l.previous_outstanding
        as worker_previous_outstanding,
      l.period_work_salary
        as worker_period_work_salary,
      l.total_payable
        as worker_total_payable,
      l.amount_paid
        as worker_amount_paid,
      l.new_outstanding
        as worker_new_outstanding,

      b.created_at as batch_created_at

    from public.rr_pcs_work_claims_v784 c
    join public.rr_pcs_payment_batches_v784 b
      on b.id=c.batch_id
     and b.status='POSTED'
    join public.rr_pcs_payment_batch_lines_v784 l
      on l.id=c.batch_line_id
    where c.data_mode=v_mode
      and c.status='POSTED'
      and c.work_date between v_from and v_to
  ),
  combined as(
    select * from unpaid
    where v_show in('UNPAID_WORK','ALL')

    union all

    select * from claimed
    where v_show in('SALARY_ADDED','ALL')
       or(
         v_show='PAYMENT_POSTED'
         and coalesce(worker_amount_paid,0)>0.005
       )
  )
  select x.*
  from combined x
  where
    v_search is null
    or lower(concat_ws(
      ' ',
      x.worker_name,
      x.worker_code,
      x.department_code,
      x.lot_no,
      x.canonical_lot_id,
      x.colour_code,
      x.colour_name,
      x.size_code,
      x.voucher_no,
      x.payment_mode,
      x.work_status,
      x.worker_batch_payment_status
    )) like '%'||v_search||'%'
  order by
    x.work_date desc,
    x.worker_name,
    x.department_code,
    x.lot_no,
    x.colour_code,
    x.size_code,
    x.work_key;
end;
$$;


grant execute
on function public.rr_pcs_work_payment_audit_v786_3_1(
  date,date,text,text,text
)
to authenticated;

notify pgrst,'reload schema';


select
  case
    when to_regprocedure(
      'public.rr_pcs_work_payment_audit_v786_3_1(date,date,text,text,text)'
    ) is null then 'FAIL'
    else 'PASS'
  end as pcs_unpaid_paid_audit_v786_3_1_result,

  to_regclass(
    'public.rr_pcs_work_claims_v784'
  ) is not null as exact_claimed_work_ready,

  to_regclass(
    'public.rr_pcs_payment_batch_lines_v784'
  ) is not null as worker_payment_line_ready,

  to_regprocedure(
    'public.rr_pcs_unpaid_work_v784(date,date,text,uuid)'
  ) is not null as exact_unpaid_work_ready;
