# Isolated TEST source intake implemented

Migration: `supabase/migrations/20261011114419_test71_isolated_source_dataset.sql`.

The implementation gives new source data a separate, durable dataset namespace in the existing TEST database. It creates new dataset/batch/row/finding tables; it does not add labels to or relocate old MC1, CB, lot, salary or accounting records. Dataset status is restricted to DRAFT; no function can activate operational posting. Existing business readers and original staging functions remain unchanged.

Authorized Owner/Admin/Super Admin users create a named dataset and stage up to 10,000 rows within 10MB. A source reference and SHA-256 identify the source version; request/source retry keys are scoped to the dataset. Identical retries return the same batch; changed payloads require a new version. The SHA-256 is supplied source provenance, not proof of external source approval. The full JSON payload is also compared for retry conflicts.

`rr_dataset_import_report_test71(dataset,batch)` requires that the batch belongs to the requested dataset. It returns only that batch's rows, findings, dates and source-review opening totals. Invalid/unknown values are excluded from totals and remain unresolved rather than becoming zero. Numeric NaN/Infinity are rejected before casting. Stock/WIP totals are grouped by module and unit; they are source values, not current stock balances or an approved ledger posting.

All new tables enable RLS and deny direct PUBLIC/anon/authenticated access. Exposed RPCs require the existing server-side import Admin identity assertion and TEST mode assertion. No user metadata authorization, permission widening, legacy record classification, history deletion, trigger disabling or shared business posting is introduced.

Focused live transaction validation ran the migration plus evidence inside BEGIN/ROLLBACK: **15 checks passed**. Evidence file: `tests/evidence/test71-isolated-source-dataset-rollback-20261011.sql`. Coverage includes independent dataset source keys, retry/conflict guards, cross-dataset denial, scoped source totals, UNKNOWN/NaN handling, null identifiers/date/reference findings, Worker/anonymous denial and direct table closure. Original staging batch and account transaction counts stayed unchanged. The transaction committed no fixtures or migration objects; persisted deployment is handled by the root after combined opening validation.

This solves safe source entry and review without mixing legacy fixtures. It does not certify operational dataset isolation in the existing MC1/CB/manufacturing/payroll/report flows. Historical untagged rows remain ambiguous; active stock and balance readers still need a complete scoped business path before operational release. Approved actual opening figures/source mappings are business inputs and cannot be manufactured.

Live application checkpoint: migration is now applied and recorded. Focused evidence was then replayed against the applied schema inside ROLLBACK; no synthetic source or approval remains. Actual source datasets/batches/approvals remain zero.
