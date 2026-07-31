REDZED UPM V750 — STATE SYNC CLEANUP
====================================

PURPOSE
-------
Fix only the current frontend state/selection problem:
- Assigned/Running Colour stays selectable for Alter, Damage and Submit.
- Open Queue Colour remains for Assignment.
- Submitted Colour is disabled for normal Submit.
- Owner/Admin can act on an active Alter journey even when the Colour card is open in another relevant view.
- Selection survives frontend re-render.
- Existing CB/Art/Print/Frame mapping and all SQL/RPC signatures remain untouched.

INSTALL
-------
1. Upload this file to GitHub root:
   real-universal-production-v750-state-sync.js

2. Open real-universal-production-v729.html and add this ONE line immediately AFTER:
   <script src="real-universal-production-v729.js"></script>

   ADD:
   <script src="real-universal-production-v750-state-sync.js?v=750"></script>

3. Commit and wait for GitHub Pages deployment.
4. Open the same v729 URL.
5. Hard refresh with Ctrl + Shift + R.

NO SQL
------
No SQL is required for this patch.

EXPECTED TEST
-------------
A. STITCHING assigned/running:
   - C1...C6 checkboxes active.
   - Alter, Damage and Submit use selected running Colours.
   - Assign does not reassign them.

B. KR/other relevant view with active Alter journey:
   - Select that Colour.
   - Enter Remake Issue Qty.
   - Owner/Admin action reaches backend instead of frontend error:
     "Select at least one assigned Colour..."

C. Submit:
   - Only genuinely assigned/running Colours can be submitted.
   - An open/unassigned Colour is not bridged into Submit.

ROLLBACK
--------
Remove this line from HTML:
<script src="real-universal-production-v750-state-sync.js?v=750"></script>
