# TEST71 import readiness — 2026-10-11

Decision: NOT CLEARED for new business-data import. This is an evidence checkpoint, not a universal sign-off.

## Current live implementation — 2026-10-11

Current matrix remains **99 PASS, 10 FAIL, 4 BLOCKED, 19 NOT_RUN**. Passed MC1/CB/Material/Commercial/Factory receipt checkpoints are carried forward. Historical counts, preview URLs and quota restrictions in the dated notes below do not replace the current checkpoint.

Opening source readiness, evidence-based archive planning and independent authenticated financial-role tooling were completed as source tooling in three parallel workstreams. Live isolated source review and opening approval-plan workflows are now applied. Six independent Auth roles passed 12 financial API authority checks and were retired with zero sessions remaining. Actual approved opening source, complete operational reader/aggregate isolation and browser financial journeys remain prerequisites. See [live implementation](test71-live-readiness-implementation-20261011.md). See [three-target continuation](test71-three-target-continuation-20261011.md) for concrete results and live limitations.

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

## Further verified continuation: salary board and accrual
- TEST earned-to-cutoff calculation now uses approved resolved canonical V777 attendance and the existing monthly calculator. Actual HALF_DAY, full-month and fixed-30 partial-month amounts match monthly payroll in rollback tests. Missing/unresolved active days block provisional payment rather than inventing an absence or full pay.
- Safe V779_5 generation classifies departed TEST salaried workers at their last active day in the month. A September 15–25 active interval generates 11/30 salary and matches the earned board.
- New TEST MONTHLY_SALARY_DUE entries now atomically create Salary Expense debit / worker payable credit. Negative MONTHLY_FINAL_ADJUSTMENT posts worker payable debit / Salary Expense credit. The existing active EXP_MONTHLY_SALARY ledger was verified before mapping.
- Journaled accrual amount/source/mode edits are rejected. POSTED → VOID reverses the Accounts source; void reactivation is rejected. Historical dues were not backfilled.
- Individual salary, Committee and material protected-request rollback evidence replayed successfully after the accrual trigger. Fresh unbalanced posted journals: 0; persisted rollback accrual/manual attendance rows: 0.
- New accrual trigger is private (anon and authenticated direct EXECUTE false). Existing earned/safe-generation RPCs retain guarded authenticated access and anon EXECUTE false. Security advisors were fetched; existing project-wide notices remain outside this targeted proof.
- Evidence: tests/evidence/test71-salary-earned-canonical-20261011.sql and tests/evidence/test71-salary-accrual-accounts-20261011.sql.
- V779 TEST finalization now creates a mapped MONTHLY_SALARY_DUE and balanced expense/payable journal. The old amount-only TEST monthly payment route is blocked. Cash/Bank-mode/reference/date payment goes through the protected request path and updates the same settlement; partial/full payment and reversal keep FINAL/PAID and balances aligned. Eighteen rollback assertions passed, including missing Bank route atomic failure. Claim/advance-recovery payroll is explicitly blocked until its approved Accounts source mapping is complete; this is not full recovery clearance.
- Ten duplicate-prone raw TEST financial writers now require a live protected request context. Private assertion cannot be executed directly by anon/authenticated. Accounts protected retry creates one journal and restores context; individual salary, material and Committee protected flows passed after the guards. REAL legacy behavior was not changed. Old bulk writers and remaining source-level APIs still need independent review.
- Source staging now preserves original normalized rows, source reference/SHA256, explicit KNOWN/ZERO/UNKNOWN/NOT_APPLICABLE and row findings. Earliest supplied date determines the proposed cutoff. Exact retry, changed-payload rejection, unresolved reference, duplicate identity, opening imbalance, false zero and invalid-date/N/A checks passed. Staging always returns cleared_for_import=false and writes no business records; no source file from the user has been staged.
- The TEST salary management board now reports resolved/required active days and blocks unknown-history legacy generation. One approved day stays WAITING_FOR_ATTENDANCE (1/30); full resolved coverage is READY_TO_GENERATE. Existing historical records remain intact.
- Signed-in Owner browser on READY preview 34c5c939d99a6ccbb9f5e316c422c4745903bacb rendered October 1–11 only, with October 11 PENDING and no future absence rows; annual calendar rendered all seven selected paid holidays. This supersedes the old future-day browser blocker. Current payroll coverage UI changes are newer than that preview and need redeployment.

## Verified continuation: approved advance recovery and Accounts OPEN
- Protected V785 TEST salary posting now routes through V786 and the canonical attendance-derived earned amount. Missing attendance is pending per worker, with null earned/payable amounts rather than guessed pay. Unselected workers are not accrued or recovered.
- Approved September salary test: ₹15,000 accrual, ₹100 dedicated advance recovery, ₹14,900 cash payment; salary payable and advance balance both clear. Full audited TEST batch reversal restores the advance to ₹100 and salary balance to zero; duplicate reversal is rejected. Six rollback assertions passed, including all three audited Accounts source reversals.
- Finalized V779 salary cannot be paid through alternate V785/V786 salary routes. Nineteen monthly-source/payment rollback assertions passed. Legacy V782/V782_2 TEST bulk writers are retired; REAL behavior remains as before. Nonzero opening monthly settlements are blocked until approved due allocation exists.
- Accounts OPEN now includes canonical outstanding bills, individual salary dues, finalized mapped monthly salary settlements and TEST Committee dues. Five rollback assertions prove all pending bills, explicit modes, no TEST Committee leakage to REAL, invalid-mode rejection and anonymous rejection. This does not certify every untagged claim or source pipeline.
- Accounts action UI syntax passed. Changes are committed only to TEST71. The next preview deployment was rejected with Vercel 402 api-deployments-free-per-day (>100 deployments); CLI fallback is unavailable. No billing/settings change was made.

## Remaining import blockers

1. Implement and verify the selected old-fixture archive boundary in this same database, including readers and aggregated stock/balances, not merely a new label or URL.
2. Approved universal opening batch, cutoff, source evidence and UNKNOWN/ZERO/N/A handling; balance and stock/WIP/COGS reconciliation.
3. Complete approved payroll accrual, claim and advance settlement pipeline through payment and reversal. Direct advance recovery event tests alone do not prove approved payroll recovery.
4. Original MC1 purchases remain untagged; archive/reconciliation needs source evidence rather than blind mode backfill.
5. Retirement/guarding of legacy duplicate-prone financial writers, Accounts pending-source queue and generic report fallback.
6. Remaining independent-role browser journeys, mobile/offline/concurrency, 14-department Submit/Alter/Rectify-to-Accounts journeys, Committee branches and blocked costing/despatch fixtures.
7. Future source contracts that change salary within a month currently require reviewed segmented payroll; no guessed rate is applied.

Evidence SQL is committed under tests/evidence/*20261011.sql. Each business-record scenario ends in ROLLBACK. Existing imaginary records and production/main git remain intact.

## Latest checkpoint: bounded source rerun and current blockers
- Current scenario matrix: 97 PASS, 12 FAIL, 4 BLOCKED, 19 NOT_RUN. No universal clean chit.
- Current bounded source suite: 110 files, 83 pass, 27 fail, zero timeouts. Evidence saved in test71-source-suite-evidence-20261011.json; assertions were not waived.
- Four required CI suites were enabled; the real push-triggered workflow ran and stopped at failing static contracts. This is execution evidence, not CI success.
- Customer approval security suite: 38 tests passed after current DOM fixture fixes. Session/notification/OTP suite: 18 tests passed; native rendered garment receipt suite: 8 tests passed. An actual missing OTP identity-change control was restored. The renderer's @napi-rs/canvas dependency is pinned at1.0.11 with the lockfile.
- Signed-in existing READY preview Cutting WORKING → STAFF → ALTER6 rendered all six articles. Fabrication WORKING → Accept & Count13 rendered source submitter and department mapping. Latest newer UI code cannot be browser-certified until deployment becomes available.
- Fresh posted journal imbalance count0; persisted rollback salary records0.
- Archive/aggregate isolation, approved openings and source reconciliation, claim policy wiring, remaining static failures and independent role/mobile/GPS/push/workflows still remain. Actual CSV/Sheet source has not been supplied; no new business records were imported.
