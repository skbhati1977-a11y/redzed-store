REDZED UPM V752.2 — FINAL RECEIVE PROGRESS

WHAT CHANGED
------------
The final Karigar receive field no longer shows a sticky "Max N" label.
It now shows only "PCS".

Example:
Total Alter Qty = 3
Receive 2 PCS:
Karigar se jama 2/3 PCS · Pending 1 PCS
This flashes for about 3 seconds and hides.

Receive remaining 1 PCS:
Complete · 3/3 PCS
This flashes and hides. The Alter journey closes and the active input disappears.

INSTALL
-------
Replace:
real-universal-production-v752-stage-auto-open.js

Change HTML cache version to:
<script src="real-universal-production-v752-stage-auto-open.js?v=7522"></script>

Then commit and Ctrl + Shift + R.

NO SQL REQUIRED
---------------
V751 Step 2 backend must remain installed.
