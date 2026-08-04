-- REDZED Piece-Rate Payroll V779.2.5
-- Fixes PostgreSQL error 42803:
-- subquery uses ungrouped column "h.size_code" from outer query
--
-- Safe scope:
--   * Replaces only public.rr_piece_payroll_calculate_v779(date,text)
--   * Preserves all existing payroll data
--   * Does not alter V778 Monthly Payroll
--   * Does not write/alter UPM production tables
--   * Keeps ASSIGNMENT ACTUAL RATE ONLY policy unchanged

begin;

create or replace function public.rr_piece_payroll_calculate_v779(
  p_period_month date,
  p_data_mode text default 'REAL'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_month date:=date_trunc('month',p_period_month)::date;
  v_end date:=(date_trunc('month',p_period_month)+interval '1 month' - interval '1 day')::date;
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL'));
  v_from_ts timestamptz;
  v_to_ts timestamptz;
  v_run public.rr_piece_payroll_runs_v779%rowtype;
  w record;
  src record;
  v_lead jsonb;
  v_comp_mode text;
  v_flat numeric;
  v_enh_type text;
  v_enh_value numeric;
  v_effective_from date;
  v_effective_to date;
  v_active_days integer;
  v_flat_prorated numeric;
  v_rate numeric;
  v_rate_source text;
  v_payable numeric;
  v_enhanced_rate numeric;
  v_base_amount numeric;
  v_enh_amount numeric;
  v_payable_total numeric;
  v_base_total numeric;
  v_enh_total numeric;
  v_rate_weight numeric;
  v_missing_rate integer;
  v_missing_cap integer;
  v_adj_earning numeric;
  v_adj_deduction numeric;
  v_advance numeric;
  v_present numeric;
  v_absent numeric;
  v_half numeric;
  v_incomplete integer;
  v_damage_rows integer;
  v_damage_amount numeric;
  v_gross numeric;
  v_deduction numeric;
  v_net numeric;
  v_source_key text;
  v_mapping text;
begin
  if not public.rr_piece_has_action_v779('salary.pcs.calculate') then raise exception 'Piece payroll calculate permission required.'; end if;
  if p_period_month is null then raise exception 'Payroll month required.'; end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Invalid Data Mode.'; end if;
  if to_regclass('public.rr_upm_department_handoffs_v727') is null then raise exception 'Required UPM handoff ledger missing.'; end if;
  if to_regclass('public.rr_upm_work_assignments_v8') is null then raise exception 'Required UPM assignment table missing.'; end if;

  v_from_ts:=(v_month::timestamp at time zone 'Asia/Kolkata');
  v_to_ts:=((v_end+1)::timestamp at time zone 'Asia/Kolkata');

  select * into v_run from public.rr_piece_payroll_runs_v779
  where period_month=v_month and data_mode=v_mode for update;
  if found and v_run.status in ('APPROVED','PAID') then
    raise exception 'Piece payroll is approved/paid. Owner must reopen before recalculation.';
  end if;

  insert into public.rr_piece_payroll_runs_v779(
    period_month,period_end,data_mode,status,calculated_by,calculated_at,updated_at
  ) values(v_month,v_end,v_mode,'CALCULATED',auth.uid(),now(),now())
  on conflict(period_month,data_mode) do update set
    period_end=excluded.period_end,status='CALCULATED',calculated_by=auth.uid(),calculated_at=now(),
    approved_by=null,approved_at=null,approval_reason=null,
    paid_by=null,paid_at=null,payment_reference=null,updated_at=now()
  returning * into v_run;

  delete from public.rr_piece_payroll_details_v779 where piece_run_id=v_run.id;
  delete from public.rr_piece_payroll_run_lines_v779 where piece_run_id=v_run.id;
  update public.rr_piece_adjustments_v779 set included_piece_run_id=null where included_piece_run_id=v_run.id;

  for w in
    select distinct on(x.worker_id) x.*
    from public.rr_worker_payroll_board_v777_3 x
    where upper(coalesce(x.data_mode,'TEST'))=v_mode
      and public.rr_piece_category_normalize_v779(x.worker_category)='PIECE_RATE'
      and coalesce(x.effective_from,v_end)<=v_end
      and coalesce(x.effective_to,v_month)>=v_month
    order by x.worker_id,x.effective_from desc nulls last
  loop
    v_effective_from:=greatest(v_month,coalesce(w.effective_from,v_month));
    v_effective_to:=least(v_end,coalesce(w.effective_to,v_end));
    v_active_days:=greatest(0,(v_effective_to-v_effective_from)+1);
    v_lead:=public.rr_piece_leadership_profile_v779(w.worker_id,v_end);
    v_comp_mode:=upper(coalesce(v_lead->>'compensation_mode','PCS_ONLY'));
    v_flat:=greatest(0,coalesce(nullif(v_lead->>'monthly_flat_incentive','')::numeric,0));
    v_enh_type:=upper(coalesce(v_lead->>'rate_enhancement_type','NONE'));
    v_enh_value:=greatest(0,coalesce(nullif(v_lead->>'rate_enhancement_value','')::numeric,0));

    if v_comp_mode not in ('PCS_ONLY','PCS_PLUS_FLAT','PCS_PLUS_RATE','PCS_PLUS_FLAT_RATE') then v_comp_mode:='PCS_ONLY'; end if;
    if v_comp_mode not in ('PCS_PLUS_RATE','PCS_PLUS_FLAT_RATE') then v_enh_type:='NONE'; v_enh_value:=0; end if;
    if v_comp_mode in ('PCS_PLUS_FLAT','PCS_PLUS_FLAT_RATE') then
      v_flat_prorated:=round(v_flat*v_active_days/30.0,2);
    else
      v_flat_prorated:=0;
    end if;

    v_payable_total:=0;v_base_total:=0;v_enh_total:=0;v_rate_weight:=0;
    v_missing_rate:=0;v_missing_cap:=0;

    for src in
      with handoff_rollup as (
        select
          h.assignment_id,
          h.canonical_lot_id,
          max(h.lot_no) as lot_no,
          max(h.from_department_code) as department_code,
          max(h.to_department_code) as to_department_code,
          max(h.colour_code) as colour_code,
          max(h.colour_name) as colour_name,
          upper(h.size_code) as size_code,
          min(h.created_at) filter(where h.created_at>=v_from_ts and h.created_at<v_to_ts) as first_month_source_at,
          max(h.created_at) filter(where h.created_at>=v_from_ts and h.created_at<v_to_ts) as last_month_source_at,
          coalesce(sum(h.qty) filter(where h.created_at<v_from_ts),0)::numeric as submitted_before_qty,
          coalesce(sum(h.qty) filter(where h.created_at<v_to_ts),0)::numeric as submitted_to_end_qty
        from public.rr_upm_department_handoffs_v727 h
        where h.worker_id=w.worker_id
          and h.created_at>=((v_effective_from)::timestamp at time zone 'Asia/Kolkata')
          and h.created_at<least(v_to_ts,((v_effective_to+1)::timestamp at time zone 'Asia/Kolkata'))
        group by h.assignment_id,h.canonical_lot_id,upper(h.size_code)
        having coalesce(sum(h.qty) filter(where h.created_at>=v_from_ts and h.created_at<v_to_ts),0)>0
      )
      select
        r.assignment_id,
        r.canonical_lot_id,
        r.lot_no,
        r.department_code,
        r.to_department_code,
        r.colour_code,
        r.colour_name,
        r.size_code,
        r.first_month_source_at,
        r.last_month_source_at,
        r.submitted_before_qty,
        r.submitted_to_end_qty,
        case
          when jsonb_typeof(a.size_breakup)='array' and jsonb_array_length(a.size_breakup)>0 then
            nullif((
              select coalesce(sum(coalesce(nullif(e->>'qty','')::numeric,0)),0)
              from jsonb_array_elements(a.size_breakup) e
              where upper(coalesce(e->>'size_code',''))=r.size_code
            ),0)
          else nullif(a.assigned_qty,0)
        end::numeric as assigned_cap_qty,
        to_jsonb(a) as assignment_snapshot
      from handoff_rollup r
      join public.rr_upm_work_assignments_v8 a on a.id=r.assignment_id
    loop
      v_mapping:='OK';
      if src.assigned_cap_qty is null or src.assigned_cap_qty<=0 then
        v_payable:=0;v_missing_cap:=v_missing_cap+1;v_mapping:='MISSING_SIZE_CAP';
      else
        v_payable:=greatest(
          least(src.submitted_to_end_qty,src.assigned_cap_qty)
          -least(src.submitted_before_qty,src.assigned_cap_qty),0
        );
      end if;

      select resolved_rate,rate_source into v_rate,v_rate_source
      from public.rr_piece_resolve_rate_v779(src.assignment_id,src.canonical_lot_id,src.department_code)
      limit 1;

      if coalesce(v_rate,0)<=0 then
        v_rate:=0;
        if v_payable>0 then
          v_missing_rate:=v_missing_rate+1;
          if v_mapping='OK' then v_mapping:='MISSING_ACTUAL_RATE'; end if;
        end if;
      end if;

      if v_enh_type='FLAT_PER_PCS' then
        v_enhanced_rate:=v_rate+v_enh_value;
      elsif v_enh_type='PERCENT' then
        v_enhanced_rate:=v_rate*(1+(v_enh_value/100.0));
      else
        v_enhanced_rate:=v_rate;
      end if;

      v_base_amount:=round(v_payable*v_rate,2);
      v_enh_amount:=round(v_payable*greatest(v_enhanced_rate-v_rate,0),2);
      v_source_key:=md5(concat_ws('|',src.assignment_id,src.canonical_lot_id,src.department_code,src.size_code,v_month));

      insert into public.rr_piece_payroll_details_v779(
        piece_run_id,worker_id,source_key,assignment_id,canonical_lot_id,lot_no,
        department_code,to_department_code,colour_code,colour_name,size_code,
        assigned_cap_qty,submitted_before_qty,submitted_to_end_qty,payable_qty,
        base_rate,rate_source,enhancement_type,enhancement_value,enhanced_rate,
        base_amount,enhancement_amount,mapping_status,first_source_at,last_source_at,source_snapshot
      ) values(
        v_run.id,w.worker_id,v_source_key,src.assignment_id,src.canonical_lot_id,src.lot_no,
        src.department_code,src.to_department_code,src.colour_code,src.colour_name,src.size_code,
        src.assigned_cap_qty,src.submitted_before_qty,src.submitted_to_end_qty,v_payable,
        v_rate,v_rate_source,v_enh_type,v_enh_value,round(v_enhanced_rate,4),
        v_base_amount,v_enh_amount,v_mapping,src.first_month_source_at,src.last_month_source_at,
        jsonb_build_object('assignment',src.assignment_snapshot,'formula_version','V779.2_ACTUAL_ONLY','cap_rule','CUMULATIVE_HANDOFF_LESS_PRIOR_CAPPED_TO_ASSIGNMENT_SIZE')
      );

      v_payable_total:=v_payable_total+v_payable;
      v_base_total:=v_base_total+v_base_amount;
      v_enh_total:=v_enh_total+v_enh_amount;
      v_rate_weight:=v_rate_weight+(v_payable*v_rate);
    end loop;

    select
      coalesce(sum(amount) filter(where adjustment_type in ('EARNING','BONUS','INCENTIVE','OTHER')),0),
      coalesce(sum(amount) filter(where adjustment_type in ('DEDUCTION','FINE','DAMAGE_DEBIT')),0),
      coalesce(sum(amount) filter(where adjustment_type='ADVANCE'),0)
    into v_adj_earning,v_adj_deduction,v_advance
    from public.rr_piece_adjustments_v779
    where worker_id=w.worker_id and period_month=v_month and data_mode=v_mode and status='POSTED';

    select
      count(*) filter(where status='PRESENT')::numeric,
      count(*) filter(where status='ABSENT')::numeric,
      count(*) filter(where status='HALF_DAY')::numeric,
      count(*) filter(where status='INCOMPLETE')::integer
    into v_present,v_absent,v_half,v_incomplete
    from public.rr_piece_attendance_day_v779
    where worker_id=w.worker_id and data_mode=v_mode and attendance_date between v_effective_from and v_effective_to;

    v_damage_rows:=0;v_damage_amount:=0;
    if to_regclass('public.rr_upm_worker_ledger_v726') is not null then
      begin
        execute $q$
          select count(*)::integer,coalesce(sum(abs(coalesce(amount,qty*actual_rate,0))),0)::numeric
          from public.rr_upm_worker_ledger_v726
          where worker_id=$1 and upper(action_type)='DAMAGE'
            and created_at>=$2 and created_at<$3
        $q$ into v_damage_rows,v_damage_amount using w.worker_id,v_from_ts,v_to_ts;
      exception when others then
        v_damage_rows:=0;v_damage_amount:=0;
      end;
    end if;

    v_gross:=round(v_base_total+v_enh_total+v_flat_prorated+v_adj_earning,2);
    v_deduction:=round(v_adj_deduction+v_advance,2);
    v_net:=greatest(0,round(v_gross-v_deduction,2));

    insert into public.rr_piece_payroll_run_lines_v779(
      piece_run_id,worker_id,worker_name,worker_code,department_code,
      payroll_profile_snapshot,leadership_snapshot,compensation_mode,
      payable_qty,average_base_rate,base_piece_earning,rate_enhancement_earning,
      monthly_flat_incentive,adjustment_earning,adjustment_deduction,advance_deduction,
      damage_reference_rows,damage_reference_amount,
      attendance_present_days,attendance_absent_days,attendance_half_days,attendance_incomplete_days,
      missing_rate_rows,missing_cap_rows,gross_pay,total_deduction,net_pay,calculation_breakdown
    ) values(
      v_run.id,w.worker_id,w.worker_name,w.worker_code,w.department_code,
      to_jsonb(w),v_lead,v_comp_mode,
      round(v_payable_total,3),case when v_payable_total>0 then round(v_rate_weight/v_payable_total,4) else 0 end,
      round(v_base_total,2),round(v_enh_total,2),v_flat_prorated,
      round(v_adj_earning,2),round(v_adj_deduction,2),round(v_advance,2),
      coalesce(v_damage_rows,0),round(coalesce(v_damage_amount,0),2),
      coalesce(v_present,0),coalesce(v_absent,0),coalesce(v_half,0),coalesce(v_incomplete,0),
      v_missing_rate,v_missing_cap,v_gross,v_deduction,v_net,
      jsonb_build_object(
        'formula_version','V779.2_ACTUAL_ONLY',
        'source','rr_upm_department_handoffs_v727',
        'rate_policy','ASSIGNMENT_ACTUAL_ONLY_NO_FALLBACK',
        'double_pay_protection','Cumulative submitted PCS capped to assignment size; prior-period payable subtracted',
        'attendance_effect','INFORMATIONAL_ONLY',
        'damage_effect','REFERENCE_ONLY_UNTIL_POSTED_AS_AUDITED_DAMAGE_DEBIT',
        'effective_from',v_effective_from,'effective_to',v_effective_to,
        'active_days',v_active_days
      )
    );
  end loop;

  update public.rr_piece_adjustments_v779 set included_piece_run_id=v_run.id
  where period_month=v_month and data_mode=v_mode and status='POSTED';

  update public.rr_piece_payroll_runs_v779 r set
    worker_count=x.worker_count,
    incomplete_worker_count=x.incomplete_worker_count,
    total_payable_qty=x.total_payable_qty,
    gross_total=x.gross_total,
    deduction_total=x.deduction_total,
    net_total=x.net_total,
    status='CALCULATED',updated_at=now()
  from(
    select count(*)::integer as worker_count,
      count(*) filter(where missing_rate_rows>0 or missing_cap_rows>0)::integer as incomplete_worker_count,
      coalesce(sum(payable_qty),0)::numeric as total_payable_qty,
      coalesce(sum(gross_pay),0)::numeric as gross_total,
      coalesce(sum(total_deduction),0)::numeric as deduction_total,
      coalesce(sum(net_pay),0)::numeric as net_total
    from public.rr_piece_payroll_run_lines_v779 where piece_run_id=v_run.id
  ) x where r.id=v_run.id;

  return v_run.id;
end;
$$;

comment on function public.rr_piece_payroll_calculate_v779(date,text) is
'V779.2.5: Actual-rate-only PCS payroll; handoffs pre-aggregated by assignment/lot/size before size-cap lookup, preventing SQLSTATE 42803.';

commit;

with function_check as (
  select pg_get_functiondef(
    'public.rr_piece_payroll_calculate_v779(date,text)'::regprocedure::oid
  ) as definition
)
select
  case
    when to_regprocedure('public.rr_piece_payroll_calculate_v779(date,text)') is null then 'FAIL'
    when position('with handoff_rollup as' in lower(definition))=0 then 'FAIL'
    when position('whereupper(coalesce(e->>''size_code'',''''))=upper(h.size_code)' in lower(replace(replace(definition,' ',''),chr(10),'')))>0 then 'FAIL'
    else 'PASS'
  end as size_group_fix_result,
  (position('with handoff_rollup as' in lower(definition))>0) as preaggregation_present,
  (position('assignment_actual_only' in lower(definition))>0) as actual_rate_only_present
from function_check;
