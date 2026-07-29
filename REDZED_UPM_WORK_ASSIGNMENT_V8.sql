-- REDZED ERP — Universal Production Work Assignment V8
-- Additive patch. Existing Cutting / Production Submit / Alter / Repair / Damage /
-- Remake / Reversal / Rate logic remains unchanged.
-- Run after REDZED_UPM_FINAL_CONSOLIDATED_V6.sql (or a later compatible build).

begin;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. WORK ASSIGNMENT MASTER
-- One active assignment per Lot + Department + Colour.
-- ---------------------------------------------------------------------------
create table if not exists public.rr_upm_work_assignments_v8 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text not null,
  colour_name text not null,
  worker_id uuid not null,
  worker_code text not null,
  worker_name_snapshot text not null,
  assigned_qty integer not null check (assigned_qty > 0),
  size_breakup jsonb not null default '[]'::jsonb,
  status text not null default 'ASSIGNED'
    check (status in ('ASSIGNED','IN_PROGRESS','COMPLETED','CANCELLED','RELEASED')),
  assigned_by uuid default auth.uid(),
  assigned_by_name text,
  assigned_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists rr_upm_work_assignment_v8_active_uq
on public.rr_upm_work_assignments_v8 (
  canonical_lot_id,
  upper(department_code),
  upper(colour_code)
)
where status in ('ASSIGNED','IN_PROGRESS');

create index if not exists rr_upm_work_assignment_v8_lookup_idx
on public.rr_upm_work_assignments_v8 (
  canonical_lot_id,
  upper(department_code),
  upper(colour_code),
  status
);

alter table public.rr_upm_work_assignments_v8 enable row level security;

drop policy if exists rr_upm_work_assignment_v8_read on public.rr_upm_work_assignments_v8;
create policy rr_upm_work_assignment_v8_read
on public.rr_upm_work_assignments_v8
for select to authenticated
using (true);

grant select on public.rr_upm_work_assignments_v8 to authenticated;

-- Keep a stable worker code even when names repeat.
alter table public.rr_user_assignments_v2
  add column if not exists worker_code text;

update public.rr_user_assignments_v2
set worker_code = 'WRK-' || upper(substr(replace(user_id::text,'-',''),1,8))
where nullif(trim(worker_code),'') is null;

create unique index if not exists rr_user_assignments_v2_worker_code_uq
on public.rr_user_assignments_v2 (upper(worker_code))
where is_active and nullif(trim(worker_code),'') is not null;

-- ---------------------------------------------------------------------------
-- 2. WORKER LIST
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_worker_list_v8(
  p_department_code text default null
)
returns table(
  worker_id uuid,
  worker_code text,
  worker_name text,
  department_code text,
  department_name text
)
language sql
stable
security definer
set search_path=public
as $$
  select
    u.user_id,
    coalesce(nullif(trim(u.worker_code),''),
      'WRK-' || upper(substr(replace(u.user_id::text,'-',''),1,8))),
    u.display_name,
    u.department_code,
    u.department_name
  from public.rr_user_assignments_v2 u
  where u.is_active
    and u.user_category in ('WORKER','LINE_MAN','DEPARTMENT_HEAD','MANAGER')
    and (
      nullif(trim(p_department_code),'') is null
      or upper(coalesce(u.department_code,'')) = upper(p_department_code)
    )
  order by u.display_name, u.user_id;
$$;

grant execute on function public.rr_upm_worker_list_v8(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. COLOUR + SIZE CONTEXT
-- Side-by-side size rows are sourced from the existing V5 cutting map.
-- Already assigned colours are returned as locked.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_get_work_assign_context_v8(
  p_canonical_lot_id text,
  p_department_code text
)
returns table(
  colour_code text,
  colour_name text,
  total_qty bigint,
  size_breakup jsonb,
  is_locked boolean,
  assigned_worker_id uuid,
  assigned_worker_code text,
  assigned_worker_name text,
  assignment_id uuid
)
language sql
stable
security definer
set search_path=public
as $$
  with lot as (
    select b.canonical_lot_id, b.lot_no
    from public.rr_upm_lot_board_v1 b
    where b.canonical_lot_id = p_canonical_lot_id
    limit 1
  ),
  mapped as (
    select
      upper(m.colour_code) colour_code,
      max(m.colour_name) colour_name,
      sum(m.cut_qty)::bigint total_qty,
      jsonb_agg(
        jsonb_build_object(
          'size_code', upper(m.size_code),
          'qty', m.cut_qty
        )
        order by
          case upper(m.size_code)
            when 'XS' then 1 when 'S' then 2 when 'M' then 3
            when 'L' then 4 when 'XL' then 5 when 'XXL' then 6
            when '3XL' then 7 when '4XL' then 8 else 99
          end,
          upper(m.size_code)
      ) size_breakup
    from public.rr_upm_lot_cut_size_map_v5 m
    join lot l on upper(l.lot_no)=upper(m.lot_no)
    where m.is_active
    group by upper(m.colour_code)
  )
  select
    m.colour_code,
    m.colour_name,
    m.total_qty,
    m.size_breakup,
    (a.id is not null) is_locked,
    a.worker_id,
    a.worker_code,
    a.worker_name_snapshot,
    a.id
  from mapped m
  left join lateral (
    select x.*
    from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id
      and upper(x.department_code)=upper(p_department_code)
      and upper(x.colour_code)=m.colour_code
      and x.status in ('ASSIGNED','IN_PROGRESS')
    order by x.assigned_at desc
    limit 1
  ) a on true
  order by m.colour_name, m.colour_code;
$$;

grant execute on function public.rr_upm_get_work_assign_context_v8(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. ATOMIC SINGLE / MULTI / ALL ASSIGNMENT
-- p_rows example:
-- [{"colour_code":"R","worker_id":"uuid","assigned_qty":120,"remarks":null}]
-- Qty must equal the full mapped colour quantity. It is auto-filled in UI and
-- revalidated on the server.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_assign_colours_v8(
  p_canonical_lot_id text,
  p_department_code text,
  p_rows jsonb,
  p_remarks text default null
)
returns setof public.rr_upm_work_assignments_v8
language plpgsql
security definer
set search_path=public
as $$
declare
  v_ctx jsonb := public.rr_up_user_context_v2();
  v_role text := upper(coalesce(v_ctx->>'user_category','WORKER'));
  v_name text := coalesce(v_ctx->>'display_name',auth.uid()::text);
  v_lot_no text;
  v_row jsonb;
  v_colour text;
  v_colour_name text;
  v_worker_id uuid;
  v_worker_name text;
  v_worker_code text;
  v_qty integer;
  v_expected integer;
  v_sizes jsonb;
  v_inserted public.rr_upm_work_assignments_v8;
begin
  if v_role not in ('OWNER','ADMIN','MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION') then
    raise exception 'You are not allowed to assign production work.';
  end if;

  if nullif(trim(p_department_code),'') is null then
    raise exception 'Department is required.';
  end if;

  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows)=0 then
    raise exception 'Select at least one colour.';
  end if;

  select b.lot_no into v_lot_no
  from public.rr_upm_lot_board_v1 b
  where b.canonical_lot_id=p_canonical_lot_id
  limit 1;

  if v_lot_no is null then raise exception 'Production Lot not found.'; end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_colour := upper(trim(v_row->>'colour_code'));
    v_worker_id := nullif(v_row->>'worker_id','')::uuid;
    v_qty := coalesce((v_row->>'assigned_qty')::integer,0);

    if nullif(v_colour,'') is null then raise exception 'Colour is required.'; end if;
    if v_worker_id is null then raise exception 'Worker is required for colour %.',v_colour; end if;

    select
      max(m.colour_name),
      sum(m.cut_qty)::integer,
      jsonb_agg(
        jsonb_build_object('size_code',upper(m.size_code),'qty',m.cut_qty)
        order by upper(m.size_code)
      )
    into v_colour_name,v_expected,v_sizes
    from public.rr_upm_lot_cut_size_map_v5 m
    where m.is_active
      and upper(m.lot_no)=upper(v_lot_no)
      and upper(m.colour_code)=v_colour;

    if v_expected is null then
      raise exception 'Cutting colour-size mapping not found for colour %.',v_colour;
    end if;

    if v_qty <> v_expected then
      raise exception 'Colour % quantity must be full mapped quantity: % PCS.',v_colour,v_expected;
    end if;

    select
      u.display_name,
      coalesce(nullif(trim(u.worker_code),''),
        'WRK-' || upper(substr(replace(u.user_id::text,'-',''),1,8)))
    into v_worker_name,v_worker_code
    from public.rr_user_assignments_v2 u
    where u.user_id=v_worker_id and u.is_active
    limit 1;

    if v_worker_name is null then raise exception 'Selected worker is not active.'; end if;

    begin
      insert into public.rr_upm_work_assignments_v8(
        canonical_lot_id,lot_no,department_code,colour_code,colour_name,
        worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,
        assigned_by,assigned_by_name,remarks
      ) values (
        p_canonical_lot_id,v_lot_no,upper(trim(p_department_code)),v_colour,
        coalesce(v_colour_name,v_colour),v_worker_id,v_worker_code,v_worker_name,
        v_expected,coalesce(v_sizes,'[]'::jsonb),auth.uid(),v_name,
        coalesce(nullif(trim(v_row->>'remarks'),''),nullif(trim(p_remarks),''))
      )
      returning * into v_inserted;
    exception when unique_violation then
      raise exception 'Colour % is already assigned in department %.',v_colour,upper(trim(p_department_code));
    end;

    return next v_inserted;
  end loop;
end;
$$;

grant execute on function public.rr_upm_assign_colours_v8(text,text,jsonb,text) to authenticated;

create or replace function public.rr_upm_cancel_assignment_v8(
  p_assignment_id uuid,
  p_reason text
)
returns public.rr_upm_work_assignments_v8
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role text:=upper(coalesce(public.rr_up_user_context_v2()->>'user_category','WORKER'));
  v public.rr_upm_work_assignments_v8;
begin
  if v_role not in ('OWNER','ADMIN','MANAGER','LINE_MAN','DEPARTMENT_HEAD','PRODUCTION') then
    raise exception 'You are not allowed to cancel assignment.';
  end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Cancellation reason is mandatory.'; end if;

  update public.rr_upm_work_assignments_v8
  set status='CANCELLED',cancelled_at=now(),cancel_reason=trim(p_reason),updated_at=now()
  where id=p_assignment_id and status in ('ASSIGNED','IN_PROGRESS')
  returning * into v;

  if v.id is null then raise exception 'Active assignment not found.'; end if;
  return v;
end;
$$;

grant execute on function public.rr_upm_cancel_assignment_v8(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. BIND EXISTING PRODUCTION SUBMIT TO ASSIGNMENT
-- No rewrite of rr_upm_submit_ready_v2 is required.
-- BEFORE INSERT blocks duplicate/unassigned production.
-- AFTER INSERT completes the assignment.
-- ---------------------------------------------------------------------------
alter table public.rr_upm_submit_ledger_v2
  add column if not exists work_assignment_id uuid
    references public.rr_upm_work_assignments_v8(id) on delete restrict,
  add column if not exists assigned_worker_id uuid,
  add column if not exists assigned_worker_code text,
  add column if not exists assigned_worker_name text;

create or replace function public.rr_upm_bind_submit_assignment_v8()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v public.rr_upm_work_assignments_v8;
begin
  select * into v
  from public.rr_upm_work_assignments_v8 a
  where a.canonical_lot_id=new.canonical_lot_id
    and upper(a.department_code)=upper(new.department_code)
    and upper(a.colour_code)=upper(new.colour_code)
    and a.status in ('ASSIGNED','IN_PROGRESS')
  order by a.assigned_at desc
  limit 1
  for update;

  if v.id is null then
    raise exception 'Work assignment missing for Lot %, Department %, Colour %.',
      new.lot_no,new.department_code,new.colour_code;
  end if;

  if new.submitted_qty > v.assigned_qty then
    raise exception 'Submitted quantity % exceeds assigned quantity %.',
      new.submitted_qty,v.assigned_qty;
  end if;

  new.work_assignment_id := v.id;
  new.assigned_worker_id := v.worker_id;
  new.assigned_worker_code := v.worker_code;
  new.assigned_worker_name := v.worker_name_snapshot;

  update public.rr_upm_work_assignments_v8
  set status='IN_PROGRESS',updated_at=now()
  where id=v.id and status='ASSIGNED';

  return new;
end;
$$;

drop trigger if exists rr_upm_bind_submit_assignment_v8 on public.rr_upm_submit_ledger_v2;
create trigger rr_upm_bind_submit_assignment_v8
before insert on public.rr_upm_submit_ledger_v2
for each row execute function public.rr_upm_bind_submit_assignment_v8();

create or replace function public.rr_upm_complete_submit_assignment_v8()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.work_assignment_id is not null and new.submit_status='ACTIVE' then
    update public.rr_upm_work_assignments_v8
    set status='COMPLETED',completed_at=now(),updated_at=now()
    where id=new.work_assignment_id;
  end if;
  return new;
end;
$$;

drop trigger if exists rr_upm_complete_submit_assignment_v8 on public.rr_upm_submit_ledger_v2;
create trigger rr_upm_complete_submit_assignment_v8
after insert on public.rr_upm_submit_ledger_v2
for each row execute function public.rr_upm_complete_submit_assignment_v8();

-- Reversal releases the same colour for reassignment.
create or replace function public.rr_upm_release_reversed_assignment_v8()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if old.submit_status='ACTIVE'
     and new.submit_status<>'ACTIVE'
     and new.work_assignment_id is not null then
    update public.rr_upm_work_assignments_v8
    set status='RELEASED',updated_at=now()
    where id=new.work_assignment_id and status='COMPLETED';
  end if;
  return new;
end;
$$;

drop trigger if exists rr_upm_release_reversed_assignment_v8 on public.rr_upm_submit_ledger_v2;
create trigger rr_upm_release_reversed_assignment_v8
after update of submit_status on public.rr_upm_submit_ledger_v2
for each row execute function public.rr_upm_release_reversed_assignment_v8();

commit;
