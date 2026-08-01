REDZED UPM V760.2 — COSTING FORM CLEANUP

CHANGES
=======
1. OPEN_NEXT / Open for Next Process removed from:
   - Costing form
   - Standard fallback
   - Actual Rate list
   - Process-cost total

2. Fixed Department order:
   Cutting
   Sticker
   Print
   Karigar / Stitching
   Overlock
   Folding
   Kaaj / Button
   Tanki / Tack
   QC
   Thread Cut
   Press
   Packing
   Other

3. Per-row SAVE RATE buttons removed.

4. One SAVE COSTING button saves all changed Actual Rates.

5. Typed Actual Rate immediately shows:
   UNSAVED ACTUAL

6. After successful save:
   UPDATED

7. Top Live Cost Summary added.

INSTALL
=======
1. Run:
   REDZED_UPM_V760_2_COSTING_FORM_CLEANUP.sql

2. Upload:
   real-universal-production-v7602-costing.js

3. Replace old V760 script line with:
   <script src="real-universal-production-v7602-costing.js?v=7602"></script>

4. Do not load V760 and V760.2 together.

5. Ctrl + Shift + R.

EXPECTED SQL
============
ok = true
version = V760_2_COSTING_FORM_CLEANUP

EXPECTED CONSOLE
================
V760_2_COSTING_FORM_CLEANUP_UI
