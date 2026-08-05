-- REDZED UPM V772.6 / PCS Payroll V779.3.0
-- LOCKED RULE:
--   ONE LOT NO + ONE DEPARTMENT = ONE ASSIGNMENT ACTUAL RATE
--
-- First positive rate entered for any assignment of a Lot+Department:
--   -> auto-fills every relevant assignment of that same Lot+Department
--   -> all Colours, all bound Sizes, all Workers
--
-- Later correction:
--   -> authorized Owner/Admin/Manager only
--   -> audited
--   -> updates the complete Lot+Department group together
--
-- No Standard Rate / Department Rate / fallback is used for Submit or PCS salary.

begin;

-- =========================================================
-- A. AUDIT TABLE (kept compatible with V772)
-- =========================================================
create table if not exists public.rr_upm_assignment_rate_log_v772(
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null,
  canonical_lot_id text,
  lot_no text,
  department_code text,
  worker_id uuid,
  worker_code text,
  worker_name text,
  old_rate numeric(12,4),
  new_rate numeric(12,4) not null,
  reason text not null,
  changed_by uuid,
  changed_by_name text,
  created_at timestamptz not null default now()
);

create index if not exists rr_upm_assignment_rate_log_v772_assignment_idx
  on public.rr_upm_assignment_rate_log_v772(assignment_id,created_at desc);

create index if not exists rr_upm_work_assignments_v8_lot_dept_rate_idx
  on public.rr_upm_work_assignments_v8(
    upper(trim(lot_no)),
    upper(trim(department_code)),
    actual_rate
  );

-- =========================================================
-- B. CENTRAL GROUP RATE RPC
-- =========================================================
create or replace function public.rr_upm_set_assignment_actual_rate_v772(
  p_assignment_id uuid,
  p_actual_rate numeric,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.rr_user_profiles%rowtype;
  v_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_rate numeric(12,4);
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
  v_actor_name text;
  v_role text;

  v_lot_key text;
  v_dept_key text;
  v_group_count integer:=0;
  v_changed_count integer:=0;
  v_auto_filled_count integer:=0;
  v_colour_count integer:=0;
  v_worker_count integer:=0;

  v_existing_distinct_rates integer:=0;
  v_existing_group_rate numeric(12,4);
  v_is_group_correction boolean:=false;
  v_old_bypass text;
begin
  select * into v_profile
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then
    raise exception 'Active User Directory profile required.';
  end if;

  if p_assignment_id is null then
    raise exception 'Assignment ID required.';
  end if;

  v_rate:=round(coalesce(p_actual_rate,0),4);
  if v_rate<=0 then
    raise exception 'Actual Rate must be greater than zero.';
  end if;

  if v_reason is null or length(v_reason)<5 then
    raise exception 'Rate save reason minimum 5 characters required.';
  end if;

  select * into v_assignment
  from public.rr_upm_work_assignments_v8
  where id=p_assignment_id
  for update;

  if not found then
    raise exception 'UPM assignment not found.';
  end if;

  if not public.rr_upm_can_edit_assignment_rate_v772(v_assignment.department_code) then
    raise exception 'Assignment Actual Rate edit permission denied for department %.',
      v_assignment.department_code;
  end if;

  v_lot_key:=upper(trim(coalesce(v_assignment.lot_no,'')));
  v_dept_key:=upper(trim(coalesce(v_assignment.department_code,'')));

  if v_lot_key='' then raise exception 'Assignment Lot No missing.'; end if;
  if v_dept_key='' then raise exception 'Assignment Department missing.'; end if;

  -- Lock the complete Lot+Department group.
  perform 1
  from public.rr_upm_work_assignments_v8 a
  where upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
  for update;

  select
    count(*)::integer,
    count(distinct nullif(upper(trim(coalesce(a.colour_code,''))),''))::integer,
    count(distinct a.worker_id)::integer,
    count(distinct round(a.actual_rate,4)) filter(
      where coalesce(a.actual_rate,0)>0
    )::integer,
    min(round(a.actual_rate,4)) filter(
      where coalesce(a.actual_rate,0)>0
    )
  into
    v_group_count,
    v_colour_count,
    v_worker_count,
    v_existing_distinct_rates,
    v_existing_group_rate
  from public.rr_upm_work_assignments_v8 a
  where upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    );

  v_is_group_correction:=
    v_existing_distinct_rates>1
    or (
      v_existing_group_rate is not null
      and v_existing_group_rate<>v_rate
    );

  v_role:=lower(coalesce(v_profile.role_code,''));

  if v_is_group_correction
     and v_role not in('owner','admin','manager') then
    raise exception
      'Lot % / Department % already has Actual Rate %. Group rate correction requires Owner/Admin/Manager.',
      v_assignment.lot_no,
      v_assignment.department_code,
      coalesce(v_existing_group_rate,0);
  end if;

  -- Do not rewrite any assignment already used with positive payable PCS
  -- in an APPROVED or PAID payroll.
  if exists(
    select 1
    from public.rr_piece_payroll_details_v779 d
    join public.rr_piece_payroll_runs_v779 r
      on r.id=d.piece_run_id
    join public.rr_upm_work_assignments_v8 a
      on a.id=d.assignment_id
    where upper(trim(coalesce(a.lot_no,'')))=v_lot_key
      and upper(trim(coalesce(a.department_code,'')))=v_dept_key
      and upper(coalesce(a.status,'')) not in(
        'CANCELLED','CANCELED','VOID','REJECTED'
      )
      and coalesce(a.actual_rate,0)<>v_rate
      and r.status in('APPROVED','PAID')
      and coalesce(d.payable_qty,0)>0
  ) then
    raise exception
      'Approved/Paid payroll uses this Lot+Department group. Owner must reopen payroll before group rate correction.';
  end if;

  v_actor_name:=coalesce(
    nullif(trim(v_profile.full_name),''),
    v_profile.role_code,
    'Authorized User'
  );

  select count(*)::integer
  into v_changed_count
  from public.rr_upm_work_assignments_v8 a
  where upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
    and coalesce(a.actual_rate,0)<>v_rate;

  select count(*)::integer
  into v_auto_filled_count
  from public.rr_upm_work_assignments_v8 a
  where upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
    and coalesce(a.actual_rate,0)<=0;

  -- One audit row for every assignment whose rate changes.
  insert into public.rr_upm_assignment_rate_log_v772(
    assignment_id,
    canonical_lot_id,
    lot_no,
    department_code,
    worker_id,
    worker_code,
    worker_name,
    old_rate,
    new_rate,
    reason,
    changed_by,
    changed_by_name
  )
  select
    a.id,
    a.canonical_lot_id,
    a.lot_no,
    a.department_code,
    a.worker_id,
    a.worker_code,
    a.worker_name_snapshot,
    a.actual_rate,
    v_rate,
    v_reason || ' | LOT_DEPARTMENT_GROUP_RATE',
    auth.uid(),
    v_actor_name
  from public.rr_upm_work_assignments_v8 a
  where upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
    and coalesce(a.actual_rate,0)<>v_rate;

  -- Bypass row-level group guard only for this audited group update.
  v_old_bypass:=current_setting('app.rr_lot_department_rate_group_sync',true);
  perform set_config(
    'app.rr_lot_department_rate_group_sync',
    '1',
    true
  );

  update public.rr_upm_work_assignments_v8 a
  set actual_rate=v_rate,
      rate_filled_by=auth.uid(),
      rate_filled_by_name=v_actor_name,
      rate_filled_at=now(),
      updated_at=now()
  where upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
    and coalesce(a.actual_rate,0)<>v_rate;

  perform set_config(
    'app.rr_lot_department_rate_group_sync',
    coalesce(v_old_bypass,''),
    true
  );

  return jsonb_build_object(
    'ok',true,
    'rate_rule','ONE_LOT_ONE_DEPARTMENT_ONE_RATE',
    'source_assignment_id',v_assignment.id,
    'lot_no',v_assignment.lot_no,
    'department_code',v_assignment.department_code,
    'group_rate',v_rate,
    'group_assignments',v_group_count,
    'group_colours',v_colour_count,
    'group_workers',v_worker_count,
    'updated_assignments',v_changed_count,
    'auto_filled_assignments',v_auto_filled_count,
    'was_group_correction',v_is_group_correction,
    'saved_by',v_actor_name,
    'saved_at',now()
  );
end;
$$;

-- =========================================================
-- C. DATABASE GUARD FOR ALL DIRECT ASSIGNMENT WRITES
-- =========================================================
create or replace function public.rr_upm_lot_department_rate_before_v7726()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_bypass text;
  v_lot_key text;
  v_dept_key text;
  v_distinct_rates integer:=0;
  v_existing_rate numeric(12,4);
  v_existing_filled_by uuid;
  v_existing_filled_by_name text;
  v_existing_filled_at timestamptz;
begin
  v_bypass:=current_setting(
    'app.rr_lot_department_rate_group_sync',
    true
  );

  if v_bypass='1' then return new; end if;

  v_lot_key:=upper(trim(coalesce(new.lot_no,'')));
  v_dept_key:=upper(trim(coalesce(new.department_code,'')));

  if v_lot_key='' or v_dept_key='' then return new; end if;

  -- Any correction of an already-positive rate must use the audited group RPC.
  if tg_op='UPDATE'
     and coalesce(old.actual_rate,0)>0
     and round(coalesce(new.actual_rate,0),4)
         <> round(coalesce(old.actual_rate,0),4) then
    raise exception
      'Direct rate correction blocked. Use Lot+Department Assignment Rate editor so every Colour/Worker updates together.';
  end if;

  select
    count(distinct round(a.actual_rate,4))::integer,
    min(round(a.actual_rate,4)),
    (array_agg(a.rate_filled_by order by a.rate_filled_at desc nulls last))[1],
    (array_agg(a.rate_filled_by_name order by a.rate_filled_at desc nulls last))[1],
    (array_agg(a.rate_filled_at order by a.rate_filled_at desc nulls last))[1]
  into
    v_distinct_rates,
    v_existing_rate,
    v_existing_filled_by,
    v_existing_filled_by_name,
    v_existing_filled_at
  from public.rr_upm_work_assignments_v8 a
  where a.id is distinct from new.id
    and upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
    and coalesce(a.actual_rate,0)>0;

  if v_distinct_rates>1 then
    raise exception
      'Lot % / Department % has conflicting historical Actual Rates. Owner must normalize the whole group from Assignment Rate editor.',
      new.lot_no,new.department_code;
  end if;

  if v_existing_rate is not null then
    if coalesce(new.actual_rate,0)<=0 then
      -- New Colour/Worker assignment automatically inherits Lot+Department rate.
      new.actual_rate:=v_existing_rate;
      new.rate_filled_by:=coalesce(
        new.rate_filled_by,
        v_existing_filled_by,
        auth.uid()
      );
      new.rate_filled_by_name:=coalesce(
        nullif(trim(coalesce(new.rate_filled_by_name,'')),''),
        v_existing_filled_by_name,
        'AUTO LOT+DEPARTMENT RATE'
      );
      new.rate_filled_at:=coalesce(
        new.rate_filled_at,
        v_existing_filled_at,
        now()
      );
    elsif round(new.actual_rate,4)<>v_existing_rate then
      raise exception
        'Lot % / Department % rate is already %. Use Assignment Rate editor to correct the complete group.',
        new.lot_no,new.department_code,v_existing_rate;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists rr_upm_lot_department_rate_insert_v7726
  on public.rr_upm_work_assignments_v8;

create trigger rr_upm_lot_department_rate_insert_v7726
before insert on public.rr_upm_work_assignments_v8
for each row
execute function public.rr_upm_lot_department_rate_before_v7726();

drop trigger if exists rr_upm_lot_department_rate_update_v7726
  on public.rr_upm_work_assignments_v8;

create trigger rr_upm_lot_department_rate_update_v7726
before update of actual_rate,lot_no,department_code,status
on public.rr_upm_work_assignments_v8
for each row
execute function public.rr_upm_lot_department_rate_before_v7726();

-- =========================================================
-- D. FIRST DIRECT POSITIVE RATE AUTO-PROPAGATES TO GROUP
-- =========================================================
create or replace function public.rr_upm_lot_department_rate_after_v7726()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_bypass text;
  v_old_bypass text;
  v_lot_key text;
  v_dept_key text;
  v_actor_name text;
begin
  v_bypass:=current_setting(
    'app.rr_lot_department_rate_group_sync',
    true
  );

  if v_bypass='1' then return new; end if;
  if coalesce(new.actual_rate,0)<=0 then return new; end if;

  v_lot_key:=upper(trim(coalesce(new.lot_no,'')));
  v_dept_key:=upper(trim(coalesce(new.department_code,'')));

  if v_lot_key='' or v_dept_key='' then return new; end if;

  select coalesce(
    nullif(trim(p.full_name),''),
    p.role_code,
    new.rate_filled_by_name,
    'AUTO LOT+DEPARTMENT RATE'
  )
  into v_actor_name
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid()
  limit 1;

  v_actor_name:=coalesce(
    v_actor_name,
    new.rate_filled_by_name,
    'AUTO LOT+DEPARTMENT RATE'
  );

  -- Audit the directly written source row where applicable.
  if tg_op='INSERT' then
    insert into public.rr_upm_assignment_rate_log_v772(
      assignment_id,canonical_lot_id,lot_no,department_code,
      worker_id,worker_code,worker_name,old_rate,new_rate,reason,
      changed_by,changed_by_name
    ) values(
      new.id,new.canonical_lot_id,new.lot_no,new.department_code,
      new.worker_id,new.worker_code,new.worker_name_snapshot,
      null,new.actual_rate,
      'DIRECT ASSIGNMENT RATE · LOT_DEPARTMENT_GROUP_SOURCE',
      auth.uid(),v_actor_name
    );
  elsif coalesce(old.actual_rate,0)<=0
        and coalesce(new.actual_rate,0)>0 then
    insert into public.rr_upm_assignment_rate_log_v772(
      assignment_id,canonical_lot_id,lot_no,department_code,
      worker_id,worker_code,worker_name,old_rate,new_rate,reason,
      changed_by,changed_by_name
    ) values(
      new.id,new.canonical_lot_id,new.lot_no,new.department_code,
      new.worker_id,new.worker_code,new.worker_name_snapshot,
      old.actual_rate,new.actual_rate,
      'FIRST RATE · LOT_DEPARTMENT_GROUP_SOURCE',
      auth.uid(),v_actor_name
    );
  end if;

  -- Audit every missing group row that will inherit this rate.
  insert into public.rr_upm_assignment_rate_log_v772(
    assignment_id,canonical_lot_id,lot_no,department_code,
    worker_id,worker_code,worker_name,old_rate,new_rate,reason,
    changed_by,changed_by_name
  )
  select
    a.id,a.canonical_lot_id,a.lot_no,a.department_code,
    a.worker_id,a.worker_code,a.worker_name_snapshot,
    a.actual_rate,new.actual_rate,
    'AUTO FILL · FIRST LOT+DEPARTMENT ACTUAL RATE',
    auth.uid(),v_actor_name
  from public.rr_upm_work_assignments_v8 a
  where a.id<>new.id
    and upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
    and coalesce(a.actual_rate,0)<=0;

  v_old_bypass:=current_setting(
    'app.rr_lot_department_rate_group_sync',
    true
  );
  perform set_config(
    'app.rr_lot_department_rate_group_sync',
    '1',
    true
  );

  update public.rr_upm_work_assignments_v8 a
  set actual_rate=round(new.actual_rate,4),
      rate_filled_by=coalesce(new.rate_filled_by,auth.uid()),
      rate_filled_by_name=v_actor_name,
      rate_filled_at=coalesce(new.rate_filled_at,now()),
      updated_at=now()
  where a.id<>new.id
    and upper(trim(coalesce(a.lot_no,'')))=v_lot_key
    and upper(trim(coalesce(a.department_code,'')))=v_dept_key
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
    and coalesce(a.actual_rate,0)<=0;

  perform set_config(
    'app.rr_lot_department_rate_group_sync',
    coalesce(v_old_bypass,''),
    true
  );

  return new;
end;
$$;

drop trigger if exists rr_upm_lot_department_rate_after_insert_v7726
  on public.rr_upm_work_assignments_v8;

create trigger rr_upm_lot_department_rate_after_insert_v7726
after insert on public.rr_upm_work_assignments_v8
for each row
execute function public.rr_upm_lot_department_rate_after_v7726();

drop trigger if exists rr_upm_lot_department_rate_after_update_v7726
  on public.rr_upm_work_assignments_v8;

create trigger rr_upm_lot_department_rate_after_update_v7726
after update of actual_rate on public.rr_upm_work_assignments_v8
for each row
when (
  coalesce(new.actual_rate,0)>0
  and coalesce(old.actual_rate,0)<=0
)
execute function public.rr_upm_lot_department_rate_after_v7726();

-- =========================================================
-- E. SUBMIT BACKSTOP ALSO CHECKS GROUP CONSISTENCY
-- =========================================================
create or replace function public.rr_upm_require_assignment_actual_rate_v772()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_assignment public.rr_upm_work_assignments_v8%rowtype;
  v_distinct_rates integer:=0;
  v_missing_assignments integer:=0;
begin
  if new.assignment_id is null then
    raise exception
      'Active Assignment is required before production Submit.';
  end if;

  select * into v_assignment
  from public.rr_upm_work_assignments_v8
  where id=new.assignment_id
  limit 1;

  if not found then
    raise exception 'Submit blocked: Assignment % not found.',
      new.assignment_id;
  end if;

  if coalesce(v_assignment.actual_rate,0)<=0 then
    raise exception
      'Submit blocked: Assignment Actual Rate required. Lot %, Department %, Worker %, Colour %.',
      coalesce(v_assignment.lot_no,'—'),
      coalesce(v_assignment.department_code,'—'),
      coalesce(v_assignment.worker_name_snapshot,'—'),
      coalesce(v_assignment.colour_code,'—');
  end if;

  select
    count(distinct round(a.actual_rate,4)) filter(
      where coalesce(a.actual_rate,0)>0
    )::integer,
    count(*) filter(
      where coalesce(a.actual_rate,0)<=0
    )::integer
  into v_distinct_rates,v_missing_assignments
  from public.rr_upm_work_assignments_v8 a
  where upper(trim(coalesce(a.lot_no,'')))=
        upper(trim(coalesce(v_assignment.lot_no,'')))
    and upper(trim(coalesce(a.department_code,'')))=
        upper(trim(coalesce(v_assignment.department_code,'')))
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    );

  if v_distinct_rates>1 then
    raise exception
      'Submit blocked: Lot % / Department % has conflicting Assignment Actual Rates. Normalize the complete group.',
      v_assignment.lot_no,v_assignment.department_code;
  end if;

  if v_missing_assignments>0 then
    raise exception
      'Submit blocked: Lot % / Department % still has % assignment(s) without Actual Rate. Fill one group rate first.',
      v_assignment.lot_no,
      v_assignment.department_code,
      v_missing_assignments;
  end if;

  return new;
end;
$$;

-- Existing Dynamic Submit trigger remains attached to this replaced function.
drop trigger if exists rr_upm_dynamic_submit_require_actual_rate_v772
  on public.rr_upm_dynamic_submit_history_v741;

create trigger rr_upm_dynamic_submit_require_actual_rate_v772
before insert on public.rr_upm_dynamic_submit_history_v741
for each row
execute function public.rr_upm_require_assignment_actual_rate_v772();

-- =========================================================
-- F. SAFE HISTORICAL AUTO-BACKFILL
-- If a Lot+Department already has exactly one known positive rate,
-- fill all its missing assignment rates automatically.
-- Groups with no known rate remain for manual first fill.
-- Groups with conflicting positive rates remain blocked for Owner review.
-- =========================================================
with group_rate as (
  select
    upper(trim(coalesce(lot_no,''))) as lot_key,
    upper(trim(coalesce(department_code,''))) as dept_key,
    min(round(actual_rate,4)) filter(
      where coalesce(actual_rate,0)>0
    ) as single_rate,
    count(distinct round(actual_rate,4)) filter(
      where coalesce(actual_rate,0)>0
    ) as distinct_rates
  from public.rr_upm_work_assignments_v8
  where upper(coalesce(status,'')) not in(
    'CANCELLED','CANCELED','VOID','REJECTED'
  )
  group by
    upper(trim(coalesce(lot_no,''))),
    upper(trim(coalesce(department_code,'')))
),
targets as (
  select
    a.*,
    g.single_rate
  from public.rr_upm_work_assignments_v8 a
  join group_rate g
    on g.lot_key=upper(trim(coalesce(a.lot_no,'')))
   and g.dept_key=upper(trim(coalesce(a.department_code,'')))
  where g.distinct_rates=1
    and g.single_rate>0
    and coalesce(a.actual_rate,0)<=0
    and upper(coalesce(a.status,'')) not in(
      'CANCELLED','CANCELED','VOID','REJECTED'
    )
)
insert into public.rr_upm_assignment_rate_log_v772(
  assignment_id,canonical_lot_id,lot_no,department_code,
  worker_id,worker_code,worker_name,old_rate,new_rate,reason,
  changed_by,changed_by_name
)
select
  t.id,t.canonical_lot_id,t.lot_no,t.department_code,
  t.worker_id,t.worker_code,t.worker_name_snapshot,
  t.actual_rate,t.single_rate,
  'V772.6 INSTALL AUTO BACKFILL · EXISTING LOT+DEPARTMENT RATE',
  auth.uid(),'V772.6 INSTALL'
from targets t;

select set_config(
  'app.rr_lot_department_rate_group_sync',
  '1',
  true
);

with group_rate as (
  select
    upper(trim(coalesce(lot_no,''))) as lot_key,
    upper(trim(coalesce(department_code,''))) as dept_key,
    min(round(actual_rate,4)) filter(
      where coalesce(actual_rate,0)>0
    ) as single_rate,
    count(distinct round(actual_rate,4)) filter(
      where coalesce(actual_rate,0)>0
    ) as distinct_rates
  from public.rr_upm_work_assignments_v8
  where upper(coalesce(status,'')) not in(
    'CANCELLED','CANCELED','VOID','REJECTED'
  )
  group by
    upper(trim(coalesce(lot_no,''))),
    upper(trim(coalesce(department_code,'')))
)
update public.rr_upm_work_assignments_v8 a
set actual_rate=g.single_rate,
    rate_filled_by_name=coalesce(
      nullif(trim(coalesce(a.rate_filled_by_name,'')),''),
      'V772.6 AUTO GROUP RATE'
    ),
    rate_filled_at=coalesce(a.rate_filled_at,now()),
    updated_at=now()
from group_rate g
where g.lot_key=upper(trim(coalesce(a.lot_no,'')))
  and g.dept_key=upper(trim(coalesce(a.department_code,'')))
  and g.distinct_rates=1
  and g.single_rate>0
  and coalesce(a.actual_rate,0)<=0
  and upper(coalesce(a.status,'')) not in(
    'CANCELLED','CANCELED','VOID','REJECTED'
  );

select set_config(
  'app.rr_lot_department_rate_group_sync',
  '',
  true
);

comment on function public.rr_upm_set_assignment_actual_rate_v772(uuid,numeric,text) is
'V772.6: one Lot No + one Department = one Assignment Actual Rate across every Colour, bound Size and Worker. Audited group fill/correction; no fallback.';

grant execute on function
  public.rr_upm_set_assignment_actual_rate_v772(uuid,numeric,text)
to authenticated;

commit;

-- =========================================================
-- INSTALL VERIFICATION
-- =========================================================
select
  case
    when to_regprocedure(
      'public.rr_upm_set_assignment_actual_rate_v772(uuid,numeric,text)'
    ) is null then 'FAIL'
    when not exists(
      select 1
      from pg_trigger t
      join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public'
        and c.relname='rr_upm_work_assignments_v8'
        and t.tgname='rr_upm_lot_department_rate_insert_v7726'
        and not t.tgisinternal
        and t.tgenabled<>'D'
    ) then 'FAIL'
    when not exists(
      select 1
      from pg_trigger t
      join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public'
        and c.relname='rr_upm_work_assignments_v8'
        and t.tgname='rr_upm_lot_department_rate_after_update_v7726'
        and not t.tgisinternal
        and t.tgenabled<>'D'
    ) then 'FAIL'
    else 'PASS'
  end as v772_6_group_rate_install_result,

  to_regprocedure(
    'public.rr_upm_set_assignment_actual_rate_v772(uuid,numeric,text)'
  ) is not null as group_rate_rpc_ready,

  exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='rr_upm_work_assignments_v8'
      and t.tgname='rr_upm_lot_department_rate_insert_v7726'
      and not t.tgisinternal
      and t.tgenabled<>'D'
  ) as new_assignment_auto_inherit_ready,

  exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='rr_upm_dynamic_submit_history_v741'
      and t.tgname='rr_upm_dynamic_submit_require_actual_rate_v772'
      and not t.tgisinternal
      and t.tgenabled<>'D'
  ) as submit_group_rate_guard_ready;


-- =========================================================
-- DATA AUDIT
-- Expected after rates are completed:
--   conflicting_rate_groups = 0
--   groups_with_known_rate_but_missing_assignments = 0
-- Groups with no rate yet remain visible in the UPM Assignment Rate list.
-- =========================================================
with groups as (
  select
    upper(trim(coalesce(lot_no,''))) as lot_no,
    upper(trim(coalesce(department_code,''))) as department_code,
    count(*) as assignments,
    count(distinct round(actual_rate,4)) filter(
      where coalesce(actual_rate,0)>0
    ) as distinct_positive_rates,
    count(*) filter(
      where coalesce(actual_rate,0)<=0
    ) as missing_assignments
  from public.rr_upm_work_assignments_v8
  where upper(coalesce(status,'')) not in(
    'CANCELLED','CANCELED','VOID','REJECTED'
  )
  group by
    upper(trim(coalesce(lot_no,''))),
    upper(trim(coalesce(department_code,'')))
)
select
  count(*) filter(
    where distinct_positive_rates>1
  ) as conflicting_rate_groups,

  count(*) filter(
    where distinct_positive_rates=1
      and missing_assignments>0
  ) as groups_with_known_rate_but_missing_assignments,

  count(*) filter(
    where distinct_positive_rates=0
      and missing_assignments>0
  ) as groups_waiting_for_first_rate
from groups;
