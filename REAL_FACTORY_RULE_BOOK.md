# REAL FACTORY Rule Book

## Matching Cloth Master — source-of-truth rules

### Scope boundary
- Destination HTML: `real-matching-cloth-master.html`
- Destination JS: `real-matching-cloth-master-v9235.js`
- Slice Menu wiring file: `real-global-slice-menu-v9190.js`
- Matching Cloth work should stay in the destination HTML/JS unless a shared backend change is explicitly required.
- Do not alter CB Master, Art Decide, Cutting, Dashboard, other Product Master children, or database schema for Matching Cloth UI refinements.

### Approved UI mapping source
- Latest refined searchable mapping reference: `real-mc-searchable-mapping-v9140.js` (VERSION 9148 behavior).
- Earlier approved references: `real-mc-searchable-mapping-v9136.js` and `real-mc-mapped-dropdowns-v9135.js`.
- Fabric options RPC: `rr_get_mc1_fabric_options_v9134`.
- Vendor options RPC: `rr_get_mc_vendor_options_v9135`.
- Vendor option mapping carries `supplier_ledger_id` when available.

### Fabric rules
- Existing Fabric must resolve to the real MC1 fabric id, never just a disconnected label.
- Search/suggestion label may show Fabric Name + Available Qty + Avg Rate.
- `+ Add New Fabric` must be a separate red button outside the mapped selection field.
- New Fabric must use the existing MC1 create/upsert behavior through the approved purchase flow; never create a parallel fabric store.

### Vendor rules
- Vendor selection must be sourced from `rr_get_mc_vendor_options_v9135` and remain searchable.
- Preserve `supplier_ledger_id` on the selected vendor in UI state when returned by the RPC.
- Vendor suggestion context may show bill count, total qty, and total value.
- `+ Add New Vendor` must be a separate red button outside the mapped selection field.
- Do not replace mapped vendor selection with a plain free-text-only system.

### Purchase / Accounts rules
- Purchase posting contract: `rr_post_mc_fabric_purchase_v3`.
- Existing Product Master MC save behavior source: `real-product-master-v720.js`.
- Accounts exposure: `rr_get_mc1_purchase_account_v9076()`.
- Purchase account name: `Matching Cloth Purchase`.
- Posting must continue to update exact fabric qty/value/avg rate, consolidated MC1 qty/value/avg rate, and `PURCHASE_IN` ledger behavior.

### Dedicated page layout rule
The Matching Cloth child page order is fixed:
1. Matching Cloth Master header
2. Matching Cloth Entry Form
3. Available Matching Cloth Stock

CB cards, Art Due cards, Art Decide cards, or crafting decision controls must never render on this dedicated Matching Cloth page.

### Change discipline
Before coding Matching Cloth, read `REAL_FACTORY_PROJECT_MEMORY.md` and this rule book. Reuse approved mappings and RPCs first. Change only the minimum required destination UI/JS and do not touch unrelated modules.


## Packing — approved actual-leftover rule (V9365)

Source of truth: user-entered box capacity -> equal size split -> colour split -> same-size colour shortage adjustment -> actual leftover.

- Build only the full Fresh/ASST boxes that every active size can supply. Within each size, use maximum distinct colours first, then duplicate the colour with the highest remaining stock.
- Fresh remains the balanced one-per-colour-size repeat; ASST remains a full adjusted balanced box.
- When another balanced box cannot be formed, all remaining colour-size stock is leftover. Do not substitute another size to force an ASST box and do not throw a shortage error for valid leftover.
- Apply the half-capacity rule to that actual leftover, never merely `total % capacity`:
  - Positive leftover <= half capacity: merge with the previous full box and mark the resulting box MIX.
  - Leftover > half capacity: separate MIX with its complete leftover composition, even if that quantity equals/exceeds one capacity.
  - No previous full box: retain the leftover as its own MIX.
  - Zero leftover: no MIX.
- Preserve every source colour-size quantity exactly; box numbering starts at 1 for each lot.
- Fresh count and ASST/MIX composition views use backend marks. Never infer MIX from `qty > 18`.
- Example: capacity 12, L24/XL18/XXL18 -> four ASST boxes of L4/XL4/XXL4 plus one MIX of L8/XL2/XXL2 = five boxes / 60 PCS.
- Backend implementation: `rr_fg_generate_pack_v787(text,jsonb,text,integer)`, version `LOCKED_CAPACITY_SIZE_COLOUR_ACTUAL_LEFTOVER_V9365`.
- Feasibility calculation: balanced-box count = minimum across sizes of floor(size stock / per-box size quota); actual leftover = total minus balanced-box count times capacity. Reserving the preceding box when leftover <= half produces the same merge without writing a partial failed box.
- Frontend: `real-finished-goods-v787.js` displays backend `pack_mark` (FRESH/ASST/MIX), with existing stock-type fallback for legacy unmarked records.
- Scope: no changes to photos, AI removal, approval, WhatsApp, submit, permissions, stock categories, despatch, or other departments. Existing plans are not automatically rewritten; normal authorized rerun applies the rule to an open lot.
