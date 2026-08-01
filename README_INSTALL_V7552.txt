REDZED UPM V755.2 — HARD BOOT

WHY NOTHING CHANGED
-------------------
The page was still showing the original board and original single-colour form.
That proves the V755 script did not execute.

V755.2 uses the exact current DOM:
- .lot-card[data-lot]
- .lot-no
- #traveller
- #colours
- #dept

VISIBLE PROOF
-------------
After successful load a green badge appears:
V755.2 ACTIVE

If RPC fails, a red badge shows the exact error.

EXPECTED FIRST WINDOW
---------------------
One short row per Colour:
C1 | Department | Status | Alter
...
No combined Stitching/Submited-history line.

EXPECTED CHECK-IN
-----------------
Full table for every Colour:
Colour | Active Department | Status | Worker | Alter Journey | Open

INSTALL
-------
1. SQL V755 Final must already be installed.
2. Upload/replace:
   real-universal-production-v755-final-merged.js
3. Before </body>, keep exactly:
   <script src="real-universal-production-v755-final-merged.js?v=7552"></script>
4. Commit.
5. Ctrl + Shift + R.
6. Confirm green badge: V755.2 ACTIVE.
