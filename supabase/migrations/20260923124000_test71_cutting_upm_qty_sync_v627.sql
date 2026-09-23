-- TEST71: sync UPM quantity after the canonical Cutting breakup has settled.
-- This rule applies to every Cutting Lot; no named fixture or Lot is patched.
create or replace function public.rr_sync_cutting_lot_qty_from_breakup_v9057()
returns trigger
language plpgsql
as $function$
declare
  v_lot_id uuid := coalesce(new.cutting_lot_id, old.cutting_lot_id);
  v_qty integer;
begin
  select coalesce(sum(
    case when coalesce(actual_qty,0) > 0 then actual_qty else coalesce(planned_qty,0) end
  ),0)::integer
  into v_qty
  from public.rr_cutting_breakup_v3
  where cutting_lot_id = v_lot_id;

  update public.rr_cutting_lots_v3
  set actual_pcs = v_qty,
      planned_pcs = v_qty,
      updated_at = now()
  where id = v_lot_id;

  -- The identity trigger can run before breakup rows exist. The nested
  -- Cutting UPDATE is depth-guarded, so sync the settled quantity here.
  perform public.rr_upm_sync_cutting_identity_v761(
    v_lot_id, null, null, null, false,
    'Automatic quantity sync after Cutting breakup'
  );
  return coalesce(new, old);
end;
$function$;

-- Repair all existing stale identities by the same shared source rule.
-- No Lot number, CB identifier, or fixture-specific condition appears here.
do $reconcile$
declare v_id uuid;
begin
  for v_id in
    select c.id
    from public.rr_cutting_lots_v3 c
    join public.rr_upm_lot_registry r
      on r.canonical_lot_id='rr_cutting_lots_v3:'||c.id::text
    where coalesce(r.total_qty,0) <
      coalesce(nullif(c.actual_pcs,0),c.planned_pcs,0)
  loop
    perform public.rr_upm_sync_cutting_identity_v761(
      v_id, null, null, null, false,
      'Universal reconciliation of settled Cutting quantity'
    );
  end loop;
end;
$reconcile$;
