REDZED UPM V720.51 — VERIFIED CUTTING MAP FIX

1. Keep V720.50 Work Assignment SQL already installed.
2. Run REDZED_UPM_WORK_ASSIGNMENT_V8_1_CUTTING_MAP_FIX.sql.
3. Upload/replace:
   - real-universal-production-v72051.html
   - redzed-upm-work-assignment-v8.js
4. Keep existing files in the same GitHub folder:
   config.js
   real-common.js
   real-universal-production-v72040.js
   redzed-alter-v4.js
   redzed-upm-smart-packing-v1.js
5. Open:
   https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v72051.html
6. Hard refresh Ctrl+F5.

VERIFIED DATA SOURCE
rr_upm_lot_board_v1.lot_no
 -> rr_cutting_lots_v3.lot_no
 -> rr_cutting_breakup_v3.cutting_lot_id
 -> rr_cb_colours.id

Assign Work shows actual Cutting colour/size quantities and backend revalidates the same rows before save.
No duplicate mapping table is used.
