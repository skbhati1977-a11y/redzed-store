REDZED UPM V752 — ALTER TRANSPORT STAGE AUTO OPEN

CAUSE
-----
Backend correctly moved C3/L to CM_REMAKE_READY (1 PCS).
Frontend enabled journey fields only when the Colour had an active department assignment.
After Submit, C3 is in Random Open Queue, so the next stage input stayed disabled.

FIX
---
Stage-driven UI:
CM_REMAKE_READY        -> Receive Master · LM opens
LM_DELIVERY_PENDING    -> Deliver Karigar · LM opens
KARIGAR_REMAKE_PENDING -> Receive Karigar · LM opens

After each successful stage, the normal page context reloads and the next stage input opens.

INSTALL
-------
1. Upload to GitHub root:
   real-universal-production-v752-stage-auto-open.js

2. In real-universal-production-v729.html add AFTER V750:
   <script src="real-universal-production-v752-stage-auto-open.js?v=752"></script>

Final order:
<script src="real-universal-production-v729.js?v=741-dynamic-random-1"></script>
<script src="real-universal-production-v750-state-sync.js?v=750"></script>
<script src="real-universal-production-v752-stage-auto-open.js?v=752"></script>

3. Commit/deploy.
4. Ctrl + Shift + R.
5. Open Lot and press Flow Debug once.
6. C3/L will show Receive Master input with Max 1.

NO SQL REQUIRED
---------------
Step 2 backend SQL must already be installed.
This patch changes no mapping, quantities or database schema.
