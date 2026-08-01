REDZED UPM V757 — FINAL APPROVED SPECIMEN

LOCKED DESIGN
=============

WINDOW 1 — PRODUCTION BOARD
---------------------------
Every Lot card shows a compact Colour summary:

C1 · L 24 · XL 28 · XXL 36
Karigar / Stitching · Shamim
ACTIVE · ALTER NONE

Active Alter example:
ALTER · L 1 PCS · Dhiraj · LM

WINDOW 2 — CHECK-IN
-------------------
One always-open detailed table:

Colour / Size (PCS)
Active Department
Status
Worker
Alter Journey
Actions

Every Colour has its own independent actions:
ASSIGN WORKER
ALTER FILL
DAMAGE
SUBMIT
REMAKE ISSUE
RECEIVE MASTER
DELIVER KARIGAR
RECEIVE KARIGAR

No visible checkboxes.
No legacy single-Colour card.
No global action row.
No Flow Debug.
No duplicate tables.

SIZE DATA
=========
V757 fetches size rows directly from:
rr_upm_cut_size_rows_v726

It no longer depends on opening Check-in before showing sizes on the first board.

INSTALL
=======
1. Upload:
   real-universal-production-v757-final-approved.js

2. Remove old V756 script line.

3. Final HTML:
   <script src="real-universal-production-v729.js?v=741-dynamic-random-1"></script>
   <script src="real-universal-production-v757-final-approved.js?v=757"></script>

4. Commit, wait for GitHub Pages deployment, then Ctrl + Shift + R.

CONSOLE
=======
V757_FINAL_APPROVED_SPECIMEN
