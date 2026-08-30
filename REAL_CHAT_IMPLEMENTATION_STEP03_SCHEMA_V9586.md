# REAL CHAT IMPLEMENTATION — STEP 03 ADDITIVE LIFECYCLE SCHEMA

Status: APPLIED / STRUCTURAL TEST PASS
Date: 2026-08-30

## Scope
Applied only the additive backend lifecycle foundation designed in Step 02. No customer/staff frontend, existing chat RPC, Collection share RPC, Requirement RPC, PI/CI, stock or cancellation behavior was changed.

## Migration
Supabase migration: `real_chat_collection_lifecycle_foundation_v9586`

Created tables:
1. `rr_collection_cycle_v9586`
2. `rr_collection_send_v9586`
3. `rr_collection_requirement_link_v9586`

## Security
- RLS enabled on all 3 new tables.
- Direct table privileges revoked from `anon` and `authenticated`.
- `service_role` retains server-side access.
- Customer browser therefore cannot directly select/insert/update lifecycle rows.
- Future access must go through narrowly scoped versioned server RPCs.

## Constraints
### Collection cycle
- FK to `rr_customers(id)` and permanent `rr_customer_chat_v9433(id)`.
- Positive `collection_no`.
- Unique `(customer_id, data_mode, collection_no)` to prevent duplicate Collection numbers for one party/mode.
- Server lifecycle status is constrained to:
  `DRAFT`, `SENT_NOT_OPENED`, `OPENED_NO_RESPONSE`, `REQUIREMENT_RECEIVED`, `PI_GENERATED`, `CI_GENERATED`, `CLOSED`, `CLOSED_NO_RESPONSE`, `CANCELLED`.

### Collection send/update
- FK to Collection cycle and existing `rr_market_share_v9420`.
- Positive `send_seq`.
- `send_kind` only `FIRST` or `UPDATE`.
- Unique `share_id`.
- Unique `(collection_cycle_id, send_seq)`.

### Requirement link
- FK to Collection cycle and existing `rr_market_requirements_v9420`.
- Positive `requirement_seq`.
- Unique `requirement_id`.
- Unique `(collection_cycle_id, requirement_seq)`.

## Structural verification
PASS results after migration:
- New lifecycle tables found: 3/3.
- RLS enabled: 3/3.
- Direct `anon` / `authenticated` table grants: 0.
- Lifecycle tables contain 0 rows immediately after migration (no legacy data was mutated/backfilled).
- Existing production counts remained unchanged after migration:
  - market shares: 80
  - requirements: 17
  - permanent customer chats: 3

## Backward compatibility verdict
PASS.
The migration is additive and inert until future versioned lifecycle RPCs use it. Existing legacy shares/requirements continue to operate against their existing tables and functions.

## Next safe step
Step 04 should add server-only lifecycle helper/RPC contracts for transactional Collection-number allocation and safe FIRST/UPDATE registration, including same-Collection duplicate-lot validation. Test those RPCs using controlled TEST data before any frontend is pointed at them.
