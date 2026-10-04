-- Run BEGIN, the snapshot below, the compatibility migration, the comparison, then ROLLBACK.
create temporary table cb_costing_existing_snapshot as
select r.canonical_lot_id,public.rr_upm_product_cost_actual_v723(r.canonical_lot_id,'TEST') ctx
from public.rr_upm_lot_registry r
where r.canonical_lot_id in(
 select x.canonical_lot_id from public.rr_upm_lot_registry x join(
 select 'rr_cutting_lots_v3' source_table,id::text source_id,cb_unit_id from public.rr_cutting_lots_v3
 union all select 'rr_production_lots',id::text,cb_unit_id from public.rr_production_lots) s on s.source_table=x.source_table and s.source_id=x.source_id
 join public.rr_cb_art_assignments ca on ca.cb_id=s.cb_unit_id
);

-- Apply the compatibility migration here, then run the comparison below.
do $compare$
declare r record; c jsonb; k text; n int:=0;
begin
 for r in select * from cb_costing_existing_snapshot loop
  c:=public.rr_upm_product_cost_actual_v723(r.canonical_lot_id,'TEST');
  foreach k in array array['base_cost_per_pc','final_sale_rate','salary','foc','printing','special_departments','canonical_raw_bom_per_pc','packing_box_raw_per_pc'] loop
   if c->k is distinct from r.ctx->k then raise exception 'Existing rule/cost changed for %: %',r.canonical_lot_id,k; end if;
  end loop; n:=n+1;
 end loop;
 if n<>43 then raise exception 'Existing lot count changed, refresh baseline: %',n; end if;
end $compare$;
