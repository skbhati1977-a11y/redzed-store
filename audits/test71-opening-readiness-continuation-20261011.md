# TEST71 opening accounts continuation — 2026-10-11

Status: **BLOCKED_SOURCE_INPUT**. This is source readiness tooling, not approved accounting or import clearance.

Live read-only query confirmed `rr_import_batches_test71` has **0 batches**. No business opening source has been staged. Existing ledger/report balance checks cannot prove that absent opening quantities, liabilities or values are correct. No business data, approval, journal, staging batch or schema was written by this workstream.

`scripts/test71-opening-readiness.cjs` accepts a supplied JSON source and compares opening GL debit/credit using exact decimal cents, then independently reconciles physical STOCK and WIP values to their explicitly approved ledger mappings. It rejects unknown openings, false zero, invalid dates, cutoff differences, unapproved mappings and missing STOCK/WIP coverage. Explicit not-applicable evidence is required for absent STOCK/WIP; blank coverage stays pending. Its output always says `cleared_for_import:false` and `business_records_posted:0`, including for a synthetically balanced source.

Usage: `node scripts/test71-opening-readiness.cjs source.json`. Required envelope fields: `source_ref`, `source_sha256`, `approved_cutoff`, `approval_evidence_ref`, `approved_ledger_mapping`, `rows`; absent inventory classes require `not_applicable_evidence`. Rows use the existing staging shape: `module`, `source_key`, `record_date`, `evidence_status`, `values`. Ledger mapping values STOCK/WIP select valuation classes; other mappings remain part of GL balance only. Local approval references are input evidence to verify, not proof of authorization. This tool does not independently verify source bytes against the claimed SHA256 or resolve master identities against the live database.

Focused validation: **12/12 tests passed**, using synthetic data only. Cases cover balanced-but-unapproved source, physical valuation mismatch despite balanced GL, UNKNOWN/false ZERO, missing actual source/approved mappings, invalid date/cutoff and missing WIP coverage, malformed source rows/CLI JSON, whitespace inputs, exact tiny nonzero quantities, invalid evidence states and negative valuation formatting. Passed MC1, CB and factory suites were not replayed.

Needed to complete the business opening gate:

- Actual opening CSV/Sheet/export and its stable source reference; preserve the original file for SHA256 verification.
- Explicit business-approved opening cutoff and approval evidence identifying who approved which source version.
- Complete ledger debit/credit opening schedule: Cash/Bank, customer/supplier dues, worker advances, salary/claim liabilities, inventory/WIP, other assets/liabilities and balancing equity as applicable. Unknown entries remain pending; explicit zero and not-applicable need source evidence.
- Physical item/lot quantities, units and valuation evidence, including WIP stage/value, with approved master and inventory/WIP ledger mapping. No guessed rates.
- Reader/aggregate archive isolation, authorized posting and source-to-journal reconciliation; independent role acceptance remains a separate gate.

No universal source coverage or accounting approval is claimed. Production/main Git was unchanged.
