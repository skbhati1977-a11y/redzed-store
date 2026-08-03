
-- ============================================================
-- REDZED V779.3 — PAYROLL UI + WORKER SELF-SERVICE APIs
--
-- Dependencies:
--   V779.1 Universal Monthly Payroll Core
--   V779.2 Payroll Posting & Settlement Engine
--
-- Scope:
--   * Worker: only own payroll
--   * Owner/Admin/Manager/Production: management access
--   * Summary heads exactly as locked
--   * Details drawers
--   * Payroll history
--   * Review/dispute workflow
--   * PDF-ready and WhatsApp-ready payloads
--
-- No actual WhatsApp sending in this version.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Worker payroll dispute/review requests
-- ------------------------------------------------------------
create table if not exists public.rr_payroll_disputes_v779_3(
  dispute_id uuid primary key default gen_random_uuid(),

  payroll_id uuid not null
    references public.rr_monthly_payroll_v779_1(payroll_id)
    on delete restrict,

  worker_id uuid not null,
  payroll_month date not null,

  dispute_section text not null
    check(dispute_section in(
      'MONTHLY_SALARY',
      'NET_EXTRA_WORK',
      'MONTHLY_INCENTIVE',
      'CLAIMS_RECOVERY',
      'PAYMENT',
      'OTHER'
    )),

  dispute_text text not null,
  evidence jsonb not null default '{}'::jsonb,

  dispute_status text not null default 'OPEN'
    check(dispute_status in(
      'OPEN',
      'UNDER_REVIEW',
      'RESOLVED_ACCEPTED',
      'RESOLVED_REJECTED',
      'CANCELLED'
    )),

  data_mode text not null
    check(data_mode in('TEST','REAL')),

  opened_at timestamptz not null default now(),
  opened_by uuid default auth.uid(),

  reviewed_at timestamptz,
  reviewed_by uuid,
  resolution_note text,

  unique(payroll_id,worker_id,dispute_section,dispute_status)
);

create index if not exists rr_payroll_disputes_v779_3_worker_idx
on public.rr_payroll_disputes_v779_3(
  worker_id,payroll_month desc,dispute_status
);

-- ------------------------------------------------------------
-- 2. Payslip delivery/request audit
-- ------------------------------------------------------------
create table if not exists public.rr_payroll_payslip_requests_v779_3(
  request_id uuid primary key default gen_random_uuid(),

  payroll_id uuid not null
    references public.rr_monthly_payroll_v779_1(payroll_id)
    on delete restrict,

  worker_id uuid not null,

  request_type text not null
    check(request_type in(
      'VIEW',
      'PDF',
      'WHATSAPP'
    )),

  request_status text not null default 'REQUESTED'
    check(request_status in(
      'REQUESTED',
      'GENERATED',
      'QUEUED',
      'SENT',
      'FAILED',
      'CANCELLED'
    )),

  destination_masked text,
  payload_snapshot jsonb not null default '{}'::jsonb,

  data_mode text not null
    check(data_mode in('TEST','REAL')),

  requested_at timestamptz not null default now(),
  requested_by uuid default auth.uid(),

  completed_at timestamptz,
  external_reference text,
  failure_reason text
);

-- ------------------------------------------------------------
-- 3. Common access guard
-- ------------------------------------------------------------
create or replace function public.rr_payroll_can_view_worker_v779_3(
  p_worker_id uuid
)
returns boolean
language sql
stable
security definer
set search_path='public'
as $$
  select
    public.rr_payroll_worker_is_self_v779_1(p_worker_id)
    or public.rr_payroll_can_manage_v779_1()
$$;

-- ------------------------------------------------------------
-- 4. Worker My Payroll history
-- ------------------------------------------------------------
create or replace function public.rr_get_my_payroll_history_v779_3(
  p_limit integer default 24,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_worker record;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_rows jsonb;
begin
  select
    worker_id,
    worker_code,
    worker_name,
    department_code
  into v_worker
  from public.rr_worker_directory_unified_v1
  where linked_auth_user_id=auth.uid()
  limit 1;

  if not found then
    raise exception 'Linked Worker profile required hai.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'payroll_id',x.payroll_id,
        'salary_month',to_char(x.payroll_month,'FMMonth YYYY'),
        'payroll_month',x.payroll_month,

        'monthly_salary',x.monthly_salary_amount,

        'net_extra_work',jsonb_build_object(
          'amount',x.net_extra_work_amount,
          'time',public.rr_minutes_dhm_v778_2(
            x.net_extra_work_minutes
          ),
          'details_available',true
        ),

        'monthly_incentive',x.incentive_amount,
        'claims_recovery',x.claims_recovery_amount,
        'net_payable_salary',x.net_payable_salary,

        'payroll_status',x.payroll_status,
        'settlement_status',x.settlement_status,
        'payment_amount',coalesce(x.payment_amount,0),
        'closing_balance',coalesce(x.closing_balance,0),

        'view_details',true,
        'pdf_available',x.payroll_status in('FINAL','PAID'),
        'whatsapp_available',x.payroll_status in('FINAL','PAID')
      )
      order by x.payroll_month desc
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select *
    from public.rr_monthly_payroll_settlement_board_v779_2
    where worker_id=v_worker.worker_id
      and data_mode=v_mode
    order by payroll_month desc
    limit greatest(least(coalesce(p_limit,24),60),1)
  ) x;

  return jsonb_build_object(
    'ok',true,
    'version','V779_3_PAYROLL_UI_SELF_SERVICE',
    'worker',jsonb_build_object(
      'worker_id',v_worker.worker_id,
      'worker_code',v_worker.worker_code,
      'worker_name',v_worker.worker_name,
      'department_code',v_worker.department_code
    ),
    'payroll_history',v_rows,
    'privacy','OWN_RECORDS_ONLY'
  );
end $$;

-- ------------------------------------------------------------
-- 5. Payroll summary screen
-- ------------------------------------------------------------
create or replace function public.rr_get_payroll_summary_v779_3(
  p_payroll_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_p record;
  v_open_disputes integer:=0;
begin
  select *
  into v_p
  from public.rr_monthly_payroll_settlement_board_v779_2
  where payroll_id=p_payroll_id
  limit 1;

  if not found then
    raise exception 'Payroll record nahi mila.';
  end if;

  if not public.rr_payroll_can_view_worker_v779_3(v_p.worker_id) then
    raise exception 'Aap kisi dusre Worker ka Payroll nahi dekh sakte.';
  end if;

  select count(*)
  into v_open_disputes
  from public.rr_payroll_disputes_v779_3 d
  where d.payroll_id=p_payroll_id
    and d.dispute_status in('OPEN','UNDER_REVIEW');

  return jsonb_build_object(
    'ok',true,
    'version','V779_3_PAYROLL_UI_SELF_SERVICE',

    'header',jsonb_build_object(
      'title','MONTHLY PAYROLL',
      'worker_id',v_p.worker_id,
      'worker_code',v_p.worker_code,
      'worker_name',v_p.worker_name,
      'department_code',v_p.department_code,
      'salary_month',to_char(v_p.payroll_month,'FMMonth YYYY')
    ),

    'heads',jsonb_build_array(
      jsonb_build_object(
        'code','MONTHLY_SALARY',
        'label','Monthly Salary',
        'amount',v_p.monthly_salary_amount,
        'details_button',true
      ),

      jsonb_build_object(
        'code','NET_EXTRA_WORK',
        'label','Net Extra Work',
        'amount',v_p.net_extra_work_amount,
        'time',v_p.net_extra_work_dhm,
        'details_button',true
      ),

      jsonb_build_object(
        'code','MONTHLY_INCENTIVE',
        'label','Monthly Incentive',
        'amount',v_p.incentive_amount,
        'details_button',true
      ),

      jsonb_build_object(
        'code','CLAIMS_RECOVERY',
        'label','Claims / Recovery',
        'amount',v_p.claims_recovery_amount,
        'details_button',true
      )
    ),

    'net_payable',jsonb_build_object(
      'label','NET PAYABLE SALARY',
      'amount',v_p.net_payable_salary
    ),

    'payment',jsonb_build_object(
      'paid_amount',coalesce(v_p.payment_amount,0),
      'closing_balance',coalesce(v_p.closing_balance,0),
      'details_button',true
    ),

    'status',jsonb_build_object(
      'payroll_status',v_p.payroll_status,
      'settlement_status',v_p.settlement_status,
      'posting_date',v_p.posting_date,
      'review_from',v_p.review_from,
      'review_until',v_p.review_until,
      'open_disputes',v_open_disputes
    ),

    'actions',jsonb_build_object(
      'view_details',true,
      'raise_dispute',
        current_date between v_p.review_from and v_p.review_until
        and v_p.payroll_status in('POSTED','UNDER_REVIEW'),
      'download_pdf',
        v_p.payroll_status in('FINAL','PAID'),
      'share_whatsapp',
        v_p.payroll_status in('FINAL','PAID')
    )
  );
end $$;

-- ------------------------------------------------------------
-- 6. Section details drawer
-- ------------------------------------------------------------
create or replace function public.rr_get_payroll_section_details_v779_3(
  p_payroll_id uuid,
  p_section text
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_p public.rr_monthly_payroll_v779_1%rowtype;
  v_section text:=upper(trim(coalesce(p_section,'')));
  v_rows jsonb;
begin
  select *
  into v_p
  from public.rr_monthly_payroll_v779_1
  where payroll_id=p_payroll_id;

  if not found then raise exception 'Payroll record nahi mila.'; end if;

  if not public.rr_payroll_can_view_worker_v779_3(v_p.worker_id) then
    raise exception 'Aap kisi dusre Worker ki details nahi dekh sakte.';
  end if;

  if v_section='MONTHLY_SALARY' then
    return jsonb_build_object(
      'ok',true,
      'section','MONTHLY_SALARY',
      'title','Monthly Salary Details',
      'contract_monthly_salary',v_p.monthly_salary_contract,
      'monthly_salary_amount',v_p.monthly_salary_amount,
      'basis_days',30,
      'minutes_per_day',600,
      'monthly_base_minutes',18000,
      'net_deduction',jsonb_build_object(
        'minutes',v_p.net_deduction_minutes,
        'time',public.rr_minutes_dhm_v778_2(
          v_p.net_deduction_minutes
        ),
        'amount',v_p.deduction_amount
      ),
      'per_minute_rate',v_p.per_minute_rate
    );

  elsif v_section='NET_EXTRA_WORK' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'date',d.attendance_date,
          'minutes',d.net_extra_work_minutes,
          'time',public.rr_minutes_dhm_v778_2(
            d.net_extra_work_minutes
          )
        )
        order by d.attendance_date
      ),
      '[]'::jsonb
    )
    into v_rows
    from public.rr_attendance_day_v777_2 d
    where d.worker_id=v_p.worker_id
      and d.attendance_date between
        v_p.payroll_month
        and (v_p.payroll_month+interval '1 month-1 day')::date
      and d.data_mode=v_p.data_mode
      and d.net_extra_work_minutes>0;

    return jsonb_build_object(
      'ok',true,
      'section','NET_EXTRA_WORK',
      'title','Net Extra Work Details',
      'total_minutes',v_p.net_extra_work_minutes,
      'total_time',public.rr_minutes_dhm_v778_2(
        v_p.net_extra_work_minutes
      ),
      'amount',v_p.net_extra_work_amount,
      'date_wise',v_rows
    );

  elsif v_section='MONTHLY_INCENTIVE' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'incentive_id',i.incentive_id,
          'type',i.incentive_type,
          'amount',i.incentive_amount,
          'description',i.description,
          'status',i.incentive_status
        )
        order by i.created_at
      ),
      '[]'::jsonb
    )
    into v_rows
    from public.rr_payroll_incentives_v779_1 i
    where i.worker_id=v_p.worker_id
      and i.payroll_month=v_p.payroll_month
      and i.data_mode=v_p.data_mode
      and i.incentive_status='APPROVED';

    return jsonb_build_object(
      'ok',true,
      'section','MONTHLY_INCENTIVE',
      'title','Monthly Incentive Details',
      'total_amount',v_p.incentive_amount,
      'items',v_rows
    );

  elsif v_section='CLAIMS_RECOVERY' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'source_type',a.source_type,
          'source_id',a.source_id,
          'amount',a.applied_amount,
          'applied_at',a.applied_at
        )
        order by a.applied_at
      ),
      '[]'::jsonb
    )
    into v_rows
    from public.rr_payroll_source_applications_v779_1 a
    where a.payroll_id=p_payroll_id
      and a.source_type in('CLAIM','ADVANCE')
      and a.reversed_at is null;

    return jsonb_build_object(
      'ok',true,
      'section','CLAIMS_RECOVERY',
      'title','Claims / Recovery Details',
      'approved_claims',v_p.approved_claim_amount,
      'advance_recovery',v_p.advance_recovery_amount,
      'total_amount',v_p.claims_recovery_amount,
      'items',v_rows
    );

  elsif v_section='PAYMENT' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'event_id',e.payroll_event_id,
          'date',e.created_at,
          'event_type',e.event_type,
          'details',e.new_snapshot,
          'reason',e.reason
        )
        order by e.created_at
      ),
      '[]'::jsonb
    )
    into v_rows
    from public.rr_payroll_events_v779_1 e
    where e.payroll_id=p_payroll_id
      and e.event_type='SALARY_PAYMENT_RECORDED';

    return jsonb_build_object(
      'ok',true,
      'section','PAYMENT',
      'title','Payment History',
      'items',v_rows
    );

  else
    raise exception 'Payroll detail section invalid hai.';
  end if;
end $$;

-- ------------------------------------------------------------
-- 7. Worker raises a payroll dispute
-- ------------------------------------------------------------
create or replace function public.rr_raise_payroll_dispute_v779_3(
  p_payroll_id uuid,
  p_section text,
  p_dispute_text text,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_p public.rr_monthly_payroll_v779_1%rowtype;
  v_section text:=upper(trim(coalesce(p_section,'')));
  v_id uuid;
begin
  select *
  into v_p
  from public.rr_monthly_payroll_v779_1
  where payroll_id=p_payroll_id
  for update;

  if not found then raise exception 'Payroll record nahi mila.'; end if;

  if not public.rr_payroll_worker_is_self_v779_1(v_p.worker_id) then
    raise exception 'Worker sirf apna payroll dispute raise kar sakta hai.';
  end if;

  if current_date not between v_p.review_from and v_p.review_until then
    raise exception 'Payroll review window active nahi hai.';
  end if;

  if v_p.payroll_status not in('POSTED','UNDER_REVIEW') then
    raise exception 'Payroll review ke liye available nahi hai.';
  end if;

  insert into public.rr_payroll_disputes_v779_3(
    payroll_id,worker_id,payroll_month,
    dispute_section,dispute_text,evidence,
    dispute_status,data_mode,opened_by
  )
  values(
    p_payroll_id,v_p.worker_id,v_p.payroll_month,
    v_section,p_dispute_text,coalesce(p_evidence,'{}'::jsonb),
    'OPEN',v_p.data_mode,auth.uid()
  )
  returning dispute_id into v_id;

  if v_p.payroll_status='POSTED' then
    update public.rr_monthly_payroll_v779_1
    set payroll_status='UNDER_REVIEW',updated_at=now()
    where payroll_id=p_payroll_id;

    update public.rr_worker_settlements_v777_2
    set settlement_status='CALCULATED'
    where settlement_id=v_p.settlement_id
      and settlement_status='CALCULATED';
  end if;

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,
    new_snapshot,reason,data_mode
  )
  values(
    p_payroll_id,v_p.worker_id,v_p.payroll_month,
    'WORKER_DISPUTE_RAISED',
    jsonb_build_object(
      'dispute_id',v_id,
      'section',v_section
    ),
    p_dispute_text,v_p.data_mode
  );

  return jsonb_build_object(
    'ok',true,
    'dispute_id',v_id,
    'status','OPEN',
    'payroll_status','UNDER_REVIEW'
  );
end $$;

-- ------------------------------------------------------------
-- 8. Management resolves dispute
-- ------------------------------------------------------------
create or replace function public.rr_resolve_payroll_dispute_v779_3(
  p_dispute_id uuid,
  p_decision text,
  p_resolution_note text
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_decision text:=upper(trim(coalesce(p_decision,'')));
  v_d public.rr_payroll_disputes_v779_3%rowtype;
  v_remaining integer;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll dispute review permission denied.';
  end if;

  if v_decision not in('ACCEPTED','REJECTED') then
    raise exception 'Decision ACCEPTED ya REJECTED hona chahiye.';
  end if;

  select *
  into v_d
  from public.rr_payroll_disputes_v779_3
  where dispute_id=p_dispute_id
  for update;

  if not found then raise exception 'Dispute nahi mila.'; end if;

  if v_d.dispute_status not in('OPEN','UNDER_REVIEW') then
    raise exception 'Dispute already resolved hai.';
  end if;

  update public.rr_payroll_disputes_v779_3
  set dispute_status=case
        when v_decision='ACCEPTED'
        then 'RESOLVED_ACCEPTED'
        else 'RESOLVED_REJECTED'
      end,
      reviewed_at=now(),
      reviewed_by=auth.uid(),
      resolution_note=p_resolution_note
  where dispute_id=p_dispute_id;

  select count(*)
  into v_remaining
  from public.rr_payroll_disputes_v779_3
  where payroll_id=v_d.payroll_id
    and dispute_status in('OPEN','UNDER_REVIEW');

  insert into public.rr_payroll_events_v779_1(
    payroll_id,worker_id,payroll_month,event_type,
    new_snapshot,reason,data_mode
  )
  values(
    v_d.payroll_id,v_d.worker_id,v_d.payroll_month,
    'DISPUTE_RESOLVED',
    jsonb_build_object(
      'dispute_id',p_dispute_id,
      'decision',v_decision,
      'remaining_open_disputes',v_remaining
    ),
    p_resolution_note,v_d.data_mode
  );

  return jsonb_build_object(
    'ok',true,
    'dispute_id',p_dispute_id,
    'decision',v_decision,
    'remaining_open_disputes',v_remaining
  );
end $$;

-- ------------------------------------------------------------
-- 9. Management payroll board API
-- ------------------------------------------------------------
create or replace function public.rr_get_payroll_management_board_v779_3(
  p_payroll_month date,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_rows jsonb;
  v_summary jsonb;
begin
  if not public.rr_payroll_can_manage_v779_1() then
    raise exception 'Payroll management permission denied.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'payroll_id',b.payroll_id,
        'worker_id',b.worker_id,
        'worker_code',b.worker_code,
        'worker_name',b.worker_name,
        'department_code',b.department_code,

        'monthly_salary',b.monthly_salary_amount,
        'net_extra_work_amount',b.net_extra_work_amount,
        'net_extra_work_time',b.net_extra_work_dhm,
        'monthly_incentive',b.incentive_amount,
        'claims_recovery',b.claims_recovery_amount,
        'net_payable_salary',b.net_payable_salary,

        'payroll_status',b.payroll_status,
        'settlement_status',b.settlement_status,
        'payment_amount',coalesce(b.payment_amount,0),
        'closing_balance',coalesce(b.closing_balance,0),

        'open_disputes',(
          select count(*)
          from public.rr_payroll_disputes_v779_3 d
          where d.payroll_id=b.payroll_id
            and d.dispute_status in('OPEN','UNDER_REVIEW')
        )
      )
      order by b.department_code,b.worker_name
    ),
    '[]'::jsonb
  )
  into v_rows
  from public.rr_monthly_payroll_settlement_board_v779_2 b
  where b.payroll_month=p_payroll_month
    and b.data_mode=v_mode;

  select jsonb_build_object(
    'workers',count(*),
    'monthly_salary_total',coalesce(sum(monthly_salary_amount),0),
    'net_extra_work_total',coalesce(sum(net_extra_work_amount),0),
    'incentive_total',coalesce(sum(incentive_amount),0),
    'claims_recovery_total',coalesce(sum(claims_recovery_amount),0),
    'net_payable_total',coalesce(sum(net_payable_salary),0),
    'paid_total',coalesce(sum(payment_amount),0),
    'closing_balance_total',coalesce(sum(closing_balance),0)
  )
  into v_summary
  from public.rr_monthly_payroll_settlement_board_v779_2
  where payroll_month=p_payroll_month
    and data_mode=v_mode;

  return jsonb_build_object(
    'ok',true,
    'payroll_month',p_payroll_month,
    'salary_month',to_char(p_payroll_month,'FMMonth YYYY'),
    'summary',v_summary,
    'workers',v_rows
  );
end $$;

-- ------------------------------------------------------------
-- 10. PDF-ready payslip payload
-- ------------------------------------------------------------
create or replace function public.rr_get_payslip_payload_v779_3(
  p_payroll_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_summary jsonb;
  v_p record;
  v_request_id uuid;
begin
  v_summary:=public.rr_get_payroll_summary_v779_3(p_payroll_id);

  select *
  into v_p
  from public.rr_monthly_payroll_settlement_board_v779_2
  where payroll_id=p_payroll_id;

  if v_p.payroll_status not in('FINAL','PAID') then
    raise exception 'Final payroll ke baad payslip available hogi.';
  end if;

  insert into public.rr_payroll_payslip_requests_v779_3(
    payroll_id,worker_id,request_type,request_status,
    payload_snapshot,data_mode,requested_by
  )
  values(
    p_payroll_id,v_p.worker_id,'PDF','REQUESTED',
    v_summary,v_p.data_mode,auth.uid()
  )
  returning request_id into v_request_id;

  return jsonb_build_object(
    'ok',true,
    'request_id',v_request_id,
    'document_type','MONTHLY_PAYROLL_SLIP',
    'company','JAI GIRVER GARMENTS',
    'brand','REDZED',
    'payload',v_summary,
    'render_status','PDF_READY_PAYLOAD'
  );
end $$;

-- ------------------------------------------------------------
-- 11. WhatsApp-ready payload
-- Actual sending remains in future WhatsApp Module.
-- ------------------------------------------------------------
create or replace function public.rr_get_whatsapp_payslip_payload_v779_3(
  p_payroll_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_summary jsonb;
  v_p record;
  v_request_id uuid;
  v_text text;
begin
  v_summary:=public.rr_get_payroll_summary_v779_3(p_payroll_id);

  select *
  into v_p
  from public.rr_monthly_payroll_settlement_board_v779_2
  where payroll_id=p_payroll_id;

  if v_p.payroll_status not in('FINAL','PAID') then
    raise exception 'Final payroll ke baad WhatsApp slip available hogi.';
  end if;

  v_text:=
      'REDZED MONTHLY PAYROLL'||E'\n'
    ||to_char(v_p.payroll_month,'FMMonth YYYY')||E'\n\n'
    ||'Monthly Salary: ₹'||to_char(v_p.monthly_salary_amount,'FM999999990.00')||E'\n'
    ||'Net Extra Work: ₹'||to_char(v_p.net_extra_work_amount,'FM999999990.00')
      ||' ('||coalesce(v_p.net_extra_work_dhm,'0 M')||')'||E'\n'
    ||'Monthly Incentive: ₹'||to_char(v_p.incentive_amount,'FM999999990.00')||E'\n'
    ||'Claims / Recovery: ₹'||to_char(v_p.claims_recovery_amount,'FM999999990.00')||E'\n'
    ||'NET PAYABLE SALARY: ₹'||to_char(v_p.net_payable_salary,'FM999999990.00');

  insert into public.rr_payroll_payslip_requests_v779_3(
    payroll_id,worker_id,request_type,request_status,
    payload_snapshot,data_mode,requested_by
  )
  values(
    p_payroll_id,v_p.worker_id,'WHATSAPP','REQUESTED',
    jsonb_build_object(
      'text',v_text,
      'summary',v_summary
    ),
    v_p.data_mode,auth.uid()
  )
  returning request_id into v_request_id;

  return jsonb_build_object(
    'ok',true,
    'request_id',v_request_id,
    'send_status','READY_FOR_WHATSAPP_MODULE',
    'message_text',v_text,
    'payroll_id',p_payroll_id
  );
end $$;

-- ------------------------------------------------------------
-- 12. Secure direct-access lockdown
-- ------------------------------------------------------------
revoke all
on public.rr_payroll_disputes_v779_3,
   public.rr_payroll_payslip_requests_v779_3
from anon,authenticated;

grant execute on function public.rr_payroll_can_view_worker_v779_3(uuid)
to authenticated;

grant execute on function public.rr_get_my_payroll_history_v779_3(integer,text)
to authenticated;

grant execute on function public.rr_get_payroll_summary_v779_3(uuid)
to authenticated;

grant execute on function public.rr_get_payroll_section_details_v779_3(uuid,text)
to authenticated;

grant execute on function public.rr_raise_payroll_dispute_v779_3(
  uuid,text,text,jsonb
) to authenticated;

grant execute on function public.rr_resolve_payroll_dispute_v779_3(
  uuid,text,text
) to authenticated;

grant execute on function public.rr_get_payroll_management_board_v779_3(
  date,text
) to authenticated;

grant execute on function public.rr_get_payslip_payload_v779_3(uuid)
to authenticated;

grant execute on function public.rr_get_whatsapp_payslip_payload_v779_3(uuid)
to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V779_3_PAYROLL_UI_SELF_SERVICE',

  'worker_privacy','OWN_LINKED_USER_ID_ONLY',

  'payslip_heads',jsonb_build_array(
    'MONTHLY_SALARY',
    'NET_EXTRA_WORK',
    'MONTHLY_INCENTIVE',
    'CLAIMS_RECOVERY',
    'NET_PAYABLE_SALARY'
  ),

  'details_drawers',jsonb_build_array(
    'MONTHLY_SALARY',
    'NET_EXTRA_WORK',
    'MONTHLY_INCENTIVE',
    'CLAIMS_RECOVERY',
    'PAYMENT'
  ),

  'payroll_history',true,
  'worker_dispute_flow',true,
  'management_board_api',true,
  'pdf_ready_payload',true,
  'whatsapp_ready_payload',true,
  'actual_whatsapp_sending',false,

  'salary_detail_hidden_from_summary',true,
  'other_worker_data_access',false
) as rr_upm_v779_3_result;
