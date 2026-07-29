-- REDZED UPM V7 FINAL MOUNT
-- Additive patch. Existing Cutting/UPM/Alter/Repair/Damage/Remake flows remain unchanged.

begin;

create or replace function public.rr_upm_get_lot_visuals_v6(
  p_canonical_lot_id text,
  p_art_no text default null
)
returns table(garment_url text, print_urls jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with requested_lot as (
    select cl.id, cl.lot_no, cl.art_no, cl.print_no
    from public.rr_cutting_lots_v3 cl
    where ('rr_cutting_lots_v3:' || cl.id::text) = p_canonical_lot_id
       or cl.lot_no = p_canonical_lot_id
    order by case when ('rr_cutting_lots_v3:' || cl.id::text) = p_canonical_lot_id then 0 else 1 end
    limit 1
  ),
  selected_print as (
    select pm.garment_preview_url, pm.artwork_url
    from requested_lot rl
    left join public.rr_print_master pm
      on pm.print_no = rl.print_no
     and coalesce(pm.is_active, true)
    limit 1
  )
  select
    nullif(trim(sp.garment_preview_url), ''),
    case
      when nullif(trim(sp.artwork_url), '') is null then '[]'::jsonb
      else jsonb_build_array(trim(sp.artwork_url))
    end
  from selected_print sp
  union all
  select null::text, '[]'::jsonb
  where not exists (select 1 from selected_print)
  limit 1;
$$;

grant execute on function public.rr_upm_get_lot_visuals_v6(text,text) to authenticated;

commit;
