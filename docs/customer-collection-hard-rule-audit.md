# TEST71 customer and distributor collection hard rule — 7 October 2026

The rule is per customer. Different customers can each have one open collection. Distributor private customer scope is (distributor owner, private customer), with one root collection and multiple updates sharing that number.

An open collection accepts its own collection updates and requirement quantities. Customer Close Requirement or making PI/CI ends that collection. Closed/PI/CI collection quantities are frozen and the collection cannot reopen. The next sales send starts a new higher customer collection number and U0; its required quantity starts separately. Explicit stale links to closed records cannot append new items to them. Requirements and shares must match the collection customer and authority.

## Audited result

| Direct customer | Only active collection |
| --- | --- |
| Avnimycutie | 1 |
| LUKMAN SALES | 2 |
| Mumtaz Khan | 12 |
| Pragya | 9 |
| Reeka Bhati | 12 |
| Shailendra saini | 10 |
| Veer Bhati | 18 |

Veer Bhati → private customer sudesh (T67-C-0002): Collection 1 closed after CI; Collection 2 is the only open root, currently U2. Its next updates remain Collection 2 until close/PI/CI, then the next collection is 3.

17 historical direct duplicate open cycles were closed with audit reasons; no collection identifiers were renumbered. 10 obsolete collection/requirement chat cards were archived. Six legacy direct shares had missing/wrong customer metadata repaired from their unique canonical cycle/chat association. Three private distributor shares were incorrectly adopted into their owner's direct collections: only those incorrect send associations were removed and distributor authority restored. Snapshots of each change are retained in private audit tables. Quantities, requirements, orders and bills were not moved or deleted.

Final audit: zero duplicate direct active collections, zero duplicate distributor active roots, zero mismatched requirement cycle/customer/number links, zero requirements linked to multiple cycles, zero share/customer mismatches, and zero private distributor shares in direct send associations.

## Applied database changes, in order

1. `sql/test71_one_open_collection.sql` (previous turn)
2. `sql/test71_collection_lifecycle_hard_rule.sql`
3. `sql/test71_collection_requirement_chat_cleanup.sql`
4. `sql/test71_collection_requirement_history_guard.sql`
5. `sql/test71_distributor_one_open_collection.sql`
6. `sql/test71_collection_rule_quantity_hardening.sql`
7. `sql/test71_partner_cycle_history_on_close.sql`
8. `sql/test71_collection_share_wiring_cleanup.sql`
9. `sql/test71_direct_distributor_route_guard.sql`

Database unique indexes, private serialized gates and table triggers enforce the rule even if a new UI or RPC omits a check. Existing sales authorization and customer approval remain enforced. The changes cover TEST71 data; production/Main was not migrated.

## Verification

Executed rollback suites: customer-one-open-collection-rollback.sql, customer-collection-lifecycle-rollback.sql, customer-distributor-lifecycle-rollback.sql and customer-login-approval-rollback.sql. These verify three legacy create APIs, independent customers, same-number open context, actual Close Requirement, automatic chat archival, frozen old quantities, rejection of closed sends and reopening, actual sales send to the next customer number from a stale old route, actual PI linkage closing the cycle, distributor updates within their root, customer closure, and creation of the next distributor number. Every test fixture change rolls back.

The 13 customer mobile/approval contract tests also pass. No physical phone test is claimed. No real customer session approvals were seeded for test convenience.


## Closed read-only cards and per-cycle item visibility — 7 October 2026

Closing a TEST71 direct/distributor cycle freezes requirement quantities and collection edits. The latest white collection card stays visible and opens a read-only viewer on both sides. Preparing PI from a closed customer requirement remains permitted. The previous card is archived only when an actual next-number collection is sent; its business history is preserved. Live status follows the latest sent cycle, while exact-cycle staff reads preserve the requested cycle identity.

The live card shows collection number and U0, then U1/U2 for collection sends. No update dropdown is rendered. The collection viewer aggregates this cycle's sent items, puts the newest send first, and retains saved required quantities. Each item can be sent once per cycle regardless of zero/nonzero requirement; a fresh cycle makes eligible items shareable again.

Zero-quantity items have a red × hide button. Positive typed qty immediately hides that button. Hidden item records are private database rows scoped by collection UUID and lot, separate from send history and saved quantities; they never prevent sharing in a new cycle. The API checks authorized collection access, lot membership, active status and saved zero qty.

Verification: SQL rollback suites exercise closure, exact read-only state, immutable qty, replacement-card archiving, duplicate item rejection, and fresh-cycle sending. Node tests cover iPhone alignment/metrics and cross visibility. No physical iPhone/Android test is claimed.
