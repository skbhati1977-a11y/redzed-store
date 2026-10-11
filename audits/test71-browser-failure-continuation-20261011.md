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
