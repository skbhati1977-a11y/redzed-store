-- REDZED ERP — UPM V726 FULLY MAPPED
-- Additive migration aligned to the uploaded REDZED production repository.
-- Uses the existing Cutting, Worker Assignment, Submit, Visual and Packing engines.
-- Run after the existing UPM consolidated migrations, Work Assignment V8.3 patch,
-- Production Submit V2, Alter/Remake/Damage V1 and Smart Packing V1.

begin;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Owner/Admin visibility helper used only for standard costing fields.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_is_owner_admin_v726()
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_role text;
begin
  if to_regprocedure('public.rr_up_is_owner_admin_v1()') is not null then
    begin return public.rr_up_is_owner_admin_v1(); exception when others then null; end;
  end if;
  select lower(coalesce(p.role_code,'')) into v_role
  from public.rr_user_profiles p
  where p.auth_user_id=auth.uid() and coalesce(p.is_active,false)
  limit 1;
  return v_role in ('owner','admin');
end $$;

grant execute on function public.rr_upm_is_owner_admin_v726() to authenticated;

-- ---------------------------------------------------------------------------
-- Standard rate and owner flat margin. Actual rate remains in the existing
-- rr_upm_department_rates_v2 table and is not duplicated.
-- ---------------------------------------------------------------------------
create table if not exists public.rr_upm_standard_rates_v726 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  standard_rate numeric(14,4) not null check (standard_rate>=0),
  reason text,
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  unique(canonical_lot_id,department_code)
);

create table if not exists public.rr_upm_owner_margin_v726 (
  id uuid primary key default gen_random_uuid(),
  flat_amount_per_piece numeric(14,4) not null check (flat_amount_per_piece>=0),
  reason text,
  effective_from timestamptz not null default now(),
  is_active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

alter table public.rr_upm_standard_rates_v726 enable row level security;
alter table public.rr_upm_owner_margin_v726 enable row level security;

drop policy if exists rr_upm_standard_rates_v726_read on public.rr_upm_standard_rates_v726;
create policy rr_upm_standard_rates_v726_read on public.rr_upm_standard_rates_v726
for select to authenticated using (public.rr_upm_is_owner_admin_v726());

drop policy if exists rr_upm_owner_margin_v726_read on public.rr_upm_owner_margin_v726;
create policy rr_upm_owner_margin_v726_read on public.rr_upm_owner_margin_v726
for select to authenticated using (public.rr_upm_is_owner_admin_v726());

grant select on public.rr_upm_standard_rates_v726,public.rr_upm_owner_margin_v726 to authenticated;

create or replace function public.rr_upm_set_standard_rate_v726(
  p_canonical_lot_id text,
  p_department_code text,
  p_standard_rate numeric,
  p_reason text default null
) returns public.rr_upm_standard_rates_v726
language plpgsql security definer set search_path=public
as $$
declare v_lot_no text; v_row public.rr_upm_standard_rates_v726;
begin
  if not public.rr_upm_is_owner_admin_v726() then raise exception 'Owner/Admin permission required.'; end if;
  if p_standard_rate is null or p_standard_rate<0 then raise exception 'Valid Standard Rate required.'; end if;
  select lot_no into v_lot_no from public.rr_upm_lot_board_v1 where canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot_no is null then raise exception 'Lot not found.'; end if;
  insert into public.rr_upm_standard_rates_v726(canonical_lot_id,lot_no,department_code,standard_rate,reason,updated_by,updated_at)
  values(p_canonical_lot_id,v_lot_no,upper(trim(p_department_code)),p_standard_rate,p_reason,auth.uid(),now())
  on conflict(canonical_lot_id,department_code) do update set
    standard_rate=excluded.standard_rate,reason=excluded.reason,updated_by=auth.uid(),updated_at=now()
  returning * into v_row;
  return v_row;
end $$;

grant execute on function public.rr_upm_set_standard_rate_v726(text,text,numeric,text) to authenticated;

create or replace function public.rr_upm_set_owner_margin_v726(
  p_amount numeric,
  p_reason text default null
) returns public.rr_upm_owner_margin_v726
language plpgsql security definer set search_path=public
as $$
declare v_row public.rr_upm_owner_margin_v726;
begin
  if not public.rr_upm_is_owner_admin_v726() then raise exception 'Owner/Admin permission required.'; end if;
  if p_amount is null or p_amount<0 then raise exception 'Valid flat margin required.'; end if;
  update public.rr_upm_owner_margin_v726 set is_active=false where is_active;
  insert into public.rr_upm_owner_margin_v726(flat_amount_per_piece,reason,is_active)
  values(p_amount,p_reason,true) returning * into v_row;
  return v_row;
end $$;

grant execute on function public.rr_upm_set_owner_margin_v726(numeric,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Universal context resolver.
-- Authoritative Cutting source is the unchanged Cutting module:
-- rr_cutting_lots_v3 + rr_cutting_breakup_v3.planned_qty.
-- Canonical map is used only as a fallback when direct Cutting breakup is empty.
-- Worker list and assignment records remain the existing V8.3 engine.
-- Production totals remain the existing Submit V2 ledger.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_universal_form_v726(
  p_canonical_lot_id text,
  p_department_code text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_lot jsonb;
  v_lot_no text;
  v_cutting_lot_id uuid;
  v_rows jsonb := '[]'::jsonb;
  v_workers jsonb := '[]'::jsonb;
  v_actual_rate numeric := null;
  v_standard_rate numeric := null;
  v_margin numeric := null;
  v_owner boolean := false;
begin
  select to_jsonb(b),b.lot_no into v_lot,v_lot_no
  from public.rr_upm_lot_board_v1 b
  where b.canonical_lot_id=p_canonical_lot_id
  limit 1;
  if v_lot is null then raise exception 'Lot not found in UPM lot board.'; end if;

  select l.id into v_cutting_lot_id
  from public.rr_cutting_lots_v3 l
  where upper(trim(l.lot_no))=upper(trim(v_lot_no))
  order by l.created_at desc
  limit 1;

  select r.actual_rate into v_actual_rate
  from public.rr_upm_department_rates_v2 r
  where r.canonical_lot_id=p_canonical_lot_id
    and upper(trim(r.department_code))=upper(trim(p_department_code))
  limit 1;

  v_owner:=public.rr_upm_is_owner_admin_v726();
  if v_owner then
    select s.standard_rate into v_standard_rate
    from public.rr_upm_standard_rates_v726 s
    where s.canonical_lot_id=p_canonical_lot_id
      and upper(trim(s.department_code))=upper(trim(p_department_code))
    limit 1;
    select m.flat_amount_per_piece into v_margin
    from public.rr_upm_owner_margin_v726 m
    where m.is_active
    order by m.effective_from desc,m.created_at desc
    limit 1;
  end if;

  with direct_sizes as (
    select
      case
        when c.col_no is not null then upper('C'||c.col_no::text)
        when nullif(trim(x.colour_name_snapshot),'') is not null then upper(trim(x.colour_name_snapshot))
        else 'COLOUR'
      end colour_code,
      max(coalesce(nullif(trim(x.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour')) colour_name,
      upper(trim(x.size_code)) size_code,
      sum(coalesce(x.planned_qty,0))::numeric cutting_qty
    from public.rr_cutting_breakup_v3 x
    left join public.rr_cb_colours c on c.id=x.cb_colour_id
    where x.cutting_lot_id=v_cutting_lot_id
      and coalesce(x.planned_qty,0)>0
    group by 1,upper(trim(x.size_code))
  ), canonical_sizes as (
    select
      upper(trim(m.colour_code)) colour_code,
      max(coalesce(nullif(trim(m.colour_name),''),upper(trim(m.colour_code)))) colour_name,
      upper(trim(m.size_code)) size_code,
      sum(coalesce(m.cut_qty,0))::numeric cutting_qty
    from public.rr_upm_lot_cut_size_map_v5 m
    where m.is_active
      and (m.canonical_lot_id=p_canonical_lot_id or upper(trim(m.lot_no))=upper(trim(v_lot_no)))
      and coalesce(m.cut_qty,0)>0
    group by upper(trim(m.colour_code)),upper(trim(m.size_code))
  ), sizes as (
    select * from direct_sizes
    union all
    select * from canonical_sizes where not exists(select 1 from direct_sizes)
  ), latest_assignment as (
    select distinct on (upper(trim(a.colour_code)))
      upper(trim(a.colour_code)) colour_code,
      a.id assignment_id,a.worker_id,a.worker_code,a.worker_name_snapshot worker_name,
      a.assigned_qty,a.size_breakup,a.status,a.actual_rate
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(trim(a.department_code))=upper(trim(p_department_code))
      and a.status in ('ASSIGNED','IN_PROGRESS','COMPLETED')
    order by upper(trim(a.colour_code)),a.assigned_at desc
  ), assignment_sizes as (
    select la.colour_code,la.assignment_id,la.worker_id,la.worker_code,la.worker_name,
      la.status,la.actual_rate,
      upper(trim(z->>'size_code')) size_code,
      coalesce(nullif(z->>'qty','')::numeric,0) assigned_qty
    from latest_assignment la
    cross join lateral jsonb_array_elements(coalesce(la.size_breakup,'[]'::jsonb)) z
  ), submitted as (
    select upper(trim(s.colour_code)) colour_code,upper(trim(s.size_code)) size_code,
      sum(s.submitted_qty)::numeric good_qty
    from public.rr_upm_submit_ledger_v2 s
    where s.canonical_lot_id=p_canonical_lot_id
      and upper(trim(s.department_code))=upper(trim(p_department_code))
    group by upper(trim(s.colour_code)),upper(trim(s.size_code))
  ), alters as (
    select
      upper(trim(al.colour_name)) colour_code,
      upper(trim(al.size_code)) size_code,
      sum(coalesce(al.alter_qty,0))::numeric alter_qty
    from public.rr_up_alters ac
    join public.rr_up_alter_lines al on al.alter_id=ac.id
    left join public.rr_upm_departments d
      on upper(trim(d.department_code))=upper(trim(p_department_code))
    where upper(trim(ac.lot_no))=upper(trim(v_lot_no))
      and (
        upper(trim(ac.department_name))=upper(trim(p_department_code))
        or upper(trim(ac.department_name))=upper(trim(coalesce(d.department_name,'')))
      )
    group by upper(trim(al.colour_name)),upper(trim(al.size_code))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'colour_code',s.colour_code,
    'colour_name',s.colour_name,
    'size_code',s.size_code,
    'cutting_qty',s.cutting_qty,
    'assignment_id',a.assignment_id,
    'worker_id',a.worker_id,
    'worker_code',a.worker_code,
    'worker_name',a.worker_name,
    'assignment_status',a.status,
    'assigned_qty',coalesce(a.assigned_qty,0),
    'good_qty',coalesce(g.good_qty,0),
    'alter_qty',coalesce(alt.alter_qty,0),
    'remake_qty',0,
    'damage_qty',0,
    'pending_qty',greatest(coalesce(a.assigned_qty,0)-coalesce(g.good_qty,0),0),
    'actual_rate',coalesce(v_actual_rate,a.actual_rate),
    'standard_rate',case when v_owner then v_standard_rate else null end
  ) order by
    case when regexp_replace(s.colour_code,'[^0-9]','','g')<>'' then regexp_replace(s.colour_code,'[^0-9]','','g')::int else 999999 end,
    case s.size_code when 'XS' then 1 when 'S' then 2 when 'M' then 3 when 'L' then 4 when 'XL' then 5 when 'XXL' then 6 when '3XL' then 7 when '4XL' then 8 else 99 end,
    s.size_code),'[]'::jsonb)
  into v_rows
  from sizes s
  left join assignment_sizes a on a.colour_code=s.colour_code and a.size_code=s.size_code
  left join submitted g on g.colour_code=s.colour_code and (g.size_code=s.size_code or g.size_code='ALL')
  left join alters alt on (alt.colour_code=s.colour_code or alt.colour_code=upper(trim(s.colour_name))) and alt.size_code=s.size_code;

  select coalesce(jsonb_agg(to_jsonb(w) order by w.worker_name),'[]'::jsonb)
  into v_workers
  from public.rr_upm_worker_list_v8_3(p_department_code) w;

  return jsonb_build_object(
    'lot',v_lot,
    'department_code',upper(trim(p_department_code)),
    'rows',v_rows,
    'workers',v_workers,
    'actual_rate',v_actual_rate,
    'standard_rate',case when v_owner then v_standard_rate else null end,
    'owner_margin',case when v_owner then coalesce(v_margin,0) else null end,
    'can_view_standard',v_owner,
    'can_change_standard',v_owner,
    'can_change_margin',v_owner,
    'cutting_source',case when v_cutting_lot_id is not null then 'CUTTING_MODULE' else 'CANONICAL_FALLBACK' end
  );
end $$;

grant execute on function public.rr_upm_universal_form_v726(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Preflight: returns missing dependency names instead of allowing silent UI
-- mismatches. The page displays these directly.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_v726_preflight()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
select jsonb_build_object(
  'ok',
    to_regclass('public.rr_upm_lot_board_v1') is not null and
    to_regclass('public.rr_cutting_lots_v3') is not null and
    to_regclass('public.rr_cutting_breakup_v3') is not null and
    to_regclass('public.rr_upm_work_assignments_v8') is not null and
    to_regclass('public.rr_upm_submit_ledger_v2') is not null and
    to_regprocedure('public.rr_upm_get_lot_visuals_v6(text,text)') is not null and
    to_regprocedure('public.rr_upm_worker_list_v8_3(text)') is not null and
    to_regprocedure('public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text)') is not null and
    to_regprocedure('public.rr_upm_submit_ready_v2(text,text,text,text,text,text[])') is not null,
  'dependencies',jsonb_build_object(
    'lot_board',to_regclass('public.rr_upm_lot_board_v1') is not null,
    'cutting_lots',to_regclass('public.rr_cutting_lots_v3') is not null,
    'cutting_breakup',to_regclass('public.rr_cutting_breakup_v3') is not null,
    'visuals_v6',to_regprocedure('public.rr_upm_get_lot_visuals_v6(text,text)') is not null,
    'worker_list_v8_3',to_regprocedure('public.rr_upm_worker_list_v8_3(text)') is not null,
    'assign_v8_3',to_regprocedure('public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text)') is not null,
    'submit_v2',to_regprocedure('public.rr_upm_submit_ready_v2(text,text,text,text,text,text[])') is not null,
    'packing_matrix',to_regprocedure('public.rr_get_packable_matrix_v1(text)') is not null,
    'packing_generate',to_regprocedure('public.rr_generate_smart_pack_plan_v1(text,jsonb,integer)') is not null,
    'packing_submit',to_regprocedure('public.rr_submit_smart_pack_plan_v1(uuid)') is not null
  )
);
$$;

grant execute on function public.rr_upm_v726_preflight() to authenticated;

commit;
