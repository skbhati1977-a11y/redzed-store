REDZED UPM V763 — BULK SUBMIT

WHAT IS ADDED
=============
A new BULK SUBMIT section beside BULK ASSIGN.

FLOW
====
Select active Department
→ System lists/counts all running Colours owned by that Department
→ SUBMIT ALL RUNNING
→ One confirmation shows every Colour, Sizes and Worker
→ One rate gate for Lot + Department
→ One rr_upm_submit_colours_v741 transaction
→ All Colours move to RANDOM OPEN QUEUE

IMPORTANT
=========
Bulk Submit never mixes Departments.

Example:
PRINTING selected
→ only currently running PRINTING Colours submit

OVERLOCK selected
→ only currently running OVERLOCK Colours submit

RATE RULE
=========
If this is the first Submit for that Lot + Department and Actual Rate is
missing:

Bulk Submit hold
→ Costing popup opens
→ Actual Rate save
→ already-confirmed Bulk Submit automatically continues

SAFETY
======
- Only rows with active assignment_id are included.
- OPEN queue Colours are not submitted.
- Completed Colours are not resubmitted.
- Single Colour Submit remains unchanged.
- Bulk Assign remains unchanged.
- Submit result always goes to Random Open Queue.
- No Next Department is preselected.

INSTALL
=======
1. No SQL required.

2. Upload:
   real-universal-production-v763-bulk-submit.js

3. Replace V762 script line with:
   <script src="real-universal-production-v763-bulk-submit.js?v=7631"></script>

4. Keep base:
   <script src="real-universal-production-v729.js?v=741-dynamic-random-1"></script>

5. Do not load V762 and V763 together.

6. Commit → Pages deployment → Ctrl + Shift + R.

EXPECTED CONSOLE
================
V763_BULK_SUBMIT_UI
