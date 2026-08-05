REDZED PCS Payroll V779.3.1 — Collaborative Lot View

Upload/replace these matching files in GitHub root:
1. real-pcs-rate-payroll-v779.html
2. real-pcs-rate-payroll-v779.js
3. real-table-freeze-v773.js

Main view:
- One summary row = Worker + Lot + Department
- All Colours and all bound Sizes are combined
- Assigned Cap, submitted quantities, payable PCS and amounts are totals
- One Group Actual Rate editor controls the complete Lot+Department rate
- Enter or SAVE/UPDATE GROUP + NEXT saves and moves to the next unresolved group

Separate evaluation:
- VIEW EVALUATION opens a separate raw Colour/Size table under the group
- Raw assignment IDs, quantities, rates, mapping and timestamps remain visible
- Payroll calculation still uses the raw underlying detail records

This is a web-view change only. No new SQL is required because V772.6 group-rate SQL is already installed.
