# REAL CHAT IMPLEMENTATION — STEP 06 REQUIREMENT LINK V9588

Status: APPLIED / FUNCTIONAL TEST PASS
Date: 2026-08-30

## Scope
Added a versioned Requirement submit wrapper for the new Collection lifecycle without replacing existing `rr_market_submit_requirement_v9508`.

## Added function
`rr_collection_submit_requirement_v9588(token, customer_name, mobile, message, lines, requirement_id default null)`

Behavior:
- Resolves the legacy share from token/short code.
- If the share has no new lifecycle mapping, falls back directly to existing v9508 behavior for backward compatibility.
- If the share belongs to a Collection cycle, rejects CLOSED/CLOSED_NO_RESPONSE/CANCELLED cycles.
- New Requirement is created by existing v9508, so existing customer registration, stock availability capping, chat message creation and Requirement trigger behavior stay intact.
- Requirement number is allocated only when the Requirement row is actually inserted. Existing `trg_rr_requirement_no_v9543` remains the numbering authority.
- New Requirement is linked to the correct Collection cycle in `rr_collection_requirement_link_v9586`.
- Append/update requires the Requirement already be linked to that same Collection cycle.
- Collection status advances to `REQUIREMENT_RECEIVED` unless already at a higher terminal/business stage.
- Customer mismatch between submitted Requirement and Collection customer is rejected.

## Controlled TEST functional verification
Using an existing TEST-mode permanent customer chat and TEST stock lot:
- Created temporary `RZ COLLECTION 01`.
- Submitted one actual Requirement through the new wrapper.
- Requirement returned with `requirement_no = REQ-002` (existing party sequence authority).
- `requirement_seq = 1` linked to Collection cycle.
- Collection status became `REQUIREMENT_RECEIVED`.
- Accepted quantity was validated from existing FG stock availability.

## Cleanup verification
Temporary test data was fully removed after verification:
- Chat test message deleted: 1
- Lifecycle Requirement link deleted: 1
- Requirement deleted: 1
- Collection send deleted: 1
- Test share deleted: 1
- Test Collection cycle deleted: 1

Post-cleanup baseline:
- Collection cycles: 0
- Collection sends: 0
- Collection Requirement links: 0
- Market shares: 80
- Market Requirements: 17

## Compatibility / security note
The wrapper currently has the same customer-facing callable posture needed by the existing token-based requirement flow (`anon/authenticated/service_role`). This step does NOT claim token+mobile is final permanent authentication. Secure customer session/device binding is a later dedicated phase and must harden entry without breaking this lifecycle linkage.

## Verdict
STEP 06 PASS.
No customer frontend file changed in this step.