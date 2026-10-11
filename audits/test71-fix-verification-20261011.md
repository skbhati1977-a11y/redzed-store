# TEST71 fix verification — 11 October 2026

Full clean chit: **NOT CLEARED**. Business import: **NOT CLEARED**.

Four runtime defects were fixed: hidden saved collection quantity exceeding reduced stock; external notification destinations accepted because `/s.html` was checked before origin; CB field-required errors incorrectly shown as permission errors; MC1 empty-state observer erasing valid purchase/consumption/closing cards.

Current source verification: **116/116 files and 665/665 tests pass, zero skips**, plus the Real Chat projection gate. Obsolete contradictory historical assertions are recorded in `test71-superseded-source-assertions-20261011.json`; current executable behavior tests replace them. This is source evidence, not universal business-flow approval.

Runtime commit `3adfb887978a82651d7fc115652b4aa60735f5c4` is READY at https://redzed-test65-dvcpl29xw-skbhati1977-4414.vercel.app. CB, collection and service-worker assets returned HTTP 200 and exactly matched committed files. Latest MC1 observer fix is committed in `785f6176233f1009111e9ead39277ac4b7808250` but **not deployed**: Vercel API returned HTTP 402 `api-deployments-free-per-day`, and Git commit status says deployment rate limited, retry in 24 hours. No authenticated local Vercel CLI is installed.

At deployed commit 3adfb887, CI Print/Projection and customer mobile contract succeeded. Super Admin auth and 511 static tests succeeded in full module CI. MC1 browser failed because the observer erased its form; source regression verifies the fix. Remaining module suites are enabled to run independently after successful auth; latest deployed-role evidence is blocked by quota.

Fresh SQL rollback checks passed for source staging (10 checks), opening retry/payload conflicts, approved salary advance recovery, salary source exclusivity, canonical earned salary, assignment staff authority (3 checks), and atomic receiver lifecycle (12 checks). No business transactions from these replays were committed. The original receipt fixture failed on an unmapped historical worker; the valid-fixture selector now requires directory mapping and the orphan cohort remains an explicit unresolved data blocker.

Authoritative scenario matrix: **98 PASS, 10 FAIL, 5 BLOCKED, 19 NOT_RUN** of 132. Remaining gates include universal old-fixture reader/aggregate isolation (no dataset/workspace/rehearsal columns), approved real source and opening GL/stock/WIP evidence, historical mode/worker mappings, independent role/mobile/offline/concurrency proof, and exhaustive department financial journeys. No actual new source dataset has been supplied. Unknown balances and identities were not invented.

Evidence: `test71-fix-verification-20261011.json`, `test71-source-suite-evidence-20261011.json`, `test71-audit-scenario-matrix-20261010.json`.
