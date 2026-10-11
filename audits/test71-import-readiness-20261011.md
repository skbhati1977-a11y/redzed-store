# TEST71 import readiness — 2026-10-11

Decision: NOT CLEARED for new business-data import. This is an evidence checkpoint, not a universal sign-off.

## Authorized target and selected rules

Continue only on test71-real-chat-e2e-finalization with the existing hruartsemierwhtzonei backend in the organization now named Ci. The user explicitly deferred creating another database. Preserve old imaginary fixtures and archive them separately from future active stock, balances and cards; this logical separation has been selected but is not yet implemented or activated.
Partial-month salaried pay uses fixed 30-day basis. HALF_DAY uses actual punch hours, rather than a flat 50% day. Full active-month salary retains the monthly contract; partial salary is monthly contract × active calendar days / 30, while time deduction/extra rates retain the contract / 18000 minute basis.

## Verified and committed

- Opening exact retries retain the original purchase; changed quantity/value/date under the same reference are rejected. This does not provide a universal approved opening GL batch.
- New TEST advance payments create a balanced worker advance asset / approved Cash-Bank journal in the same transaction. Recovery debits salary payable and credits the advance asset; linked recovery reversal and payment void reverse the source journal. Missing bank routes fail the whole payment. Retries make exactly one payment and journal.
- Individual salary payment through the existing protected request path now has an assertion proving exactly one posted Accounts journal across retries. Historical test text saying “still pending” is stale; the new 20261011 assertion is authoritative.
- Audited manual V778 attendance now updates the canonical V777 day. Incomplete punches remain review/pending without final deduction. Paid Monday has 600 paid minutes. A 10:00–14:00 HALF_DAY has 240 working minutes and 360 deduction minutes under the selected actual-hours rule.
- TEST monthly payroll requires every active date to have approved resolved canonical attendance. One day cannot generate a full-month salary. Before/after activation days are excluded. A September 15 joining date produces 16/30 base salary; contract minute rate is preserved.
- Super Admin monthly generation permission parity is fixed. Manual and GPS canonical sync lock against finalized monthly payroll; audited manual attendance has priority over raw GPS recalculation.
- MC1 master form now uses the protected financial request path. A new purchase, TEST source tag and balanced supplier/purchase Accounts journal are atomic. Same request retries preserve the purchase/journal; changed payload is rejected. Legacy untagged purchases were not backfilled.
- Eleven prior rollback scripts replayed without execution errors. Their results are not a universal pass: some historical scripts emit hardcoded old commentary, and their scenario coverage is limited.
- New MC1 client routing/retry and syntax checks passed. Preview commit 6def39720bf4446145c61019b91ee4f30451a915 is READY at https://redzed-test65-djuijrqp9-skbhati1977-4414.vercel.app . Deployed MC1 JS and financial helper exactly match source. HTML source matches before Vercel's appended feedback script.
- Fresh invariant check: unbalanced posted journals 0; duplicate active source mappings 0; rollback advance assets/purchases/manual attendance rows 0. No new business import was performed.

## Remaining import blockers

1. Implement and verify the selected old-fixture archive boundary in this same database, including readers and aggregated stock/balances, not merely a new label or URL.
2. Approved universal opening batch, cutoff, source evidence and UNKNOWN/ZERO/N/A handling; balance and stock/WIP/COGS reconciliation.
3. Complete approved payroll accrual, claim and advance settlement pipeline through payment and reversal. Direct advance recovery event tests alone do not prove approved payroll recovery.
4. Original MC1 purchases remain untagged; archive/reconciliation needs source evidence rather than blind mode backfill.
5. Retirement/guarding of legacy duplicate-prone financial writers, Accounts pending-source queue and generic report fallback.
6. Remaining independent-role browser journeys, mobile/offline/concurrency, 14-department Submit/Alter/Rectify-to-Accounts journeys, Committee branches and blocked costing/despatch fixtures.
7. Future source contracts that change salary within a month currently require reviewed segmented payroll; no guessed rate is applied.

Evidence SQL is committed under tests/evidence/*20261011.sql. Each business-record scenario ends in ROLLBACK. Existing imaginary records and production/main git remain intact.
