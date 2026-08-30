# REAL CHAT IMPLEMENTATION — STEP 05 FUNCTIONAL TEST V9587

Status: PASS / TEST DATA CLEANED
Date: 2026-08-30

## Scope
Controlled TEST-mode functional verification of the new Collection lifecycle backend. No frontend/runtime file changed.

## Test fixture
Used an existing TEST customer/chat and existing TEST lot numbers only. Test-created lifecycle/share records were removed after verification.

## Functional results
1. FIRST send
- `rr_collection_create_first_v9587` created `RZ COLLECTION 01`.
- Returned `send_seq=1`, `send_kind=FIRST`.
- Created one compatible market share with one lot.
- Lifecycle status became `SENT_NOT_OPENED`.

2. UPDATE send
- `rr_collection_add_update_v9587` on the same cycle accepted a different lot.
- Returned `send_seq=2`, `send_kind=UPDATE`.
- Cumulative blocked-lot helper then returned both FIRST and UPDATE lots.

3. Same-Collection duplicate rejection
- Attempting to send the FIRST lot again in the same Collection was rejected server-side with:
  `Lot(s) already sent in this Collection: RMTST-102A`
- No additional share/send row was created by the rejected call.

4. New Collection reset invariant
- A second isolated lifecycle cycle for the same customer was created during the controlled fixture check.
- The lot used in Collection 01 was valid in Collection 02 because blocking is scoped only by `collection_cycle_id`.
- Verification after commit showed:
  Collection 01 blocked = `RMTST-102A`, `RMTST-102B`
  Collection 02 blocked = `RMTST-102A`
- This confirms old Collection history does not globally block the same lot in a new Collection cycle.

## Cleanup
All temporary lifecycle sends/cycles and the three test-created shares were deleted after verification.

Post-cleanup baseline:
- `rr_collection_cycle_v9586` rows = 0
- `rr_collection_send_v9586` rows = 0
- `rr_collection_requirement_link_v9586` rows = 0
- Existing market shares restored to 80
- Existing Requirements remain 17

## Notes
The second-cycle reset check used the same underlying schema/invariant directly after the real FIRST/UPDATE RPC test, rather than leaving a synthetic business record behind. No production history remains from this test.

## Verdict
STEP 05 PASS.
Backend Collection FIRST/UPDATE/cumulative same-cycle blocking/new-cycle reset behavior is verified and the database is clean.
