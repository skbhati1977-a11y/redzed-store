# REAL CHAT IMPLEMENTATION — STEP 04 SERVER RPCS V9587

Status: APPLIED / STRUCTURAL TEST PASS
Date: 2026-08-30

## Scope
Added only versioned server-side Collection lifecycle RPCs. No frontend file or existing v9420/v9433/v9508 function was replaced.

## Added functions
1. `rr_collection_create_first_v9587(customer_id,lots,data_mode)`
   - Requires existing sales actor authorization.
   - Requires permanent customer chat for the same customer/data mode.
   - Uses transaction advisory lock per customer+data_mode before allocating Collection number.
   - Allocates next Collection number server-side.
   - Creates legacy-compatible share using existing `rr_market_create_share_v9420`.
   - Registers FIRST send and moves cycle DRAFT -> SENT_NOT_OPENED.

2. `rr_collection_add_update_v9587(collection_cycle_id,lots)`
   - Requires existing sales actor authorization.
   - Locks cycle row during update.
   - Rejects CLOSED/CLOSED_NO_RESPONSE/CANCELLED cycles.
   - Rejects every lot already present in any prior FIRST/UPDATE share in the same cycle.
   - Creates a fresh legacy-compatible share for valid update lots and registers sequential UPDATE send.

3. `rr_collection_blocked_lots_v9587(collection_cycle_id)`
   - Internal/service-only helper returning cumulative lots already sent in that cycle.

## Security
- FIRST and UPDATE RPCs: authenticated + service_role execute; anon denied.
- Existing `rr_market_assert_sales_actor_v9420()` remains the authorization gate, so authenticated non-sales users are rejected by the function itself.
- Blocked-lots helper: service_role only; browser cannot query arbitrary lifecycle IDs through it.
- All functions are SECURITY DEFINER with fixed public search_path.

## Structural verification
After migration:
- Lifecycle cycle rows: 0
- Lifecycle send rows: 0
- Existing market shares: 80
- Existing Requirements: 17
Therefore migration itself did not create/alter business records.

Permission verification:
- create_first: anon=false, authenticated=true, service_role=true
- add_update: anon=false, authenticated=true, service_role=true
- blocked_lots: anon=false, authenticated=false, service_role=true

## Test boundary
No live business Collection was created just to test the RPC because that would pollute production history. Functional FIRST/UPDATE/duplicate rejection should be exercised only through a controlled TEST-mode customer/fixture in a later isolated integration step.

## Verdict
STEP 04 PASS for server implementation and structural/security verification.
Frontend/runtime remains unchanged.