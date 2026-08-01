REDZED UPM V762 — CANONICAL DEPARTMENT FOUNDATION

CANONICAL MASTER
================
rr_departments_v1 is now the assignment Department source.

rr_upm_departments remains a compatibility/read layer and is synchronized from
the canonical master.

UNIVERSAL ALIASES
=================
OV / OVERLOCK              → OVERLOCK
FLD / FOLDING              → FOLDING
PRINT / PRINTER / PRINTING → PRINTING
KR / KARIGAR / STITCHING   → STITCHING
TH CUT / THREAD CUT        → THREAD_CUT
CHECKING / QC              → QC
KAJ / KAAJ                 → KAAJ
BTN / BUTTON               → BUTTON

WORKER RULE
===========
Selected canonical Department:
→ Primary Department workers
→ Additional Skill mapped workers
→ Active workers only

Examples:
OVERLOCK → ahmed
FOLDING → khan
STICKER / PRINTING → madan where mapped
QC / THREAD_CUT → madam1 where mapped

ASSIGNMENT LIST
===============
Included:
- active PRODUCTION processes
- active FABRICATION child processes
- worker + colour assignment enabled

Excluded:
- Admin
- Accounts
- Cutting
- Fabrication parent
- Sales
- Dispatch
- Distributor
- OPEN_NEXT

HISTORY SAFETY
==============
Existing production history is not bulk rewritten.
Legacy codes remain readable through canonical resolver.
All new assignments are written with canonical Department codes.

INSTALL
=======
1. Run:
   REDZED_UPM_V762_CANONICAL_DEPARTMENT_FOUNDATION.sql

2. Expected:
   ok = true
   version = V762_CANONICAL_DEPARTMENT_FOUNDATION

3. Upload:
   real-universal-production-v762-departments.js

4. HTML:
   <script src="real-universal-production-v729.js?v=741-dynamic-random-1"></script>
   <script src="real-universal-production-v762-departments.js?v=7621"></script>

5. Remove the V760.4.3 line. Do not load both.

6. Commit → Pages deployment → Ctrl + Shift + R.

EXPECTED CONSOLE
================
V762_CANONICAL_DEPARTMENT_FOUNDATION_UI
