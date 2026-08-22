-- RUN_NOW_V9311_PACKING_FG_BRIDGE.sql
-- Purpose:
-- 1) UPM PACKING submit ke baad FG Packing algorithm source table sync ho.
-- 2) FG Packing ready cards PRESS ke saath PACKING output ko bhi source maan sake.
-- 3) Matrix duplicate na ho: PACKING rows available hon to PACKING prefer kare, warna PRESS fallback.
-- 4) Existing completed UPM PACKING lots ka one-time backfill.

create or replace function public.rr_fg_sync_packing_actuals_from_upm_v9311(
  p_canonical_lot_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_lot_no text;
  v_rows int := 0;
  v_pcs int := 0;
begin
  select lot_no
  into v_lot_no
  from public.rr_upm_lot_registry
  where canonical_lot_id = p_canonical_lot_id
  limit 1;

  if v_lot_no is null then
    select lot_no
    into v_lot_no
    from public.rr_upm_dynamic_submit_history_v741
    where canonical_lot_id = p_canonical_lot_id
    order by submitted_at desc
    limit 1;
  end if;

  if v_lot_no is null then
    raise exception 'Lot not found for packing bridge.';
  end if;

  delete from public.rr_lot_process_actuals
  where lot_no = v_lot_no
    and upper(process_code) = 'PACKING';

  insert into public.rr_lot_process_actuals(
    id,
    lot_no,
    process_code,
    colour_id,
    colour_name,
    size_code,
    in_pcs,
    out_pcs,
    short_pcs,
    reject_pcs,
    actual_rate,
    process_status,
    remarks,
    is_frozen,
    frozen_at,
    created_at,
    updated_at
  )
  select
    gen_random_uuid(),
    x.lot_no,
    'PACKING',
    x.colour_id,
    x.colour_name,
    x.size_code,
    x.qty,
    x.qty,
    0,
    0,
    0,
    'COMPLETED',
    'V9311 UPM PACKING submit bridge',
    true,
    now(),
    now(),
    now()
  from (
    select
      h.lot_no,
      h.colour_id,
      h.colour_name,
      h.size_code,
      sum(h.good_qty)::int as qty
    from public.rr_upm_dynamic_submit_history_v741 h
    where h.canonical_lot_id = p_canonical_lot_id
      and h.department_code = 'PACKING'
      and h.good_qty > 0
    group by h.lot_no, h.colour_id, h.colour_name, h.size_code
  ) x;

  get diagnostics v_rows = row_count;

  select coalesce(sum(out_pcs),0)::int
  into v_pcs
  from public.rr_lot_process_actuals
  where lot_no = v_lot_no
    and upper(process_code) = 'PACKING';

  return jsonb_build_object('ok', true, 'lot_no', v_lot_no, 'rows', v_rows, 'pcs', v_pcs);
end;
$$;

create or replace function public.rr_fg_packable_matrix_v787(
  p_lot_no text,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  r jsonb;
  v_process text;
begin
  perform public.rr_fg_assert_user_v787();

  if to_regclass('public.rr_lot_process_actuals') is null then
    return '[]'::jsonb;
  end if;

  select case
    when exists (
      select 1
      from public.rr_lot_process_actuals
      where lot_no = p_lot_no
        and upper(process_code) = 'PACKING'
        and coalesce(out_pcs, in_pcs, 0) > 0
    )
    then 'PACKING'
    else 'PRESS'
  end
  into v_process;

  select coalesce(jsonb_agg(jsonb_build_object(
    'colour_code', colour_code,
    'size_code', size_code,
    'qty', qty
  ) order by colour_code, size_code), '[]'::jsonb)
  into r
  from (
    select
      coalesce(colour_name, colour_id::text, 'UNKNOWN') as colour_code,
      coalesce(size_code, 'ALL') as size_code,
      greatest(0, floor(sum(coalesce(out_pcs, in_pcs, 0))))::int as qty
    from public.rr_lot_process_actuals
    where lot_no = p_lot_no
      and upper(process_code) = v_process
    group by coalesce(colour_name, colour_id::text, 'UNKNOWN'), coalesce(size_code, 'ALL')
    having greatest(0, floor(sum(coalesce(out_pcs, in_pcs, 0))))::int > 0
  ) s;

  return coalesce(r, '[]'::jsonb);
end;
$$;

create or replace function public.rr_fg_ready_packing_cards_v788(
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  out_json jsonb;
begin
  perform public.rr_fg_assert_user_v787();

  if p_data_mode not in ('TEST','REAL') then
    raise exception 'Invalid data mode';
  end if;

  if to_regclass('public.rr_lot_process_actuals') is null then
    return '[]'::jsonb;
  end if;

  execute $q$
    with lots as (
      select distinct trim(lot_no) as lot_no
      from rr_lot_process_actuals
      where nullif(trim(lot_no),'') is not null
        and upper(process_code) in ('PRESS','PACKING')
    ),
    matrices as (
      select l.lot_no, public.rr_fg_packable_matrix_v787(l.lot_no,$1) as matrix
      from lots l
    ),
    ready as (
      select
        m.lot_no,
        m.matrix,
        coalesce((select sum((z->>'qty')::int) from jsonb_array_elements(m.matrix) z),0)::int as ready_qty,
        coalesce((select count(distinct z->>'colour_code') from jsonb_array_elements(m.matrix) z),0)::int as colours,
        coalesce((select count(distinct z->>'size_code') from jsonb_array_elements(m.matrix) z),0)::int as sizes
      from matrices m
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'lot_no', r.lot_no,
      'ready_qty', r.ready_qty,
      'colours', r.colours,
      'sizes', r.sizes,
      'assignment_id', a.id,
      'assignment_status', a.status,
      'worker_user_id', a.worker_user_id,
      'worker_name', a.worker_name,
      'is_mine', (a.worker_user_id = auth.uid()),
      'status_label', case
        when a.id is null then 'READY · TAP TO ASSIGN'
        when a.worker_user_id = auth.uid() and a.status = 'ASSIGNED' then 'MY WORK · TAP TO ACCEPT'
        when a.worker_user_id = auth.uid() and a.status = 'ACCEPTED' then 'MY WORK · TAP TO PACK'
        else 'ASSIGNED'
      end
    ) order by r.lot_no), '[]'::jsonb)
    from ready r
    left join rr_fg_packing_assignments_v788 a
      on a.lot_no = r.lot_no
     and a.data_mode = $1
     and a.status in ('ASSIGNED','ACCEPTED')
    where r.ready_qty > 0
      and not exists (
        select 1
        from rr_fg_pack_plans_v787 p
        where p.lot_no = r.lot_no
          and p.data_mode = $1
          and p.status = 'SUBMITTED'
      )
      and (public.rr_fg_is_pack_assigner_v788() or a.worker_user_id = auth.uid())
  $q$
  into out_json
  using p_data_mode;

  return coalesce(out_json, '[]'::jsonb);
end;
$$;

create or replace function public.rr_upm_submit_with_actual_cost_gate_v9300(
  p_canonical_lot_id text,
  p_department_code text,
  p_rows jsonb,
  p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_code text;
  v_core text;
  v_rate numeric;
  v_result jsonb;
  v_bridge jsonb := null;
begin
  v_code := public.rr_costing_canonical_department_v760(p_department_code);
  v_core := public.rr_upm_core_department_v9077(p_department_code);

  select actual_rate
  into v_rate
  from public.rr_upm_department_rates_v2
  where canonical_lot_id = p_canonical_lot_id
    and public.rr_costing_canonical_department_v760(department_code) = v_code
  order by updated_at desc
  limit 1;

  if coalesce(v_rate,0) <= 0 then
    raise exception 'Actual Cost / PCS is mandatory before submit for %', v_code;
  end if;

  select public.rr_upm_submit_colours_v741(p_canonical_lot_id, v_core, p_rows, p_remarks)
  into v_result;

  if v_core = 'PACKING' then
    v_bridge := public.rr_fg_sync_packing_actuals_from_upm_v9311(p_canonical_lot_id);
  end if;

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'actual_rate', v_rate,
    'actual_cost_gate', 'PASSED',
    'costing_department_code', v_code,
    'fg_packing_bridge', v_bridge
  );
end;
$$;

grant execute on function public.rr_fg_sync_packing_actuals_from_upm_v9311(text) to authenticated;
grant execute on function public.rr_fg_packable_matrix_v787(text,text) to authenticated;
grant execute on function public.rr_fg_ready_packing_cards_v788(text) to authenticated;
grant execute on function public.rr_upm_submit_with_actual_cost_gate_v9300(text,text,jsonb,text) to authenticated;

do $$
declare
  r record;
begin
  for r in
    select distinct canonical_lot_id
    from public.rr_upm_dynamic_submit_history_v741
    where department_code = 'PACKING'
      and good_qty > 0
      and canonical_lot_id is not null
  loop
    perform public.rr_fg_sync_packing_actuals_from_upm_v9311(r.canonical_lot_id);
  end loop;
end;
$$;
