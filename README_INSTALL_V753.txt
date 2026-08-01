REDZED UPM V753 — ACTIVE DEPARTMENT LOCK

PURPOSE
-------
- Hide the manual Department selector from normal use.
- Show every Colour with its Active Department as a locked chip.
- Clicking a Colour chip automatically loads its active department.
- The Colour is automatically selected for the next action.
- Before the worker selector, show:
  Active Department · Locked
- Load workers directly from rr_upm_worker_list_v8_3(active department).
- If no worker is mapped, show a clear message instead of a blank dropdown.

FLOW
----
Submit confirmation selects Next Department.
Backend freezes that department for the Colour.
V753 shows the frozen department beside the Colour.
Only workers from that department are offered.

INSTALL
-------
1. Upload:
   real-universal-production-v753-active-department-lock.js

2. Add after V752:
   <script src="real-universal-production-v753-active-department-lock.js?v=753"></script>

Final order:
<script src="real-universal-production-v729.js?v=741-dynamic-random-1"></script>
<script src="real-universal-production-v750-state-sync.js?v=750"></script>
<script src="real-universal-production-v752-stage-auto-open.js?v=7522"></script>
<script src="real-universal-production-v753-active-department-lock.js?v=753"></script>

3. Commit and Ctrl + Shift + R.

IMPORTANT
---------
This patch does not change CB/Art/Print/Frame mapping or Alter quantities.
It uses the department already frozen by Submit/colour state.
