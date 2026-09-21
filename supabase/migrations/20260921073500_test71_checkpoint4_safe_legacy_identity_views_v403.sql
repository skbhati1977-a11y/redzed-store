-- TEST71 Checkpoint 4 compatibility hardening.
-- Preserve legacy Art/Lot identity operations while making private columns
-- unreachable by their renamed base-relation names.

begin;

-- V402 kept Art identity DML through a safe view. Remove the inherited broad
-- table grant from its renamed base and publish only non-private columns.
revoke all on table public.rr_art_master_core_v402
  from public,anon,authenticated;
grant select(
  id,art_no,item_name,product_name,category,fabric_id,description,
  standard_sizes,default_box_qty,cuff_collar_required,
  matching_cloth_required,folding_patti_required,other_material_required,
  other_material_note,dealer_rate,mrp,is_active,created_at,updated_at,
  caption_text,caption_items,art_category_id,material_requirements
) on public.rr_art_master_core_v402 to authenticated;
grant insert(
  id,art_no,item_name,product_name,category,fabric_id,description,
  standard_sizes,default_box_qty,cuff_collar_required,
  matching_cloth_required,folding_patti_required,other_material_required,
  other_material_note,dealer_rate,mrp,is_active,created_at,updated_at,
  caption_text,caption_items,art_category_id,material_requirements
) on public.rr_art_master_core_v402 to authenticated;
grant update(
  art_no,item_name,product_name,category,fabric_id,description,
  standard_sizes,default_box_qty,cuff_collar_required,
  matching_cloth_required,folding_patti_required,other_material_required,
  other_material_note,dealer_rate,mrp,is_active,updated_at,
  caption_text,caption_items,art_category_id,material_requirements
) on public.rr_art_master_core_v402 to authenticated;
grant delete on public.rr_art_master_core_v402 to authenticated;
grant all on table public.rr_art_master_core_v402 to service_role;

-- Restore Owner/Admin/Super Admin operational access to the legacy Lot
-- identity without returning hidden adjustments, cost snapshots or margin.
alter table public.rr_lots rename to rr_lots_core_v403;

drop policy if exists rr_super_admin_private_cost_v402
  on public.rr_lots_core_v403;
drop policy if exists rr_lots_operational_v403
  on public.rr_lots_core_v403;
create policy rr_lots_operational_v403
on public.rr_lots_core_v403 for all to authenticated
using (
  public.rr_is_owner_or_admin()
  or public.rr_private_cost_scope_v402()
)
with check (
  public.rr_is_owner_or_admin()
  or public.rr_private_cost_scope_v402()
);

revoke all on table public.rr_lots_core_v403
  from public,anon,authenticated;
grant select(
  id,cutting_sheet_id,lot_no,lot_group,size_group,sleeve_type,
  selected_sizes,planned_qty,cut_qty,current_department_code,status,box_qty,
  created_at,updated_at,art_id,cb_id,final_rate_snapshot,total_planned_pcs,
  total_cut_pcs,total_packed_pcs,notes,created_by
) on public.rr_lots_core_v403 to authenticated;
grant insert(
  id,cutting_sheet_id,lot_no,lot_group,size_group,sleeve_type,
  selected_sizes,planned_qty,cut_qty,current_department_code,status,box_qty,
  created_at,updated_at,art_id,cb_id,final_rate_snapshot,total_planned_pcs,
  total_cut_pcs,total_packed_pcs,notes,created_by
) on public.rr_lots_core_v403 to authenticated;
grant update(
  cutting_sheet_id,lot_no,lot_group,size_group,sleeve_type,selected_sizes,
  planned_qty,cut_qty,current_department_code,status,box_qty,updated_at,
  art_id,cb_id,final_rate_snapshot,total_planned_pcs,total_cut_pcs,
  total_packed_pcs,notes,created_by
) on public.rr_lots_core_v403 to authenticated;
grant delete on public.rr_lots_core_v403 to authenticated;
grant all on table public.rr_lots_core_v403 to service_role;

create view public.rr_lots
with (security_invoker=true)
as
select
  l.id,l.cutting_sheet_id,l.lot_no,l.lot_group,l.size_group,l.sleeve_type,
  l.selected_sizes,l.planned_qty,l.cut_qty,l.current_department_code,l.status,
  l.box_qty,l.created_at,l.updated_at,l.art_id,l.cb_id,l.final_rate_snapshot,
  l.total_planned_pcs,l.total_cut_pcs,l.total_packed_pcs,l.notes,l.created_by
from public.rr_lots_core_v403 l;

revoke all on table public.rr_lots from public,anon;
grant select,insert,update,delete on table public.rr_lots to authenticated;
grant all on table public.rr_lots to service_role;

-- Re-publish the old dashboard projection with operational fields only.
alter view public.rr_live_lot_status
  rename to rr_live_lot_status_private_core_v403;
revoke all on table public.rr_live_lot_status_private_core_v403
  from public,anon,authenticated;
grant select on table public.rr_live_lot_status_private_core_v403
  to service_role;

create view public.rr_live_lot_status
with (security_invoker=true)
as
select
  l.id,l.lot_no,l.art_id,a.art_no,a.item_name,l.cb_id,
  cb.cb_code,cb.cb_base_no,cb.division_index,
  cb.sleeve_type as cb_sleeve_type,cb.size_family,l.status,
  l.final_rate_snapshot,l.total_planned_pcs,l.total_cut_pcs,
  l.total_packed_pcs,
  greatest(l.total_planned_pcs-l.total_packed_pcs,0) as pending_pcs,
  l.created_at,l.updated_at
from public.rr_lots_core_v403 l
left join public.rr_art_master_core_v402 a on a.id=l.art_id
left join public.rr_cb_units cb on cb.id=l.cb_id;

revoke all on table public.rr_live_lot_status from public,anon;
grant select on table public.rr_live_lot_status to authenticated,service_role;

comment on view public.rr_lots is
  'V403 updatable operational Lot identity; cost snapshots, hidden adjustment and margin are omitted.';
comment on view public.rr_live_lot_status is
  'V403 operational dashboard projection; manufacturing cost and margin fields are omitted.';

commit;
