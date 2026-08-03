
-- ============================================================
-- REDZED V778.2 REVISED — NET-MINUTE ATTENDANCE ENGINE
-- Dependencies: V777.2 + V778.1
-- Attendance calculates minutes only; no salary amount/multiplier.
-- ============================================================

begin;

update public.rr_attendance_premises_v778_1
set premise_name=case premise_code
  when 'LOCATION_1' then 'L1'
  when 'LOCATION_2' then 'L2'
  else premise_name
end,
updated_at=now()
where premise_code in('LOCATION_1','LOCATION_2');

alter table public.rr_attendance_day_v777_2
  add column if not exists scheduled_payable_minutes integer not null default 0,
  add column if not exists net_deduction_minutes integer not null default 0,
  add column if not exists net_extra_work_minutes integer not null default 0,
  add column if not exists net_working_minutes integer not null default 0,
  add column if not exists paid_leave_minutes integer not null default 0,
  add column if not exists unpaid_leave_minutes integer not null default 0;

create table if not exists public.rr_worker_leave_v778_2(
  leave_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  leave_date date not null,
  leave_type text not null check(leave_type in(
    'CASUAL_LEAVE','MEDICAL_LEAVE','PERSONAL_LEAVE','OFFICIAL_DUTY'
  )),
  pay_treatment text not null check(pay_treatment in('PAID','UNPAID')),
  requested_minutes integer not null default 600
    check(requested_minutes between 1 and 600),
  leave_status text not null default 'PENDING'
    check(leave_status in('PENDING','APPROVED','REJECTED','CANCELLED')),
  reason text,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  requested_at timestamptz not null default now(),
  requested_by uuid default auth.uid(),
  approved_at timestamptz,
  approved_by uuid,
  approval_reason text,
  unique(worker_id,leave_date,data_mode)
);

create table if not exists public.rr_attendance_corrections_v778_2(
  correction_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  attendance_date date not null,
  correction_type text not null check(correction_type in(
    'ADD_CHECK_IN','ADD_CHECK_OUT','VOID_EVENT',
    'RECALCULATE_DAY','LEAVE_DECISION','OWNER_OVERRIDE'
  )),
  source_attendance_event_id uuid,
  old_snapshot jsonb,
  new_snapshot jsonb,
  reason text not null,
  data_mode text not null default 'TEST' check(data_mode in('TEST','REAL')),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create or replace function public.rr_active_attendance_policy_v778_2(
  p_worker_id uuid,
  p_on_date date,
  p_data_mode text default 'TEST'
)
returns public.rr_worker_attendance_policy_v778_1
language sql stable security definer set search_path='public'
as $$
  select p
  from public.rr_worker_attendance_policy_v778_1 p
  where p.worker_id=p_worker_id
    and p.data_mode=upper(trim(coalesce(p_data_mode,'TEST')))
    and p.status='ACTIVE'
    and p.effective_from<=p_on_date
    and (p.effective_to is null or p.effective_to>=p_on_date)
  order by p.effective_from desc,p.configured_at desc
  limit 1
$$;

create or replace function public.rr_active_payroll_profile_v778_2(
  p_worker_id uuid,
  p_on_date date,
  p_data_mode text default 'TEST'
)
returns public.rr_worker_payroll_profile_v777_2
language sql stable security definer set search_path='public'
as $$
  select p
  from public.rr_worker_payroll_profile_v777_2 p
  where p.worker_id=p_worker_id
    and p.data_mode=upper(trim(coalesce(p_data_mode,'TEST')))
    and p.status='ACTIVE'
    and p.effective_from<=p_on_date
    and (p.effective_to is null or p.effective_to>=p_on_date)
  order by p.effective_from desc,p.configured_at desc
  limit 1
$$;

create or replace function public.rr_attendance_actor_allowed_v778_2(
  p_worker_id uuid
)
returns boolean
language plpgsql stable security definer set search_path='public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_link uuid;
begin
  select * into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then return false; end if;

  if lower(coalesce(v_actor.role_code,'')) in(
    'owner','admin','manager','production','department_head','line_man'
  ) then return true; end if;

  select linked_auth_user_id into v_link
  from public.rr_worker_directory_unified_v1
  where worker_id=p_worker_id limit 1;

  return v_link is not null and v_link=auth.uid();
end $$;

create or replace function public.rr_set_worker_attendance_premises_v778_2(
  p_worker_id uuid,
  p_premise_codes jsonb,
  p_effective_from date default current_date,
  p_effective_to date default null,
  p_reason text default null
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_code text;
  v_count integer:=0;
begin
  select * into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then raise exception 'Active ERP profile required.'; end if;
  if lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Premise assignment permission denied.';
  end if;

  update public.rr_worker_attendance_premises_v778_1
  set is_active=false,
      effective_to=coalesce(effective_to,p_effective_from-1)
  where worker_id=p_worker_id and is_active and effective_to is null;

  for v_code in
    select distinct upper(trim(value))
    from jsonb_array_elements_text(coalesce(p_premise_codes,'[]'::jsonb))
  loop
    if v_code not in('LOCATION_1','LOCATION_2') then
      raise exception 'Premise LOCATION_1 ya LOCATION_2 hona chahiye.';
    end if;

    insert into public.rr_worker_attendance_premises_v778_1(
      worker_id,premise_id,is_primary,is_active,
      effective_from,effective_to,assigned_at,assigned_by,reason
    )
    select p_worker_id,p.premise_id,(v_count=0),true,
           p_effective_from,p_effective_to,now(),auth.uid(),p_reason
    from public.rr_attendance_premises_v778_1 p
    where p.premise_code=v_code and p.is_active;

    v_count:=v_count+1;
  end loop;

  if v_count=0 then raise exception 'L1 ya L2 select karein.'; end if;

  return jsonb_build_object(
    'ok',true,'version','V778_2_REVISED_NET_MINUTE_ENGINE',
    'worker_id',p_worker_id,'premises_assigned',v_count
  );
end $$;

create or replace function public.rr_factory_attendance_event_v778_2(
  p_worker_id uuid,
  p_event_type text,
  p_event_at timestamptz,
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy_meters numeric,
  p_source_event_id text default null,
  p_data_mode text default 'TEST',
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
declare
  v_event text:=upper(trim(coalesce(p_event_type,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_date date:=public.rr_business_date_v777_2(p_event_at);
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_profile public.rr_worker_payroll_profile_v777_2%rowtype;
  v_match jsonb;
  v_id uuid;
begin
  if not public.rr_attendance_actor_allowed_v778_2(p_worker_id) then
    raise exception 'Attendance permission denied.';
  end if;

  if v_event not in('CHECK_IN','CHECK_OUT') then
    raise exception 'CHECK_IN ya CHECK_OUT required hai.';
  end if;

  select * into v_policy
  from public.rr_active_attendance_policy_v778_2(p_worker_id,v_date,v_mode);

  if v_policy.policy_id is null or v_policy.attendance_type<>'FACTORY_GEOFENCE' then
    raise exception 'Active FACTORY_GEOFENCE policy required hai.';
  end if;

  if p_latitude is null or p_longitude is null
     or p_gps_accuracy_meters is null
     or p_gps_accuracy_meters>v_policy.gps_accuracy_limit_meters then
    raise exception 'Valid live GPS required hai.';
  end if;

  select * into v_profile
  from public.rr_active_payroll_profile_v778_2(p_worker_id,v_date,v_mode);

  if v_profile.profile_id is null or v_profile.worker_category<>'SALARIED' then
    raise exception 'Active SALARIED payroll profile required hai.';
  end if;

  v_match:=public.rr_match_attendance_premise_v778_1(
    p_worker_id,p_latitude,p_longitude,v_date,v_mode
  );

  if not coalesce((v_match->>'ok')::boolean,false) then
    raise exception 'Authorized L1/L2 premise nahi mila.';
  end if;

  insert into public.rr_attendance_geofence_audit_v778_1(
    worker_id,event_type,event_at,business_date,
    latitude,longitude,gps_accuracy_meters,
    matched_premise_id,matched_premise_name,
    distance_meters,allowed_radius_meters,inside_geofence,
    source_module,source_record_id,data_mode
  )
  values(
    p_worker_id,v_event,p_event_at,v_date,
    p_latitude,p_longitude,p_gps_accuracy_meters,
    (v_match->>'premise_id')::uuid,
    v_match->>'premise_name',
    (v_match->>'distance_meters')::numeric,
    (v_match->>'allowed_radius_meters')::numeric,
    (v_match->>'inside_geofence')::boolean,
    'ATTENDANCE',nullif(trim(p_source_event_id),''),v_mode
  );

  if not (v_match->>'inside_geofence')::boolean then
    raise exception 'Worker authorized 100-meter geofence ke bahar hai.';
  end if;

  insert into public.rr_attendance_events_v777_2(
    worker_id,event_type,event_at,attendance_source,
    latitude,longitude,gps_accuracy_meters,
    factory_radius_meters,inside_factory_radius,
    source_event_id,metadata,data_mode,created_by
  )
  values(
    p_worker_id,v_event,p_event_at,'GPS',
    p_latitude,p_longitude,p_gps_accuracy_meters,
    (v_match->>'allowed_radius_meters')::numeric,true,
    nullif(trim(p_source_event_id),''),
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'premise',v_match->>'premise_name',
      'distance_meters',(v_match->>'distance_meters')::numeric,
      'engine_version','V778.2_REVISED'
    ),
    v_mode,auth.uid()
  )
  returning attendance_event_id into v_id;

  return jsonb_build_object(
    'ok',true,'attendance_event_id',v_id,
    'event_type',v_event,'business_date',v_date,
    'premise',v_match->>'premise_name'
  );
end $$;

create or replace function public.rr_save_worker_leave_v778_2(
  p_worker_id uuid,
  p_leave_date date,
  p_leave_type text,
  p_pay_treatment text,
  p_requested_minutes integer default 600,
  p_reason text default null,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
declare
  v_id uuid;
begin
  if not public.rr_attendance_actor_allowed_v778_2(p_worker_id) then
    raise exception 'Leave permission denied.';
  end if;

  insert into public.rr_worker_leave_v778_2(
    worker_id,leave_date,leave_type,pay_treatment,
    requested_minutes,leave_status,reason,data_mode,requested_by
  )
  values(
    p_worker_id,p_leave_date,upper(trim(p_leave_type)),
    upper(trim(p_pay_treatment)),p_requested_minutes,
    'PENDING',p_reason,upper(trim(coalesce(p_data_mode,'TEST'))),auth.uid()
  )
  on conflict(worker_id,leave_date,data_mode) do update set
    leave_type=excluded.leave_type,
    pay_treatment=excluded.pay_treatment,
    requested_minutes=excluded.requested_minutes,
    leave_status='PENDING',
    reason=excluded.reason,
    requested_at=now(),
    requested_by=auth.uid(),
    approved_at=null,approved_by=null,approval_reason=null
  returning leave_id into v_id;

  return jsonb_build_object('ok',true,'leave_id',v_id,'status','PENDING');
end $$;

create or replace function public.rr_decide_worker_leave_v778_2(
  p_leave_id uuid,
  p_decision text,
  p_reason text
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_decision text:=upper(trim(coalesce(p_decision,'')));
  v_leave public.rr_worker_leave_v778_2%rowtype;
begin
  select * into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found or lower(coalesce(v_actor.role_code,'')) not in(
    'owner','admin','production','department_head','manager'
  ) then raise exception 'Leave approval permission denied.'; end if;

  if v_decision not in('APPROVED','REJECTED','CANCELLED') then
    raise exception 'Invalid decision.';
  end if;

  select * into v_leave
  from public.rr_worker_leave_v778_2
  where leave_id=p_leave_id for update;

  if not found then raise exception 'Leave record nahi mila.'; end if;

  update public.rr_worker_leave_v778_2
  set leave_status=v_decision,
      approved_at=now(),
      approved_by=auth.uid(),
      approval_reason=p_reason
  where leave_id=p_leave_id;

  insert into public.rr_attendance_corrections_v778_2(
    worker_id,attendance_date,correction_type,
    old_snapshot,new_snapshot,reason,data_mode,created_by
  )
  values(
    v_leave.worker_id,v_leave.leave_date,'LEAVE_DECISION',
    to_jsonb(v_leave),jsonb_build_object('decision',v_decision),
    coalesce(nullif(trim(p_reason),''),'Leave decision'),
    v_leave.data_mode,auth.uid()
  );

  return jsonb_build_object('ok',true,'leave_id',p_leave_id,'decision',v_decision);
end $$;

create or replace function public.rr_recalculate_attendance_day_v778_2(
  p_worker_id uuid,
  p_attendance_date date,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
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
end $$;

create or replace function public.rr_minutes_dhm_v778_2(
  p_minutes integer
)
returns text
language sql immutable
as $$
  select concat_ws(' ',
    case when floor(greatest(coalesce(p_minutes,0),0)/600)>0
      then floor(greatest(coalesce(p_minutes,0),0)/600)::int||' D' end,
    case when floor((greatest(coalesce(p_minutes,0),0)%600)/60)>0
      then floor((greatest(coalesce(p_minutes,0),0)%600)/60)::int||' H' end,
    case when greatest(coalesce(p_minutes,0),0)%60>0
      then (greatest(coalesce(p_minutes,0),0)%60)::int||' M' end
  )
$$;

create or replace view public.rr_attendance_live_board_v778_2 as
select
  d.attendance_day_id,d.worker_id,
  w.worker_code,w.worker_name,w.department_code,
  d.attendance_date,d.first_check_in,d.last_check_out,
  d.attendance_status,d.approval_status,d.is_holiday,
  d.scheduled_payable_minutes,
  d.net_deduction_minutes,
  public.rr_minutes_dhm_v778_2(d.net_deduction_minutes) as net_deduction_dhm,
  d.net_extra_work_minutes,
  public.rr_minutes_dhm_v778_2(d.net_extra_work_minutes) as net_extra_work_dhm,
  d.net_working_minutes,
  public.rr_minutes_dhm_v778_2(d.net_working_minutes) as net_working_dhm,
  d.data_mode
from public.rr_attendance_day_v777_2 d
join public.rr_worker_directory_unified_v1 w on w.worker_id=d.worker_id;

grant execute on function public.rr_active_attendance_policy_v778_2(uuid,date,text) to authenticated;
grant execute on function public.rr_active_payroll_profile_v778_2(uuid,date,text) to authenticated;
grant execute on function public.rr_attendance_actor_allowed_v778_2(uuid) to authenticated;
grant execute on function public.rr_set_worker_attendance_premises_v778_2(uuid,jsonb,date,date,text) to authenticated;
grant execute on function public.rr_factory_attendance_event_v778_2(uuid,text,timestamptz,numeric,numeric,numeric,text,text,jsonb) to authenticated;
grant execute on function public.rr_save_worker_leave_v778_2(uuid,date,text,text,integer,text,text) to authenticated;
grant execute on function public.rr_decide_worker_leave_v778_2(uuid,text,text) to authenticated;
grant execute on function public.rr_recalculate_attendance_day_v778_2(uuid,date,text) to authenticated;
grant execute on function public.rr_minutes_dhm_v778_2(integer) to authenticated;
grant select on public.rr_attendance_live_board_v778_2 to authenticated;

revoke all on public.rr_worker_leave_v778_2,
              public.rr_attendance_corrections_v778_2
from anon,authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V778_2_REVISED_NET_MINUTE_ENGINE',
  'premises',jsonb_build_array('L1','L2'),
  'monday_paid_holiday',true,
  'manual_paid_holidays',true,
  'holiday_multiplier',1,
  'overtime_multiplier',1,
  'special_multiplier_used',false,
  'minute_outputs',jsonb_build_array(
    'net_deduction_minutes','net_extra_work_minutes','net_working_minutes'
  ),
  'dhm_display_rule','1D=600MIN; H_REMAINDER_MAX=9',
  'money_calculation_included',false,
  'payroll_posting_included',false
) as rr_upm_v778_2_revised_result;
