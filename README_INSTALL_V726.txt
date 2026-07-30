REDZED UPM V726 — FULLY MAPPED INSTALL

FILES TO UPLOAD TO THE GITHUB REPOSITORY ROOT
1. real-universal-production-v726.html
2. real-universal-production-v726.js
3. redzed-alter-v6.js (same existing module; included only for deployment convenience)
4. redzed-alter-v1.css (same existing stylesheet)
5. redzed-upm-smart-packing-v1.js (same existing packing algorithm; unchanged)

SQL
Run REDZED_UPM_V726_FULLY_MAPPED.sql in Supabase SQL Editor after the existing migrations.

REQUIRED EXISTING FILES
- config.js
- real-common.js
- real-cutting-master.html

REQUIRED EXISTING DATABASE ENGINES
- rr_upm_get_lot_visuals_v6
- rr_upm_worker_list_v8_3
- rr_upm_assign_colours_v8_3
- rr_upm_set_department_rate_v2
- rr_upm_submit_ready_v2
- Alter/Remake/Damage V1 tables/functions
- Smart Packing V1 functions/views

PAGE
https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v726.html?build=726

IMPORTANT BEHAVIOUR
- Colour/Size/Cut PCS first reads the unchanged Cutting module tables and planned_qty.
- rr_upm_lot_cut_size_map_v5 is only a fallback.
- Worker dropdown reads rr_upm_worker_list_v8_3.
- Assignment saves through rr_upm_assign_colours_v8_3 with Lot No, full colour quantity and Actual Rate.
- Production submits through rr_upm_submit_ready_v2; the server calculates ready quantity.
- Alter/Remake/Damage uses the existing redzed-alter-v6 module mounted inside the same traveller.
- Cutting module is mounted unchanged in an iframe at dashboard top.
- Smart Packing module file is unchanged and mounted at dashboard top.
- SQL preflight exposes any missing backend dependency clearly instead of silently showing empty controls.
