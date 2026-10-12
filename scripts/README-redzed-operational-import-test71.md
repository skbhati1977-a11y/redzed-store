# Redzed legacy operational importer core (TEST71)

`redzed-operational-import-core.test71.cjs` is the controlled orchestration layer for the Clothing-to-CI operational import. It is separate from the existing review-only dataset intake.

## Import contract

- Input format: `redzed-ci-operational-import/v1`.
- Every row retains its module, source ID as text, raw source object, source timestamp where supplied, canonical mapped values, explicit classification, and source dependencies.
- Every module must have an explicit adapter. A ready adapter must name one `public.*` target table, declare `testModeOnly: true`, `writeMode: 'insert-only'`, and `sideEffectFree: true`, and implement source identity conflict lookup, insert, and read-back verification.
- The planner rejects duplicate source IDs, missing dependencies, dependency cycles, missing adapters, and unproven writer behavior. It emits parent rows before dependent rows.
- `DRY_RUN` is the default. It requires a repository transaction marked read-only and never calls row insert, identity-record, or row-log writes.
- `APPLY` requires `environment: 'TEST'` and a non-empty target backup reference. Each batch uses a rollback-capable repository transaction. Existing source IDs with the same payload are skipped; changed source payloads and target identity conflicts are held for review; no update/upsert path exists.
- New rows are returned as `IMPORTED_PENDING_VERIFY`. `verifyImportedRows` reads each mapped operational row and marks it verified only after the adapter confirms values.

## Adapter work still required

Module adapters and the CI repository implementation are intentionally not guessed. They must be based on authenticated source records, the approved field mapping, and the actual TEST operational RPC/table behavior. Historical sales, purchase, return, stock, and accounting rows must use side-effect-free import adapters that preserve history without triggering current postings. No database migration or operational write is performed by this core alone.
