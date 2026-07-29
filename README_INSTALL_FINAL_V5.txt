REDZED UNIVERSAL PRODUCTION — FINAL V5
======================================

FINAL ALTER RULES
-----------------
1. Lot No is highlighted in Register Alter.
2. Colour is dropdown only, from that Lot's cutting mapping.
3. Size is dropdown only, filtered by selected Lot + Colour.
4. Size free-text is removed.
5. Alter Qty is manual, but cannot exceed:
   Cut Qty - Already Registered Alter Qty.
6. Duplicate Colour + Size rows are totalled before validation.
7. The same validation runs in Supabase SQL, so frontend/API bypass is blocked.
8. Fault image is mandatory only at Alter registration.
9. Repair Submit and Remake Complete do not require an image.
10. Add Next Colour / Size creates another mapped row.

FILES TO UPLOAD
---------------
- real-universal-production-v72040.html
- real-universal-production-v72040.js
- redzed-alter-v4.js
- redzed-alter-v1.css

SQL
---
Run:
  REDZED_UPM_FINAL_CONSOLIDATED_V5.sql

This V5 file contains the prior V4 consolidation plus the V5 mapping and quantity-limit patch.
The earlier base Alter V1 and Universal Production V2 schema must already exist, as with V4.

CUT COLOUR-SIZE MAPPING
-----------------------
Alter registration stays blocked until the Lot has a saved cutting map.
Example mapping JSON:
[
  {"colour_code":"BLACK","colour_name":"Black","size_code":"M","cut_qty":50},
  {"colour_code":"BLACK","colour_name":"Black","size_code":"L","cut_qty":50},
  {"colour_code":"RED","colour_name":"Red","size_code":"M","cut_qty":30}
]

For a newly registered manual Lot, paste this into:
  Cut Colour-Size Mapping JSON

For an existing Lot, call this RPC from SQL/API:
  rr_upm_save_cut_size_map_v5(canonical_lot_id, lot_no, rows_json)

IMPORTANT
---------
- Do not upload the old Owner/Admin Fix separately.
- HTML now loads redzed-alter-v4.js.
- Remove/ignore redzed-alter-v3.js.
- After GitHub Pages deploy, hard refresh with Ctrl + Shift + R.

QUICK TEST
----------
1. Open a Lot with cutting mapping.
2. Open Alter / Remake / Damage > Register Alter.
3. Select Colour.
4. Confirm only cut Sizes appear.
5. Select Size and check Cut / Already Alter / Maximum New Alter.
6. Enter Qty above maximum: UI must cap/block it.
7. Submit a valid Qty with fault camera image.
8. Try direct RPC above limit: SQL must reject it.
