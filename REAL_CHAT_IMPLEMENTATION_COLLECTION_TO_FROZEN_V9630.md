# REAL CHAT IMPLEMENTATION — COLLECTION TO PI FREEZE V9630

Status: ISOLATED / TEST-ONLY BACKEND FOUNDATION
Date: 2026-08-31

## Goal
Implement the locked Collection -> Updates/More Samples -> Requirement -> PI Freeze architecture without changing the currently approved production customer/staff UI or the canonical CPI stock-deduction engine.

## Safety boundary
- Existing production customer entry/UI is untouched.
- Existing staff Real Chat is untouched.
- Existing canonical PI/CPI function `rr_fg_save_pi_v787` is untouched.
- Existing CPI stock deduction remains the authoritative physical deduction path.
- New PI reservation engine is TEST-only until isolated functional approval.
- No automatic PI expiry/cancellation scheduler is enabled yet; working-day calendar and reminder automation will be added only after the reservation flow is functionally certified.

## Database migration applied
`real_chat_collection_to_pi_freeze_foundation_v9630`

### New lifecycle/update tables
- `rr_collection_update_request_v9630`
- `rr_collection_update_category_v9630`

### New PI reservation tables
- `rr_pi_reservation_v9630`
- `rr_pi_reservation_audit_v9630`

### New RPCs
- `rr_collection_categories_v9630()` — returns configured nonblank product categories from Art Master.
- `rr_collection_more_samples_request_v9630(token,categories,note)` — creates a MORE_SAMPLES update inside the SAME Collection number.
- `rr_collection_customer_close_v9630(token,reason)` — terminal customer close before PI; blocks close if PI already exists.
- `rr_pi_reservation_conflicts_v9630(pi_id)` — calculates Lot-level demand vs current on-hand stock after other active PI reservations.
- `rr_pi_reservation_sync_v9630(pi_id)` — TEST-only PI freeze/reserve operation; refuses freeze on unresolved shortage and marks linked Collection `PI_GENERATED`.
- `rr_pi_reservation_modify_v9630(reservation_id,new_qty,reason)` — authorized audited reduction/reallocation of an existing active reservation.
- `rr_pi_party_confirm_v9630(pi_id)` — records party confirmation for active reservations.

## Locked inventory behavior now represented
Requirement = demand only.
PI reservation = separate freeze overlay; no stock ledger deduction.
Conflict = visible calculation against other active PI reservations.
Authorized reallocation = explicit reduction only, mandatory reason, audit trail.
CI = remains existing physical stock deduction path.

## Next safe sequence
1. Add isolated customer 3-action UI: SEND MORE SAMPLES / SEND REQUIREMENT / CLOSE REQUIREMENT.
2. Verify category multi-select persists against the SAME Collection cycle and staff can read identical preselected categories.
3. Add isolated staff reservation-conflict panel for a selected PI.
4. Functional test with TEST PI: freeze -> competing demand -> audited reduction -> confirmation.
5. Add configurable working-day calendar + 5-working-day expiry engine.
6. Add sixth-working-day auto-cancel/restore only after expiry tests pass.
7. Integrate CI reservation-consume/Collection final-close after canonical CPI flow audit.
8. Only after approval, wire isolated paths into production UI.

## Invariant
One active commercial conversation keeps one Collection Number through all updates, Requirement and PI/CI. Requirement does not reserve stock. PI freezes stock. CI deducts stock. No reservation is silently stolen, and no existing production stock rule is replaced before isolated certification.
