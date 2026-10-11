CREATE OR REPLACE FUNCTION public.rr_salary_monthly_earned_v782(p_worker_id uuid, p_cutoff_date date, p_data_mode text)
 RETURNS TABLE(worker_id uuid, worker_name text, worker_code text, department_code text, monthly_salary numeric, earned_to_cutoff numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL'));
  v_month date:=date_trunc('month',p_cutoff_date)::date;
  v_profile record;
  v_shift record;
  v_start date;
  v_daily_rate numeric;
  v_minute_rate numeric;
  v_grace integer:=10;
  v_normal_minutes integer:=600;
  v_earned numeric:=0;
  v_days int;v_missing int;v_contracts int;v_contract numeric;v_base numeric;v_ded int;v_extra int;v_calc jsonb;
begin
  IF v_mode='TEST' THEN
   IF auth.uid() IS NULL OR NOT public.rr_worker_salary_can_view_v781() THEN RAISE EXCEPTION 'Salary view permission required.' USING ERRCODE='42501';END IF;
   IF p_cutoff_date IS NULL OR p_cutoff_date>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Valid non-future salary cutoff required.';END IF;
   SELECT count(*),count(*) FILTER(WHERE d.attendance_day_id IS NULL OR d.approval_status<>'APPROVED' OR d.attendance_status IN('PENDING','REVIEW_REQUIRED') OR d.profile_id IS DISTINCT FROM a.profile_id),count(DISTINCT a.monthly_salary),max(a.monthly_salary),coalesce(sum(d.net_deduction_minutes),0),coalesce(sum(d.net_extra_work_minutes),0)
   INTO v_days,v_missing,v_contracts,v_contract,v_ded,v_extra
   FROM generate_series(v_month::timestamp,p_cutoff_date::timestamp,interval '1 day') g(dt)
   CROSS JOIN LATERAL public.rr_active_payroll_profile_v778_2(p_worker_id,g.dt::date,'TEST') a
   LEFT JOIN public.rr_attendance_day_v777_2 d ON d.worker_id=p_worker_id AND d.attendance_date=g.dt::date AND d.data_mode='TEST'
   WHERE a.profile_id IS NOT NULL AND a.worker_category='SALARIED';
   IF v_days=0 THEN RETURN;END IF;
   IF v_missing>0 THEN RAISE EXCEPTION 'Attendance incomplete: % of % active salary days unresolved.',v_missing,v_days;END IF;
   IF v_contracts<>1 THEN RAISE EXCEPTION 'Salary contract changes within month require reviewed segmented payroll.';END IF;
   v_base:=CASE WHEN p_cutoff_date=(v_month+interval '1 month'-interval '1 day')::date AND v_days=(p_cutoff_date-v_month+1) THEN v_contract ELSE round(v_contract*v_days/30.0,2) END;
   v_calc:=public.rr_calculate_monthly_salary_v779_1(v_contract,v_ded,v_extra,0,0);
   v_earned:=greatest(0,round(greatest(v_base-(v_calc->>'deduction_amount')::numeric,0)+(v_calc->>'net_extra_work_amount')::numeric,2));
   RETURN QUERY SELECT b.worker_id,b.worker_name,b.worker_code,b.department_code,v_contract,v_earned
    FROM public.rr_worker_payroll_board_v777_3 b WHERE b.worker_id=p_worker_id AND upper(coalesce(b.data_mode,'TEST'))='TEST' AND upper(b.worker_category)='SALARIED' AND b.effective_from<=p_cutoff_date AND coalesce(b.effective_to,p_cutoff_date)>=v_month ORDER BY b.effective_from DESC LIMIT 1;
   RETURN;
  END IF;
  select distinct on(x.worker_id)
    x.*
  into v_profile
  from public.rr_worker_payroll_board_v777_3 x
  where x.worker_id=p_worker_id
    and upper(coalesce(x.data_mode,'TEST'))=v_mode
    and upper(coalesce(x.worker_category,''))='SALARIED'
    and coalesce(x.effective_from,p_cutoff_date)<=p_cutoff_date
    and coalesce(x.effective_to,p_cutoff_date)>=v_month
  order by x.worker_id,x.effective_from desc nulls last;

  if not found or coalesce(v_profile.monthly_salary,0)<=0 then
    return;
  end if;

  select s.*
  into v_shift
  from public.rr_shift_options_v777_3 s
  where s.shift_id=v_profile.shift_id
  limit 1;

  v_start:=greatest(
    v_month,
    coalesce(v_profile.effective_from,v_month)
  );

  if v_start>p_cutoff_date then
    return;
  end if;

  v_daily_rate:=coalesce(v_profile.monthly_salary,0)::numeric/30.0;
  v_normal_minutes:=greatest(
    1,
    coalesce(v_shift.normal_payable_minutes,600)::integer
  );
  v_minute_rate:=v_daily_rate/v_normal_minutes;

  with calendar as(
    select d::date as work_date
    from generate_series(
      v_start,
      p_cutoff_date,
      interval '1 day'
    ) d
  ),
  day_data as(
    select
      c.work_date,
      coalesce(
        a.status,
        case
          when h.holiday_date is not null then 'HOLIDAY'
          when extract(isodow from c.work_date)=1 then 'WEEKLY_OFF'
          else 'ABSENT'
        end
      ) as status,

      coalesce(
        a.is_weekly_off,
        extract(isodow from c.work_date)=1
      ) as is_weekly_off,

      coalesce(
        a.is_holiday,
        h.holiday_date is not null
      ) as is_holiday,

      coalesce(h.extra_pay_factor,0.50) as holiday_factor,

      greatest(
        0,
        coalesce(
          floor(
            extract(
              epoch from(
                a.check_in_at-a.shift_start_at
              )
            )/60
          ),
          0
        )
      )::integer as raw_late,

      (
        greatest(
          0,
          coalesce(
            floor(
              extract(
                epoch from(
                  a.shift_start_at-a.check_in_at
                )
              )/60
            ),
            0
          )
        )
        +
        greatest(
          0,
          coalesce(
            floor(
              extract(
                epoch from(
                  a.check_out_at-a.shift_end_at
                )
              )/60
            ),
            0
          )
        )
      )::integer as raw_ot

    from calendar c

    left join public.rr_attendance_day_v778 a
      on a.worker_id=p_worker_id
     and a.attendance_date=c.work_date
     and a.data_mode=v_mode

    left join public.rr_payroll_holidays_v778 h
      on h.holiday_date=c.work_date
     and h.is_active
  ),
  calc as(
    select
      *,
      case
        when status in(
          'PRESENT',
          'LEAVE_PAID',
          'WEEKLY_OFF',
          'HOLIDAY'
        ) then 1.0
        when status='HALF_DAY' then 0.5
        else 0
      end::numeric as earned_day_factor,

      case
        when status='PRESENT'
         and coalesce(
           v_profile.late_deduction_applicable,
           true
         )
          then greatest(raw_late-v_grace,0)
        else 0
      end as deductible_late,

      case
        when status='PRESENT'
         and coalesce(
           v_profile.overtime_applicable,
           true
         )
          then greatest(
            raw_ot
            -
            case
              when coalesce(
                v_profile.grace_offset_against_ot,
                true
              )
                then least(
                  raw_ot,
                  least(raw_late,v_grace)
                )
              else 0
            end,
            0
          )
        else 0
      end as payable_ot
    from day_data
  )
  select greatest(
    0,
    round(
      coalesce(sum(earned_day_factor),0)*v_daily_rate
      -coalesce(sum(deductible_late),0)*v_minute_rate
      +coalesce(sum(payable_ot),0)*v_minute_rate
      +coalesce(sum(
        case
          when status='PRESENT'
           and (is_weekly_off or is_holiday)
           and coalesce(
             v_profile.holiday_extra_applicable,
             true
           )
            then holiday_factor*v_daily_rate
          else 0
        end
      ),0),
      2
    )
  )
  into v_earned
  from calc;

  return query
  select
    v_profile.worker_id,
    v_profile.worker_name,
    v_profile.worker_code,
    v_profile.department_code,
    coalesce(v_profile.monthly_salary,0)::numeric,
    v_earned::numeric;
end;
$function$
;
REVOKE ALL ON FUNCTION public.rr_salary_monthly_earned_v782(uuid,date,text) FROM PUBLIC,anon;
