# TEST71 import readiness — 2026-10-11

Decision: NOT CLEARED for new business-data import.

Continued the October 10 Accounts audit on branch test71-real-chat-e2e-finalization. Production/main has not been changed.

## Verified in this continuation
- Existing posted journals: 319; duplicate active source mappings: 0; unbalanced or fewer-than-two-line posted journals: 0.
- Opening balance exact retry preserves the original purchase; changing quantity, value or date under the same reference now raises an error.
- The opening retry verification used a transaction ending in ROLLBACK. No import business records were retained.
- Opening conflict guard source and rollback evidence are committed in sql/test71_opening_import_payload_conflict_guard.sql and tests/evidence/test71-opening-payload-conflict-20261011.sql.

## Remaining blockers
- Advance payment replay creates the worker advance but Accounts journal delta is zero.
- Individual salary payment Accounts bridge remains incomplete.
- Manual attendance save replay creates no canonical v777 payroll day.
- Completed-month payroll needs full effective-period attendance resolution, rather than merely at least one approved day.
- MC1 purchase v3 does not call the existing mode tag and Accounts mirror. Its current master UI directly calls v3 and falls back to v2. Existing untagged purchases must not be blindly backfilled.
- Universal opening batch approval, cutoff and source-evidence contract remain incomplete.
- Inventory/WIP/COGS and remaining role/mobile/module scenarios have not passed universal verification.
- A separate rehearsal database is absent. A new preview URL would still use the shared backend.

The user selected a different Supabase organization for the new TEST database. Only the redzed organization is currently available through the connection; the selected other organization's name/ID and access are needed before provisioning or importing there.

The eleven replay scripts executing successfully are not eleven universal passes: advance and manual-attendance evidence explicitly contains zero mapping deltas. The historical scenario matrix must not be marked universally passed based on these replays.
