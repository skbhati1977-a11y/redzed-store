# REAL FACTORY — PI Rule Book

## PI Permanent Serial Cancellation — LOCKED RULE (2026-08-30)

### Core invariant
Once a physical S.No. is committed, that serial belongs permanently to that PI position. Cancellation removes the item's commercial effect, not its serial position or history.

### Locked rules
1. PI S.No. is immutable after physical/committed allocation. A cancelled middle serial must never cause following serials to renumber and must never be reused for another item.
2. DELETE and CANCEL are different operations. DELETE is only for a wrong/extra row before serial commitment. An occupied physical serial uses CANCEL ITEM.
3. CANCEL must show a warning containing S.No., Lot No. and original Qty, and must require a non-empty cancellation reason entered by the authorized Admin/Sales user.
4. Confirmation must preserve the row at the same S.No. and visually mark the cancelled commercial fields as `XXXXX` / `CANCELLED`. Original lot/item details remain retained internally for audit.
5. A cancelled row has zero commercial effect: it contributes zero billable Qty, zero Amount, zero box/commercial totals, zero RRQ effect and is excluded from active item totals.
6. General Remarks must not be overwritten. The system appends an automatic cancellation entry in this format: `S.No. 13 | Lot No. 2609 | 36 PCS | CANCELLED — Due to: <reason>`.
7. Every cancel/restore state change must preserve an append-only audit record containing PI, S.No., original Lot No., original Qty, reason, snapshot, acting user and timestamp.
8. Cancellation must be persisted together with PI save so a failed save cannot leave only a visual cancellation. Canonical PI commercial lines contain active items only; cancelled serial positions are retained separately and reconstructed on reopen.
9. Reopening/reloading the PI must reproduce the same serial sequence including cancelled rows at their original physical S.No.; following S.Nos must remain unchanged.
10. Draft PI may provide RESTORE to authorized users. Restore uses the same original S.No., must re-enter the normal stock validation path, and must not erase the prior cancellation audit/history.
11. CPI_FINAL is locked: ordinary PI cancel/restore is blocked after final CPI. Post-final corrections belong to the authorized correction/return workflow.
12. Customer-facing PI/PDF/WhatsApp/Real Chat outputs must use the same serial sequence. A cancelled S.No. remains visible as CANCELLED/XXXXX while its commercial quantity and amount are excluded from totals.
13. Multiple cancellations append independently and chronologically; existing manual General Remarks remain intact.
14. Double-cancel must be idempotent/protected: an already-cancelled serial cannot create duplicate commercial effects or duplicate state transitions merely from refresh/re-render.
15. New rows added after a cancellation receive a new next serial; they never fill a cancelled serial gap.

### V9577 implementation mapping
- Rollback checkpoint branch: `stable-before-pi-serial-cancel-20260830`.
- Database migration: `pi_serial_cancel_v9577`.
- Canonical active PI line serial column: `rr_fg_pi_lines_v787.serial_no`.
- Current serial state table: `rr_pi_serial_state_v9577`.
- Append-only audit table: `rr_pi_serial_audit_v9577`.
- Atomic save RPC: `rr_fg_save_pi_cancelaware_v9577`.
- Cancel-aware reopen RPC: `rr_pi_requirement_reopen_cancelaware_v9577`.
- Serial state lookup RPC: `rr_pi_serial_state_get_v9577`.
- Isolated PI frontend integration: `real-pi-party-discount-test-v9557.js` V9577 loaded by `real-pi-specimen-v9514-replace-test.html`.

### Change discipline
This rule is a PI source-of-truth rule. Do not renumber physical/committed S.Nos, silently delete cancellation history, or convert CANCEL into DELETE. Preserve the already-working Replace/Add Qty, customer PDF, WhatsApp and Real Chat share flows unless an explicit PI change requires a narrowly-scoped adjustment. Promote the V9577 isolated implementation to the production PI only after its cancellation flow is validated.