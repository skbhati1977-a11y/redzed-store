# TEST71 health recovery — 11 October 2026

Full clean chit remains **NOT CLEARED**. This checkpoint restores service health and addresses the next observed CB failures; it does not approve new business-data imports.

The user authorized health repair after the fast database reboot failed to restore reliable service. A full project restart was performed. PostgreSQL restarted at `2026-10-11 09:08:59.59377+00`; subsequent SQL probes succeeded. The dashboard then reported Database, PostgREST, Auth, Realtime, Storage and Edge Functions all Healthy. Actual TEST Super Admin authentication succeeded in the CB, Material Unit and Commercial jobs. This is observed recovery, not a guarantee against future resource pressure.

The preceding live run at `73ca4de683f0f3475a2005c782d26f4ae4af024f`, run `38126709321` attempt 2, passed 13 of 14 CB scenarios. Its remaining CB failure was mobile document overflow (515/518px at a 390px viewport). A CSS change wraps the CB header and allows long identifiers to wrap. Chromium reproduced the old header overflow; the corrected page stayed within 360, 390, 700 and 960px viewports.

An independent rollback-only CB Art replay timed out in legacy global lifecycle reconciliation. The existing TEST-only Art batch now scopes that reconciliation to the authoritative purchase and its related Cutting lots. Unscoped calls, including the REAL path, retain their original predicates. Ownership, grants, security-definer status, search path, timeouts, authority gates and all triggers remain unchanged. The migration was applied directly with `execute_sql`; this did not create a remote migration-history entry. The committed idempotent migration retains the change for future deployments.

Before applying the change, transactional candidate checks passed for partial Art decisions, retry identity, complete Art decisions, parent CLOSE, independent Cutting HOLD/READY, and zero fixture residue. Applying the migration twice succeeded. A nonexistent purchase scope produced no bridge-row updates, verified by comparing every existing row's tuple identity. ACL and function-configuration equality were checked during application.

The Material Unit live failure used retired `materials[]` renderer input. The updated check exercises the canonical `quantity` / `quantity_unit` caption; shared additional-material mapping, persistence and Worker denial remain in the same scenario. The commercial historical-card check expected an obsolete RELEASED button after production assignment. It now independently verifies backend RELEASED/CLOSE/assigned state and the disabled CUTTING CLOSE and HISTORY ONLY controls before and after reload. No business state was changed to satisfy these checks.

Local regression: 536 static checks passed without skips. Notification focus: 12 targeted behavioral checks passed. Security and performance advisors were retrieved; existing advisory findings remain outside this targeted change and prevent treating health recovery as universal security approval.

Remaining evidence: rerun the complete live workflow at the new exact commit. Approved real opening balances, historical worker/mode mappings, universal fixture isolation and the remaining role/mobile/offline/concurrency financial scenarios still require their own evidence.
