# TEST71 browser failure continuation — 2026-10-11

Full clean chit: **NOT CLEARED**. Production/main unchanged.

Run 38117590903 completed: MC1 passed; CB department, material unit,
commercial checkpoint and full factory failed. Failures are retained.

Targeted corrections:
- Material Unit browser test now uses the current progressive additional-material
  button and container. The retired global Add Material selector caused its timeout.
- Mobile CB browser test verifies normal-flow save actions, matching the existing
  application and its uppercase/layout contract. No form redesign was made.
- Eight TEST-only proof functions use the existing v601 batched save wrapper;
  signatures, grants and rollback assertions are preserved. Migration applied as
  20261011064158_test71_cb_proofs_current_save_path; database check confirms all eight.

Verification: 55 related source tests pass; both edited browser files parse;
git diff has no whitespace errors. Rollback diagnostic of the basic CB proof with
the v601 route passed Draft/Confirm/DUE completion, duplicate protection and
persisted=false. This is SQL request-claim simulation, not an independent browser login.

Remaining failures:
- Art proof still performs expensive global chat reconciliation while refreshing
  derived material requirements. An own diagnostic was cancelled after exceeding
  a minute; its transaction was rolled back. No blocked/idle transaction remained.
- Released D-card proof reports rr_cb_units_cb_code_key collision.
- Historical mobile Cutting cards and full-factory Stitching accept card were absent.
- Browser rerun required for the corrected tests; source tests do not certify them.
- Archive/aggregate separation, approved real openings, four historical test 03
  lots' costing, independent role sessions and complete department journeys remain.

No opening balances, business purchases or payments were invented. No old records
were deleted or moved to manufacture a pass.

## Continuation at 12:40 IST

Run 38119117716 on 072834: MC1 success; CB 7 passed/7 failed;
Material Unit failed on hidden additional-material UI; commercial 5 passed/2 failed;
full factory failed. The progressive button correction above was insufficient:
manual additional materials are intentionally retired. The current test now creates
and reloads Units/Materials through Material Master and retains CB backend invariants.

Applied 20261011065351: unchanged TEST OPEN Cutting cards avoid repeat updates;
release proof locks its existing TEST parent and uses the next canonical division;
released/unassigned lots assert WORKING/ASSIGN_WORKER under v632. A rollback check
confirmed normalized OPEN state and zero repeat normalization. Related 11 checks pass.

Applied 20261011070325: exact unchanged TEST CB projection upserts and Art receiver
bindings avoid repeat writes; REAL behavior is preserved. Experimental combined
D-card rollback proof passed in 19 seconds, once-only release, blocked retry/cross-mode,
zero residue. Post-apply repetition timed out at another trigger: this is NOT a stable
performance pass. Art rollback proof also timed out in child reconciliation.

Notification focus now resolves read notifications through loaded action history,
not just unread inbox, preserving department/worker/status checks. Consolidated event
matching precedes CB fallback; an exact UPM assignment never falls back to another
card sharing CB/lot. Ten notification tests pass including group/personal exact
focus and unrelated-worker rejection. Full local suite: 522 pass before the final
fallback-order change; notification suite rerun after it passes. Preview/mobile tap
verification is still required; local DOM checks do not establish physical push delivery.

No opening balances were invented, history deleted, security grants broadened,
production deployed or main changed. Full clean chit remains NOT CLEARED.
