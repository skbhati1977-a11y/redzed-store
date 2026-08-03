REDZED V779.1 — UNIVERSAL MONTHLY PAYROLL CORE

INSTALL
=======
1. Run REDZED_V779_1_UNIVERSAL_MONTHLY_PAYROLL_CORE.sql
2. Run VERIFY_V779_1.sql
3. Run PREFLIGHT_V779_2_SETTLEMENT_CONSTRAINTS.sql

FINAL PAYROLL SUMMARY HEADS
===========================
Monthly Salary
Net Extra Work — Amount + D/H/M + Details button
Monthly Incentive
Claims / Recovery
Net Payable Salary

CALCULATION
===========
30-day salary basis
1 day = 600 minutes
Monthly base = 18,000 minutes

Monthly Salary Amount
= Contract Monthly Salary
- hidden minute-deduction amount

Net Payable Salary
= Monthly Salary Amount
+ Net Extra Work Amount
+ Monthly Incentive
- Claims / Recovery

SECURITY
========
Worker self-service RPC verifies linked_auth_user_id.
A worker can see only their own payroll/details.

IMPORTANT
=========
This phase does not write rr_worker_settlements_v777_2 or worker ledger.
Their CHECK constraint values must be verified first.
No constraint/status guessing is used.
