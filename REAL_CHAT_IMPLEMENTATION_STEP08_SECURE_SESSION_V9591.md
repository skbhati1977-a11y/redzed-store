# REAL CHAT IMPLEMENTATION — STEP 08 SECURE CUSTOMER SESSION V9591

Status: APPLIED / FULL FUNCTIONAL PASS
Date: 2026-08-30

## Scope
Introduced additive server-issued customer session foundation. Existing customer frontend/localStorage behavior is not yet replaced.

## Added
- `rr_customer_session_v9590`: private RLS-enabled session table; no anon/authenticated direct table grants.
- `rr_customer_session_issue_v9590(token,name,mobile,device_id)`
- `rr_customer_session_validate_v9590(session_token,device_id)`
- `rr_customer_session_revoke_v9590(session_token)`

## Security model
- Share token/short-code is the entry capability.
- Existing customer bootstrap resolves/creates the permanent customer/chat.
- If a share is already customer-bound, issuing a session for another customer is rejected.
- Server creates a cryptographically random 256-bit session token.
- Database stores SHA-256 token hash, not the raw session token.
- Optional device binding is stored as SHA-256 hash.
- Session has expiry, last-seen and revocation timestamps.
- Direct session-table browser access is denied by RLS/grants.

## Test and correction
Initial functional test exposed a real implementation issue: pgcrypto functions live in the Supabase `extensions` schema, while the first functions used only `public` search_path. This caused `gen_random_bytes(integer) does not exist`.

V9591 corrected the functions to use explicitly qualified `extensions.gen_random_bytes` and `extensions.digest` with fixed `public,extensions` search path.

## Full functional verification
Using TEST data:
1. Session issuance succeeded.
2. Returned customer/chat/share IDs matched the existing TEST customer context.
3. Session validation with the bound test device succeeded and returned `valid=true`.
4. Session revocation succeeded.
5. Separate deterministic TEST session fixture was inserted with a hashed correct-device binding.
6. Validation using a deliberately different device ID failed exactly with `Trusted device does not match.`
7. The same session validated successfully with the correct device ID (`valid=true`).
8. Test session rows were deleted after verification.
9. Session table returned to 0 rows after cleanup.

The earlier connector limitation was avoided by testing the negative path as a single direct RPC call instead of a compound exception-catching SQL statement.

## Verdict
STEP 08 FULL FUNCTIONAL PASS. No pending backend test remains for the secure session foundation. Do not replace the existing customer frontend/localStorage path until its isolated integration step is implemented and browser-tested.