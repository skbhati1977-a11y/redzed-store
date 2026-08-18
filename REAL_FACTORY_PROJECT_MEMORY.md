# REAL FACTORY Project Memory

## Matching Cloth Master — verified behavior (2026-08-18)

This note records the verified, already-existing Matching Cloth behavior so future work should consult this file before re-researching or changing code.

### Destination files for the dedicated Matching Cloth child master
- Final destination HTML: `real-matching-cloth-master.html`
- Final destination JS: `real-matching-cloth-master-v9235.js`
- Slice Menu link source/wiring file: `real-global-slice-menu-v9190.js`
- Product Master -> Matching Cloth child menu must point to `real-matching-cloth-master.html`.
- Future Matching Cloth UI/mapping work should normally be implemented only in the destination HTML/JS above unless an existing shared backend rule genuinely requires a different file.

### Approved behavior source files / historical references
- Primary searchable Fabric + Vendor UI source: `real-mc-searchable-mapping-v9136.js`
  - Historical commit: `4771689a97c80c030fda00f2717fdf8681aa2dfd`
  - Fabric RPC: `rr_get_mc1_fabric_options_v9134`
  - Vendor RPC: `rr_get_mc_vendor_options_v9135`
- Earlier mapped dropdown source: `real-mc-mapped-dropdowns-v9135.js`
  - Historical commit: `abf4cbafac2d20f9e515401317bac6243662af5c`
  - Confirms vendor option -> `supplier_ledger_id` mapping.
- Existing Product Master MC entry/save behavior source: `real-product-master-v720.js`
  - Reuse its MC purchase field behavior and `rr_post_mc_fabric_purchase_v3` posting contract; do not invent a parallel purchase flow.
- Accounts/backend source: `REAL_FACTORY_V9076_MC_PURCHASE_ACCOUNT_MAPPING.sql`
  - Purchase RPC: `rr_post_mc_fabric_purchase_v3`
  - Accounts RPC: `rr_get_mc1_purchase_account_v9076()`
  - Purchase account name: `Matching Cloth Purchase`

### Verified Fabric mapping
- Existing Matching Fabric options come from RPC `rr_get_mc1_fabric_options_v9134`.
- UI behavior was implemented in approved mapping layers v9135/v9136.
- Fabric selection is tied to the real MC1 fabric record/id, not just free text.
- Existing option labels can include Fabric Name + Available Qty + Avg Rate.
- New fabric must reuse the existing MC1 fabric create/upsert flow; do not create a parallel fabric store.

### Verified Vendor mapping
- Existing Vendor options come from RPC `rr_get_mc_vendor_options_v9135`.
- Approved v9135 mapping includes `supplier_ledger_id` on vendor options.
- Approved v9136 made Vendor selection searchable and can show purchase history context such as bill count, total qty and total value.
- Therefore Vendor mapping already exists and must be reused. Do not replace it with an unrelated free-text-only system.

### Verified Purchase / Accounts mapping
- Purchase posting uses `rr_post_mc_fabric_purchase_v3`.
- Purchase posts to the exact MC1 fabric account, updates fabric qty/value/avg rate, updates consolidated MC1 qty/value/avg rate, creates `PURCHASE_IN` ledger entry, and stores vendor/bill details.
- Accounts exposure uses `rr_get_mc1_purchase_account_v9076()` and purchase account name `Matching Cloth Purchase`.

### UI direction agreed with user
- Dedicated Matching Cloth child page remains: Header -> Entry Form -> Available Matching Cloth Stock.
- CB / Art Due / Art Decide cards must not appear on this page.
- Fabric and Vendor selection must reuse the approved mapped/searchable behavior above.
- `+ Add New Fabric` and `+ Add New Vendor` should be separate red buttons outside the selection fields.
- Do not change unrelated modules, database schema, or existing approved save/account behavior unless explicitly required.

### Implementation rule
Before changing Matching Cloth code, read this memory note first. Source behavior from the approved files/RPCs listed above, then apply only the required UI/integration changes to the destination files. Do not re-create mappings from scratch when these verified sources already exist.
