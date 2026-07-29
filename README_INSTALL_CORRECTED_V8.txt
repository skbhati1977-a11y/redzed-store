REDZED UPM V8 — CORRECTED WEB PACKAGE
====================================

WHY THE OLD SCREEN WAS BROKEN
-----------------------------
The old assignment script created its modal dynamically while the V7 mount script
was moving all body nodes into the Production panel. This caused the assignment
form to appear in normal page flow with Lot No "—" and empty controls.

THIS PACKAGE FIXES
------------------
- Register Lot button and manual Register Lot modal removed from the HTML.
- Assignment modal is statically defined, closed by default and uses its own
  is-open display rule.
- Global assignment modal stays outside the mounted Production panel.
- Assign Work button is inserted inside each real Lot card, before Production Submit.
- Clicking Assign Work passes the real card canonical_lot_id and Lot No.
- Department → Single / Multiple / ALL colours → OK → Worker/Qty rows.
- Cutting mapped colour-size Qty appears horizontally.
- Qty auto-fills.
- Common Worker is selected once and copied to all selected rows.
- Already assigned Lot + Department + Colour is locked.
- Production Submit shows the assigned Worker Name + Worker ID.

UPLOAD / REPLACE THESE FILES
----------------------------
1. Replace:
   real-universal-production-v72040-mounted.html
2. Replace:
   redzed-upm-v7-final-mount.js
3. Upload:
   redzed-upm-work-assignment-v8-fixed.js

KEEP THESE EXISTING FILES
-------------------------
- real-universal-production-v72040.js
- redzed-alter-v5.js
- redzed-alter-v1.css
- config.js
- real-common.js
- real-cutting-master.html

SQL
---
The corrected web files expect the V8 SQL RPCs to already exist:
- rr_upm_worker_list_v8
- rr_upm_get_work_assign_context_v8
- rr_upm_assign_colours_v8

If the earlier V8 SQL was not run successfully, run:
REDZED_UPM_WORK_ASSIGNMENT_V8.sql

IMPORTANT SCRIPT ORDER
----------------------
The supplied complete HTML already contains the correct order:
1. real-universal-production-v72040.js
2. redzed-upm-v7-final-mount.js
3. redzed-upm-work-assignment-v8-fixed.js

Do not add the old:
redzed-upm-work-assignment-v8.js

CACHE CLEAN
-----------
After GitHub commit/deploy:
1. Open DevTools > Application > Clear site data, or use Ctrl+Shift+Delete.
2. Hard refresh Ctrl+Shift+R.
3. Console must show:
   REDZED UPM Work Assignment 8.1.0 loaded

QUICK TEST
----------
1. Department Production tab opens cleanly; no assignment form at page bottom.
2. Register Lot button is absent.
3. Every Lot card has:
   Assign Work | Production Submit | Alter / Remake / Damage
4. Click Assign Work on Lot 2SKB6.
5. Modal header must show "Assign Work — 2SKB6".
6. Choose Department.
7. Tap one/multiple/all unassigned colours and press OK.
8. Confirm horizontal Size PCS and auto Total.
9. Select Worker once; all rows copy the worker.
10. Save; reopen same Department: assigned colours must be locked.
