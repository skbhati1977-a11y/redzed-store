REDZED V776.7 — DUPLICATE WORKER GUARD

RULE
====
Same Primary Department me same normalized Worker Name dobara save nahi hoga.

These are treated as same:
Ahmed
AHMED
 Ahmed
Ahmed with repeated spaces

FRONTEND
========
Live warning appears before Save.
Suggested suffix:
Ahmed 2
Ahmed 3

BACKEND
=======
Trigger blocks duplicate INSERT and UPDATE even on repeated submit.

Existing old duplicate records are not deleted automatically.
VERIFY_V776_7.sql reports them for review.

INSTALL
=======
1. Run:
   REDZED_V776_7_DUPLICATE_WORKER_NAME_GUARD.sql

2. Run:
   VERIFY_V776_7.sql

3. Upload:
   real-role-permission-v776-7.html
   real-role-permission-v776-7.js

Expected:
window.REDZED_ROLE_PERMISSION_VERSION
→ 776.7.0
