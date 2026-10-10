-- Future attendance is not an earned/absent day; past TEST rehearsal remains allowed.
CREATE OR REPLACE FUNCTION public.rr_attendance_save_v778(p_worker_id uuid, p_attendance_date date, p_check_in_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_check_out_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status text DEFAULT 'AUTO'::text, p_is_holiday boolean DEFAULT false, p_source_type text DEFAULT 'MANUAL'::text, p_remarks text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_data_mode text DEFAULT 'REAL'::text)
 RETURNS rr_attendance_day_v778
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL'));
  v_status text:=upper(coalesce(nullif(trim(p_status),''),'AUTO'));
  v_source text:=upper(coalesce(nullif(trim(p_source_type),''),'MANUAL'));
  v_reason text:=nullif(trim(p_reason),'');
  v_profile record;
  v_shift record;
  v_old public.rr_attendance_day_v778%rowtype;
  v_new public.rr_attendance_day_v778%rowtype;
  v_weekly_off boolean;
  v_holiday boolean;
  v_shift_start timestamptz;
  v_shift_end timestamptz;
  v_action text;
begin
  if p_attendance_date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'Future attendance cannot be marked or calculated.'; end if;
  if not public.rr_payroll_can_manage_v778() then
    raise exception 'Payroll/Attendance manage permission required.';
  end if;
  if p_worker_id is null or p_attendance_date is null then
    raise exception 'Worker and Attendance Date are required.';
  end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Invalid Data Mode.'; end if;
  if v_source not in ('MANUAL','BIOMETRIC','WHATSAPP','IMPORT','CORRECTION') then
    raise exception 'Invalid Attendance Source.';
  end if;
  if v_reason is null or length(v_reason)<5 then
    raise exception 'Audit reason minimum 5 characters required.';
  end if;

  if exists (
    select 1
    from public.rr_payroll_runs_v778 r
    join public.rr_payroll_run_lines_v778 l on l.payroll_run_id=r.id
    where l.worker_id=p_worker_id
      and r.data_mode=v_mode
      and p_attendance_date between r.period_month and r.period_end
      and r.status in ('APPROVED','PAID')
  ) then
    raise exception 'Attendance is locked by approved/paid payroll. Owner must reopen payroll first.';
  end if;

  select x.* into v_profile
  from public.rr_worker_payroll_board_v777_3 x
  where x.worker_id=p_worker_id
    and upper(coalesce(x.data_mode,'TEST'))=v_mode
    and upper(coalesce(x.worker_category,''))='SALARIED'
    and p_attendance_date>=coalesce(x.effective_from,p_attendance_date)
    and p_attendance_date<=coalesce(x.effective_to,p_attendance_date)
  order by x.effective_from desc nulls last
  limit 1;
  if not found then
    raise exception 'Active SALARIED payroll profile not found for this worker/date/data mode.';
  end if;

  select s.* into v_shift
  from public.rr_shift_options_v777_3 s
  where s.shift_id=v_profile.shift_id
  limit 1;
  if not found then raise exception 'Active payroll shift not found.'; end if;

  v_shift_start:=((p_attendance_date + (v_shift.duty_start::time))::timestamp at time zone 'Asia/Kolkata');
  v_shift_end:=((p_attendance_date + (v_shift.duty_end::time))::timestamp at time zone 'Asia/Kolkata');
  if v_shift_end<=v_shift_start then v_shift_end:=v_shift_end+interval '1 day'; end if;

  v_weekly_off:=extract(isodow from p_attendance_date)=1;
  v_holiday:=coalesce(p_is_holiday,false) or exists(
    select 1 from public.rr_payroll_holidays_v778 h
    where h.holiday_date=p_attendance_date and h.is_active
  );

  if p_check_in_at is not null and p_check_out_at is not null and p_check_out_at<p_check_in_at then
    raise exception 'Check-out cannot be earlier than check-in.';
  end if;

  if v_status='AUTO' then
    if p_check_in_at is not null and p_check_out_at is not null then v_status:='PRESENT';
    elsif p_check_in_at is not null or p_check_out_at is not null then v_status:='INCOMPLETE';
    elsif v_holiday then v_status:='HOLIDAY';
    elsif v_weekly_off then v_status:='WEEKLY_OFF';
    else v_status:='ABSENT';
    end if;
  end if;

  if v_status not in ('PRESENT','ABSENT','HALF_DAY','LEAVE_PAID','LEAVE_UNPAID','WEEKLY_OFF','HOLIDAY','INCOMPLETE') then
    raise exception 'Invalid Attendance Status.';
  end if;
  if v_status in ('PRESENT','HALF_DAY') and (p_check_in_at is null or p_check_out_at is null) then
    raise exception 'Present/Half Day requires both Check-in and Check-out.';
  end if;
  if v_status='INCOMPLETE' and not ((p_check_in_at is null) <> (p_check_out_at is null)) then
    raise exception 'Incomplete status requires exactly one punch.';
  end if;

  select * into v_old
  from public.rr_attendance_day_v778
  where worker_id=p_worker_id and attendance_date=p_attendance_date and data_mode=v_mode
  for update;

  if found then
    v_action:='UPDATE';
    update public.rr_attendance_day_v778
    set shift_start_at=v_shift_start,
        shift_end_at=v_shift_end,
        check_in_at=p_check_in_at,
        check_out_at=p_check_out_at,
        status=v_status,
        is_weekly_off=v_weekly_off,
        is_holiday=v_holiday,
        source_type=v_source,
        remarks=nullif(trim(p_remarks),''),
        correction_reason=v_reason,
        revision_no=revision_no+1,
        updated_by=auth.uid(),
        updated_at=now()
    where id=v_old.id
    returning * into v_new;
  else
    v_action:='CREATE';
    insert into public.rr_attendance_day_v778(
      worker_id,attendance_date,data_mode,shift_start_at,shift_end_at,
      check_in_at,check_out_at,status,is_weekly_off,is_holiday,source_type,
      remarks,correction_reason,created_by,updated_by
    ) values (
      p_worker_id,p_attendance_date,v_mode,v_shift_start,v_shift_end,
      p_check_in_at,p_check_out_at,v_status,v_weekly_off,v_holiday,v_source,
      nullif(trim(p_remarks),''),v_reason,auth.uid(),auth.uid()
    ) returning * into v_new;
  end if;

  insert into public.rr_attendance_audit_v778(
    attendance_id,worker_id,attendance_date,data_mode,action_code,
    before_data,after_data,reason,actor_user_id
  ) values (
    v_new.id,p_worker_id,p_attendance_date,v_mode,v_action,
    case when v_action='UPDATE' then to_jsonb(v_old) else null end,
    to_jsonb(v_new),v_reason,auth.uid()
  );

  return v_new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_calculate_attendance_day_v778_2(p_worker_id uuid, p_business_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_regular public.rr_regular_attendance_sessions_v778_2%rowtype;
  v_checkin_local timestamp;
  v_checkout_local timestamp;
  v_early_in integer:=0;
  v_late_in integer:=0;
  v_early_out integer:=0;
  v_ot integer:=0;
  v_holiday integer:=0;
  v_net integer:=0;
  v_status text:='PENDING';
begin
  if p_business_date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'Future attendance cannot be marked or calculated.'; end if;
  select * into v_policy
  from public.rr_current_attendance_policy_v778_2(
    p_worker_id,p_business_date,v_mode
  );

  if exists(
    select 1
    from public.rr_worker_leave_requests_v778_2 l
    where l.worker_id=p_worker_id
      and l.status='APPROVED'
      and p_business_date between l.leave_from and l.leave_to
      and l.data_mode=v_mode
  ) then
    v_status:='ON_LEAVE';
  end if;

  select * into v_regular
  from public.rr_regular_attendance_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=p_business_date
    and data_mode=v_mode
  limit 1;

  if found then
    v_checkin_local:=v_regular.checkin_at at time zone 'Asia/Kolkata';
    v_checkout_local:=v_regular.checkout_at at time zone 'Asia/Kolkata';

    if v_policy.early_checkin_payable
       and v_checkin_local::time<time '10:00'
    then
      v_early_in:=floor(extract(epoch from(
        (p_business_date+time '10:00')-v_checkin_local
      ))/60)::integer;
    end if;

    if v_checkin_local::time>time '10:10' then
      v_late_in:=floor(extract(epoch from(
        v_checkin_local-(p_business_date+time '10:10')
      ))/60)::integer;
    end if;

    if v_checkout_local is not null
       and v_checkout_local::time<time '20:00'
    then
      v_early_out:=floor(extract(epoch from(
        (p_business_date+time '20:00')-v_checkout_local
      ))/60)::integer;
    end if;

    v_status:=case
      when v_regular.checkout_at is null then 'REVIEW_REQUIRED'
      else 'PRESENT'
    end;
  elsif v_status<>'ON_LEAVE' then
    v_status:='ABSENT';
  end if;

  select coalesce(sum(payable_minutes),0)
  into v_ot
  from public.rr_ot_work_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=p_business_date
    and work_type='REGULAR_OT'
    and status='COMPLETED'
    and payable_eligible
    and data_mode=v_mode;

  select coalesce(sum(payable_minutes),0)
  into v_holiday
  from public.rr_ot_work_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=p_business_date
    and work_type='HOLIDAY_WORK'
    and status='COMPLETED'
    and payable_eligible
    and data_mode=v_mode;

  if coalesce(v_regular.ot_hard_zero,false) then v_ot:=0; end if;

  v_net:=v_early_in+v_ot+v_holiday-v_late_in-v_early_out;

  insert into public.rr_attendance_daily_minutes_v778_2(
    worker_id,business_date,
    regular_checkin_at,regular_checkout_at,
    early_checkin_minutes,late_checkin_minutes,early_checkout_minutes,
    verified_ot_minutes,verified_holiday_minutes,
    net_adjustment_minutes,attendance_status,
    forgot_checkout,outside_checkout,data_mode,calculated_at
  )
  values(
    p_worker_id,p_business_date,
    v_regular.checkin_at,v_regular.checkout_at,
    v_early_in,v_late_in,v_early_out,
    v_ot,v_holiday,v_net,v_status,
    coalesce(v_regular.forgot_checkout,false),
    coalesce(v_regular.checkout_inside_geofence=false,false),
    v_mode,now()
  )
  on conflict(worker_id,business_date,data_mode) do update set
    regular_checkin_at=excluded.regular_checkin_at,
    regular_checkout_at=excluded.regular_checkout_at,
    early_checkin_minutes=excluded.early_checkin_minutes,
    late_checkin_minutes=excluded.late_checkin_minutes,
    early_checkout_minutes=excluded.early_checkout_minutes,
    verified_ot_minutes=excluded.verified_ot_minutes,
    verified_holiday_minutes=excluded.verified_holiday_minutes,
    net_adjustment_minutes=excluded.net_adjustment_minutes,
    attendance_status=excluded.attendance_status,
    forgot_checkout=excluded.forgot_checkout,
    outside_checkout=excluded.outside_checkout,
    calculated_at=now();

  return jsonb_build_object(
    'ok',true,
    'worker_id',p_worker_id,
    'business_date',p_business_date,
    'early_checkin_minutes',v_early_in,
    'late_checkin_minutes',v_late_in,
    'early_checkout_minutes',v_early_out,
    'verified_ot_minutes',v_ot,
    'verified_holiday_minutes',v_holiday,
    'net_adjustment_minutes',v_net,
    'attendance_status',v_status
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_recalculate_attendance_day_v778_2(p_worker_id uuid, p_attendance_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_profile public.rr_worker_payroll_profile_v777_2%rowtype;
  v_shift public.rr_shift_master_v777_2%rowtype;
  v_leave public.rr_worker_leave_v778_2%rowtype;
  v_first_in timestamptz;
  v_last_out timestamptz;
  v_in_local timestamp;
  v_out_local timestamp;
  v_shift_start timestamp;
  v_shift_end timestamp;
  v_gross integer:=0;
  v_scheduled integer:=600;
  v_grace_used integer:=0;
  v_late integer:=0;
  v_early integer:=0;
  v_extra integer:=0;
  v_deduction integer:=0;
  v_working integer:=0;
  v_paid_leave integer:=0;
  v_unpaid_leave integer:=0;
  v_holiday boolean:=false;
  v_status text:='PENDING';
  v_id uuid;
begin
  if p_attendance_date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'Future attendance cannot be marked or calculated.'; end if;
  select * into v_profile
  from public.rr_active_payroll_profile_v778_2(
    p_worker_id,p_attendance_date,v_mode
  );

  if v_profile.profile_id is null or v_profile.worker_category<>'SALARIED' then
    raise exception 'Active SALARIED payroll profile required hai.';
  end if;

  select * into v_shift
  from public.rr_shift_master_v777_2
  where shift_id=v_profile.shift_id limit 1;

  if not found then raise exception 'Shift nahi mila.'; end if;
  v_scheduled:=v_shift.normal_payable_minutes;

  select * into v_leave
  from public.rr_worker_leave_v778_2
  where worker_id=p_worker_id
    and leave_date=p_attendance_date
    and data_mode=v_mode
    and leave_status='APPROVED'
  limit 1;

  select
    min(event_at) filter(where event_type='CHECK_IN' and not is_void),
    max(event_at) filter(where event_type='CHECK_OUT' and not is_void)
  into v_first_in,v_last_out
  from public.rr_attendance_events_v777_2
  where worker_id=p_worker_id
    and business_date=p_attendance_date
    and data_mode=v_mode;

  v_holiday:=extract(isodow from p_attendance_date)=1
    or exists(
      select 1
      from public.rr_holiday_calendar_v777_2 h
      where h.holiday_date=p_attendance_date
        and h.data_mode=v_mode
        and h.is_active
        and h.is_paid_holiday
        and h.applies_to in('ALL','SALARIED_ONLY')
    );

  if v_leave.leave_id is not null
     and (v_first_in is null or v_last_out is null) then
    if v_leave.pay_treatment='PAID' then
      v_paid_leave:=least(v_leave.requested_minutes,v_scheduled);
      v_working:=v_paid_leave;
      v_deduction:=greatest(v_scheduled-v_paid_leave,0);
      v_status:='PRESENT';
    else
      v_unpaid_leave:=least(v_leave.requested_minutes,v_scheduled);
      v_deduction:=v_unpaid_leave;
      v_working:=greatest(v_scheduled-v_unpaid_leave,0);
      v_status:='ABSENT';
    end if;

  elsif v_holiday and (v_first_in is null or v_last_out is null) then
    v_working:=v_scheduled;
    v_status:='HOLIDAY';

  elsif v_first_in is null or v_last_out is null then
    v_deduction:=v_scheduled;
    v_status:='REVIEW_REQUIRED';

  else
    v_in_local:=v_first_in at time zone 'Asia/Kolkata';
    v_out_local:=v_last_out at time zone 'Asia/Kolkata';
    v_gross:=greatest(floor(extract(epoch from(v_out_local-v_in_local))/60)::integer,0);

    if v_holiday then
      v_extra:=v_gross;
      v_working:=v_scheduled+v_extra;
      v_status:='HOLIDAY_WORKED';

    elsif v_gross<v_shift.minimum_presence_minutes then
      v_deduction:=v_scheduled;
      v_status:='ABSENT';

    else
      v_shift_start:=p_attendance_date::timestamp+v_shift.duty_start;
      v_shift_end:=p_attendance_date::timestamp+v_shift.duty_end;

      v_grace_used:=least(
        greatest(floor(extract(epoch from(v_in_local-v_shift_start))/60)::integer,0),
        v_shift.grace_in_minutes
      );

      if v_profile.late_deduction_applicable then
        v_late:=greatest(
          floor(extract(epoch from(v_in_local-v_shift_start))/60)::integer
          -v_shift.grace_in_minutes,0
        );
      end if;

      v_early:=greatest(
        floor(extract(epoch from(v_shift_end-v_out_local))/60)::integer,0
      );

      if v_profile.overtime_applicable then
        v_extra:=greatest(
          floor(extract(epoch from(v_out_local-v_shift_end))/60)::integer,0
        );
        if v_profile.grace_offset_against_ot then
          v_extra:=greatest(v_extra-v_grace_used,0);
        end if;
      end if;

      v_deduction:=least(v_late+v_early,v_scheduled);
      v_working:=greatest(v_scheduled-v_deduction+v_extra,0);
      v_status:='PRESENT';
    end if;
  end if;

  insert into public.rr_attendance_day_v777_2(
    worker_id,profile_id,attendance_date,
    first_check_in,last_check_out,
    gross_presence_minutes,grace_used_minutes,
    late_deduction_minutes,early_exit_deduction_minutes,
    normal_payable_minutes,gross_overtime_minutes,
    payable_overtime_minutes,holiday_work_minutes,
    attendance_status,is_holiday,calculation_snapshot,
    approval_status,data_mode,
    scheduled_payable_minutes,net_deduction_minutes,
    net_extra_work_minutes,net_working_minutes,
    paid_leave_minutes,unpaid_leave_minutes,
    created_at,updated_at
  )
  values(
    p_worker_id,v_profile.profile_id,p_attendance_date,
    v_first_in,v_last_out,
    v_gross,v_grace_used,v_late,v_early,
    greatest(v_scheduled-v_deduction,0),
    v_extra,v_extra,case when v_holiday then v_gross else 0 end,
    v_status,v_holiday,
    jsonb_build_object(
      'engine_version','V778_2_REVISED_NET_MINUTE_ENGINE',
      'holiday_multiplier',1,
      'overtime_multiplier',1,
      'money_calculation_included',false
    ),
    case when v_status='REVIEW_REQUIRED' then 'PENDING' else 'APPROVED' end,
    v_mode,
    v_scheduled,v_deduction,v_extra,v_working,
    v_paid_leave,v_unpaid_leave,now(),now()
  )
  on conflict(worker_id,attendance_date,data_mode) do update set
    profile_id=excluded.profile_id,
    first_check_in=excluded.first_check_in,
    last_check_out=excluded.last_check_out,
    gross_presence_minutes=excluded.gross_presence_minutes,
    grace_used_minutes=excluded.grace_used_minutes,
    late_deduction_minutes=excluded.late_deduction_minutes,
    early_exit_deduction_minutes=excluded.early_exit_deduction_minutes,
    normal_payable_minutes=excluded.normal_payable_minutes,
    gross_overtime_minutes=excluded.gross_overtime_minutes,
    payable_overtime_minutes=excluded.payable_overtime_minutes,
    holiday_work_minutes=excluded.holiday_work_minutes,
    attendance_status=excluded.attendance_status,
    is_holiday=excluded.is_holiday,
    calculation_snapshot=excluded.calculation_snapshot,
    approval_status=excluded.approval_status,
    scheduled_payable_minutes=excluded.scheduled_payable_minutes,
    net_deduction_minutes=excluded.net_deduction_minutes,
    net_extra_work_minutes=excluded.net_extra_work_minutes,
    net_working_minutes=excluded.net_working_minutes,
    paid_leave_minutes=excluded.paid_leave_minutes,
    unpaid_leave_minutes=excluded.unpaid_leave_minutes,
    updated_at=now()
  returning attendance_day_id into v_id;

  return jsonb_build_object(
    'ok',true,'version','V778_2_REVISED_NET_MINUTE_ENGINE',
    'attendance_day_id',v_id,'attendance_status',v_status,
    'scheduled_payable_minutes',v_scheduled,
    'net_deduction_minutes',v_deduction,
    'net_extra_work_minutes',v_extra,
    'net_working_minutes',v_working,
    'special_multiplier_used',false,
    'money_calculation_included',false
  );
end $function$
;
