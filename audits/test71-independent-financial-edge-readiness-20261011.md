# TEST71 independent Auth financial verification readiness

A bounded Supabase Edge function is prepared for actual independent password-authenticated financial authority checks. It accepts only the existing dedicated E2E Super Admin UID, verifies Auth user plus active profile and canonical independent identity, and creates exactly six new fixture actors in its server-only runtime. No caller-selected identities, credentials, roles or business operations are accepted.

The private run guard prevents overlapping fixture runs, caches completed proof for ten minutes, and permanently blocks subsequent creation after ambiguous Auth creation/login or incomplete cleanup until reconciliation. New Auth actors are marked through server-controlled app metadata. Profile creation uses the real Super Admin JWT and existing RLS/OWNER guard. Each actor's own Auth session and profile/effective identity are checked before TEST trial balance and Accounts OPEN reads. Exact Accounts P0001 permission exception is accepted only for that known RPC; generic errors never count as authorization denial.

Cleanup verifies fixture identity, signs out, bans only newly created Auth users with readback, and deactivates/readbacks only their profiles. Auth users and inactive profile history remain as explicit fixtures. Ambiguous creation/login stops expansion and records a blocked run. No passwords, service keys, sessions, private report payloads or arbitrary user records appear in proof output.

Verified before deployment:

- 10 mocked Edge security/lifecycle checks passed.
- 4 mocked CI runner checks passed.
- 7 focused credential-runner checks passed.
- 6 new run-guard SQL checks passed inside BEGIN/ROLLBACK; schema and fixture changes were rolled back.
- Fresh catalog inspection found no noninternal Auth.users triggers. Profile triggers only assign username, enforce OWNER/Admin protection and update timestamp; none provision workers/ledgers.
- Initial Auth count in exact `test71-financial-%@realfactory.invalid` namespace was zero.
- Live catalog confirmed lowercase role codes and RPC signatures. Finance RPC inspected bodies only read financial data.

At this checkpoint, live deployment and actual six-session execution are pending root review. Local mocks and SQL claims are not independent authenticated financial clearance. Approved opening values, historical isolation and full financial transaction/browser journeys remain separate gates.
