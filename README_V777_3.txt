REDZED ROLE & PERMISSION V777.3 — PAYROLL PROFILE UI

DEPENDENCIES
============
V776.1 frontend/backend
V777.2 Final Consolidated Foundation

INSTALL ORDER
=============
1. Run:
   REDZED_V777_3_PAYROLL_PROFILE_UI_BRIDGE.sql

2. Run:
   VERIFY_V777_3_UI_BRIDGE.sql

3. Upload:
   real-role-permission-v777-3.html
   real-role-permission-v777-3.js

4. Open real-role-permission-v777-3.html
5. Ctrl + Shift + R

Expected:
window.REDZED_ROLE_PERMISSION_VERSION
→ 777.3.0

WORKER FORM
===========
1. Normal Job & Skills
2. Leadership Assignment
3. Leadership Compensation
4. Worker Payroll Profile

PAYROLL CATEGORIES
==================
PIECE_RATE:
- attendance excluded
- UPM job presence
- weekly advance
- 15-day settlement
- advance rule remains 40% earned or ₹2000, whichever is higher

SALARIED:
- monthly salary
- active shift
- late deduction switch
- overtime switch
- holiday extra switch
- grace-used-vs-OT switch
- configurable advance percent/fixed limit
- effective dates
- TEST / REAL data modes

This UI does not calculate salary and does not post Worker Ledger entries.
