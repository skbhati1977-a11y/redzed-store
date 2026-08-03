
-- ============================================================
-- REDZED V778.1 — ATTENDANCE CORE FOUNDATION
-- Zero-guess scope:
--   * Uses verified V777.2 objects only.
--   * Does not guess Witness/Device/Test-phone schemas.
--   * Adds multi-premises geofence and attendance policy extension.
--   * Supports low-hassle FIELD attendance for Commission Agents.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Attendance Premises Master
-- ------------------------------------------------------------
create table if not exists public.rr_attendance_premises_v778_1 (
  premise_id uuid primary key default gen_random_uuid(),

  premise_code text not null unique,
  premise_name text not null,

  premise_type text not null
    check(premise_type in(
      'FACTORY',
      'OFFICE',
      'WAREHOUSE',
      'CUSTOMER',
      'MARKET',
      'FIELD_POINT',
      'OTHER'
    )),

  latitude numeric(10,7) not null
    check(latitude between -90 and 90),

  longitude numeric(10,7) not null
    check(longitude between -180 and 180),

  radius_meters numeric(10,2) not null default 100
    check(radius_meters>0),

  is_fixed_location boolean not null default true,
  is_active boolean not null default true,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  effective_from date not null default current_date,
  effective_to date,

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),

  check(effective_to is null or effective_to>=effective_from)
);

create unique index if not exists rr_attendance_premises_v778_1_coord_uq
on public.rr_attendance_premises_v778_1(
  latitude,
  longitude,
  data_mode
);

-- Verified locations supplied by user.
insert into public.rr_attendance_premises_v778_1(
  premise_code,
  premise_name,
  premise_type,
  latitude,
  longitude,
  radius_meters,
  is_fixed_location,
  is_active,
  data_mode
)
values
(
  'LOCATION_1',
  'REDZED Location 1',
  'FACTORY',
  28.6628890,
  77.2590560,
  100,
  true,
  true,
  'TEST'
),
(
  'LOCATION_2',
  'REDZED Location 2 — Kailash Nagar',
  'FACTORY',
  28.6660260,
  77.2566850,
  100,
  true,
  true,
  'TEST'
)
on conflict(premise_code) do update set
  premise_name=excluded.premise_name,
  premise_type=excluded.premise_type,
  latitude=excluded.latitude,
  longitude=excluded.longitude,
  radius_meters=excluded.radius_meters,
  is_fixed_location=excluded.is_fixed_location,
  is_active=excluded.is_active,
  data_mode=excluded.data_mode,
  updated_at=now();

-- ------------------------------------------------------------
-- 2. Worker Attendance Policy Extension
--
-- Keeps workforce type separate from attendance type.
-- Existing Worker ID remains the common identity.
-- ------------------------------------------------------------
create table if not exists public.rr_worker_attendance_policy_v778_1 (
  policy_id uuid primary key default gen_random_uuid(),
  worker_id uuid not null,

  workforce_type text not null
    check(workforce_type in(
      'FACTORY_WORKER',
      'FIELD_WORKER',
      'COMMISSION_AGENT',
      'REMOTE_STAFF',
      'VENDOR_REPRESENTATIVE'
    )),

  attendance_type text not null
    check(attendance_type in(
      'FACTORY_GEOFENCE',
      'FIELD_EVENT',
      'REMOTE_EVENT',
      'PRODUCTION_ACTIVITY',
      'VISIT_BASED',
      'NONE'
    )),

  continuous_location_required boolean not null default false,

  start_day_required boolean not null default false,
  end_day_required boolean not null default false,

  auto_start_from_first_business_event boolean not null default false,
  auto_end_at_business_day_close boolean not null default false,

  location_required_on_start boolean not null default true,
  location_required_on_end boolean not null default true,
  location_required_on_business_event boolean not null default true,

  minimum_verified_business_events integer not null default 0
    check(minimum_verified_business_events>=0),

  gps_accuracy_limit_meters numeric(10,2) not null default 100
    check(gps_accuracy_limit_meters>0),

  status text not null default 'ACTIVE'
    check(status in('ACTIVE','INACTIVE')),

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  effective_from date not null default current_date,
  effective_to date,

  configured_at timestamptz not null default now(),
  configured_by uuid default auth.uid(),
  reason text,

  check(effective_to is null or effective_to>=effective_from),

  check(
    (
      workforce_type='COMMISSION_AGENT'
      and attendance_type in('FIELD_EVENT','VISIT_BASED')
      and continuous_location_required=false
    )
    or workforce_type<>'COMMISSION_AGENT'
  )
);

create index if not exists rr_worker_attendance_policy_v778_1_worker_idx
on public.rr_worker_attendance_policy_v778_1(
  worker_id,
  data_mode,
  effective_from,
  effective_to,
  status
);

-- ------------------------------------------------------------
-- 3. Worker-Premise Authorization
-- ------------------------------------------------------------
create table if not exists public.rr_worker_attendance_premises_v778_1 (
  worker_id uuid not null,
  premise_id uuid not null
    references public.rr_attendance_premises_v778_1(premise_id),

  is_primary boolean not null default false,
  is_active boolean not null default true,

  effective_from date not null default current_date,
  effective_to date,

  assigned_at timestamptz not null default now(),
  assigned_by uuid default auth.uid(),
  reason text,

  primary key(worker_id,premise_id,effective_from),

  check(effective_to is null or effective_to>=effective_from)
);

-- ------------------------------------------------------------
-- 4. Field Attendance Sessions
--
-- No continuous tracking.
-- One Start Day + business events + one End Day.
-- ------------------------------------------------------------
create table if not exists public.rr_field_attendance_sessions_v778_1 (
  session_id uuid primary key default gen_random_uuid(),

  worker_id uuid not null,
  business_date date not null,

  workforce_type text not null
    check(workforce_type in(
      'FIELD_WORKER',
      'COMMISSION_AGENT',
      'REMOTE_STAFF',
      'VENDOR_REPRESENTATIVE'
    )),

  session_status text not null default 'OPEN'
    check(session_status in(
      'OPEN',
      'AUTO_OPENED',
      'CLOSED',
      'AUTO_CLOSED',
      'REVIEW_REQUIRED',
      'CANCELLED'
    )),

  started_at timestamptz not null,
  ended_at timestamptz,

  start_latitude numeric(10,7),
  start_longitude numeric(10,7),
  start_accuracy_meters numeric(10,2),

  end_latitude numeric(10,7),
  end_longitude numeric(10,7),
  end_accuracy_meters numeric(10,2),

  verified_business_events integer not null default 0
    check(verified_business_events>=0),

  start_source text not null
    check(start_source in(
      'MANUAL_START',
      'AUTO_FROM_FIRST_EVENT',
      'OWNER_ADMIN'
    )),

  end_source text
    check(end_source is null or end_source in(
      'MANUAL_END',
      'AUTO_DAY_CLOSE',
      'OWNER_ADMIN'
    )),

  review_reason text,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),

  unique(worker_id,business_date,data_mode),

  check(ended_at is null or ended_at>=started_at)
);

-- ------------------------------------------------------------
-- 5. Field Business Events
--
-- Normal business actions create these automatically:
-- order, collection, customer visit, invoice, follow-up, etc.
-- ------------------------------------------------------------
create table if not exists public.rr_field_business_events_v778_1 (
  field_event_id uuid primary key default gen_random_uuid(),

  session_id uuid
    references public.rr_field_attendance_sessions_v778_1(session_id),

  worker_id uuid not null,
  business_date date not null,

  event_type text not null
    check(event_type in(
      'CUSTOMER_VISIT',
      'ORDER_CREATED',
      'ORDER_APPROVED',
      'COLLECTION_RECORDED',
      'INVOICE_ACTIVITY',
      'FOLLOW_UP',
      'NEW_CUSTOMER',
      'OTHER_WORK_EVENT'
    )),

  source_module text not null,
  source_record_id text not null,

  occurred_at timestamptz not null,

  latitude numeric(10,7),
  longitude numeric(10,7),
  gps_accuracy_meters numeric(10,2),

  customer_id text,
  customer_latitude numeric(10,7),
  customer_longitude numeric(10,7),
  customer_distance_meters numeric(12,2),

  verification_status text not null default 'VERIFIED'
    check(verification_status in(
      'VERIFIED',
      'REVIEW_REQUIRED',
      'REJECTED'
    )),

  verification_reason text,

  metadata jsonb not null default '{}'::jsonb,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now(),

  unique(source_module,source_record_id,data_mode)
);

-- ------------------------------------------------------------
-- 6. Geofence Event Audit
-- ------------------------------------------------------------
create table if not exists public.rr_attendance_geofence_audit_v778_1 (
  geofence_audit_id uuid primary key default gen_random_uuid(),

  worker_id uuid not null,
  event_type text not null,

  event_at timestamptz not null,
  business_date date not null,

  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  gps_accuracy_meters numeric(10,2),

  matched_premise_id uuid
    references public.rr_attendance_premises_v778_1(premise_id),

  matched_premise_name text,
  distance_meters numeric(12,2),
  allowed_radius_meters numeric(10,2),

  inside_geofence boolean not null,

  source_module text,
  source_record_id text,

  data_mode text not null default 'TEST'
    check(data_mode in('TEST','REAL')),

  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 7. Haversine Distance Helper
-- ------------------------------------------------------------
create or replace function public.rr_distance_meters_v778_1(
  p_lat1 numeric,
  p_lon1 numeric,
  p_lat2 numeric,
  p_lon2 numeric
)
returns numeric
language sql
immutable
as $$
  select 6371000 * 2 * asin(
    sqrt(
      power(sin(radians((p_lat2-p_lat1)/2)),2)
      +
      cos(radians(p_lat1))
      * cos(radians(p_lat2))
      * power(sin(radians((p_lon2-p_lon1)/2)),2)
    )
  )
$$;

-- ------------------------------------------------------------
-- 8. Match Nearest Authorized Premise
-- ------------------------------------------------------------
create or replace function public.rr_match_attendance_premise_v778_1(
  p_worker_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_on_date date,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_row record;
begin
  select
    p.premise_id,
    p.premise_code,
    p.premise_name,
    p.radius_meters,
    public.rr_distance_meters_v778_1(
      p_latitude,
      p_longitude,
      p.latitude,
      p.longitude
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

  if not found then
    return jsonb_build_object(
      'ok',false,
      'code','NO_AUTHORIZED_PREMISE',
      'worker_id',p_worker_id,
      'data_mode',v_mode
    );
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
-- 9. Set Worker Attendance Policy RPC
-- ------------------------------------------------------------
create or replace function public.rr_set_worker_attendance_policy_v778_1(
  p_worker_id uuid,
  p_workforce_type text,
  p_attendance_type text,
  p_start_day_required boolean default false,
  p_end_day_required boolean default false,
  p_auto_start_from_first_business_event boolean default false,
  p_auto_end_at_business_day_close boolean default false,
  p_location_required_on_start boolean default true,
  p_location_required_on_end boolean default true,
  p_location_required_on_business_event boolean default true,
  p_minimum_verified_business_events integer default 0,
  p_gps_accuracy_limit_meters numeric default 100,
  p_effective_from date default current_date,
  p_effective_to date default null,
  p_data_mode text default 'TEST',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_workforce text:=upper(trim(coalesce(p_workforce_type,'')));
  v_attendance text:=upper(trim(coalesce(p_attendance_type,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_id uuid;
begin
  select *
  into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then raise exception 'Active ERP profile required.'; end if;

  if lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Attendance Policy permission denied.';
  end if;

  if not exists(
    select 1
    from public.rr_worker_directory_unified_v1 w
    where w.worker_id=p_worker_id
  ) then
    raise exception 'Worker nahi mila.';
  end if;

  if v_workforce not in(
    'FACTORY_WORKER','FIELD_WORKER','COMMISSION_AGENT',
    'REMOTE_STAFF','VENDOR_REPRESENTATIVE'
  ) then
    raise exception 'Workforce Type invalid hai.';
  end if;

  if v_attendance not in(
    'FACTORY_GEOFENCE','FIELD_EVENT','REMOTE_EVENT',
    'PRODUCTION_ACTIVITY','VISIT_BASED','NONE'
  ) then
    raise exception 'Attendance Type invalid hai.';
  end if;

  if v_workforce='COMMISSION_AGENT'
     and v_attendance not in('FIELD_EVENT','VISIT_BASED')
  then
    raise exception
      'COMMISSION_AGENT ke liye FIELD_EVENT ya VISIT_BASED attendance use karein.';
  end if;

  if p_effective_to is not null and p_effective_to<p_effective_from then
    raise exception 'Effective dates invalid hain.';
  end if;

  insert into public.rr_worker_attendance_policy_v778_1(
    worker_id,
    workforce_type,
    attendance_type,
    continuous_location_required,
    start_day_required,
    end_day_required,
    auto_start_from_first_business_event,
    auto_end_at_business_day_close,
    location_required_on_start,
    location_required_on_end,
    location_required_on_business_event,
    minimum_verified_business_events,
    gps_accuracy_limit_meters,
    status,
    data_mode,
    effective_from,
    effective_to,
    configured_at,
    configured_by,
    reason
  )
  values(
    p_worker_id,
    v_workforce,
    v_attendance,
    false,
    p_start_day_required,
    p_end_day_required,
    p_auto_start_from_first_business_event,
    p_auto_end_at_business_day_close,
    p_location_required_on_start,
    p_location_required_on_end,
    p_location_required_on_business_event,
    coalesce(p_minimum_verified_business_events,0),
    coalesce(p_gps_accuracy_limit_meters,100),
    'ACTIVE',
    v_mode,
    p_effective_from,
    p_effective_to,
    now(),
    auth.uid(),
    p_reason
  )
  returning policy_id into v_id;

  return jsonb_build_object(
    'ok',true,
    'version','V778_1_ATTENDANCE_CORE_FOUNDATION',
    'policy_id',v_id,
    'worker_id',p_worker_id,
    'workforce_type',v_workforce,
    'attendance_type',v_attendance,
    'continuous_location_required',false,
    'data_mode',v_mode
  );
end $$;

-- ------------------------------------------------------------
-- 10. Read Models
-- ------------------------------------------------------------
create or replace view public.rr_attendance_premises_board_v778_1 as
select
  premise_id,
  premise_code,
  premise_name,
  premise_type,
  latitude,
  longitude,
  radius_meters,
  is_fixed_location,
  is_active,
  data_mode,
  effective_from,
  effective_to
from public.rr_attendance_premises_v778_1;

create or replace view public.rr_worker_attendance_policy_board_v778_1 as
select
  w.worker_id,
  w.worker_code,
  w.worker_name,
  w.department_code,
  w.role_code,

  p.policy_id,
  p.workforce_type,
  p.attendance_type,
  p.continuous_location_required,
  p.start_day_required,
  p.end_day_required,
  p.auto_start_from_first_business_event,
  p.auto_end_at_business_day_close,
  p.location_required_on_start,
  p.location_required_on_end,
  p.location_required_on_business_event,
  p.minimum_verified_business_events,
  p.gps_accuracy_limit_meters,
  p.status,
  p.data_mode,
  p.effective_from,
  p.effective_to

from public.rr_worker_directory_unified_v1 w
left join lateral(
  select x.*
  from public.rr_worker_attendance_policy_v778_1 x
  where x.worker_id=w.worker_id
  order by
    (x.status='ACTIVE') desc,
    x.effective_from desc,
    x.configured_at desc
  limit 1
) p on true;

-- ------------------------------------------------------------
-- 11. Direct Write Lock
-- ------------------------------------------------------------
revoke all
on public.rr_attendance_premises_v778_1,
   public.rr_worker_attendance_policy_v778_1,
   public.rr_worker_attendance_premises_v778_1,
   public.rr_field_attendance_sessions_v778_1,
   public.rr_field_business_events_v778_1,
   public.rr_attendance_geofence_audit_v778_1
from anon,authenticated;

grant select on public.rr_attendance_premises_board_v778_1
to authenticated;

grant select on public.rr_worker_attendance_policy_board_v778_1
to authenticated;

grant execute on function public.rr_distance_meters_v778_1(
  numeric,numeric,numeric,numeric
) to authenticated;

grant execute on function public.rr_match_attendance_premise_v778_1(
  uuid,numeric,numeric,date,text
) to authenticated;

grant execute on function public.rr_set_worker_attendance_policy_v778_1(
  uuid,text,text,boolean,boolean,boolean,boolean,
  boolean,boolean,boolean,integer,numeric,date,date,text,text
) to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V778_1_ATTENDANCE_CORE_FOUNDATION',

  'premises',jsonb_build_array(
    jsonb_build_object(
      'code','LOCATION_1',
      'latitude',28.6628890,
      'longitude',77.2590560,
      'radius_meters',100
    ),
    jsonb_build_object(
      'code','LOCATION_2',
      'latitude',28.6660260,
      'longitude',77.2566850,
      'radius_meters',100
    )
  ),

  'continuous_location_tracking',false,
  'commission_agent_attendance',jsonb_build_object(
    'attendance_type','FIELD_EVENT_OR_VISIT_BASED',
    'start_end_day_supported',true,
    'business_event_location_snapshots',true,
    'background_tracking_required',false
  ),

  'worker_core_reused',true,
  'existing_v777_2_tables_modified',false,
  'witness_schema_guessed',false,
  'device_schema_guessed',false,
  'payroll_posting_included',false
) as rr_upm_v778_1_result;
