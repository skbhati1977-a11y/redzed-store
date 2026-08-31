# REAL FACTORY — CPI TO CI CANONICAL NAMING V9632

Status: IMPLEMENTED / COMPATIBILITY-SAFE
Date: 2026-08-31

## Locked naming
Customer/staff/business-facing term is now **CI** (Commercial Invoice). `CPI` is no longer a business-facing label.

## Database records
Migration `canonical_ci_records_compat_v9635`:
- Existing `rr_fg_pi_v787.status='CPI_FINAL'` records migrated to `CI_FINAL`.
- Existing invoice values `TCPI*` / `CPI*` migrated to `TCI*` / `CI*`.
- Existing stock ledger `CPI_SALE` / `CPI_LINE` records migrated to `CI_SALE` / `CI_LINE`.
- Existing linked accounts invoice numbers/messages normalized from CPI to CI.
- New compatibility trigger normalizes any legacy CPI_FINAL / CPI-number write to canonical CI values.
- Functions that read/write CPI_FINAL / CPI_SALE / CPI_LINE were compatibility-migrated to CI tokens.
- New canonical read view: `rr_fg_final_ci_v9632`.
- New canonical verify wrapper: `rr_fg_verify_ci_qty_v9632`.

Technical legacy object/column/function names containing `cpi` remain temporarily as compatibility identifiers so existing modules are not broken. Their stored business values and visible output are canonical CI. Do not remove those compatibility identifiers until all callers have been migrated and certified.

## Frontend
- Added `real-global-ci-label-v9632.js` to convert remaining legacy visible CPI/TCPI labels to CI/TCI without changing DOM IDs, RPC names or technical keys.
- `config.js` loads the CI label compatibility layer on current pages.
- Current Finished Goods UI directly says PI / CI, Final CI, Submit as CI, Refresh CI, Original CI.
- Finished Goods warning now matches inventory rule: PI freezes/reserves approved quantity; CI is the final invoice and stock deduction point.

## Verification
- Existing final PI records now use `CI_FINAL`.
- No old CPI/TCPI invoice-number values remain in `rr_fg_pi_v787`.
- No old CPI_SALE/CPI_LINE values remain in `rr_fg_stock_ledger_v787`.
- Canonical CI final view returns the existing final invoice records.

## Safety invariant
Rename business semantics and stored values first; preserve legacy technical identifiers only as a compatibility bridge. Never perform a blind schema-wide identifier rename that could break production callers.