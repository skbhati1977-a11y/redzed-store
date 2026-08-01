REDZED UPM V756 — INDEPENDENT COLOUR ACTIONS

FINAL UI
========

FIRST WINDOW
------------
Short summary only:
C1 | Department | ACTIVE | Alter summary
C2 | Department | ACTIVE | Alter summary

CHECK-IN
--------
The complete Colour table is always open.

Columns:
Colour
Active Department
Status
Worker
Alter Journey
Actions

OPEN / ASSIGNED / RUNNING are retained internally.
User-facing status is ACTIVE.

NO VISIBLE CHECKBOXES
---------------------
- Colour checkboxes are hidden.
- Select All Open Colours is hidden.
- Global action button row is hidden.
- They remain internally available only as the existing action engine.

INDEPENDENT ROW ACTIONS
-----------------------
Each Colour row shows only valid actions:
- ASSIGN WORKER
- ALTER FILL
- DAMAGE
- SUBMIT
- REMAKE ISSUE · CM
- RECEIVE MASTER · LM
- DELIVER KARIGAR · LM
- RECEIVE KARIGAR · LM

When an action is clicked:
- that Colour row remains highlighted,
- all other rows become black/dim,
- the correct hidden Colour card is selected internally,
- the existing backend action is used.

BULK ASSIGN
-----------
Bulk Assign appears above the table.

It assigns all eligible OPEN Colours locked to the selected department
to one selected worker.

Colours locked to other departments are not silently moved.

INSTALL
=======
1. V754.4 and V755.3 SQL must already be installed.

2. Upload:
   real-universal-production-v756-independent-colour-actions.js

3. Add after V755.2:
   <script src="real-universal-production-v756-independent-colour-actions.js?v=756"></script>

4. Keep the existing V755.2 line:
   <script src="real-universal-production-v755-final-merged.js?v=7552"></script>

5. Commit and press Ctrl + Shift + R.
