# Old TEST data isolation: executable dry-run barrier

Scope: TEST71 branch only. No live table or row was changed, deleted, relabelled or archived by this work.

Live read-only catalog on 11 October 2026 found **175 base tables with data_mode**, **721 functions referencing data_mode**, and **zero dataset/workspace/rehearsal columns** in public. Fabric purchases, cutting lots and the UPM lot registry have no data_mode column. Holiday calendar v777_2 has data_mode; payroll holidays v778 has neither data_mode nor dataset scope. These are different relations and must be checked separately.

`sql/test71_isolation_inventory.sql` reproduces the catalog query. This is a dependency inventory indicator, not proof that all 721 functions are active or all references have been reviewed.

`scripts/test71-isolation-plan.cjs` now validates a concrete archive review manifest without database access. It rejects REAL, untagged and prefix-only row classification; requires source hashes, explicit TEST mode and provenance, dependent-row closure, preserved snapshot and successful restore evidence. It also requires evidence for every reader/aggregate/writer/security surface, the complete reader inventory, an approved opening reconciliation and the exact preview artifact. A partial label or card filter cannot pass this barrier.

The script always returns `archive_activated=false` and `business_records_changed=0`, including a fully evidenced synthetic plan. It has no activation capability. Referenced evidence is a review contract, not a cryptographic verification of external facts; a reviewer must inspect live row hashes and the cited evidence before any separately implemented activation.

Run current blocked plan:

```sh
node scripts/test71-isolation-plan.cjs audits/test71-isolation-input-20261011.json
```

Exit 2 means evidence is incomplete. Exit 1 means malformed input/IO failure. Exit 0 only means ready for review; it never means archive activation or clean chit.

Targeted verification: `node --test tests/test71-isolation-plan.test.cjs` — **8 tests passed**. Tests cover full synthetic review contract, REAL/unknown mode rejection, each required reader/aggregate surface, duplicate coverage, restore/source/dependency/opening failures, malformed identifiers invalid manifests, immutable full-contract hashes and explicit REAL/ambiguous counts. These are offline planner tests; they do not certify live reader isolation.

Remaining concrete work: verified legacy row manifest (untagged original MC1/CB/lot records remain unresolved), snapshot and restore proof, TEST-scoped implementation of all active readers/aggregates and writers, shared-calendar decision, and approved opening stock/WIP/ledger bridge. Import readiness remains HOLD; isolation audit cases A055/A056/A057 remain uncleared.
