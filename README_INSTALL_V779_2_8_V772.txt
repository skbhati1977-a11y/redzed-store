REDZED V779.2.8 + UPM V772
INLINE ASSIGNMENT RATE · SUBMITTED WORK REPORT · ZERO-RATE SUBMIT LOCK
====================================================================

FINAL BEHAVIOUR
1. PCS Payroll > Lot / PCS Details:
   - Missing Assignment Actual Rate can be filled in the same row.
   - Authorized Owner/Admin/Manager can correct existing Assignment Actual Rate.
   - Department Head can fill missing rate only for own department.
   - Save automatically recalculates the selected Piece Payroll month.
   - Approved/Paid payable assignment rate cannot be changed until Owner Reopen.

2. Universal Production > SUBMITTED WORK:
   - Department and Worker searchable filters.
   - Lot / Colour / Size submitted PCS details.
   - Exact Assignment Actual Rate, submitted amount and missing-rate status.
   - Authorized inline rate fill/edit and full row View.

3. HARD DATABASE LOCK:
   - rr_upm_submit_colours_v741 blocks Submit when Assignment Actual Rate is missing/zero.
   - rr_upm_dynamic_submit_history_v741 has a BEFORE INSERT backstop trigger.
   - Legacy rr_upm_submit_ledger_v2 is also guarded whenever work_assignment_id exists.
   - No Standard Rate or Department Rate fallback is used for Piece Salary.

4. Existing rules unchanged:
   - V778 Monthly Salary remains separate.
   - V779 reads V741 Dynamic Submit quantity.
   - Assignment size cap and prior-period duplicate-pay protection remain.
   - Zero Payable PCS = Zero Monthly Flat Incentive remains.

INSTALL ORDER
A) SUPABASE SQL EDITOR
Run complete file:
01_SUPABASE_RUN_FIRST/RUN_NOW_V779_2_8_RATE_EDITOR_SUBMITTED_WORK_SUBMIT_LOCK.sql

Expected verification:
v779_2_8_install_result = PASS
inline_rate_editor_ready = true
submitted_work_report_ready = true
zero_rate_submit_block_ready = true

B) GITHUB ROOT — upload/replace
Replace:
- real-pcs-rate-payroll-v779.html
- real-pcs-rate-payroll-v779.js

Upload new:
- real-upm-submitted-work-v772.html
- real-upm-submitted-work-v772.js
- real-universal-production-v772-submitted-work-link.js

C) CURRENT UPM HTML
Open:
03_ADD_TO_CURRENT_UPM_HTML/HTML_ADD_THIS_SCRIPT_V772.txt
Add the one script line to your active real-universal-production-v729.html / V771 HTML.

D) AFTER GITHUB COMMIT
1. Open Piece Payroll and press Ctrl + Shift + R.
2. Open Universal Production and press Ctrl + Shift + R.
3. UPM module bar must show SUBMITTED WORK.

SAFE TEST
1. Open Piece Payroll > TEST > August 2026 > Calculate/Recalculate.
2. Open Lot / PCS Details.
3. Fill one MISSING_ASSIGNMENT_ACTUAL row with the correct rate.
4. Row must automatically recalculate and show ASSIGNMENT_ACTUAL_ONLY.
5. Open UPM > SUBMITTED WORK and filter by Department + Worker.
6. Try submitting a TEST assignment with zero rate: Submit must be blocked with a clear Actual Rate required message.
7. Fill rate, submit, then recalculate V779.
8. Do not Approve & Lock until Missing Rate and Missing Cap are both zero.

IMPORTANT
- Historical submitted rows with missing rates are not silently assigned a fallback rate.
- Correct rates must be entered manually by an authorized user and are audit logged.
- Do not update worker categories or submitted quantities for this fix.
