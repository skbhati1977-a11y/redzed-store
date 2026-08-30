# REAL CHAT IMPLEMENTATION — STEP 02 DATA CONTRACT

Status: DESIGN VERIFIED / NO RUNTIME CHANGE
Date: 2026-08-30

## Scope
This step defines the safest backward-compatible data contract for the Real Chat -> Collection -> Requirement lifecycle. No production schema or runtime RPC was changed in this step.

## Existing compatibility findings
- Existing `rr_market_share_v9420` already provides the Collection/share base: id, token, customer_id, customer_name, data_mode, status, created_at, last_opened_at, short_code.
- Existing `rr_market_share_lots_v9420` already binds lots to each share with `(share_id, lot_no)` uniqueness.
- Existing `rr_market_requirements_v9420.share_id` already links Requirement to the originating share.
- Existing `rr_customer_chat_v9433` already enforces one chat per `(customer_id, data_mode)`.
- Existing `rr_market_submit_requirement_v9508` can append to an existing Requirement and blocks duplicate lot rows within that Requirement.
- Existing share view updates `last_opened_at`, which can be reused as the OPENED signal.

## Data audit findings
- 77 legacy shares currently have no `customer_id`; these cannot be blindly backfilled by assumption.
- 1 legacy Requirement currently has no `customer_id`.
- 5 existing shares have more than one Requirement; therefore any future lifecycle model must support legacy multi-Requirement history without destructive normalization.
- 0 detected Requirement/customer mismatches where both share and Requirement customer IDs are present.
- 0 detected Requirements-with-customer missing their matching permanent chat.
- 0 detected duplicate lot rows inside a Requirement.

## Final safe contract
Do NOT overload or rewrite legacy columns. Add a versioned lifecycle layer that references existing IDs.

### A. Collection cycle master
Proposed table: `rr_collection_cycle_v9586`
- `id uuid primary key`
- `customer_id uuid not null -> rr_customers(id)`
- `chat_id uuid not null -> rr_customer_chat_v9433(id)`
- `data_mode text not null`
- `collection_no integer not null`
- `display_no text not null` e.g. `RZ COLLECTION 01`
- `status text not null`
- `opened_at timestamptz null`
- `closed_at timestamptz null`
- `close_reason text null`
- `created_at timestamptz not null`
- `created_by uuid null`
- Unique `(customer_id, data_mode, collection_no)`.

### B. Collection sends/updates
Proposed table: `rr_collection_send_v9586`
- `id uuid primary key`
- `collection_cycle_id uuid not null`
- `share_id uuid not null -> rr_market_share_v9420(id)`
- `send_seq integer not null` (`1` first send, `2+` updates)
- `send_kind text not null` (`FIRST`,`UPDATE`)
- `sent_at timestamptz not null`
- `sent_by uuid null`
- Unique `share_id`; unique `(collection_cycle_id, send_seq)`.

This lets every existing share remain physically unchanged while grouping new shares/updates under one Collection Number.

### C. Cumulative style eligibility
No separate copied style master is required initially. Eligibility is derived from all `rr_market_share_lots_v9420` rows belonging to every share linked through `rr_collection_send_v9586` for the same Collection Cycle.

Exact rule:
`blocked lots = UNION(all lots from all previous sends/updates in same collection_cycle_id)`

New Collection cycle = new `collection_cycle_id`; old blocked set does not carry forward.

### D. Requirement lifecycle link
Proposed table: `rr_collection_requirement_link_v9586`
- `id uuid primary key`
- `collection_cycle_id uuid not null`
- `requirement_id uuid not null -> rr_market_requirements_v9420(id)`
- `requirement_seq integer not null`
- `linked_at timestamptz not null`
- `is_primary boolean not null default true`
- Unique `requirement_id`.

For the new flow, one Collection Cycle should normally resolve to Requirement 01. The model intentionally permits legacy/history edge cases without rewriting old rows.

### E. Lifecycle statuses
Collection cycle statuses:
- `DRAFT`
- `SENT_NOT_OPENED`
- `OPENED_NO_RESPONSE`
- `REQUIREMENT_RECEIVED`
- `PI_GENERATED`
- `CI_GENERATED`
- `CLOSED`
- `CLOSED_NO_RESPONSE`
- `CANCELLED`

Status transitions must be server-controlled in later versioned RPCs, not writable directly by customer browser code.

## Backward compatibility strategy
1. Do not alter existing working `v9420/v9433/v9508` RPC behavior in place.
2. New versioned RPCs wrap/extend existing records.
3. Existing old share links continue working even when no lifecycle row exists.
4. Legacy shares with unknown customer remain legacy-unmapped until deterministic evidence exists; never infer customer from name alone.
5. New Collection numbers begin only for records created through the new lifecycle RPC.
6. Old multiple Requirements on one share remain untouched; new flow enforces the intended lifecycle going forward.

## Security contract
- Customer browser never selects arbitrary `customer_id`, `chat_id`, `collection_cycle_id`, or lifecycle status.
- Server resolves these from verified secure entry/session and existing authenticated linkage.
- Collection number allocation must happen transactionally server-side to prevent duplicate Collection 01/02 under concurrent sends.
- All update sends validate same customer + same data_mode + active Collection Cycle.
- Same-Collection duplicate-lot rule is enforced server-side, not only hidden in UI.

## Step 02 verdict
PASS FOR DESIGN.

No schema migration is applied yet. The next safe step is Step 03: prepare and apply only the additive lifecycle schema + indexes + RLS/server ownership, then run structural DB tests before touching frontend/runtime business flow.
