REDZED V774 — DEPARTMENT WITNESS POLICY

RULE
====
Primary Witness:
Explicit Department Head.

Secondary Witness:
Random active Self-Login Worker from the same Department.

Random selection is saved. It does not change on page refresh.

CONFIGURATION
=============
Department Master
→ Witness Policy
→ Select Department Head
→ Save Head + Select Secondary

Worker Identity:
BASIC_PHONE / NO_PHONE
→ Department policy automatically applies Primary Head
→ Secondary is fallback when Primary is not eligible

NOT ALLOWED
===========
Any unrelated worker
Cross-department random witness
Physical Worker as own witness
Mobile-number auto match

INSTALL
=======
1. Run:
   REDZED_V774_DEPARTMENT_WITNESS_POLICY.sql

2. Upload:
   real-role-permission-v774.html
   real-role-permission-v774.js

3. Ctrl + Shift + R

Expected:
window.REDZED_ROLE_PERMISSION_VERSION
→ 774.0.0
