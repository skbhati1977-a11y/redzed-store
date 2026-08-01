REDZED UPM V757.6 — SINGLE ASSIGN DEPARTMENT BIND FIX

EXACT ERROR
===========
Selected worker is not actively mapped to department OPEN_NEXT.

CAUSE
=====
The row correctly showed:
C3 → Print

But before the assignment RPC, the legacy hidden #dept context reverted to:
OPEN_NEXT

Therefore the backend checked the selected Print worker against OPEN_NEXT
and rejected the assignment.

FIX
===
For single Colour assignment only:

1. Force hidden department to the Colour's canonical department:
   C3 → PRINTING

2. Select only C3.

3. Bind the selected mapped worker to:
   - C3 hidden worker control
   - original bulkWorker engine context

4. If legacy APPLY WORKER rebuilds the cards:
   - force PRINTING again
   - re-find C3 card
   - reselect C3
   - rebind the worker

5. Then open the existing confirmation and assignment RPC.

6. Refresh the matrix only after YES is clicked.

NOT CHANGED
===========
- Bulk Assign
- First-window layout
- Check-in table layout
- Alter / Damage / Submit
- Size / PCS
- Journey logic
- Assignment RPC itself

INSTALL
=======
Replace:
real-universal-production-v757-final-approved.js

HTML:
<script src="real-universal-production-v757-final-approved.js?v=7576"></script>

Console:
V757_6_SINGLE_ASSIGN_DEPARTMENT_BIND_FIX
