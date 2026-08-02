REDZED ROLE & PERMISSION V774.3 — LOGIN SELECTOR FIX

NO SQL REQUIRED
===============
This is a frontend-only fix.

FIXED RULE
==========
SMARTPHONE Login dropdown now shows only:

- Active Login Users not linked to any other Worker
- Current Worker's own existing linked Login

It hides:

- Owner Login already linked to Owner Worker
- Any Login linked to another Worker
- Inactive/blocked Login Users

EMPTY STATE
===========
When no separate Login is available:

No unlinked active Login User available · Create User first

Ahmed cannot be linked to Sudesh Bhati's Owner Login.

INSTALL
=======
Upload:

real-role-permission-v774-3.html
real-role-permission-v774-3.js

Open:
real-role-permission-v774-3.html

Ctrl + Shift + R

Expected:
window.REDZED_ROLE_PERMISSION_VERSION
→ 774.3.0

No database SQL should be run for this patch.
