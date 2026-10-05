# TEST71 Sales collection follow-up audit

Scope: test71-real-chat-e2e-finalization, TEST direct-customer collections. Main is unchanged. Partner collections keep their existing flow.

## Universal path
Sales OPEN collection → Detail / Follow-up → exact party/chat/cycle context → category-filtered unsent catalogue → Select & Send → same collection → customer requirement update → same current snapshot in Sales.

## Required fields
| Field | Purpose | Ownership |
| --- | --- | --- |
| Party ID and chat ID | Prevent cross-party targeting | Resolved and checked by server |
| Collection cycle ID and display number | Keep history, links and updates within the selected collection | Server identity, carried by navigation |
| Requirement ID and lifecycle status | Update existing requirement, stop after close/PI | Server |
| Requested category IDs/names | Eligible collection categories | Party request, canonical taxonomy |
| Sent lot numbers per cycle | Hide and reject repeat sends | Server share history |
| Lot number and requested qty | Preserve customer selections and explicit zero removals | Customer; one authoritative snapshot |
| Accepted qty and current stock | Keep requested need separate from available fulfillment | Server |
| Update number and history | Refresh reused cards and audit changes | Server |

No extra manual identity fields are required. Collection note stays optional. Lot/category/size/cloth/GSM/rate/stock are canonical catalogue metadata, not duplicate workflow inputs.

## Retired from this follow-up path
- Sale Bucket and ADD/SET quantity controls: design sending uses Select & Send; requirement quantities stay with the customer.
- DOM-only exclude-used script: server filters the entire catalogue before pagination and validates again at send.
- Customer-wide latest requirement summary: token resolves its exact collection.
- Generic multi-party shared token sender: each party receives its own eligible designs and collection.
- Alternate direct-chat sender: existing v9684 compatibility delegates the guarded core.
- Direct anonymous/authenticated execution of the legacy quantity implementation: revoked; protected token wrapper remains.
- Cold-load list redirect that discarded follow-up identity and stale requirement-only caches.

Files with compatibility names remain to avoid breaking old links; they delegate or are inactive rather than deleting history.

## Corrected behavior
- All previous shares in the exact cycle are excluded from resend; category scope comes from current open requests or last fulfilled request until changed.
- New designs sort first, previously selected designs follow with saved requested quantities.
- Existing quantities update, explicit zeros remove selections without resurrecting historical values.
- Requested quantities are not silently capped to stock; accepted quantity remains stock bounded.
- Customer links, detail cards and root OPEN queue read the same current per-lot snapshot.
- Duplicate send clicks and cross-party/cycle submissions are rejected.
- Terminal/PI collections cannot send or mutate through this path.
- Future lots and categories use the canonical catalogue/taxonomy, with no party or lot hardcoding in implementation.

## Verification
- JavaScript syntax: passed.
- DOM integration suite: 6/6 passed; real scripts executed in jsdom.
- Transactional database regression: 13 checks passed; rolled back (no persistent customer messages).
- Existing TEST cycle identity/lifecycle audit: 27 cycles passed.
- OPEN queue vs authoritative snapshot: 24 cards checked, zero contradictions.
- Staff RPC permissions: anonymous denied; legacy internal writer execution revoked.
- Full live browser/mobile/Codespaces validation has not been completed.

Run: `node --test tests/e2e/test71-sales-collection-followup.unit.test.js`.
Database regression: `tests/test71_sales_collection_followup_rollback.sql` against the authorized TEST fixture; it ends in ROLLBACK.
Apply migrations in timestamp order. Staff frontend must serve this branch and cache-bumped HTML. The public customer Site separately preserves its installation gate and updates the quantity card script/cache.


## Fresh-session requirement opening (2026-10-05)
- Card metadata and detail use one shared in-flight loader scoped by chat and requirement.
- Detail prefetch starts when the card appears; tap opens the panel synchronously.
- Failed requests are evicted; an eight-second timeout provides Retry instead of indefinite loading.
- One-message refresh polls no longer invalidate full-chat detail snapshots.
- Metadata observes message rows only; no independent sheet writer or sheet observer remains.
- Closing/switching chat and newer taps prevent stale responses/actions.
- Added five regression checks (including three independent fresh DOM sessions). Combined targeted suites: 11/11 pass.
- Actual user Codespaces/mobile verification is still pending; data rendering depends on network availability.
