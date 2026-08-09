-- Run AFTER REAL_FACTORY_V804_ACCESSORY_FRONTEND_BACKEND.sql

select 'FUNCTION' as check_type, p.proname as object_name
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'rr_upsert_sticker_master_v804',
  'rr_upsert_metal_id_master_v804',
  'rr_post_accessory_purchase_v804',
  'rr_sticker_instruction_for_master_v804',
  'rr_metal_id_instruction_for_master_v804',
  'rr_sync_accessory_requirements_for_lot_v804',
  'rr_pm_save_decision_bundle_v804',
  'rr_accessory_lot_release_sync_trigger_v804'
)
union all
select 'TRIGGER',tgname
from pg_trigger
where not tgisinternal and tgname in (
  'rr_accessory_cutting_release_sync_v804',
  'rr_accessory_multi_release_sync_v804'
)
order by check_type,object_name;

select
  'STICKER' as item_type,
  s.sticker_no as item_no,
  s.sticker_name as item_name,
  s.sticker_quality as attribute,
  b.physical_stock_qty,
  round(b.weighted_avg_cost_per_piece,2) as avg_cost,
  b.open_requirement_qty,
  b.free_stock_qty,
  b.req_now_qty
from public.rr_sticker_master_v803 s
left join public.rr_accessory_stock_balance_v804 b
  on b.sticker_master_id=s.id and b.data_mode='TEST'
union all
select
  'METAL_ID',m.metal_id_no,m.metal_id_name,m.id_size,
  b.physical_stock_qty,round(b.weighted_avg_cost_per_piece,2),
  b.open_requirement_qty,b.free_stock_qty,b.req_now_qty
from public.rr_metal_id_master_v803 m
left join public.rr_accessory_stock_balance_v804 b
  on b.metal_id_master_id=m.id and b.data_mode='TEST'
order by item_type,item_no;

-- Existing verified lot requirement sync should remain callable.
select public.rr_sync_accessory_requirements_for_lot_v804('2NSKB1','TEST');
