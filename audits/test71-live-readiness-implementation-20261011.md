# TEST71 live readiness implementation — 11 October 2026

**Operational business import is NOT CLEARED.** The previously missing isolated source-review backend and source-bound opening approval workflow are now applied, not merely offline tools.

- Separate TEST dataset create/stage/read and source-only totals never query legacy operational tables. New intake page: `test71-isolated-source-intake.html`.
- Approved opening plans require explicit cutoff, evidence, all financial classes, active master mappings, balanced GL and stock/WIP reconciliation. Shared posting remains closed until downstream dataset isolation is verified.
- Applied-schema targeted rollback evidence: 15 intake + 17 opening + 6 independent-run guard checks passed. No synthetic source or approval was committed.
- Thirty focused local identity/UI/role/cleanup checks passed. Actual six-role Auth verification then passed: 12 permission checks, all six logout/ban/inactive cleanup checks true. Mocked tests remain distinct from this live evidence.
- New source page fits mocked widths 360, 390 and700. Local runtime lacks Devanagari fonts; screenshot is not a real Android text-rendering certificate.
- MC1/CB/Material/Commercial/Factory receipt passed checkpoints are carried forward. Dedicated source migrations and financial identity changes run their own gate; they do not restart factory CI.

Security advisors reported expected RLS-without-policies INFO for private direct-denied tables, and authenticated SECURITY DEFINER WARN for explicitly guarded Admin RPCs. Direct table access and anonymous/worker RPC denial were separately exercised; no grants were loosened. References: [private RLS advisory](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [guarded RPC advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). Existing project-wide findings remain outside this targeted certificate.

Actual business opening source, complete operational reader/aggregate/writer isolation and browser financial/department journeys remain required. Production/main Git was unchanged; no production deployment was promoted. The shared backend received only new TEST-scoped objects.

## Synthetic run coordination correction
A root post-apply guard test was mistakenly executed without its required transaction wrapper and left two coordination-only records (no Auth users/profiles or journals). The dedicated CI guard correctly refused to proceed. Fresh counts proved Auth/profile fixture0. A targeted recorded migration preserved both original records/proofs/timestamps, appended reconciliation evidence and marked them RECONCILED; normal RUNNING/BLOCKED records still deny creation. The evidence script now contains explicit BEGIN/ROLLBACK. Six post-correction checks passed with no remaining synthetic records; only the failed independent-role job was rerun, with existing MC1/CB/factory checkpoints retained.

## Actual independent Auth result
Focused CI run38137072013, successful job114463398199, tested preview commit bf1a9110df91dc5d64855e1ca7e57aa71f069a9f: Worker, Line Manager, Manager and Sales correctly denied both financial RPCs; Admin and Accounts permitted both. Six distinct Auth sessions were created through Auth Admin, independently logged in and verified without Act As. [Sanitized live proof](test71-independent-financial-live-proof-20261011.json). Post-run database counts: six Auth fixtures preserved and banned, six profiles preserved and inactive/BLOCKED, zero Auth sessions, zero active/unbanned fixtures. Auth/profile triggers were inspected: no worker or ledger creation side effects.

Live intake HTML/JS exactly match source on the READY TEST preview. [Upload new source for isolated review](https://redzed-test65-eecuedwb8-skbhati1977-4414.vercel.app/test71-isolated-source-intake.html). This is approved-role source staging only, not clearance to use ordinary operational stock/financial forms with new business data.
