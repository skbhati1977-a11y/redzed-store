-- REDZED ERP — UPM Work Assignment V8.1
-- VERIFIED SOURCE FIX: rr_cutting_lots_v3 + rr_cutting_breakup_v3 + rr_cb_colours
-- Run AFTER REDZED_UPM_WORK_ASSIGNMENT_V8.sql.
-- Additive: no Cutting, Production Submit, Alter, Repair, Damage, Remake or Reversal rewrite.

begin;

-- Context now reads the live Cutting tables actually used by Cutting Master.
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
  with board_lot as (
    select b.canonical_lot_id, b.lot_no
    from public.rr_upm_lot_board_v1 b
    where b.canonical_lot_id = p_canonical_lot_id
    limit 1
  ),
  cutting_lot as (
    select l.id cutting_lot_id, l.lot_no
    from public.rr_cutting_lots_v3 l
    join board_lot b on upper(trim(b.lot_no)) = upper(trim(l.lot_no))
    order by l.created_at desc
    limit 1
  ),
  mapped as (
    select
      upper('C' || coalesce(c.col_no::text, '0')) as colour_code,
      max(coalesce(nullif(trim(x.colour_name_snapshot),''), nullif(trim(c.colour_name),''), 'Colour')) as colour_name,
      sum(x.actual_qty)::bigint as total_qty,
      jsonb_agg(
        jsonb_build_object(
          'size_code', upper(trim(x.size_code)),
          'qty', x.actual_qty
        )
        order by
          case upper(trim(x.size_code))
            when 'XS' then 1 when 'S' then 2 when 'M' then 3
            when 'L' then 4 when 'XL' then 5 when 'XXL' then 6
            when '3XL' then 7 when '4XL' then 8 else 99
          end,
          upper(trim(x.size_code))
      ) as size_breakup
    from public.rr_cutting_breakup_v3 x
    join cutting_lot l on l.cutting_lot_id = x.cutting_lot_id
    left join public.rr_cb_colours c on c.id = x.cb_colour_id
    where x.actual_qty > 0
    group by upper('C' || coalesce(c.col_no::text, '0'))
  )
  select
    m.colour_code,
    m.colour_name,
    m.total_qty,
    m.size_breakup,
    (a.id is not null) as is_locked,
    a.worker_id,
    a.worker_code,
    a.worker_name_snapshot,
    a.id
  from mapped m
  left join lateral (
    select x.*
    from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id = p_canonical_lot_id
      and upper(x.department_code) = upper(p_department_code)
      and upper(x.colour_code) = m.colour_code
      and x.status in ('ASSIGNED','IN_PROGRESS')
    order by x.assigned_at desc
    limit 1
  ) a on true
  order by regexp_replace(m.colour_code,'[^0-9]','','g')::integer, m.colour_name;
$$;

grant execute on function public.rr_upm_get_work_assign_context_v8(text,text) to authenticated;

-- Atomic assignment now revalidates against the same live Cutting source.
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
  v_cutting_lot_id uuid;
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
  where b.canonical_lot_id = p_canonical_lot_id
  limit 1;
  if v_lot_no is null then raise exception 'Production Lot not found.'; end if;

  select l.id into v_cutting_lot_id
  from public.rr_cutting_lots_v3 l
  where upper(trim(l.lot_no)) = upper(trim(v_lot_no))
  order by l.created_at desc
  limit 1;
  if v_cutting_lot_id is null then
    raise exception 'Cutting Lot mapping not found for Lot %.', v_lot_no;
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_colour := upper(trim(v_row->>'colour_code'));
    v_worker_id := nullif(v_row->>'worker_id','')::uuid;
    v_qty := coalesce((v_row->>'assigned_qty')::integer,0);
    if nullif(v_colour,'') is null then raise exception 'Colour is required.'; end if;
    if v_worker_id is null then raise exception 'Worker is required for colour %.',v_colour; end if;

    select
      max(coalesce(nullif(trim(x.colour_name_snapshot),''), nullif(trim(c.colour_name),''), v_colour)),
      sum(x.actual_qty)::integer,
      jsonb_agg(
        jsonb_build_object('size_code',upper(trim(x.size_code)),'qty',x.actual_qty)
        order by
          case upper(trim(x.size_code))
            when 'XS' then 1 when 'S' then 2 when 'M' then 3
            when 'L' then 4 when 'XL' then 5 when 'XXL' then 6
            when '3XL' then 7 when '4XL' then 8 else 99
          end,
          upper(trim(x.size_code))
      )
    into v_colour_name,v_expected,v_sizes
    from public.rr_cutting_breakup_v3 x
    left join public.rr_cb_colours c on c.id=x.cb_colour_id
    where x.cutting_lot_id=v_cutting_lot_id
      and upper('C' || coalesce(c.col_no::text,'0'))=v_colour
      and x.actual_qty > 0;

    if v_expected is null then
      raise exception 'Actual Cutting colour-size quantity not found for colour %.',v_colour;
    end if;
    if v_qty <> v_expected then
      raise exception 'Colour % quantity must equal mapped Cutting quantity: % PCS.',v_colour,v_expected;
    end if;

    select u.display_name,
      coalesce(nullif(trim(u.worker_code),''),'WRK-' || upper(substr(replace(u.user_id::text,'-',''),1,8)))
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
      ) returning * into v_inserted;
    exception when unique_violation then
      raise exception 'Colour % is already assigned in department %.',v_colour,upper(trim(p_department_code));
    end;
    return next v_inserted;
  end loop;
end;
$$;

grant execute on function public.rr_upm_assign_colours_v8(text,text,jsonb,text) to authenticated;

-- Quick verification helper. Replace LOT-... before running manually.
create or replace function public.rr_upm_verify_cutting_assignment_map_v8_1(p_lot_no text)
returns table(colour_code text, colour_name text, size_code text, mapped_qty integer)
language sql stable security definer set search_path=public as $$
  select
    upper('C' || coalesce(c.col_no::text,'0')),
    coalesce(nullif(trim(x.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour'),
    upper(trim(x.size_code)),
    x.actual_qty
  from public.rr_cutting_lots_v3 l
  join public.rr_cutting_breakup_v3 x on x.cutting_lot_id=l.id
  left join public.rr_cb_colours c on c.id=x.cb_colour_id
  where upper(trim(l.lot_no))=upper(trim(p_lot_no)) and x.actual_qty>0
  order by c.col_no,
    case upper(trim(x.size_code)) when 'XS' then 1 when 'S' then 2 when 'M' then 3 when 'L' then 4 when 'XL' then 5 when 'XXL' then 6 else 99 end;
$$;

grant execute on function public.rr_upm_verify_cutting_assignment_map_v8_1(text) to authenticated;

commit;

-- TEST AFTER COMMIT:
-- select * from public.rr_upm_verify_cutting_assignment_map_v8_1('YOUR-LOT-NO');
