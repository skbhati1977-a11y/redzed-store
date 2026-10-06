# TEST71 Ready-made receipt reconciliation

Scope: Readymade OPEN creation only, using existing TEST purchase, stock, Accounts and report engines.

- Party Bill Quantity and Received Quantity are separate whole-PCS fields for each garment lot.
- Live preview uses purchase rate, original bill value, Short/Excess PCS, Debit/Credit Note value and net supplier payable.
- Save Draft preserves both quantities without stock or financial postings. Reopening recalculates the preview.
- Save & Confirm posts original billed value, received stock and purchase-linked notes in one database transaction.
- SHORT: supplier DR / Readymade Purchase CR. EXCESS: Readymade Purchase DR / supplier CR.
- Each note retains supplier, bill number/date, purchase-line ID, rate, direction, PCS and Accounts voucher link.
- Net supplier liability and net purchases equal received quantity times purchase rate. Receipts remain accessible from WORKING to purchase roles.
- Existing purchase-cost stock, salary/overhead allocation and subsequent Purchase Return continue to use received PCS.
- No additional stock movement is posted for a receipt note: the first inward movement already contains actual received PCS.
- Confirmation aborts on missing stock, note links, supplier-value mismatch or missing P&L/Balance Sheet mapping. Retry uses the existing purchase lock and source guards.
- Historical posted purchases remain unchanged; legacy payloads that only supply qty are treated as bill=received.
- Real Chat script cache version is updated only for this file. No unrelated layout changes.

Validation:

- 17 focused jsdom tests pass, including the existing Real Chat shell and new receipt preview, validation, draft reopening, payload and receipt access cases.
- Live transactional rollback test passes 540→530, 540→550 and 540→540 at ₹100/PCS; original purchase, notes, supplier payable, received stock, P&L, Balance Sheet and Trial Balance deltas, duplicate confirmation, Purchase Return, OPEN edit and fractional-input rollback.
- Sales financial receipt access is denied; anonymous execution is revoked. Fixtures left no audit purchase headers.
- Current TEST Trial Balance debit-credit difference is ₹0.00.
- Security advisors reviewed: new authenticated SECURITY DEFINER receipt RPC notices are intentional and guarded by the existing authenticated purchase-operator role check and TEST restriction.

Database migrations applied: 20261006110419 (receipt reconciliation), 20261006110547 (record scope), 20261006110602 (stock alias). The script contains the final corrected definitions.

Limits: no signed-in mobile visual check was performed. The older readymade rollback fixture stops at its Market thumbnail assertion under the current market-readiness gate; it is not counted as a passing regression suite. REAL-mode activation, main and production deployment were not performed.
