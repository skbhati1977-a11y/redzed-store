-- REDZED ERP UPM V725 — Integrated Dashboard + canonical Cutting map adapter
-- Fixes V723 cutting map source, size rows, worker list, assignment/production summary.
begin;

create or replace function public.rr_upm_universal_form_v725(
  p_canonical_lot_id text,
  p_department_code text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_lot jsonb; v_rows jsonb; v_workers jsonb;
  v_rate numeric:=0; v_std numeric:=null; v_owner boolean:=false; v_margin numeric:=0;
begin
  v_owner:=public.rr_upm_is_owner_admin_v723();
  select to_jsonb(x) into v_lot from public.rr_upm_lot_board_v1 x
  where x.canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot is null then raise exception 'Lot not found'; end if;

  select coalesce(r.actual_rate,0) into v_rate
  from public.rr_upm_department_rates_v2 r
  where r.canonical_lot_id=p_canonical_lot_id
    and upper(r.department_code)=upper(p_department_code)
  limit 1;

  if v_owner then
    select r.standard_rate into v_std from public.rr_upm_standard_rates_v723 r
    where r.canonical_lot_id=p_canonical_lot_id
      and upper(r.department_code)=upper(p_department_code) limit 1;
    select m.flat_amount_per_piece into v_margin from public.rr_upm_owner_margin_v723 m
    where m.is_active order by m.effective_from desc limit 1;
  end if;

  with mapped_sizes as (
    select upper(trim(m.colour_code)) colour_code,
      max(coalesce(nullif(trim(m.colour_name),''),upper(trim(m.colour_code)))) colour_name,
      upper(trim(m.size_code)) size_code,
      sum(m.cut_qty)::numeric cutting_qty
    from public.rr_upm_lot_cut_size_map_v5 m
    where m.is_active
      and (m.canonical_lot_id=p_canonical_lot_id
           or upper(trim(m.lot_no))=upper(trim(v_lot->>'lot_no')))
    group by upper(trim(m.colour_code)),upper(trim(m.size_code))
  ), cutting_lot as (
    select l.id
    from public.rr_cutting_lots_v3 l
    where upper(trim(l.lot_no))=upper(trim(v_lot->>'lot_no'))
    order by l.created_at desc limit 1
  ), direct_sizes as (
    select upper('C'||coalesce(c.col_no::text,'0')) colour_code,
      max(coalesce(nullif(trim(x.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour')) colour_name,
      upper(trim(x.size_code)) size_code,
      sum(x.actual_qty)::numeric cutting_qty
    from public.rr_cutting_breakup_v3 x
    join cutting_lot cl on cl.id=x.cutting_lot_id
    left join public.rr_cb_colours c on c.id=x.cb_colour_id
    where x.actual_qty>0
    group by upper('C'||coalesce(c.col_no::text,'0')),upper(trim(x.size_code))
  ), sizes as (
    select * from mapped_sizes
    union all
    select * from direct_sizes where not exists (select 1 from mapped_sizes)
  ), active_assign as (
    select distinct on (upper(a.colour_code))
      upper(a.colour_code) colour_code,a.worker_id,a.worker_name_snapshot worker_name,
      a.worker_code,a.size_breakup,a.assigned_qty,a.status,a.id assignment_id
    from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id
      and upper(a.department_code)=upper(p_department_code)
      and a.status in ('ASSIGNED','IN_PROGRESS','COMPLETED')
    order by upper(a.colour_code),a.assigned_at desc
  ), assign_size as (
    select a.colour_code,a.worker_id,a.worker_name,a.worker_code,a.status,a.assignment_id,
      upper(trim(z->>'size_code')) size_code,
      coalesce((z->>'qty')::numeric,0) assigned_qty
    from active_assign a
    cross join lateral jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb)) z
  ), prod as (
    select upper(e.colour_code) colour_code,upper(e.size_code) size_code,
      sum(case when e.entry_type='GOOD' then e.qty else 0 end)::numeric good_qty,
      sum(case when e.entry_type in ('ALTER_OUT','REJECT') then e.qty else 0 end)::numeric alter_qty,
      sum(case when e.entry_type='REMAKE' then e.qty else 0 end)::numeric remake_qty
    from public.rr_upm_entries e
    where e.canonical_lot_id=p_canonical_lot_id
      and upper(e.department_code)=upper(p_department_code)
    group by upper(e.colour_code),upper(e.size_code)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'colour_code',s.colour_code,'colour_name',s.colour_name,'size_code',s.size_code,
    'cutting_qty',s.cutting_qty,'worker_id',a.worker_id,'worker_name',a.worker_name,
    'worker_code',a.worker_code,'assignment_id',a.assignment_id,'assignment_status',a.status,
    'assigned_qty',coalesce(a.assigned_qty,0),'good_qty',coalesce(p.good_qty,0),
    'alter_qty',coalesce(p.alter_qty,0),'remake_qty',coalesce(p.remake_qty,0),'damage_qty',0,
    'pending_qty',greatest(coalesce(a.assigned_qty,0)-coalesce(p.good_qty,0)-coalesce(p.alter_qty,0),0),
    'actual_rate',v_rate,'standard_rate',case when v_owner then v_std else null end
  ) order by case when regexp_replace(s.colour_code,'[^0-9]','','g')<>'' then regexp_replace(s.colour_code,'[^0-9]','','g')::int else 999999 end,
    case s.size_code when 'XS' then 1 when 'S' then 2 when 'M' then 3 when 'L' then 4 when 'XL' then 5 when 'XXL' then 6 when '3XL' then 7 when '4XL' then 8 else 99 end,
    s.size_code),'[]'::jsonb) into v_rows
  from sizes s
  left join assign_size a on a.colour_code=s.colour_code and a.size_code=s.size_code
  left join prod p on p.colour_code=s.colour_code and (p.size_code=s.size_code or p.size_code='ALL');

  select coalesce(jsonb_agg(to_jsonb(w) order by w.worker_name),'[]'::jsonb)
  into v_workers from public.rr_upm_worker_list_v8(p_department_code) w;

  return jsonb_build_object(
    'lot',v_lot,'department_code',upper(p_department_code),'rows',v_rows,'workers',v_workers,
    'actual_rate',v_rate,'standard_rate',case when v_owner then v_std else null end,
    'owner_margin',case when v_owner then coalesce(v_margin,0) else null end,
    'can_view_standard',v_owner,'can_change_standard',v_owner,'can_change_margin',v_owner
  );
end $$;

grant execute on function public.rr_upm_universal_form_v725(text,text) to authenticated;
commit;
