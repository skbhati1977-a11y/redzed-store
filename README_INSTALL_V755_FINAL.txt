REDZED UPM V755 — FINAL MERGED

FINAL UI STRUCTURE
==================

1ST WINDOW — SHORT SUMMARY CARD
-------------------------------
Each Colour appears as one compact row:

C1 | OV | OPEN | Alter NONE
C2 | Karigar / Stitching | RUNNING | Alter NONE
C3 | QC | OPEN | REMAKE READY · 1 PCS · badsha CM

Only current ownership is shown.
Old submitted history is not mixed into current department ownership.

CHECK-IN WINDOW — DETAILED TABLE
--------------------------------
Every Colour appears in a full table:

Colour
Active Department
Status
Worker
Alter Journey
Open

Click OPEN:
- correct locked department loads automatically,
- that Colour is selected,
- normal Assign / Alter / Submit actions continue.

ALTER JOURNEY
-------------
The same live Alter Journey data appears in both windows:
- stage
- open Qty
- mapped responsible person
- short role
- size-wise pending details

When the journey closes:
ALTER JOURNEY = NONE

HARD OWNERSHIP PRIORITY
-----------------------
1. Active assignment
2. Active Colour department lock
3. Last Submit route
4. Valid Colour state
5. Legacy exception only

ALIASES
-------
KR / KAJ / KARIGAR / STITCH -> STITCHING
Display: Karigar / Stitching

CHECKING / QA / QUALITY CHECK -> QC

INSTALL
=======
1. V754.4 must already be installed.

2. Run:
   REDZED_UPM_V755_FINAL_MERGED.sql

3. Upload:
   real-universal-production-v755-final-merged.js

4. REMOVE old separate V755/V755.1 script lines if present:
   real-universal-production-v755-hard-colour-matrix.js
   real-universal-production-v7551-alter-journey-matrix.js

5. Add only:
   <script src="real-universal-production-v755-final-merged.js?v=755f"></script>

6. Commit and press Ctrl + Shift + R.
