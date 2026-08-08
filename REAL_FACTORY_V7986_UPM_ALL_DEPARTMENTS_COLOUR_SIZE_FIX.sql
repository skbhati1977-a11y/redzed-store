-- REAL FACTORY V798.6
-- UPM GLOBAL SMART ASSIGN COLOUR × SIZE SOURCE FIX
-- Scope: ALL production departments from PRINTING through PACKING.
-- Root cause fixed: released Cutting uses rr_cutting_breakup_v3.actual_qty,
-- while the shared UPM cut-size source had been reading planned_qty.
-- This patch does NOT alter historical assignments, production actions,
-- payroll, Packing/Despatch stock, or submitted history.

begin;

-- Guard the exact shared contracts used by Universal Production.
do $$
begin
  if to_regclass('public.rr_cutting_lots_v3') is null
     or to_regclass('public.rr_cutting_breakup_v3') is null then
    raise exception 'Cutting V3 source tables are required.';
  end if;
  if to_regprocedure('public.rr_upm_universal_form_v741(text,text)') is null then
    raise exception 'UPM universal form V741 is required.';
  end if;
end $$;

-- Shared source used by UPM assignment / balance / inbound logic.
-- SINGLE = released Cutting Master lot: ACTUAL cutting quantity is authoritative.
-- MULTI = preserve the existing production-lot source contract.
drop function if exists public.rr_upm_cut_size_rows_v726(text);
create function public.rr_upm_cut_size_rows_v726(p_lot_no text)
returns table(
  source_type text,
  source_lot_id uuid,
  colour_id uuid,
  colour_code text,
  colour_name text,
  size_code text,
  cutting_qty numeric
)
language sql
stable
security definer
set search_path=public
as $function$
with single_rows as(
  select
    1 source_priority,
    'SINGLE'::text source_type,
    l.id source_lot_id,
    b.cb_colour_id colour_id,
    case
      when c.col_no is not null then upper('C'||c.col_no::text)
      when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
      else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR'))
    end colour_code,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour') colour_name,
    upper(trim(b.size_code)) size_code,
    sum(coalesce(b.actual_qty,0))::numeric cutting_qty
  from public.rr_cutting_lots_v3 l
  join public.rr_cutting_breakup_v3 b on b.cutting_lot_id=l.id
  left join public.rr_cb_colours c on c.id=b.cb_colour_id
  where upper(trim(l.lot_no))=upper(trim(p_lot_no))
    and coalesce(b.actual_qty,0)>0
  group by
    l.id,b.cb_colour_id,c.col_no,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour'),
    upper(trim(b.size_code)),
    case
      when c.col_no is not null then upper('C'||c.col_no::text)
      when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
      else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR'))
    end
),
multi_rows as(
  select
    2 source_priority,
    'MULTI'::text source_type,
    l.id source_lot_id,
    b.cb_colour_id colour_id,
    case
      when c.col_no is not null then upper('C'||c.col_no::text)
      when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
      else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR'))
    end colour_code,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour') colour_name,
    upper(trim(b.size_code)) size_code,
    sum(coalesce(b.planned_qty,0))::numeric cutting_qty
  from public.rr_production_lots l
  join public.rr_production_lot_breakup_v3 b on b.production_lot_id=l.id
  left join public.rr_cb_colours c on c.id=b.cb_colour_id
  where upper(trim(l.lot_no))=upper(trim(p_lot_no))
    and coalesce(b.planned_qty,0)>0
  group by
    l.id,b.cb_colour_id,c.col_no,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour'),
    upper(trim(b.size_code)),
    case
      when c.col_no is not null then upper('C'||c.col_no::text)
      when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
      else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR'))
    end
),
all_rows as(
  select * from single_rows
  union all
  select * from multi_rows
),
chosen as(
  select min(source_priority) source_priority from all_rows
)
select
  a.source_type,a.source_lot_id,a.colour_id,a.colour_code,
  a.colour_name,a.size_code,a.cutting_qty
from all_rows a
cross join chosen c
where a.source_priority=c.source_priority
order by
  case when a.colour_code~'^C[0-9]+$'
       then regexp_replace(a.colour_code,'[^0-9]','','g')::integer
       else 999999 end,
  a.colour_name,
  case a.size_code
    when 'XS' then 1 when 'S' then 2 when 'M' then 3 when 'L' then 4
    when 'XL' then 5 when 'XXL' then 6 when '2XL' then 6
    when '3XL' then 7 when '4XL' then 8 when '5XL' then 9 else 99 end,
  a.size_code;
$function$;

grant execute on function public.rr_upm_cut_size_rows_v726(text) to authenticated;

-- Refresh already released Cutting lots into the UPM registry/queue when the
-- installed bridge is available. It is intentionally idempotent.
do $$
begin
  if to_regprocedure('public.rr_upm_sync_cutting_lots_v2()') is not null then
    perform public.rr_upm_sync_cutting_lots_v2();
  end if;
end $$;

commit;

-- GLOBAL PROOF 1: recently released Cutting lots must now return Colour × Size rows.
select
  l.lot_no,
  count(m.*) as colour_size_rows,
  coalesce(sum(m.cutting_qty),0) as mapped_cutting_qty
from public.rr_cutting_lots_v3 l
left join lateral public.rr_upm_cut_size_rows_v726(l.lot_no) m on true
where exists (
  select 1 from public.rr_cutting_breakup_v3 b
  where b.cutting_lot_id=l.id and coalesce(b.actual_qty,0)>0
)
group by l.lot_no,l.created_at
order by l.created_at desc nulls last
limit 30;

-- GLOBAL PROOF 2: show any released Cutting lot that STILL has no shared UPM map.
-- Expected result: 0 rows.
select l.lot_no
from public.rr_cutting_lots_v3 l
where exists (
  select 1 from public.rr_cutting_breakup_v3 b
  where b.cutting_lot_id=l.id and coalesce(b.actual_qty,0)>0
)
and not exists (
  select 1 from public.rr_upm_cut_size_rows_v726(l.lot_no)
)
order by l.created_at desc nulls last;
