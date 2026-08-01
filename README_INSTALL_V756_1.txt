REDZED UPM V756.1 — SCOPE AND DUPLICATE FIX

EXACT CAUSE
-----------
1. V755.2 and V756 were both rendering Check-in matrices.
2. V756 used every .lot-card, including elements related to the open modal.
3. Short summary therefore appeared inside Check-in instead of the first window.
4. The first-window card itself was not reliably identified.

FIX
---
FIRST WINDOW:
- A card is treated as a board Lot card only if:
  - it is outside #traveller,
  - it is not a colour-card,
  - it contains a CHECK IN button.
- Short summary is inserted immediately before CHECK IN.

CHECK-IN:
- Removes/hides:
  .v7552-detail-panel
  .v755-checkin-matrix
  .v7552-short-matrix
  .v755-board-matrix
  any misplaced .v756-short-summary
- Only one V756 table remains.
- Legacy detailed Colour cards stay hidden until a row action needs them.

VISIBLE PROOF
-------------
A blue badge appears briefly:
V756.1 ACTIVE

INSTALL
-------
1. Replace GitHub file:
   real-universal-production-v756-independent-colour-actions.js

2. Change HTML line to:
   <script src="real-universal-production-v756-independent-colour-actions.js?v=7561"></script>

3. Keep V755.2 before it:
   <script src="real-universal-production-v755-final-merged.js?v=7552"></script>

4. Commit and Ctrl + Shift + R.

NO SQL REQUIRED
---------------
V755.3 RPC is already working.
