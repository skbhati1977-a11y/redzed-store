
-- ============================================================
-- REDZED V778.2 FINAL
-- ATTENDANCE + LEAVE + WORK-PROOF OT CORE
--
-- Dependencies:
--   V777.2 foundation
--   V778.1 attendance premises/policy foundation
--
-- Important:
--   This supersedes the earlier draft V778.2.
--   It does not modify ARD business rules.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 0. Prerequisite guard
-- ------------------------------------------------------------
do $$
begin
  if to_regclass('public.rr_worker_directory_unified_v1') is null then
    raise exception 'Missing rr_worker_directory_unified_v1';
  end if;

  if to_regclass('public.rr_user_profiles') is null then
    raise exception 'Missing rr_user_profiles';
  end if;

  if to_regclass('public.rr_worker_payroll_profile_v777_2') is null then
    raise exception 'Missing rr_worker_payroll_profile_v777_2';
  end if;

  if to_regclass('public.rr_attendance_premises_v778_1') is null then
    raise exception 'Run V778.1 first: attendance premises missing';
  end if;

  if to_regclass('public.rr_worker_attendance_policy_v778_1') is null then
    raise exception 'Run V778.1 first: attendance policy missing';
  end if;

  if to_regprocedure(
    'public.rr_distance_meters_v778_1(numeric,numeric,numeric,numeric)'
  ) is null then
    raise exception 'Run V778.1 first: distance RPC missing';
  end if;
end $$;

-- ------------------------------------------------------------
-- 1. Final policy extensions
-- ------------------------------------------------------------
alter table public.rr_worker_attendance_policy_v778_1
  add column if not exists premise_access_mode text not null default 'ALL_ACTIVE',
  add column if not exists regular_checkin_grace_minutes integer not null default 10,
  add column if not exists regular_checkout_grace_minutes integer not null default 10,
  add column if not exists reminder_repeat_minutes integer not null default 15,
  add column if not exists outside_checkout_monthly_limit integer not null default 4,
  add column if not exists outside_checkout_penalty_amount numeric(12,2) not null default 50,
  add column if not exists early_checkin_payable boolean not null default true,
  add column if not exists forgot_checkout_ot_zero boolean not null default true,
  add column if not exists ot_start_video_min_seconds integer not null default 10,
  add column if not exists ot_start_video_max_seconds integer not null default 30,
  add column if not exists ot_end_video_min_seconds integer not null default 10,
  add column if not exists ot_end_video_max_seconds integer not null default 45,
  add column if not exists holiday_rate_multiplier numeric(6,3) not null default 1.000;

alter table public.rr_worker_attendance_policy_v778_1
drop constraint if exists rr_attendance_premise_access_v778_2_chk;

alter table public.rr_worker_attendance_policy_v778_1
add constraint rr_attendance_premise_access_v778_2_chk
check(premise_access_mode in('ALL_ACTIVE','SELECTED_ONLY'));

alter table public.rr_worker_attendance_policy_v778_1
drop constraint if exists rr_attendance_final_policy_values_v778_2_chk;

alter table public.rr_worker_attendance_policy_v778_1
add constraint rr_attendance_final_policy_values_v778_2_chk
check(
  regular_checkin_grace_minutes>=0
  and regular_checkout_grace_minutes>=0
  and reminder_repeat_minutes>=5
  and outside_checkout_monthly_limit>=0
  and outside_checkout_penalty_amount>=0
  and ot_start_video_min_seconds between 1 and ot_start_video_max_seconds
  and ot_start_video_max_seconds<=60
  and ot_end_video_min_seconds between 1 and ot_end_video_max_seconds
  and ot_end_video_max_seconds<=60
  and holiday_rate_multiplier=1.000
);

-- ------------------------------------------------------------
-- 2. Secure multi-premise management
-- ------------------------------------------------------------
create or replace function public.rr_save_attendance_premise_v778_2(
  p_premise_id uuid default null,
  p_premise_code text default null,
  p_premise_name text default null,
  p_premise_type text default 'FACTORY',
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_radius_meters numeric default 100,
  p_is_active boolean default true,
  p_data_mode text default 'TEST',
  p_effective_from date default current_date,
  p_effective_to date default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_id uuid;
  v_code text:=upper(trim(coalesce(p_premise_code,'')));
  v_type text:=upper(trim(coalesce(p_premise_type,'FACTORY')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
begin
  select * into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found or lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Owner/Admin premise permission required.';
  end if;

  if v_code='' or nullif(trim(coalesce(p_premise_name,'')),'') is null then
    raise exception 'Premise code and name required.';
  end if;

  if v_type not in(
    'FACTORY','OFFICE','WAREHOUSE','CUSTOMER',
    'MARKET','FIELD_POINT','OTHER'
  ) then raise exception 'Invalid premise type.'; end if;

  if p_latitude not between -90 and 90
     or p_longitude not between -180 and 180
  then raise exception 'Invalid coordinates.'; end if;

  if coalesce(p_radius_meters,0)<=0 then
    raise exception 'Radius must be greater than zero.';
  end if;

  if v_mode not in('TEST','REAL') then
    raise exception 'Data mode must be TEST or REAL.';
  end if;

  if p_effective_to is not null and p_effective_to<p_effective_from then
    raise exception 'Invalid effective dates.';
  end if;

  if p_premise_id is null then
    insert into public.rr_attendance_premises_v778_1(
      premise_code,premise_name,premise_type,
      latitude,longitude,radius_meters,
      is_fixed_location,is_active,data_mode,
      effective_from,effective_to,
      created_at,created_by,updated_at
    )
    values(
      v_code,trim(p_premise_name),v_type,
      p_latitude,p_longitude,p_radius_meters,
      true,p_is_active,v_mode,
      p_effective_from,p_effective_to,
      now(),auth.uid(),now()
    )
    returning premise_id into v_id;
  else
    update public.rr_attendance_premises_v778_1
    set premise_code=v_code,
        premise_name=trim(p_premise_name),
        premise_type=v_type,
        latitude=p_latitude,
        longitude=p_longitude,
        radius_meters=p_radius_meters,
        is_active=p_is_active,
        data_mode=v_mode,
        effective_from=p_effective_from,
        effective_to=p_effective_to,
        updated_at=now()
    where premise_id=p_premise_id
    returning premise_id into v_id;

    if v_id is null then raise exception 'Premise not found.'; end if;
  end if;

  return jsonb_build_object(
    'ok',true,
    'version','V778_2_FINAL_ATTENDANCE_LEAVE_OT_CORE',
    'premise_id',v_id,
    'hard_delete_used',false
  );
end $$;

-- ------------------------------------------------------------
-- 3. Regular attendance session
-- ------------------------------------------------------------
create table if not exists public.rr_regular_attendance_sessions_v778_2(
  session_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  business_date date not null,

  checkin_at timestamptz not null,
  checkout_at timestamptz,

  checkin_latitude numeric(10,7) not null,
  checkin_longitude numeric(10,7) not null,
  checkin_accuracy_meters numeric(10,2),
  checkin_premise_id uuid,
  checkin_premise_name text,
  checkin_distance_meters numeric(12,2),
  checkin_inside_geofence boolean not null,

  checkout_latitude numeric(10,7),
  checkout_longitude numeric(10,7),
  checkout_accuracy_meters numeric(10,2),
  checkout_premise_id uuid,
  checkout_premise_name text,
  checkout_distance_meters numeric(12,2),
  checkout_inside_geofence boolean,

  checkout_status text
    check(checkout_status is null or checkout_status in(
      'INSIDE_GEOFENCE',
      'OUTSIDE_GEOFENCE_ALLOWED',
      'AUTO_CLOSED_FORGOT_CHECKOUT'
    )),

  forgot_checkout boolean not null default false,
  ot_hard_zero boolean not null default false,

  source_checkin_id text not null,
  source_checkout_id text,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),

  unique(worker_id,business_date,data_mode),
  unique(source_checkin_id,data_mode),
  check(checkout_at is null or checkout_at>=checkin_at)
);

create index if not exists rr_regular_attendance_sessions_v778_2_worker_date_idx
on public.rr_regular_attendance_sessions_v778_2(
  worker_id,business_date,data_mode
);

-- ------------------------------------------------------------
-- 4. Outside-geofence checkout violations / penalty events
-- ------------------------------------------------------------
create table if not exists public.rr_attendance_checkout_violations_v778_2(
  violation_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  session_id uuid not null
    references public.rr_regular_attendance_sessions_v778_2(session_id),

  business_date date not null,
  violation_month date not null,

  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  accuracy_meters numeric(10,2),
  nearest_premise_id uuid,
  nearest_premise_name text,
  distance_meters numeric(12,2),
  allowed_radius_meters numeric(10,2),

  monthly_sequence integer not null,
  penalty_amount numeric(12,2) not null default 50,

  penalty_status text not null default 'PROPOSED'
    check(penalty_status in(
      'PROPOSED','POSTED','WAIVED','REVERSED'
    )),

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),
  unique(session_id)
);

-- ------------------------------------------------------------
-- 5. OT / Holiday work sessions
-- ------------------------------------------------------------
create table if not exists public.rr_ot_work_sessions_v778_2(
  ot_session_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  business_date date not null,

  work_type text not null
    check(work_type in('REGULAR_OT','HOLIDAY_WORK')),

  status text not null default 'OPEN'
    check(status in(
      'OPEN','COMPLETED','REJECTED','FORGOT_OT_CHECKOUT'
    )),

  ot_checkin_at timestamptz not null,
  ot_checkout_at timestamptz,

  start_latitude numeric(10,7) not null,
  start_longitude numeric(10,7) not null,
  start_accuracy_meters numeric(10,2),
  start_premise_id uuid,
  start_premise_name text,
  start_distance_meters numeric(12,2),
  start_inside_geofence boolean not null,

  end_latitude numeric(10,7),
  end_longitude numeric(10,7),
  end_accuracy_meters numeric(10,2),
  end_premise_id uuid,
  end_premise_name text,
  end_distance_meters numeric(12,2),
  end_inside_geofence boolean,

  start_video_evidence_id uuid,
  end_video_evidence_id uuid,

  payable_minutes integer not null default 0,
  rate_multiplier numeric(6,3) not null default 1.000,
  payable_eligible boolean not null default false,
  rejection_reason text,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),

  unique(worker_id,business_date,work_type,data_mode),
  check(ot_checkout_at is null or ot_checkout_at>=ot_checkin_at),
  check(rate_multiplier=1.000)
);

-- ------------------------------------------------------------
-- 6. Live video evidence metadata
-- Actual file upload occurs through frontend/storage.
-- SQL stores immutable evidence contract.
-- ------------------------------------------------------------
create table if not exists public.rr_attendance_video_evidence_v778_2(
  evidence_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  evidence_type text not null
    check(evidence_type in(
      'OT_START','OT_END','HOLIDAY_START','HOLIDAY_END'
    )),

  captured_at timestamptz not null,
  duration_seconds integer not null,
  live_camera_capture boolean not null,
  gallery_upload boolean not null default false,

  storage_bucket text not null,
  storage_path text not null,
  content_hash text not null,

  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  gps_accuracy_meters numeric(10,2),
  premise_id uuid,
  premise_name text,
  distance_meters numeric(12,2),
  inside_geofence boolean not null,

  device_session_id text,
  source_capture_id text not null,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),

  unique(content_hash),
  unique(source_capture_id,data_mode),
  check(live_camera_capture=true),
  check(gallery_upload=false),
  check(duration_seconds between 1 and 60)
);

alter table public.rr_ot_work_sessions_v778_2
drop constraint if exists rr_ot_start_evidence_v778_2_fk;

alter table public.rr_ot_work_sessions_v778_2
add constraint rr_ot_start_evidence_v778_2_fk
foreign key(start_video_evidence_id)
references public.rr_attendance_video_evidence_v778_2(evidence_id);

alter table public.rr_ot_work_sessions_v778_2
drop constraint if exists rr_ot_end_evidence_v778_2_fk;

alter table public.rr_ot_work_sessions_v778_2
add constraint rr_ot_end_evidence_v778_2_fk
foreign key(end_video_evidence_id)
references public.rr_attendance_video_evidence_v778_2(evidence_id);

-- ------------------------------------------------------------
-- 7. Leave requests + approval + reactivation
-- ------------------------------------------------------------
create table if not exists public.rr_worker_leave_requests_v778_2(
  leave_request_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,

  leave_type text not null default 'UNPAID_LEAVE'
    check(leave_type in(
      'UNPAID_LEAVE','PAID_LEAVE','HALF_DAY',
      'EMERGENCY_LEAVE','OTHER'
    )),

  leave_from date not null,
  leave_to date not null,
  expected_return_date date not null,

  worker_message text not null,

  status text not null default 'PENDING'
    check(status in(
      'PENDING','APPROVED','REJECTED',
      'CANCELLED','RETURNED','EXPIRED'
    )),

  requested_at timestamptz not null default now(),
  requested_by uuid default auth.uid(),

  decided_at timestamptz,
  decided_by uuid,
  decision_note text,

  returned_at timestamptz,
  return_attendance_session_id uuid,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  check(leave_to>=leave_from),
  check(expected_return_date=leave_to+1)
);

create index if not exists rr_worker_leave_requests_v778_2_worker_idx
on public.rr_worker_leave_requests_v778_2(
  worker_id,status,leave_from,leave_to,data_mode
);

create table if not exists public.rr_worker_reactivation_requests_v778_2(
  reactivation_request_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  requested_at timestamptz not null,
  requested_latitude numeric(10,7) not null,
  requested_longitude numeric(10,7) not null,
  requested_accuracy_meters numeric(10,2),
  premise_id uuid,
  premise_name text,
  distance_meters numeric(12,2),
  inside_geofence boolean not null,

  status text not null default 'PENDING'
    check(status in('PENDING','APPROVED','REJECTED')),

  decided_at timestamptz,
  decided_by uuid,
  decision_note text,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 8. Reminder state
-- ------------------------------------------------------------
create table if not exists public.rr_attendance_reminder_state_v778_2(
  reminder_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  business_date date not null,

  reminder_type text not null
    check(reminder_type in(
      'CHECKIN_PENDING',
      'CHECKOUT_PENDING',
      'OT_CHECKOUT_PENDING',
      'FORGOT_CHECKOUT_NOTICE'
    )),

  first_due_at timestamptz not null,
  next_due_at timestamptz not null,
  repeat_minutes integer not null default 15,
  delivered_count integer not null default 0,

  status text not null default 'DUE'
    check(status in('DUE','ACKNOWLEDGED','RESOLVED','EXPIRED')),

  last_delivered_at timestamptz,
  resolved_at timestamptz,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  unique(worker_id,business_date,reminder_type,data_mode)
);

-- ------------------------------------------------------------
-- 9. Daily minute summary
-- ------------------------------------------------------------
create table if not exists public.rr_attendance_daily_minutes_v778_2(
  daily_minutes_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,
  business_date date not null,

  regular_checkin_at timestamptz,
  regular_checkout_at timestamptz,

  early_checkin_minutes integer not null default 0,
  late_checkin_minutes integer not null default 0,
  early_checkout_minutes integer not null default 0,

  verified_ot_minutes integer not null default 0,
  verified_holiday_minutes integer not null default 0,

  net_adjustment_minutes integer not null default 0,

  attendance_status text not null default 'PENDING'
    check(attendance_status in(
      'PENDING','PRESENT','ABSENT','ON_LEAVE',
      'HOLIDAY_WORK','REVIEW_REQUIRED'
    )),

  forgot_checkout boolean not null default false,
  outside_checkout boolean not null default false,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  calculated_at timestamptz not null default now(),
  calculation_version text not null default 'V778_2_FINAL',

  unique(worker_id,business_date,data_mode)
);

-- ------------------------------------------------------------
-- 10. Common actor authorization helper
-- ------------------------------------------------------------
create or replace function public.rr_attendance_actor_v778_2(
  p_worker_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_worker record;
  v_admin boolean;
  v_self boolean;
begin
  select * into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then raise exception 'Active ERP profile required.'; end if;

  select
    worker_id,worker_name,worker_code,department_code,role_code,
    linked_auth_user_id,is_active,access_status
  into v_worker
  from public.rr_worker_directory_unified_v1
  where worker_id=p_worker_id
  limit 1;

  if not found then raise exception 'Worker not found.'; end if;

  v_admin:=lower(coalesce(v_actor.role_code,'')) in('owner','admin');
  v_self:=v_worker.linked_auth_user_id=auth.uid();

  if not v_admin and not v_self then
    raise exception 'Self-login or Owner/Admin required.';
  end if;

  return jsonb_build_object(
    'actor_auth_user_id',auth.uid(),
    'actor_name',v_actor.full_name,
    'actor_role',v_actor.role_code,
    'owner_admin',v_admin,
    'self_login',v_self,
    'worker_id',v_worker.worker_id,
    'worker_name',v_worker.worker_name,
    'department_code',v_worker.department_code,
    'worker_role_code',v_worker.role_code,
    'worker_is_active',v_worker.is_active,
    'worker_access_status',v_worker.access_status
  );
end $$;

-- ------------------------------------------------------------
-- 11. Current policy resolver
-- ------------------------------------------------------------
create or replace function public.rr_current_attendance_policy_v778_2(
  p_worker_id uuid,
  p_on_date date,
  p_data_mode text default 'TEST'
)
returns public.rr_worker_attendance_policy_v778_1
language sql
stable
security definer
set search_path='public'
as $$
  select p
  from public.rr_worker_attendance_policy_v778_1 p
  where p.worker_id=p_worker_id
    and p.status='ACTIVE'
    and p.data_mode=upper(trim(coalesce(p_data_mode,'TEST')))
    and p.effective_from<=p_on_date
    and (p.effective_to is null or p.effective_to>=p_on_date)
  order by p.effective_from desc,p.configured_at desc
  limit 1
$$;

-- ------------------------------------------------------------
-- 12. Nearest active premise helper
-- ALL_ACTIVE is default. SELECTED_ONLY uses existing map table if present.
-- ------------------------------------------------------------
create or replace function public.rr_nearest_attendance_premise_v778_2(
  p_worker_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_on_date date,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_row record;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
begin
  select * into v_policy
  from public.rr_current_attendance_policy_v778_2(
    p_worker_id,p_on_date,v_mode
  );

  if v_policy.policy_id is null then
    return jsonb_build_object('ok',false,'code','NO_ACTIVE_POLICY');
  end if;

  if v_policy.premise_access_mode='SELECTED_ONLY'
     and to_regclass('public.rr_worker_attendance_premises_v778_1') is not null
  then
    select
      p.premise_id,p.premise_code,p.premise_name,p.radius_meters,
      public.rr_distance_meters_v778_1(
        p_latitude,p_longitude,p.latitude,p.longitude
      ) as distance_meters
    into v_row
    from public.rr_worker_attendance_premises_v778_1 wp
    join public.rr_attendance_premises_v778_1 p
      on p.premise_id=wp.premise_id
    where wp.worker_id=p_worker_id
      and wp.is_active
      and wp.effective_from<=p_on_date
      and (wp.effective_to is null or wp.effective_to>=p_on_date)
      and p.is_active
      and p.data_mode=v_mode
      and p.effective_from<=p_on_date
      and (p.effective_to is null or p.effective_to>=p_on_date)
    order by distance_meters
    limit 1;
  else
    select
      p.premise_id,p.premise_code,p.premise_name,p.radius_meters,
      public.rr_distance_meters_v778_1(
        p_latitude,p_longitude,p.latitude,p.longitude
      ) as distance_meters
    into v_row
    from public.rr_attendance_premises_v778_1 p
    where p.is_active
      and p.data_mode=v_mode
      and p.effective_from<=p_on_date
      and (p.effective_to is null or p.effective_to>=p_on_date)
    order by distance_meters
    limit 1;
  end if;

  if not found then
    return jsonb_build_object('ok',false,'code','NO_ALLOWED_PREMISE');
  end if;

  return jsonb_build_object(
    'ok',true,
    'premise_id',v_row.premise_id,
    'premise_code',v_row.premise_code,
    'premise_name',v_row.premise_name,
    'distance_meters',round(v_row.distance_meters,2),
    'allowed_radius_meters',v_row.radius_meters,
    'inside_geofence',v_row.distance_meters<=v_row.radius_meters
  );
end $$;

-- ------------------------------------------------------------
-- 13. Regular Check-In
-- Check-In outside geofence is fully blocked.
-- ------------------------------------------------------------
create or replace function public.rr_regular_checkin_v778_2(
  p_worker_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy_meters numeric,
  p_source_checkin_id text,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_now timestamptz:=now();
  v_date date:=(v_now at time zone 'Asia/Kolkata')::date;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_actor jsonb;
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_match jsonb;
  v_id uuid;
  v_active boolean;
begin
  v_actor:=public.rr_attendance_actor_v778_2(p_worker_id);

  select * into v_policy
  from public.rr_current_attendance_policy_v778_2(
    p_worker_id,v_date,v_mode
  );

  if v_policy.policy_id is null then
    raise exception 'Active attendance policy required.';
  end if;

  if v_policy.attendance_type<>'FACTORY_GEOFENCE' then
    raise exception 'Regular attendance requires FACTORY_GEOFENCE policy.';
  end if;

  if p_gps_accuracy_meters is null
     or p_gps_accuracy_meters>v_policy.gps_accuracy_limit_meters
  then raise exception 'GPS accuracy is outside policy limit.'; end if;

  v_active:=coalesce((v_actor->>'worker_is_active')::boolean,false);

  if not v_active
     or upper(coalesce(v_actor->>'worker_access_status','ACTIVE'))<>'ACTIVE'
  then
    insert into public.rr_worker_reactivation_requests_v778_2(
      worker_id,requested_at,
      requested_latitude,requested_longitude,requested_accuracy_meters,
      inside_geofence,data_mode
    )
    values(
      p_worker_id,v_now,
      p_latitude,p_longitude,p_gps_accuracy_meters,
      false,v_mode
    );

    return jsonb_build_object(
      'ok',false,
      'code','REACTIVATION_APPROVAL_REQUIRED',
      'request_time_frozen',v_now
    );
  end if;

  v_match:=public.rr_nearest_attendance_premise_v778_2(
    p_worker_id,p_latitude,p_longitude,v_date,v_mode
  );

  if not coalesce((v_match->>'ok')::boolean,false)
     or not coalesce((v_match->>'inside_geofence')::boolean,false)
  then
    raise exception 'Check-In outside allowed geofence is blocked.';
  end if;

  insert into public.rr_regular_attendance_sessions_v778_2(
    worker_id,business_date,checkin_at,
    checkin_latitude,checkin_longitude,checkin_accuracy_meters,
    checkin_premise_id,checkin_premise_name,
    checkin_distance_meters,checkin_inside_geofence,
    source_checkin_id,data_mode,created_by
  )
  values(
    p_worker_id,v_date,v_now,
    p_latitude,p_longitude,p_gps_accuracy_meters,
    (v_match->>'premise_id')::uuid,
    v_match->>'premise_name',
    (v_match->>'distance_meters')::numeric,
    true,
    trim(p_source_checkin_id),v_mode,auth.uid()
  )
  returning session_id into v_id;

  update public.rr_attendance_reminder_state_v778_2
  set status='RESOLVED',resolved_at=v_now
  where worker_id=p_worker_id
    and business_date=v_date
    and reminder_type='CHECKIN_PENDING'
    and data_mode=v_mode
    and status in('DUE','ACKNOWLEDGED');

  return jsonb_build_object(
    'ok',true,
    'version','V778_2_FINAL_ATTENDANCE_LEAVE_OT_CORE',
    'session_id',v_id,
    'event','CHECK_IN',
    'server_time',v_now,
    'premise',v_match
  );
end $$;

-- ------------------------------------------------------------
-- 14. Regular Check-Out
-- Inside accepted.
-- Outside accepted only for first N times/month, ₹50 proposed each time.
-- Fifth+ outside checkout blocked when monthly limit=4.
-- ------------------------------------------------------------
create or replace function public.rr_regular_checkout_v778_2(
  p_worker_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy_meters numeric,
  p_source_checkout_id text,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_now timestamptz:=now();
  v_date date:=(v_now at time zone 'Asia/Kolkata')::date;
  v_month date:=date_trunc('month',v_date)::date;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_match jsonb;
  v_session public.rr_regular_attendance_sessions_v778_2%rowtype;
  v_inside boolean;
  v_count integer;
  v_violation_id uuid;
begin
  perform public.rr_attendance_actor_v778_2(p_worker_id);

  select * into v_policy
  from public.rr_current_attendance_policy_v778_2(
    p_worker_id,v_date,v_mode
  );

  select * into v_session
  from public.rr_regular_attendance_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=v_date
    and data_mode=v_mode
  limit 1
  for update;

  if not found then raise exception 'Open Check-In required.'; end if;
  if v_session.checkout_at is not null then raise exception 'Already checked-out.'; end if;

  if p_gps_accuracy_meters is null
     or p_gps_accuracy_meters>v_policy.gps_accuracy_limit_meters
  then raise exception 'GPS accuracy is outside policy limit.'; end if;

  v_match:=public.rr_nearest_attendance_premise_v778_2(
    p_worker_id,p_latitude,p_longitude,v_date,v_mode
  );

  if not coalesce((v_match->>'ok')::boolean,false) then
    raise exception 'No allowed premise available.';
  end if;

  v_inside:=coalesce((v_match->>'inside_geofence')::boolean,false);

  if not v_inside then
    select count(*) into v_count
    from public.rr_attendance_checkout_violations_v778_2
    where worker_id=p_worker_id
      and violation_month=v_month
      and data_mode=v_mode;

    if v_count>=v_policy.outside_checkout_monthly_limit then
      raise exception
        'Outside-geofence monthly checkout limit exhausted.';
    end if;

    update public.rr_regular_attendance_sessions_v778_2
    set checkout_at=v_now,
        checkout_latitude=p_latitude,
        checkout_longitude=p_longitude,
        checkout_accuracy_meters=p_gps_accuracy_meters,
        checkout_premise_id=(v_match->>'premise_id')::uuid,
        checkout_premise_name=v_match->>'premise_name',
        checkout_distance_meters=(v_match->>'distance_meters')::numeric,
        checkout_inside_geofence=false,
        checkout_status='OUTSIDE_GEOFENCE_ALLOWED',
        source_checkout_id=trim(p_source_checkout_id),
        updated_at=now()
    where session_id=v_session.session_id;

    insert into public.rr_attendance_checkout_violations_v778_2(
      worker_id,session_id,business_date,violation_month,
      latitude,longitude,accuracy_meters,
      nearest_premise_id,nearest_premise_name,
      distance_meters,allowed_radius_meters,
      monthly_sequence,penalty_amount,data_mode
    )
    values(
      p_worker_id,v_session.session_id,v_date,v_month,
      p_latitude,p_longitude,p_gps_accuracy_meters,
      (v_match->>'premise_id')::uuid,
      v_match->>'premise_name',
      (v_match->>'distance_meters')::numeric,
      (v_match->>'allowed_radius_meters')::numeric,
      v_count+1,
      v_policy.outside_checkout_penalty_amount,
      v_mode
    )
    returning violation_id into v_violation_id;

    return jsonb_build_object(
      'ok',true,
      'event','CHECK_OUT',
      'checkout_status','OUTSIDE_GEOFENCE_ALLOWED',
      'violation_number',v_count+1,
      'monthly_limit',v_policy.outside_checkout_monthly_limit,
      'penalty_proposed',v_policy.outside_checkout_penalty_amount,
      'violation_id',v_violation_id,
      'ot_eligible',false
    );
  end if;

  update public.rr_regular_attendance_sessions_v778_2
  set checkout_at=v_now,
      checkout_latitude=p_latitude,
      checkout_longitude=p_longitude,
      checkout_accuracy_meters=p_gps_accuracy_meters,
      checkout_premise_id=(v_match->>'premise_id')::uuid,
      checkout_premise_name=v_match->>'premise_name',
      checkout_distance_meters=(v_match->>'distance_meters')::numeric,
      checkout_inside_geofence=true,
      checkout_status='INSIDE_GEOFENCE',
      source_checkout_id=trim(p_source_checkout_id),
      updated_at=now()
  where session_id=v_session.session_id;

  update public.rr_attendance_reminder_state_v778_2
  set status='RESOLVED',resolved_at=v_now
  where worker_id=p_worker_id
    and business_date=v_date
    and reminder_type='CHECKOUT_PENDING'
    and data_mode=v_mode
    and status in('DUE','ACKNOWLEDGED');

  return jsonb_build_object(
    'ok',true,
    'event','CHECK_OUT',
    'checkout_status','INSIDE_GEOFENCE',
    'server_time',v_now,
    'premise',v_match
  );
end $$;

-- ------------------------------------------------------------
-- 15. Register immutable live-video evidence
-- Frontend must open live camera and upload file first.
-- ------------------------------------------------------------
create or replace function public.rr_register_attendance_video_v778_2(
  p_worker_id uuid,
  p_evidence_type text,
  p_duration_seconds integer,
  p_storage_bucket text,
  p_storage_path text,
  p_content_hash text,
  p_latitude numeric,
  p_longitude numeric,
  p_gps_accuracy_meters numeric,
  p_device_session_id text,
  p_source_capture_id text,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_now timestamptz:=now();
  v_date date:=(v_now at time zone 'Asia/Kolkata')::date;
  v_type text:=upper(trim(coalesce(p_evidence_type,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_match jsonb;
  v_min integer;
  v_max integer;
  v_id uuid;
begin
  perform public.rr_attendance_actor_v778_2(p_worker_id);

  select * into v_policy
  from public.rr_current_attendance_policy_v778_2(
    p_worker_id,v_date,v_mode
  );

  if v_type in('OT_START','HOLIDAY_START') then
    v_min:=v_policy.ot_start_video_min_seconds;
    v_max:=v_policy.ot_start_video_max_seconds;
  elsif v_type in('OT_END','HOLIDAY_END') then
    v_min:=v_policy.ot_end_video_min_seconds;
    v_max:=v_policy.ot_end_video_max_seconds;
  else
    raise exception 'Invalid evidence type.';
  end if;

  if p_duration_seconds<v_min or p_duration_seconds>v_max then
    raise exception 'Video duration outside allowed standard %-% seconds.',
      v_min,v_max;
  end if;

  v_match:=public.rr_nearest_attendance_premise_v778_2(
    p_worker_id,p_latitude,p_longitude,v_date,v_mode
  );

  if not coalesce((v_match->>'ok')::boolean,false)
     or not coalesce((v_match->>'inside_geofence')::boolean,false)
  then
    raise exception 'OT/Holiday video must be captured inside geofence.';
  end if;

  insert into public.rr_attendance_video_evidence_v778_2(
    worker_id,evidence_type,captured_at,duration_seconds,
    live_camera_capture,gallery_upload,
    storage_bucket,storage_path,content_hash,
    latitude,longitude,gps_accuracy_meters,
    premise_id,premise_name,distance_meters,inside_geofence,
    device_session_id,source_capture_id,data_mode
  )
  values(
    p_worker_id,v_type,v_now,p_duration_seconds,
    true,false,
    trim(p_storage_bucket),trim(p_storage_path),trim(p_content_hash),
    p_latitude,p_longitude,p_gps_accuracy_meters,
    (v_match->>'premise_id')::uuid,
    v_match->>'premise_name',
    (v_match->>'distance_meters')::numeric,
    true,
    nullif(trim(p_device_session_id),''),
    trim(p_source_capture_id),v_mode
  )
  returning evidence_id into v_id;

  return jsonb_build_object(
    'ok',true,
    'evidence_id',v_id,
    'captured_at',v_now,
    'evidence_type',v_type,
    'duration_standard',jsonb_build_object('min',v_min,'max',v_max)
  );
end $$;

-- ------------------------------------------------------------
-- 16. OT / Holiday Check-In
-- Holiday classification is explicitly supplied by trusted UI/calendar adapter.
-- It cannot change rate: always 1.0.
-- ------------------------------------------------------------
create or replace function public.rr_ot_checkin_v778_2(
  p_worker_id uuid,
  p_start_evidence_id uuid,
  p_is_holiday boolean default false,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_now timestamptz:=now();
  v_date date:=(v_now at time zone 'Asia/Kolkata')::date;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_work_type text:=case when p_is_holiday then 'HOLIDAY_WORK' else 'REGULAR_OT' end;
  v_policy public.rr_worker_attendance_policy_v778_1%rowtype;
  v_evidence public.rr_attendance_video_evidence_v778_2%rowtype;
  v_payroll record;
  v_regular public.rr_regular_attendance_sessions_v778_2%rowtype;
  v_id uuid;
begin
  perform public.rr_attendance_actor_v778_2(p_worker_id);

  select * into v_policy
  from public.rr_current_attendance_policy_v778_2(
    p_worker_id,v_date,v_mode
  );

  select worker_category,overtime_applicable,holiday_extra_applicable
  into v_payroll
  from public.rr_worker_payroll_profile_v777_2
  where worker_id=p_worker_id
    and status='ACTIVE'
    and data_mode=v_mode
    and effective_from<=v_date
    and (effective_to is null or effective_to>=v_date)
  order by effective_from desc
  limit 1;

  if not found or upper(coalesce(v_payroll.worker_category,''))<>'SALARIED' then
    raise exception 'OT/Holiday work is only for SALARIED workers.';
  end if;

  if not p_is_holiday and not coalesce(v_payroll.overtime_applicable,false) then
    raise exception 'OT is disabled for this worker.';
  end if;

  if p_is_holiday and not coalesce(v_payroll.holiday_extra_applicable,false) then
    raise exception 'Holiday work is disabled for this worker.';
  end if;

  if not p_is_holiday then
    select * into v_regular
    from public.rr_regular_attendance_sessions_v778_2
    where worker_id=p_worker_id
      and business_date=v_date
      and data_mode=v_mode
    limit 1;

    if not found
       or v_regular.checkout_at is null
       or v_regular.checkout_inside_geofence is not true
       or v_regular.forgot_checkout
    then
      raise exception 'Valid inside-geofence regular checkout required before OT.';
    end if;

    if (v_now at time zone 'Asia/Kolkata')::time < time '20:10' then
      raise exception 'Regular OT may start only at/after 8:10 PM.';
    end if;
  end if;

  select * into v_evidence
  from public.rr_attendance_video_evidence_v778_2
  where evidence_id=p_start_evidence_id
    and worker_id=p_worker_id
    and data_mode=v_mode;

  if not found then raise exception 'Start video evidence not found.'; end if;

  if p_is_holiday and v_evidence.evidence_type<>'HOLIDAY_START' then
    raise exception 'HOLIDAY_START evidence required.';
  end if;

  if not p_is_holiday and v_evidence.evidence_type<>'OT_START' then
    raise exception 'OT_START evidence required.';
  end if;

  insert into public.rr_ot_work_sessions_v778_2(
    worker_id,business_date,work_type,status,
    ot_checkin_at,
    start_latitude,start_longitude,start_accuracy_meters,
    start_premise_id,start_premise_name,start_distance_meters,
    start_inside_geofence,
    start_video_evidence_id,
    rate_multiplier,payable_eligible,data_mode,created_by
  )
  values(
    p_worker_id,v_date,v_work_type,'OPEN',
    v_evidence.captured_at,
    v_evidence.latitude,v_evidence.longitude,v_evidence.gps_accuracy_meters,
    v_evidence.premise_id,v_evidence.premise_name,v_evidence.distance_meters,
    true,
    v_evidence.evidence_id,
    1.000,false,v_mode,auth.uid()
  )
  returning ot_session_id into v_id;

  return jsonb_build_object(
    'ok',true,
    'ot_session_id',v_id,
    'work_type',v_work_type,
    'payable_start_time',v_evidence.captured_at,
    'rate_multiplier',1.0
  );
end $$;

-- ------------------------------------------------------------
-- 17. OT / Holiday Check-Out
-- Both start and end live-video evidence mandatory.
-- ------------------------------------------------------------
create or replace function public.rr_ot_checkout_v778_2(
  p_worker_id uuid,
  p_end_evidence_id uuid,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_session public.rr_ot_work_sessions_v778_2%rowtype;
  v_evidence public.rr_attendance_video_evidence_v778_2%rowtype;
  v_expected text;
  v_minutes integer;
begin
  perform public.rr_attendance_actor_v778_2(p_worker_id);

  select * into v_session
  from public.rr_ot_work_sessions_v778_2
  where worker_id=p_worker_id
    and status='OPEN'
    and data_mode=v_mode
  order by ot_checkin_at desc
  limit 1
  for update;

  if not found then raise exception 'Open OT/Holiday session not found.'; end if;

  select * into v_evidence
  from public.rr_attendance_video_evidence_v778_2
  where evidence_id=p_end_evidence_id
    and worker_id=p_worker_id
    and data_mode=v_mode;

  if not found then raise exception 'End video evidence not found.'; end if;

  v_expected:=case
    when v_session.work_type='HOLIDAY_WORK' then 'HOLIDAY_END'
    else 'OT_END'
  end;

  if v_evidence.evidence_type<>v_expected then
    raise exception '% evidence required.',v_expected;
  end if;

  if not v_evidence.inside_geofence then
    raise exception 'OT/Holiday Check-Out outside geofence is blocked.';
  end if;

  v_minutes:=greatest(
    0,
    floor(extract(epoch from(
      v_evidence.captured_at-v_session.ot_checkin_at
    ))/60)::integer
  );

  update public.rr_ot_work_sessions_v778_2
  set status='COMPLETED',
      ot_checkout_at=v_evidence.captured_at,
      end_latitude=v_evidence.latitude,
      end_longitude=v_evidence.longitude,
      end_accuracy_meters=v_evidence.gps_accuracy_meters,
      end_premise_id=v_evidence.premise_id,
      end_premise_name=v_evidence.premise_name,
      end_distance_meters=v_evidence.distance_meters,
      end_inside_geofence=true,
      end_video_evidence_id=v_evidence.evidence_id,
      payable_minutes=v_minutes,
      payable_eligible=true,
      updated_at=now()
  where ot_session_id=v_session.ot_session_id;

  return jsonb_build_object(
    'ok',true,
    'ot_session_id',v_session.ot_session_id,
    'work_type',v_session.work_type,
    'payable_minutes',v_minutes,
    'rate_multiplier',1.0
  );
end $$;

-- ------------------------------------------------------------
-- 18. Leave request
-- ------------------------------------------------------------
create or replace function public.rr_request_leave_v778_2(
  p_worker_id uuid,
  p_leave_from date,
  p_leave_to date,
  p_worker_message text,
  p_leave_type text default 'UNPAID_LEAVE',
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_type text:=upper(trim(coalesce(p_leave_type,'UNPAID_LEAVE')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_id uuid;
begin
  perform public.rr_attendance_actor_v778_2(p_worker_id);

  if p_leave_from<current_date then
    raise exception 'Worker cannot create a backdated leave request.';
  end if;

  if p_leave_to<p_leave_from then raise exception 'Invalid leave dates.'; end if;

  if v_type not in(
    'UNPAID_LEAVE','PAID_LEAVE','HALF_DAY',
    'EMERGENCY_LEAVE','OTHER'
  ) then raise exception 'Invalid leave type.'; end if;

  if exists(
    select 1
    from public.rr_worker_leave_requests_v778_2 l
    where l.worker_id=p_worker_id
      and l.data_mode=v_mode
      and l.status in('PENDING','APPROVED')
      and daterange(l.leave_from,l.leave_to,'[]')
        && daterange(p_leave_from,p_leave_to,'[]')
  ) then raise exception 'Overlapping leave request exists.'; end if;

  insert into public.rr_worker_leave_requests_v778_2(
    worker_id,leave_type,leave_from,leave_to,expected_return_date,
    worker_message,status,data_mode
  )
  values(
    p_worker_id,v_type,p_leave_from,p_leave_to,p_leave_to+1,
    trim(p_worker_message),'PENDING',v_mode
  )
  returning leave_request_id into v_id;

  return jsonb_build_object(
    'ok',true,
    'leave_request_id',v_id,
    'status','PENDING',
    'admin_message',jsonb_build_object(
      'worker_id',p_worker_id,
      'leave_from',p_leave_from,
      'leave_to',p_leave_to,
      'message',trim(p_worker_message)
    )
  );
end $$;

-- ------------------------------------------------------------
-- 19. Admin leave decision
-- ------------------------------------------------------------
create or replace function public.rr_decide_leave_v778_2(
  p_leave_request_id uuid,
  p_decision text,
  p_decision_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_decision text:=upper(trim(coalesce(p_decision,'')));
  v_leave public.rr_worker_leave_requests_v778_2%rowtype;
begin
  select * into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found or lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Owner/Admin leave approval required.';
  end if;

  if v_decision not in('APPROVED','REJECTED') then
    raise exception 'Decision must be APPROVED or REJECTED.';
  end if;

  update public.rr_worker_leave_requests_v778_2
  set status=v_decision,
      decided_at=now(),
      decided_by=auth.uid(),
      decision_note=p_decision_note
  where leave_request_id=p_leave_request_id
    and status='PENDING'
  returning * into v_leave;

  if not found then raise exception 'Pending leave request not found.'; end if;

  return jsonb_build_object(
    'ok',true,
    'leave_request_id',v_leave.leave_request_id,
    'worker_id',v_leave.worker_id,
    'status',v_decision,
    'expected_return_date',v_leave.expected_return_date
  );
end $$;

-- ------------------------------------------------------------
-- 20. Reminder generator
-- Call hourly or from app foreground.
-- 10:10 Check-In reminder.
-- 20:10 Check-Out reminder, repeat every 15 min.
-- ------------------------------------------------------------
create or replace function public.rr_generate_attendance_reminders_v778_2(
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_now timestamptz:=now();
  v_local timestamp:=v_now at time zone 'Asia/Kolkata';
  v_date date:=v_local::date;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_count integer:=0;
begin
  insert into public.rr_attendance_reminder_state_v778_2(
    worker_id,business_date,reminder_type,
    first_due_at,next_due_at,repeat_minutes,status,data_mode
  )
  select
    p.worker_id,v_date,'CHECKIN_PENDING',
    (v_date+time '10:10') at time zone 'Asia/Kolkata',
    (v_date+time '10:10') at time zone 'Asia/Kolkata',
    p.reminder_repeat_minutes,'DUE',v_mode
  from public.rr_worker_attendance_policy_v778_1 p
  join public.rr_worker_payroll_profile_v777_2 pay
    on pay.worker_id=p.worker_id
  where p.status='ACTIVE'
    and p.data_mode=v_mode
    and pay.status='ACTIVE'
    and pay.data_mode=v_mode
    and upper(pay.worker_category)='SALARIED'
    and p.attendance_type='FACTORY_GEOFENCE'
    and v_local::time>=time '10:10'
    and not exists(
      select 1
      from public.rr_regular_attendance_sessions_v778_2 s
      where s.worker_id=p.worker_id
        and s.business_date=v_date
        and s.data_mode=v_mode
    )
    and not exists(
      select 1
      from public.rr_worker_leave_requests_v778_2 l
      where l.worker_id=p.worker_id
        and l.status='APPROVED'
        and v_date between l.leave_from and l.leave_to
        and l.data_mode=v_mode
    )
  on conflict(worker_id,business_date,reminder_type,data_mode) do nothing;

  get diagnostics v_count=row_count;

  insert into public.rr_attendance_reminder_state_v778_2(
    worker_id,business_date,reminder_type,
    first_due_at,next_due_at,repeat_minutes,status,data_mode
  )
  select
    s.worker_id,v_date,'CHECKOUT_PENDING',
    (v_date+time '20:10') at time zone 'Asia/Kolkata',
    (v_date+time '20:10') at time zone 'Asia/Kolkata',
    p.reminder_repeat_minutes,'DUE',v_mode
  from public.rr_regular_attendance_sessions_v778_2 s
  join public.rr_worker_attendance_policy_v778_1 p
    on p.worker_id=s.worker_id
   and p.status='ACTIVE'
   and p.data_mode=s.data_mode
  where s.business_date=v_date
    and s.data_mode=v_mode
    and s.checkout_at is null
    and v_local::time>=time '20:10'
  on conflict(worker_id,business_date,reminder_type,data_mode) do nothing;

  return jsonb_build_object(
    'ok',true,
    'business_date',v_date,
    'reminders_ready',true,
    'delivery_note',
      'Frontend/push worker must deliver DUE reminders every repeat_minutes.'
  );
end $$;

-- ------------------------------------------------------------
-- 21. Resolve forgotten checkout
-- Hard rule: OT zero, no override.
-- ------------------------------------------------------------
create or replace function public.rr_auto_close_forgot_checkout_v778_2(
  p_worker_id uuid,
  p_business_date date,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_session public.rr_regular_attendance_sessions_v778_2%rowtype;
  v_close timestamptz:=(p_business_date+time '20:00') at time zone 'Asia/Kolkata';
begin
  select * into v_session
  from public.rr_regular_attendance_sessions_v778_2
  where worker_id=p_worker_id
    and business_date=p_business_date
    and data_mode=v_mode
  limit 1
  for update;

  if not found or v_session.checkout_at is not null then
    raise exception 'Open forgotten checkout session not found.';
  end if;

  update public.rr_regular_attendance_sessions_v778_2
  set checkout_at=v_close,
      checkout_status='AUTO_CLOSED_FORGOT_CHECKOUT',
      forgot_checkout=true,
      ot_hard_zero=true,
      updated_at=now()
  where session_id=v_session.session_id;

  update public.rr_ot_work_sessions_v778_2
  set status='REJECTED',
      payable_minutes=0,
      payable_eligible=false,
      rejection_reason='FORGOT_REGULAR_CHECKOUT_HARD_OT_ZERO',
      updated_at=now()
  where worker_id=p_worker_id
    and business_date=p_business_date
    and data_mode=v_mode
    and status='OPEN';

  return jsonb_build_object(
    'ok',true,
    'checkout_status','AUTO_CLOSED_FORGOT_CHECKOUT',
    'ot_payable_minutes',0,
    'override_allowed',false
  );
end $$;

-- ------------------------------------------------------------
-- 22. Daily minute calculation
-- Time rules:
-- Shift 10:00-20:00.
-- Check-in 10:00-10:10: no deduction.
-- Check-in after 10:10: late minutes from 10:10.
-- Early Check-In before 10:00: positive minutes if policy enabled.
-- Check-Out before 20:00: early-out deduction.
-- Check-Out 20:00-20:10: no OT.
-- OT only from valid OT session.
-- ------------------------------------------------------------
create or replace function public.rr_calculate_attendance_day_v778_2(
  p_worker_id uuid,
  p_business_date date,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
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
end $$;

-- ------------------------------------------------------------
-- 23. Exact monthly salary formula helper
-- Final salary =
-- base salary
-- + net minute adjustment × per-minute rate
-- - claims
-- + incentives
-- ------------------------------------------------------------
create or replace function public.rr_calculate_monthly_salary_v778_2(
  p_monthly_salary numeric,
  p_scheduled_payable_minutes integer,
  p_early_checkin_minutes integer,
  p_verified_ot_minutes integer,
  p_verified_holiday_minutes integer,
  p_late_checkin_minutes integer,
  p_early_checkout_minutes integer,
  p_claims numeric default 0,
  p_incentives numeric default 0
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_rate numeric;
  v_net_minutes integer;
  v_time_adjustment numeric;
  v_final numeric;
begin
  if coalesce(p_scheduled_payable_minutes,0)<=0 then
    raise exception 'Scheduled payable minutes must be greater than zero.';
  end if;

  v_rate:=p_monthly_salary/p_scheduled_payable_minutes;

  v_net_minutes:=
      coalesce(p_early_checkin_minutes,0)
    + coalesce(p_verified_ot_minutes,0)
    + coalesce(p_verified_holiday_minutes,0)
    - coalesce(p_late_checkin_minutes,0)
    - coalesce(p_early_checkout_minutes,0);

  v_time_adjustment:=v_net_minutes*v_rate;

  v_final:=
      p_monthly_salary
    + v_time_adjustment
    - coalesce(p_claims,0)
    + coalesce(p_incentives,0);

  return jsonb_build_object(
    'monthly_salary',round(p_monthly_salary,2),
    'scheduled_payable_minutes',p_scheduled_payable_minutes,
    'per_minute_rate',round(v_rate,6),
    'net_adjustment_minutes',v_net_minutes,
    'time_adjustment_amount',round(v_time_adjustment,2),
    'claims',round(coalesce(p_claims,0),2),
    'incentives',round(coalesce(p_incentives,0),2),
    'final_payable_salary',round(v_final,2),
    'holiday_multiplier',1.0
  );
end $$;

-- ------------------------------------------------------------
-- 24. Read boards
-- ------------------------------------------------------------
create or replace view public.rr_attendance_live_board_v778_2 as
select
  w.worker_id,
  w.worker_code,
  w.worker_name,
  w.department_code,

  p.workforce_type,
  p.attendance_type,
  p.premise_access_mode,

  s.business_date,
  s.checkin_at,
  s.checkout_at,
  s.checkout_status,
  s.forgot_checkout,
  s.ot_hard_zero,

  d.early_checkin_minutes,
  d.late_checkin_minutes,
  d.early_checkout_minutes,
  d.verified_ot_minutes,
  d.verified_holiday_minutes,
  d.net_adjustment_minutes,
  d.attendance_status,

  p.data_mode
from public.rr_worker_directory_unified_v1 w
left join lateral(
  select x.*
  from public.rr_worker_attendance_policy_v778_1 x
  where x.worker_id=w.worker_id
  order by (x.status='ACTIVE') desc,x.effective_from desc,x.configured_at desc
  limit 1
) p on true
left join public.rr_regular_attendance_sessions_v778_2 s
  on s.worker_id=w.worker_id
 and s.business_date=(now() at time zone 'Asia/Kolkata')::date
 and s.data_mode=coalesce(p.data_mode,'TEST')
left join public.rr_attendance_daily_minutes_v778_2 d
  on d.worker_id=w.worker_id
 and d.business_date=(now() at time zone 'Asia/Kolkata')::date
 and d.data_mode=coalesce(p.data_mode,'TEST');

create or replace view public.rr_attendance_reminders_due_v778_2 as
select
  r.*,
  w.worker_name,
  w.department_code
from public.rr_attendance_reminder_state_v778_2 r
join public.rr_worker_directory_unified_v1 w
  on w.worker_id=r.worker_id
where r.status='DUE'
  and r.next_due_at<=now();

create or replace view public.rr_leave_approval_board_v778_2 as
select
  l.*,
  w.worker_name,
  w.worker_code,
  w.department_code
from public.rr_worker_leave_requests_v778_2 l
join public.rr_worker_directory_unified_v1 w
  on w.worker_id=l.worker_id;

-- ------------------------------------------------------------
-- 25. Direct-write lock and grants
-- ------------------------------------------------------------
revoke all on
  public.rr_regular_attendance_sessions_v778_2,
  public.rr_attendance_checkout_violations_v778_2,
  public.rr_ot_work_sessions_v778_2,
  public.rr_attendance_video_evidence_v778_2,
  public.rr_worker_leave_requests_v778_2,
  public.rr_worker_reactivation_requests_v778_2,
  public.rr_attendance_reminder_state_v778_2,
  public.rr_attendance_daily_minutes_v778_2
from anon,authenticated;

grant select on
  public.rr_attendance_live_board_v778_2,
  public.rr_attendance_reminders_due_v778_2,
  public.rr_leave_approval_board_v778_2
to authenticated;

grant execute on function public.rr_save_attendance_premise_v778_2(
  uuid,text,text,text,numeric,numeric,numeric,boolean,text,date,date
) to authenticated;

grant execute on function public.rr_attendance_actor_v778_2(uuid)
to authenticated;

grant execute on function public.rr_current_attendance_policy_v778_2(
  uuid,date,text
) to authenticated;

grant execute on function public.rr_nearest_attendance_premise_v778_2(
  uuid,numeric,numeric,date,text
) to authenticated;

grant execute on function public.rr_regular_checkin_v778_2(
  uuid,numeric,numeric,numeric,text,text
) to authenticated;

grant execute on function public.rr_regular_checkout_v778_2(
  uuid,numeric,numeric,numeric,text,text
) to authenticated;

grant execute on function public.rr_register_attendance_video_v778_2(
  uuid,text,integer,text,text,text,numeric,numeric,numeric,text,text,text
) to authenticated;

grant execute on function public.rr_ot_checkin_v778_2(
  uuid,uuid,boolean,text
) to authenticated;

grant execute on function public.rr_ot_checkout_v778_2(
  uuid,uuid,text
) to authenticated;

grant execute on function public.rr_request_leave_v778_2(
  uuid,date,date,text,text,text
) to authenticated;

grant execute on function public.rr_decide_leave_v778_2(
  uuid,text,text
) to authenticated;

grant execute on function public.rr_generate_attendance_reminders_v778_2(text)
to authenticated;

grant execute on function public.rr_auto_close_forgot_checkout_v778_2(
  uuid,date,text
) to authenticated;

grant execute on function public.rr_calculate_attendance_day_v778_2(
  uuid,date,text
) to authenticated;

grant execute on function public.rr_calculate_monthly_salary_v778_2(
  numeric,integer,integer,integer,integer,integer,integer,numeric,numeric
) to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V778_2_FINAL_ATTENDANCE_LEAVE_OT_CORE',

  'regular_attendance',jsonb_build_object(
    'checkin_outside_geofence','BLOCKED',
    'checkout_outside_geofence','FIRST_4_PER_MONTH_ACCEPTED_WITH_50_PENALTY_EVENT',
    'fifth_outside_checkout','BLOCKED',
    'checkin_grace_until','10:10',
    'checkout_grace_until','20:10',
    'reminder_repeat_minutes',15
  ),

  'salary_time_formula',jsonb_build_object(
    'positive_minutes',jsonb_build_array(
      'EARLY_CHECKIN','VERIFIED_OT','VERIFIED_HOLIDAY_WORK'
    ),
    'negative_minutes',jsonb_build_array(
      'LATE_CHECKIN_AFTER_10_10','EARLY_CHECKOUT'
    ),
    'claims_timing','SETTLEMENT_OR_FULL_AND_FINAL',
    'incentives_added',true
  ),

  'ot',jsonb_build_object(
    'salaried_only',true,
    'start_video_seconds','10-30',
    'end_video_seconds','10-45',
    'inside_geofence_required',true,
    'forgot_regular_checkout_ot_zero',true,
    'holiday_multiplier',1.0
  ),

  'leave',jsonb_build_object(
    'simple_worker_message',true,
    'admin_approval',true,
    'approved_leave_suppresses_attendance_reminders',true,
    'inactive_return_requires_reactivation_approval',true
  ),

  'ard_business_rules_modified',false,
  'ard_bridge_next',true,
  'frontend_camera_upload_required',true,
  'push_delivery_worker_required',true,
  'payroll_ledger_posting_included',false
) as rr_upm_v778_2_final_result;
