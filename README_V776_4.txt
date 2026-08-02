REDZED ROLE & PERMISSION V776.4 — ACCURACY FIX

BACKEND TARGET
==============
V776.3 Leadership & Compensation backend.

FIXED
=====
1. Leadership status:
   ACTIVE / DEACTIVATED

2. Department Head:
   Exactly one Managed Department.
   UI auto-keeps one checkbox and save validation enforces exactly one.

3. Production Manager:
   One or multiple Managed Departments.

4. OWNER-only Leadership:
   Owner sees and saves Leadership Assignment + Compensation.

5. ADMIN-safe Job/Skills:
   Admin sees Job/Skills only.
   Leadership sections are hidden.
   Leadership RPC is not called.
   No misleading Owner-only RPC failure after Skills save.

6. HTML integrity:
   Duplicate workerSkillsMessage and duplicate stale form footer removed.

7. Version/cache:
   window.REDZED_ROLE_PERMISSION_VERSION = 776.4.0
   script = real-role-permission-v776-4.js?v=77640

FILES
=====
real-role-permission-v776-4.html
real-role-permission-v776-4.js
VERIFY_V776_4.json

UPLOAD
======
Upload both HTML and JS with the exact filenames above.
Open real-role-permission-v776-4.html and use Ctrl + Shift + R.

EXPECTED CONSOLE
================
window.REDZED_ROLE_PERMISSION_VERSION
→ 776.4.0
