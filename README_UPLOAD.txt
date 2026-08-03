REDZED V779.6 — MONTHLY PAYROLL FINAL TEST UI

UPLOAD BOTH FILES TO GITHUB
===========================
1. real-monthly-payroll-v779.html
2. real-monthly-payroll-v779.js

NO SQL RUN REQUIRED
===================
The backend board already returns:
- Eligible workers: 3
- Generated workers: 3
- Legacy generated: 3
- Net payable: ₹46,000

THIS UI FIX
===========
- TEST mode locked
- Owner/management login opens Management Board by default
- Uses rr_get_payroll_management_board_v779_5
- Normalizes summary/workers JSON
- Shows all salaried payroll rows returned by backend
- Shows complete summary totals
- Details button switches to visible payroll detail screen
- Stronger RPC error messages
- HTML and JS versions synchronized

AFTER UPLOAD
============
1. Commit both files
2. Wait for GitHub Pages deployment
3. Press Ctrl + Shift + R
4. Open real-monthly-payroll-v779.html

EXPECTED
========
Eligible Workers: 3
Generated: 3
Legacy Generated: 3
Monthly Salary: ₹46,000
Ali, Baldev and CHOTU rows visible
