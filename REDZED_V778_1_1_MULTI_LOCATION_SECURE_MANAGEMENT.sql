
-- ============================================================
-- REDZED V778.1.1 — MULTI-LOCATION SECURE MANAGEMENT
-- Dependency: V778.1 installed
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Worker premise access mode
-- ------------------------------------------------------------
alter table public.rr_worker_attendance_policy_v778_1
add column if not exists premise_access_mode text not null default 'SELECTED_ONLY';

alter table public.rr_worker_attendance_policy_v778_1
drop constraint if exists rr_worker_attendance_policy_premise_access_v778_1_1_chk;

alter table public.rr_worker_attendance_policy_v778_1
add constraint rr_worker_attendance_policy_premise_access_v778_1_1_chk
check(premise_access_mode in(
  'ALL_ACTIVE',
  'SELECTED_ONLY'
));

-- ------------------------------------------------------------
-- 2. Secure premise add/update RPC
-- Owner/Admin only
-- No hard delete; use is_active=false
-- ------------------------------------------------------------
create or replace function public.rr_save_attendance_premise_v778_1_1(
  p_premise_id uuid default null,
  p_premise_code text default null,
  p_premise_name text default null,
  p_premise_type text default 'FACTORY',
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_radius_meters numeric default 100,
  p_is_fixed_location boolean default true,
  p_is_active boolean default true,
  p_data_mode text default 'TEST',
  p_effective_from date default current_date,
  p_effective_to date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_type text:=upper(trim(coalesce(p_premise_type,'FACTORY')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_code text:=upper(trim(coalesce(p_premise_code,'')));
  v_id uuid;
begin
  select *
  into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active ERP profile required.';
  end if;

  if lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Attendance Premise manage permission denied.';
  end if;

  if nullif(v_code,'') is null then
    raise exception 'Premise Code required hai.';
  end if;

  if nullif(trim(coalesce(p_premise_name,'')),'') is null then
    raise exception 'Premise Name required hai.';
  end if;

  if v_type not in(
    'FACTORY','OFFICE','WAREHOUSE','CUSTOMER',
    'MARKET','FIELD_POINT','OTHER'
  ) then
    raise exception 'Premise Type invalid hai.';
  end if;

  if v_mode not in('TEST','REAL') then
    raise exception 'Data Mode TEST ya REAL hona chahiye.';
  end if;

  if p_latitude is null or p_latitude not between -90 and 90 then
    raise exception 'Valid Latitude required hai.';
  end if;

  if p_longitude is null or p_longitude not between -180 and 180 then
    raise exception 'Valid Longitude required hai.';
  end if;

  if coalesce(p_radius_meters,0)<=0 then
    raise exception 'Radius meters zero se bada hona chahiye.';
  end if;

  if p_effective_to is not null and p_effective_to<p_effective_from then
    raise exception 'Effective dates invalid hain.';
  end if;

  if p_premise_id is null then
    insert into public.rr_attendance_premises_v778_1(
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
      effective_to,
      created_at,
      created_by,
      updated_at
    )
    values(
      v_code,
      trim(p_premise_name),
      v_type,
      p_latitude,
      p_longitude,
      p_radius_meters,
      p_is_fixed_location,
      p_is_active,
      v_mode,
      p_effective_from,
      p_effective_to,
      now(),
      auth.uid(),
      now()
    )
    returning premise_id into v_id;
  else
    update public.rr_attendance_premises_v778_1
    set
      premise_code=v_code,
      premise_name=trim(p_premise_name),
      premise_type=v_type,
      latitude=p_latitude,
      longitude=p_longitude,
      radius_meters=p_radius_meters,
      is_fixed_location=p_is_fixed_location,
      is_active=p_is_active,
      data_mode=v_mode,
      effective_from=p_effective_from,
      effective_to=p_effective_to,
      updated_at=now()
    where premise_id=p_premise_id
    returning premise_id into v_id;

    if v_id is null then
      raise exception 'Premise ID nahi mila.';
    end if;
  end if;

  return jsonb_build_object(
    'ok',true,
    'version','V778_1_1_MULTI_LOCATION_SECURE_MANAGEMENT',
    'premise_id',v_id,
    'premise_code',v_code,
    'premise_name',trim(p_premise_name),
    'is_active',p_is_active,
    'data_mode',v_mode,
    'hard_delete_used',false
  );
end $$;

-- ------------------------------------------------------------
-- 3. Assign multiple premises to worker
-- p_premise_ids is JSON array of UUID strings
-- ------------------------------------------------------------
create or replace function public.rr_set_worker_attendance_premises_v778_1_1(
  p_worker_id uuid,
  p_premise_access_mode text,
  p_premise_ids jsonb default '[]'::jsonb,
  p_effective_from date default current_date,
  p_effective_to date default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_mode text:=upper(trim(coalesce(p_premise_access_mode,'SELECTED_ONLY')));
  v_id_text text;
  v_id uuid;
  v_count integer:=0;
begin
  select *
  into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active ERP profile required.';
  end if;

  if lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Worker Premise assignment permission denied.';
  end if;

  if not exists(
    select 1
    from public.rr_worker_directory_unified_v1 w
    where w.worker_id=p_worker_id
  ) then
    raise exception 'Worker nahi mila.';
  end if;

  if v_mode not in('ALL_ACTIVE','SELECTED_ONLY') then
    raise exception 'Premise Access Mode invalid hai.';
  end if;

  if p_effective_to is not null and p_effective_to<p_effective_from then
    raise exception 'Effective dates invalid hain.';
  end if;

  update public.rr_worker_attendance_policy_v778_1
  set premise_access_mode=v_mode
  where policy_id=(
    select p.policy_id
    from public.rr_worker_attendance_policy_v778_1 p
    where p.worker_id=p_worker_id
      and p.status='ACTIVE'
    order by p.effective_from desc,p.configured_at desc
    limit 1
  );

  if not found then
    raise exception 'Active Worker Attendance Policy required hai.';
  end if;

  update public.rr_worker_attendance_premises_v778_1
  set
    is_active=false,
    effective_to=coalesce(effective_to,current_date-1),
    reason=coalesce(p_reason,'Replaced by new premise assignment')
  where worker_id=p_worker_id
    and is_active;

  if v_mode='SELECTED_ONLY' then
    if jsonb_typeof(coalesce(p_premise_ids,'[]'::jsonb))<>'array' then
      raise exception 'Premise IDs JSON array honi chahiye.';
    end if;

    if jsonb_array_length(coalesce(p_premise_ids,'[]'::jsonb))=0 then
      raise exception 'SELECTED_ONLY me kam se kam ek Premise required hai.';
    end if;

    for v_id_text in
      select distinct trim(value)
      from jsonb_array_elements_text(p_premise_ids)
    loop
      begin
        v_id:=v_id_text::uuid;
      exception when others then
        raise exception 'Invalid Premise UUID: %',v_id_text;
      end;

      if not exists(
        select 1
        from public.rr_attendance_premises_v778_1 p
        where p.premise_id=v_id
          and p.is_active
      ) then
        raise exception 'Active Premise nahi mila: %',v_id_text;
      end if;

      insert into public.rr_worker_attendance_premises_v778_1(
        worker_id,
        premise_id,
        is_primary,
        is_active,
        effective_from,
        effective_to,
        assigned_at,
        assigned_by,
        reason
      )
      values(
        p_worker_id,
        v_id,
        v_count=0,
        true,
        p_effective_from,
        p_effective_to,
        now(),
        auth.uid(),
        p_reason
      );

      v_count:=v_count+1;
    end loop;
  end if;

  return jsonb_build_object(
    'ok',true,
    'version','V778_1_1_MULTI_LOCATION_SECURE_MANAGEMENT',
    'worker_id',p_worker_id,
    'premise_access_mode',v_mode,
    'selected_premises_count',v_count,
    'all_active_future_premises_auto_allowed',
      v_mode='ALL_ACTIVE'
  );
end $$;

-- ------------------------------------------------------------
-- 4. Replace match function to support both modes
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
  v_access_mode text;
  v_row record;
begin
  select p.premise_access_mode
  into v_access_mode
  from public.rr_worker_attendance_policy_v778_1 p
  where p.worker_id=p_worker_id
    and p.status='ACTIVE'
    and p.data_mode=v_mode
    and p.effective_from<=p_on_date
    and (p.effective_to is null or p.effective_to>=p_on_date)
  order by p.effective_from desc,p.configured_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok',false,
      'code','NO_ACTIVE_ATTENDANCE_POLICY',
      'worker_id',p_worker_id,
      'data_mode',v_mode
    );
  end if;

  if v_access_mode='ALL_ACTIVE' then
    select
      p.premise_id,
      p.premise_code,
      p.premise_name,
      p.radius_meters,
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
  else
    select
      p.premise_id,
      p.premise_code,
      p.premise_name,
      p.radius_meters,
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
  end if;

  if not found then
    return jsonb_build_object(
      'ok',false,
      'code','NO_ALLOWED_ACTIVE_PREMISE',
      'worker_id',p_worker_id,
      'premise_access_mode',v_access_mode,
      'data_mode',v_mode
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'worker_id',p_worker_id,
    'premise_access_mode',v_access_mode,
    'premise_id',v_row.premise_id,
    'premise_code',v_row.premise_code,
    'premise_name',v_row.premise_name,
    'distance_meters',round(v_row.distance_meters,2),
    'allowed_radius_meters',v_row.radius_meters,
    'inside_geofence',v_row.distance_meters<=v_row.radius_meters
  );
end $$;

-- ------------------------------------------------------------
-- 5. Secure read views
-- ------------------------------------------------------------
create or replace view public.rr_worker_attendance_premises_board_v778_1_1 as
select
  w.worker_id,
  w.worker_code,
  w.worker_name,

  p.premise_access_mode,
  p.data_mode,

  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'premise_id',ap.premise_id,
        'premise_code',ap.premise_code,
        'premise_name',ap.premise_name,
        'radius_meters',ap.radius_meters,
        'is_primary',wap.is_primary
      )
      order by wap.is_primary desc,ap.premise_name
    )
    from public.rr_worker_attendance_premises_v778_1 wap
    join public.rr_attendance_premises_v778_1 ap
      on ap.premise_id=wap.premise_id
    where wap.worker_id=w.worker_id
      and wap.is_active
      and ap.is_active
  ),'[]'::jsonb) as selected_premises

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

grant select on public.rr_worker_attendance_premises_board_v778_1_1
to authenticated;

grant execute on function public.rr_save_attendance_premise_v778_1_1(
  uuid,text,text,text,numeric,numeric,numeric,boolean,boolean,text,date,date
) to authenticated;

grant execute on function public.rr_set_worker_attendance_premises_v778_1_1(
  uuid,text,jsonb,date,date,text
) to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V778_1_1_MULTI_LOCATION_SECURE_MANAGEMENT',
  'worker_can_use_multiple_locations',true,
  'access_modes',jsonb_build_array(
    'ALL_ACTIVE',
    'SELECTED_ONLY'
  ),
  'future_location_add_via_owner_admin_rpc',true,
  'hard_delete_used',false,
  'historical_attendance_preserved',true
) as rr_upm_v778_1_1_result;
