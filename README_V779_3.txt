REDZED V779.3 — PAYROLL UI + WORKER SELF-SERVICE

RUN ORDER
=========
1. REDZED_V779_3_PAYROLL_UI_SELF_SERVICE.sql
2. VERIFY_V779_3.sql
3. TEST_V779_3.sql only with a TEST payroll ID

WORKER SCREEN
=============
MONTHLY PAYROLL

Monthly Salary        ₹ Amount    [Details]
Net Extra Work        ₹ Amount    [Details]
                      D H M
Monthly Incentive     ₹ Amount    [Details]
Claims / Recovery     ₹ Amount    [Details]

NET PAYABLE SALARY    ₹ Amount

DETAIL DRAWERS
==============
Monthly Salary:
- 30-day basis
- 18,000 monthly minutes
- hidden deduction time and amount

Net Extra Work:
- amount
- D/H/M
- date-wise details

Monthly Incentive:
- approved incentive items

Claims / Recovery:
- claims and advances used in settlement

Payment:
- payment events/history

SECURITY
========
Worker identity is resolved by linked_auth_user_id.
Worker cannot query another worker's payroll.
Management roles use the existing payroll management guard.

DISPUTE
=======
Worker may raise a dispute only:
- for own payroll
- during review window
- while POSTED/UNDER_REVIEW

PDF / WHATSAPP
==============
This phase produces secure ready-to-render payloads.
Actual PDF rendering belongs to frontend/server rendering.
Actual WhatsApp sending will be connected in the WhatsApp module.
