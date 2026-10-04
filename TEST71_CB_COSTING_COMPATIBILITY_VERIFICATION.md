# CB Art → downstream costing compatibility

2026-10-04. Scope: preserve the existing mapped costing rules after Art/Combo decisions moved into CB. No new costing model, payroll calculation, material quantity rule, margin, FOC or final-rate formula.

## Targeted changes

- Material Master is `real-material-master-v805.html`, BOM Mapping. CB now opens it with `view=costing-mapping` and a safe Back to CB link. The v853 compatibility URL retains query parameters and hash. App and Real Chat already open the same CB form, so they share this entry point.
- `rr_material_bom_apply_v662` now resolves the canonical category code through the existing lot-category authority instead of comparing a category display name against a saved category code. ALL category and saved per-piece quantities remain unchanged.
- Lot category uses the released lot's Art category identity; CB Set Art is a fallback for incomplete legacy identity. Existing lot snapshots are not overwritten.
- Current effective mapping selection excludes scheduled future rules and duplicate runtime rows while retaining distinct materials, methods, categories and departments. Historical mapping rows and posted costs remain. Repeated Save of the same scope/date leaves one active rule.
- Legacy BOM apply RPCs v657/v660/v661 delegate to v662. Legacy Worker/Direct pending and confirmation RPCs delegate to their current authorities. Quantity, weighted-rate and ledger calculations retain the existing bodies.
- Worker mapping reload resolves the Kaaj/Button department aliases.

## Executed evidence

- 43 linked CB/lot records audited: zero category mismatches.
- In one rollback transaction, all 43 existing lots retained base cost, final sale rate, salary, FOC, Printing, special-department, BOM and Packing cost values before versus after this migration.
- Nine existing rule/function definitions retained identical hashes: Gatta/Panni context, Gatta selection, BOM aggregate, Tape calculation, salary allocation, parent CB inheritance, product costing v703/v709 and final costing v691.
- Installed database proof passed: canonical category, ALL per-piece quantity, four BOM aliases, consumption idempotency, duplicate Save, effective Worker/Direct mapping, current pending compatibility and App/panel final-cost equality. All proof writes rolled back.
- Existing parent CB inheritance trigger checked on complete Sets through a temporary trigger fixture; inherited Art follows the CB assignment. Single and Multi production-table triggers were inspected and left intact.
- Five focused unit tests passed. Real Chat projection gate passed.
- Chromium browser with mocked authorization/RPC data verified actual source pages: v853 redirect, preserved view/hash/return, automatic BOM open, current rather than future Worker mapping, Kaaj alias, mobile modal and CB → Mapping → CB round trip. This is a route/form check, not an authenticated live worker workflow.
- Full static suite: 313 tests, 226 pass, 87 fail. Baseline: 308 tests, 221 pass, the same 87 failing names. Zero newly failing existing tests. This scoped fix is not a full TEST71 release certification.
- Supabase security advisors reviewed; the restricted internal effective-mapping helper is not listed.

Reproducible proofs: `tests/evidence/test71-cb-costing-rollback.sql`, `tests/evidence/test71-cb-costing-preservation.sql`, `tests/e2e/test71-cb-costing-compatibility.unit.test.js`, `tests/e2e/test71-cb-costing-browser.cjs`.

Database migration `test71_cb_costing_mapping_authority` applied successfully and the installed proof passed. Main/production Git branch is outside this change.
