# REAL CHAT IMPLEMENTATION — STEP 07 OPENED STATE V9589

Status: APPLIED / FUNCTIONAL PASS
Date: 2026-08-30

## Scope
Added versioned server-side Collection OPENED transition without replacing existing v9420 share view.

## Added
- `rr_collection_mark_opened_v9589(token)`
  - resolves active share token/short code
  - preserves first `last_opened_at`
  - for lifecycle-linked shares sets first `opened_at`
  - transitions only `SENT_NOT_OPENED -> OPENED_NO_RESPONSE`
  - does not regress REQUIREMENT_RECEIVED/PI_GENERATED/CI_GENERATED/closed/cancelled states
  - legacy non-lifecycle shares remain supported
- `rr_collection_share_view_v9589(token)`
  - wraps existing `rr_market_share_view_v9420`
  - appends lifecycle OPENED metadata
  - existing v9420 function remains unchanged

## Access
Both functions are public customer-entry RPCs because opening a secure share link can occur before Supabase staff authentication. They are SECURITY DEFINER and accept only the opaque share token/short-code entry key; no arbitrary lifecycle ID is accepted.

## Functional verification completed
User explicitly confirmed current database content is TEST data and may be used freely for testing.

A controlled TEST lifecycle fixture was created against the existing TEST customer/chat and then exercised through the actual V9589 RPC.

Verified sequence:
1. Fixture state: `SENT_NOT_OPENED`.
2. `rr_collection_mark_opened_v9589(token)` executed.
3. State became exactly `OPENED_NO_RESPONSE` and `opened_at` was populated.
4. Opening the same token again preserved the original `opened_at` (idempotent first-open behavior).
5. Fixture was advanced to `REQUIREMENT_RECEIVED` and opened again.
6. State remained `REQUIREMENT_RECEIVED`; OPENED logic did not regress a later lifecycle stage.
7. Fixture/send/share rows were deleted after test.
8. Baseline after cleanup: lifecycle cycles=0, sends=0, market shares=80, Requirements=17.

## Verdict
STEP 07 FULL FUNCTIONAL PASS.
No pending OPENED-state backend test remains. Runtime frontend still does not call the V9589 wrapper; browser integration will be tested when that isolated frontend step is introduced.