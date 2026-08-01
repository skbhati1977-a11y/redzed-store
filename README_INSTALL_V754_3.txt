REDZED UPM V754.3 — FINAL CANONICAL QC SOURCE FIX

CONFIRMED SOURCES
-----------------
rr_departments_v1 : qc / QC / true
rr_upm_departments: QC / QC / true

FIX
---
- Removed rr_departments from QC validation because it has no department_code column.
- QC validation now checks only:
  1. rr_departments_v1
  2. rr_upm_departments
- Case-insensitive code matching is used.
- No guessed department is created.

ALL V754.2 FEATURES REMAIN INCLUDED
-----------------------------------
- CHECKING/CHECK/QA/QUALITY CHECK normalize to QC.
- Colour identity locked to C1/C2/C3...
- Submit requires Next Department.
- Colour department lock is created immediately.
- Worker can be assigned later.
- First-window live status includes assigned, running, submitted and waiting-worker states.
- Manual dropdown cannot falsely lock an open Colour.

INSTALL
-------
1. Run:
   REDZED_UPM_V754_FINAL_MERGED.sql

2. Replace GitHub file:
   real-universal-production-v754-qc-colour-open-status.js

3. HTML:
   <script src="real-universal-production-v754-qc-colour-open-status.js?v=7543"></script>

4. Commit and press Ctrl + Shift + R.
