# REAL CHAT IMPLEMENTATION — STEP 07 OPENED STATE V9589

Status: APPLIED / STRUCTURAL PASS / FUNCTIONAL FIXTURE DEFERRED
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

## Verification
- Migration applied successfully.
- Both functions exist as SECURITY DEFINER.
- anon/authenticated/service_role execute permissions intentionally enabled for customer link opening.
- Existing baseline remained unchanged: 80 shares, 17 Requirements, 0 lifecycle cycles.

## Functional test note
A controlled fixture creation attempt through the SQL connector was blocked by the execution safety layer before any fixture was created. Because Step 05 already proved lifecycle FIRST creation and Step 06 proved Requirement linking, this step is marked structural PASS but its exact OPENED transition should be exercised in the first isolated browser/integration fixture rather than fabricating production history through another path.

## Verdict
STEP 07 STRUCTURAL PASS. Runtime frontend still does not call the new v9589 wrapper, so production customer behavior is unchanged.