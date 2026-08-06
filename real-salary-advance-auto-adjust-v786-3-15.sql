-- REAL FACTORY SALARY ADVANCE AUTO-ADJUST V786.3.15
-- Run once in Supabase SQL Editor. Existing rows are not rewritten.

begin;

alter table public.rr_salary_payment_batch_lines_v785
  drop constraint if exists rr_salary_payment_batch_lines_v785_current_period_payable_check;
alter table public.rr_salary_payment_batch_lines_v785
  add constraint rr_salary_payment_batch_lines_v785_current_period_payable_check
  check(current_period_payable >= 0) not valid;
alter table public.rr_salary_payment_batch_lines_v785
  validate constraint rr_salary_payment_batch_lines_v785_current_period_payable_check;

alter table public.rr_salary_payment_batches_v785
  add column if not exists total_gross_payable numeric(16,2) not null default 0,
  add column if not exists total_advance_recovery numeric(16,2) not null default 0;

alter table public.rr_salary_payment_batch_lines_v785
  add column if not exists gross_previous_outstanding numeric(16,2) not null default 0,
  add column if not exists gross_current_period_payable numeric(16,2) not null default 0,
  add column if not exists advance_opening_balance numeric(16,2) not null default 0,
  add column if not exists legacy_advance_recovery numeric(16,2) not null default 0,
  add column if not exists dedicated_advance_recovery numeric(16,2) not null default 0,
  add column if not exists advance_recovery_amount numeric(16,2) not null default 0,
  add column if not exists advance_recovery_ledger_entry_id uuid null,
  add column if not exists advance_salary_ledger_entry_id uuid null;

create unique index if not exists rr_advance_recovery_source_v786_uidx
  on public.rr_worker_advance_ledger_v785(data_mode,source_line_id,entry_type)
  where status='POSTED' and entry_type='ADVANCE_RECOVERY' and source_line_id is not null;

create unique index if not exists rr_advance_reversal_related_v786_uidx
  on public.rr_worker_advance_ledger_v785(related_entry_id)
  where status='POSTED' and entry_type='ADVANCE_REVERSAL' and related_entry_id is not null;

create table if not exists public.rr_salary_voucher_sequence_v786(
  voucher_prefix text primary key check(voucher_prefix in('PCSL','MSL')),
  last_number bigint not null default 0 check(last_number>=0),
  updated_at timestamptz not null default now(),
  updated_by uuid null
);
revoke all on table public.rr_salary_voucher_sequence_v786 from anon,authenticated;

create or replace function public.rr_salary_payment_preview_v786(
  p_payroll_category text,p_period_start date,p_period_end date,p_data_mode text,
  p_payment_method text,p_payment_scope text,p_bulk_amount numeric default 0,
  p_worker_ids uuid[] default null,p_worker_amounts jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_category text:=upper(trim(coalesce(p_payroll_category,'')));
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'TEST'));
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
  if v_category not in('PIECE_RATE','SALARIED') then raise exception 'Invalid Salary Module.'; end if;
  if v_mode not in('TEST','REAL') then raise exception 'Invalid Data Mode.'; end if;
  if v_method not in('PARTIAL_RATIO','WORKER_LEDGER_WISE','FULL_PAYMENT') then raise exception 'Invalid Payment Method.'; end if;
  if v_scope not in('OUTSTANDING_ONLY','CURRENT_PERIOD_ONLY','FULL_AND_FINAL') then raise exception 'Invalid Payment Scope.'; end if;

  create temporary table if not exists rr_salary_preview_tmp_v786(
    worker_id uuid primary key,worker_name text,worker_code text,department_code text,worker_status text,
    payment_selected boolean,
    gross_previous_outstanding numeric(16,2),gross_current_period_payable numeric(16,2),
    advance_opening_balance numeric(16,2),legacy_advance_recovery numeric(16,2),
    dedicated_advance_recovery numeric(16,2),advance_recovery_amount numeric(16,2),
    previous_outstanding numeric(16,2),current_period_payable numeric(16,2),
    unaccrued_current_amount numeric(16,2),final_total_payable numeric(16,2),scope_payable numeric(16,2),
    raw_allocation numeric(16,6),floor_allocation numeric(16,2),allocation_remainder numeric(16,6),
    amount_paid numeric(16,2),outstanding_payment numeric(16,2),current_period_payment numeric(16,2),
    new_previous_outstanding numeric(16,2),new_current_outstanding numeric(16,2),
    new_total_outstanding numeric(16,2),current_source text
  ) on commit drop;
  truncate rr_salary_preview_tmp_v786;

  insert into rr_salary_preview_tmp_v786(
    worker_id,worker_name,worker_code,department_code,worker_status,payment_selected,
    gross_previous_outstanding,gross_current_period_payable,advance_opening_balance,
    legacy_advance_recovery,dedicated_advance_recovery,advance_recovery_amount,
    previous_outstanding,current_period_payable,unaccrued_current_amount,
    final_total_payable,scope_payable,new_previous_outstanding,new_current_outstanding,
    new_total_outstanding,current_source
  )
  with base as(
    select c.*,
      coalesce(a.legacy_advance_balance,0)::numeric(16,2) legacy_advance,
      coalesce(a.dedicated_advance_balance,0)::numeric(16,2) dedicated_advance,
      coalesce(a.total_advance_balance,0)::numeric(16,2) total_advance
    from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c
    left join public.rr_worker_advance_balance_v785 a
      on a.data_mode=v_mode and a.worker_id=c.worker_id
  ), calc as(
    select b.*,
      least(b.legacy_advance,b.final_total_payable)::numeric(16,2) legacy_recovery,
      least(b.dedicated_advance,greatest(b.final_total_payable-b.legacy_advance,0))::numeric(16,2) dedicated_recovery,
      greatest(b.previous_outstanding-b.total_advance,0)::numeric(16,2) net_previous,
      greatest(b.current_period_payable-greatest(b.total_advance-b.previous_outstanding,0),0)::numeric(16,2) net_current
    from base b
  )
  select
    c.worker_id,c.worker_name,c.worker_code,c.department_code,c.worker_status,
    (p_worker_ids is null or c.worker_id=any(p_worker_ids)),
    c.previous_outstanding,c.current_period_payable,c.total_advance,
    c.legacy_recovery,c.dedicated_recovery,c.legacy_recovery+c.dedicated_recovery,
    c.net_previous,c.net_current,c.unaccrued_current_amount,
    c.net_previous+c.net_current,
    case when v_scope='OUTSTANDING_ONLY' then c.net_previous
         when v_scope='CURRENT_PERIOD_ONLY' then c.net_current
         else c.net_previous+c.net_current end,
    c.net_previous,c.net_current,c.net_previous+c.net_current,c.current_source
  from calc c
  where c.net_previous+c.net_current>0.005
    and (
      (v_scope='CURRENT_PERIOD_ONLY' and c.net_current>0.005)
      or (v_scope='OUTSTANDING_ONLY' and c.net_previous>0.005)
      or (v_scope='FULL_AND_FINAL' and c.net_previous+c.net_current>0.005)
    );

  if v_scope in('OUTSTANDING_ONLY','FULL_AND_FINAL') then
    insert into rr_salary_preview_tmp_v786(
      worker_id,worker_name,worker_code,department_code,worker_status,payment_selected,
      gross_previous_outstanding,gross_current_period_payable,advance_opening_balance,
      legacy_advance_recovery,dedicated_advance_recovery,advance_recovery_amount,
      previous_outstanding,current_period_payable,unaccrued_current_amount,
      final_total_payable,scope_payable,new_previous_outstanding,new_current_outstanding,
      new_total_outstanding,current_source
    )
    select
      b.worker_id,
      coalesce(nullif(trim(b.worker_name),''),nullif(trim(m.worker_name),''),b.worker_id::text),
      coalesce(nullif(trim(b.worker_code),''),nullif(trim(m.worker_code),'')),
      coalesce(nullif(trim(b.department_code),''),nullif(trim(m.department_code),'')),
      'ACTIVE',(p_worker_ids is null or b.worker_id=any(p_worker_ids)),
      greatest(coalesce(b.outstanding_amount,0),0),0,coalesce(a.total_advance_balance,0),
      least(coalesce(a.legacy_advance_balance,0),greatest(coalesce(b.outstanding_amount,0),0)),
      least(coalesce(a.dedicated_advance_balance,0),
        greatest(greatest(coalesce(b.outstanding_amount,0),0)-coalesce(a.legacy_advance_balance,0),0)),
      least(coalesce(a.total_advance_balance,0),greatest(coalesce(b.outstanding_amount,0),0)),
      greatest(coalesce(b.outstanding_amount,0)-coalesce(a.total_advance_balance,0),0),0,0,
      greatest(coalesce(b.outstanding_amount,0)-coalesce(a.total_advance_balance,0),0),
      greatest(coalesce(b.outstanding_amount,0)-coalesce(a.total_advance_balance,0),0),
      greatest(coalesce(b.outstanding_amount,0)-coalesce(a.total_advance_balance,0),0),0,
      greatest(coalesce(b.outstanding_amount,0)-coalesce(a.total_advance_balance,0),0),
      'LEDGER_OUTSTANDING'
    from public.rr_salary_worker_balance_v782 b
    join lateral(
      select l.worker_name,l.worker_code,l.department_code,upper(coalesce(l.payroll_category,'')) payroll_category
      from public.rr_worker_salary_ledger_v781 l
      where l.data_mode=v_mode and l.worker_id=b.worker_id and l.status='POSTED'
      order by l.created_at desc limit 1
    ) m on true
    left join public.rr_worker_advance_balance_v785 a
      on a.data_mode=v_mode and a.worker_id=b.worker_id
    where b.data_mode=v_mode
      and greatest(coalesce(b.outstanding_amount,0)-coalesce(a.total_advance_balance,0),0)>0.005
      and m.payroll_category=v_category
      and not exists(select 1 from rr_salary_preview_tmp_v786 t where t.worker_id=b.worker_id);
  end if;

  update rr_salary_preview_tmp_v786
  set raw_allocation=0,floor_allocation=0,allocation_remainder=0,amount_paid=0
  where worker_id is not null;

  select coalesce(sum(scope_payable) filter(where payment_selected),0)
  into v_selected_scope from rr_salary_preview_tmp_v786;

  if v_method='PARTIAL_RATIO' and v_selected_scope>0 then
    if v_owner<=0 then null;
    elsif v_owner>v_selected_scope+0.005 then raise exception 'Bulk Amount Payment exceeds Selected Workers Payable.';
    elsif mod(v_owner,v_rounding)<>0 then raise exception 'Ratio Division Payment amount must be a multiple of ₹100.';
    else
      v_ratio:=v_owner/v_selected_scope;
      update rr_salary_preview_tmp_v786
      set raw_allocation=round(scope_payable*v_ratio,6),
          floor_allocation=floor(scope_payable*v_ratio/v_rounding)*v_rounding
      where payment_selected;
      update rr_salary_preview_tmp_v786
      set allocation_remainder=raw_allocation-floor_allocation,amount_paid=floor_allocation
      where payment_selected;
      select coalesce(sum(amount_paid),0) into v_floor_total
      from rr_salary_preview_tmp_v786 where payment_selected;
      v_remaining:=round(v_owner-v_floor_total,2);
      while v_remaining>=v_rounding-0.005 loop
        select t.worker_id into v_worker from rr_salary_preview_tmp_v786 t
        where t.payment_selected and t.amount_paid+v_rounding<=t.scope_payable+0.005
        order by t.allocation_remainder desc,t.scope_payable desc,t.worker_id limit 1;
        if v_worker is null then raise exception '₹100 ratio cannot exactly match this Bulk Amount.'; end if;
        update rr_salary_preview_tmp_v786
        set amount_paid=amount_paid+v_rounding,floor_allocation=amount_paid+v_rounding,allocation_remainder=-1
        where worker_id=v_worker;
        v_remaining:=round(v_remaining-v_rounding,2); v_worker:=null;
      end loop;
      if abs(v_remaining)>0.005 then raise exception 'Unallocated remainder. Use a compatible ₹100 amount.'; end if;
    end if;
  end if;

  if v_method='FULL_PAYMENT' then
    v_ratio:=1;
    update rr_salary_preview_tmp_v786
    set raw_allocation=scope_payable,
        floor_allocation=floor(scope_payable/v_rounding)*v_rounding,
        allocation_remainder=scope_payable-(floor(scope_payable/v_rounding)*v_rounding),
        amount_paid=floor(scope_payable/v_rounding)*v_rounding
    where payment_selected;
    select coalesce(sum(amount_paid),0) into v_owner
    from rr_salary_preview_tmp_v786 where payment_selected;
  end if;

  if v_method='WORKER_LEDGER_WISE' then
    update rr_salary_preview_tmp_v786 t
    set amount_paid=round(greatest(coalesce(x.amount_paid,0),0),2)
    from jsonb_to_recordset(coalesce(p_worker_amounts,'[]'::jsonb)) x(worker_id uuid,amount_paid numeric)
    where t.worker_id=x.worker_id and t.payment_selected;
    if exists(select 1 from rr_salary_preview_tmp_v786 where amount_paid>scope_payable+0.005)
      then raise exception 'Worker Amount Paid cannot exceed Net Payable.'; end if;
    if exists(select 1 from rr_salary_preview_tmp_v786
      where payment_selected and amount_paid>0 and mod(amount_paid,v_rounding)<>0)
      then raise exception 'Selected Worker Payment amount must be a multiple of ₹100.'; end if;
    update rr_salary_preview_tmp_v786
    set raw_allocation=amount_paid,floor_allocation=amount_paid,allocation_remainder=0
    where payment_selected;
    select coalesce(sum(amount_paid),0) into v_owner
    from rr_salary_preview_tmp_v786 where payment_selected;
  end if;

  update rr_salary_preview_tmp_v786
  set outstanding_payment=case when not payment_selected or v_scope='CURRENT_PERIOD_ONLY' then 0
        else least(amount_paid,previous_outstanding) end,
      current_period_payment=case when not payment_selected or v_scope='OUTSTANDING_ONLY' then 0
        when v_scope='CURRENT_PERIOD_ONLY' then least(amount_paid,current_period_payable)
        else greatest(amount_paid-least(amount_paid,previous_outstanding),0) end;

  update rr_salary_preview_tmp_v786
  set new_previous_outstanding=greatest(previous_outstanding-outstanding_payment,0),
      new_current_outstanding=greatest(current_period_payable-current_period_payment,0),
      new_total_outstanding=greatest(previous_outstanding-outstanding_payment,0)
        +greatest(current_period_payable-current_period_payment,0);

  return jsonb_build_object(
    'ok',true,'data_mode',v_mode,'payroll_category',v_category,'payment_method',v_method,'payment_scope',v_scope,
    'period_start',v_start,'period_end',v_end,'period_month',v_month,
    'eligible_worker_count',(select count(*) from rr_salary_preview_tmp_v786),
    'selected_worker_count',(select count(*) from rr_salary_preview_tmp_v786 where payment_selected),
    'advance_worker_count',(select count(*) from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c
      where c.final_total_payable>0 and c.final_total_payable<=coalesce(c.total_advance_balance,0)+0.005),
    'advance_worker_amount',(select round(coalesce(sum(c.total_advance_balance),0),2)
      from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c
      where c.final_total_payable>0 and c.final_total_payable<=coalesce(c.total_advance_balance,0)+0.005),
    'total_gross_payable',(select round(coalesce(sum(gross_previous_outstanding+gross_current_period_payable),0),2) from rr_salary_preview_tmp_v786),
    'total_advance_recovery',(select round(coalesce(sum(advance_recovery_amount) filter(where payment_selected),0),2) from rr_salary_preview_tmp_v786),
    'total_previous_outstanding',(select round(coalesce(sum(previous_outstanding),0),2) from rr_salary_preview_tmp_v786),
    'total_current_period_payable',(select round(coalesce(sum(current_period_payable),0),2) from rr_salary_preview_tmp_v786),
    'total_final_payable',(select round(coalesce(sum(final_total_payable),0),2) from rr_salary_preview_tmp_v786),
    'selected_scope_payable',round(v_selected_scope,2),'bulk_amount_payment',round(v_owner,2),
    'total_outstanding_payment',(select round(coalesce(sum(outstanding_payment),0),2) from rr_salary_preview_tmp_v786),
    'total_current_period_payment',(select round(coalesce(sum(current_period_payment),0),2) from rr_salary_preview_tmp_v786),
    'total_new_outstanding',(select round(coalesce(sum(new_total_outstanding),0),2) from rr_salary_preview_tmp_v786),
    'allocation_ratio',round(v_ratio,10),'rounding_unit',v_rounding,
    'advance_workers',coalesce((select jsonb_agg(to_jsonb(q) order by q.total_advance_balance desc,q.worker_name)
      from(select c.*,greatest(coalesce(c.total_advance_balance,0)-c.final_total_payable,0) amount_needed_for_regular
        from public.rr_salary_current_board_v785(v_category,v_start,v_end,v_mode) c
        where c.final_total_payable>0 and c.final_total_payable<=coalesce(c.total_advance_balance,0)+0.005) q),'[]'::jsonb),
    'lines',coalesce((select jsonb_agg(to_jsonb(t) order by t.final_total_payable desc,t.worker_name,t.worker_id)
      from rr_salary_preview_tmp_v786 t),'[]'::jsonb)
  );
end;
$$;

create or replace function public.rr_salary_payment_post_v786(
  p_payroll_category text,p_period_start date,p_period_end date,p_data_mode text,
  p_payment_method text,p_payment_scope text,p_bulk_amount numeric,p_worker_ids uuid[],p_worker_amounts jsonb,
  p_payment_date date,p_payment_mode text,p_voucher_no text,p_remarks text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
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
    bulk_amount_payment,total_outstanding_payment,total_current_period_payment,total_new_outstanding,
    allocation_ratio,rounding_unit,total_gross_payable,total_advance_recovery,created_by,created_by_name
  ) values(
    v_mode,v_category,v_method,v_scope,v_start,v_end,v_month,p_payment_date,v_paymode,v_voucher,
    nullif(trim(coalesce(p_remarks,'')),''),(v_preview->>'eligible_worker_count')::int,
    (v_preview->>'selected_worker_count')::int,(v_preview->>'advance_worker_count')::int,
    (v_preview->>'total_previous_outstanding')::numeric,(v_preview->>'total_current_period_payable')::numeric,
    (v_preview->>'total_final_payable')::numeric,(v_preview->>'selected_scope_payable')::numeric,
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
    final_total_payable numeric,scope_payable numeric,raw_allocation numeric,floor_allocation numeric,
    allocation_remainder numeric,amount_paid numeric,outstanding_payment numeric,current_period_payment numeric,
    new_previous_outstanding numeric,new_current_outstanding numeric,new_total_outstanding numeric,current_source text
  ) loop
    insert into public.rr_salary_payment_batch_lines_v785(
      batch_id,worker_id,worker_name,worker_code,department_code,worker_status,payment_selected,
      gross_previous_outstanding,gross_current_period_payable,advance_opening_balance,
      legacy_advance_recovery,dedicated_advance_recovery,advance_recovery_amount,
      previous_outstanding,current_period_payable,unaccrued_current_amount,final_total_payable,scope_payable,
      raw_allocation,floor_allocation,allocation_remainder,amount_paid,outstanding_payment,current_period_payment,
      new_previous_outstanding,new_current_outstanding,new_total_outstanding,current_source
    ) values(
      v_batch,r.worker_id,r.worker_name,r.worker_code,r.department_code,r.worker_status,r.payment_selected,
      r.gross_previous_outstanding,r.gross_current_period_payable,r.advance_opening_balance,
      r.legacy_advance_recovery,r.dedicated_advance_recovery,r.advance_recovery_amount,
      r.previous_outstanding,r.current_period_payable,r.unaccrued_current_amount,r.final_total_payable,r.scope_payable,
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
        concat('Current salary accrued · ',r.current_source),auth.uid(),v_actor)
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
      E'\nGross Payable: ₹',to_char(r.gross_previous_outstanding+r.gross_current_period_payable,'FM9999999990.00'),
      E'\nAdvance Adjusted: ₹',to_char(r.advance_recovery_amount,'FM9999999990.00'),
      E'\nNet Payable: ₹',to_char(r.final_total_payable,'FM9999999990.00'),
      E'\nAmount Paid: ₹',to_char(r.amount_paid,'FM9999999990.00'),
      E'\nNew Outstanding: ₹',to_char(r.new_total_outstanding,'FM9999999990.00'),
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
    'total_new_outstanding',(v_preview->>'total_new_outstanding')::numeric,'messages_queued',true);
end;
$$;

create or replace function public.rr_salary_payment_void_v786(p_batch_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_result jsonb; v_actor text; v_reversed numeric(16,2):=0; r record;
begin
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Void reason required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(concat('SALARY_VOID_V786|',p_batch_id),0));

  v_result:=public.rr_salary_payment_void_v785(p_batch_id,p_reason);
  select coalesce(nullif(trim(p.full_name),''),'OWNER') into v_actor
  from public.rr_user_profiles p where p.auth_user_id=auth.uid() limit 1;

  for r in
    select l.*,b.period_month,b.period_start,b.period_end,b.voucher_no,
      x.advance_recovery_ledger_entry_id,x.advance_salary_ledger_entry_id
    from public.rr_salary_payment_batch_lines_v785 x
    join public.rr_salary_payment_batches_v785 b on b.id=x.batch_id
    join public.rr_worker_advance_ledger_v785 l on l.id=x.advance_recovery_ledger_entry_id
    where x.batch_id=p_batch_id and l.status='POSTED'
  loop
    insert into public.rr_worker_advance_ledger_v785(
      data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
      entry_date,entry_type,amount,balance_effect,reference_no,remarks,related_entry_id,
      source_batch_id,source_line_id,created_by,created_by_name)
    values(r.data_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,r.payroll_category,
      current_date,'ADVANCE_REVERSAL',r.amount,r.amount,r.voucher_no,
      concat('Salary payment void: ',trim(p_reason)),r.id,p_batch_id,r.source_line_id,auth.uid(),v_actor)
    on conflict do nothing;

    if r.advance_salary_ledger_entry_id is not null then
      insert into public.rr_worker_salary_ledger_v781(
        data_mode,worker_id,worker_name,worker_code,department_code,payroll_category,
        source_module,source_run_id,source_line_id,source_key,period_month,entry_date,
        entry_type,amount,balance_effect,related_entry_id,reference_no,remarks,
        earning_window_start,earning_window_end,created_by,created_by_name)
      values(r.data_mode,r.worker_id,r.worker_name,r.worker_code,r.department_code,r.payroll_category,
        'ADVANCE_RECOVERY_VOID_V786',p_batch_id,r.source_line_id,
        concat('ADVANCE_RECOVERY_VOID_V786|',r.source_line_id),r.period_month,current_date,
        'MANUAL_CREDIT',r.amount,r.amount,r.advance_salary_ledger_entry_id,r.voucher_no,
        concat('Advance recovery reversed: ',trim(p_reason)),r.period_start,r.period_end,auth.uid(),v_actor)
      on conflict do nothing;
    end if;
    v_reversed:=v_reversed+r.amount;
  end loop;

  return v_result||jsonb_build_object('advance_recovery_reversed',round(v_reversed,2));
end;
$$;

revoke all on function public.rr_salary_payment_preview_v786(text,date,date,text,text,text,numeric,uuid[],jsonb) from public,anon;
revoke all on function public.rr_salary_payment_post_v786(text,date,date,text,text,text,numeric,uuid[],jsonb,date,text,text,text) from public,anon;
revoke all on function public.rr_salary_payment_void_v786(uuid,text) from public,anon;
grant execute on function public.rr_salary_payment_preview_v786(text,date,date,text,text,text,numeric,uuid[],jsonb) to authenticated;
grant execute on function public.rr_salary_payment_post_v786(text,date,date,text,text,text,numeric,uuid[],jsonb,date,text,text,text) to authenticated;
grant execute on function public.rr_salary_payment_void_v786(uuid,text) to authenticated;

commit;

select
  case when
    to_regprocedure('public.rr_salary_payment_preview_v786(text,date,date,text,text,text,numeric,uuid[],jsonb)') is not null
    and to_regprocedure('public.rr_salary_payment_post_v786(text,date,date,text,text,text,numeric,uuid[],jsonb,date,text,text,text)') is not null
    and to_regprocedure('public.rr_salary_payment_void_v786(uuid,text)') is not null
    and to_regclass('public.rr_advance_recovery_source_v786_uidx') is not null
    and exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='rr_salary_payment_batch_lines_v785' and column_name='advance_recovery_amount')
  then 'PASS' else 'FAIL' end as salary_advance_auto_adjust_v786_3_15_result;
