# TEST71 health recovery — 11 October 2026

Full clean chit remains **NOT CLEARED**. This checkpoint restores service health and addresses the next observed CB failures; it does not approve new business-data imports.

The user authorized health repair after the fast database reboot failed to restore reliable service. A full project restart was performed. PostgreSQL restarted at `2026-10-11 09:08:59.59377+00`; subsequent SQL probes succeeded. The dashboard then reported Database, PostgREST, Auth, Realtime, Storage and Edge Functions all Healthy. Actual TEST Super Admin authentication succeeded in the CB, Material Unit and Commercial jobs. This is observed recovery, not a guarantee against future resource pressure.

The preceding live run at `73ca4de683f0f3475a2005c782d26f4ae4af024f`, run `38126709321` attempt 2, passed 13 of 14 CB scenarios. Its remaining CB failure was mobile document overflow (515/518px at a 390px viewport). A CSS change wraps the CB header and allows long identifiers to wrap. Chromium reproduced the old header overflow; the corrected page stayed within 360, 390, 700 and 960px viewports.

An independent rollback-only CB Art replay timed out in legacy global lifecycle reconciliation. The existing TEST-only Art batch now scopes that reconciliation to the authoritative purchase and its related Cutting lots. Unscoped calls, including the REAL path, retain their original predicates. Ownership, grants, security-definer status, search path, timeouts, authority gates and all triggers remain unchanged. The migration was applied directly with `execute_sql`; this did not create a remote migration-history entry. The committed idempotent migration retains the change for future deployments.

Before applying the change, transactional candidate checks passed for partial Art decisions, retry identity, complete Art decisions, parent CLOSE, independent Cutting HOLD/READY, and zero fixture residue. Applying the migration twice succeeded. A nonexistent purchase scope produced no bridge-row updates, verified by comparing every existing row's tuple identity. ACL and function-configuration equality were checked during application.

The Material Unit live failure used retired `materials[]` renderer input. The updated check exercises the canonical `quantity` / `quantity_unit` caption; shared additional-material mapping, persistence and Worker denial remain in the same scenario. The commercial historical-card check expected an obsolete RELEASED button after production assignment. It now independently verifies backend RELEASED/CLOSE/assigned state and the disabled CUTTING CLOSE and HISTORY ONLY controls before and after reload. No business state was changed to satisfy these checks.

Local regression: 536 static checks passed without skips. Notification focus: 12 targeted behavioral checks passed. Security and performance advisors were retrieved; existing advisory findings remain outside this targeted change and prevent treating health recovery as universal security approval.

Remaining evidence: rerun the complete live workflow at the new exact commit. Approved real opening balances, historical worker/mode mappings, universal fixture isolation and the remaining role/mobile/offline/concurrency financial scenarios still require their own evidence.

## Forward continuation after passed checkpoints

- Run 38128366128 retained successful MC1, CB Department and Material Unit live gates. No rerun requested for these modules.
- Actual commercial-directory defect: the V708 empty-card observer mistook department navigation for an empty operational queue and erased Group/Worker buttons. Guard department/division views; three behavioral tests pass.
- Factory receipt projection independently returns CONFIRM_RECEIVED_PCS for both pending assignments of TEST71-MUE2Y0Z2-8GDH5. Failure screenshot shows STAFF selected while WORKER has nine pending cards. Resume through visible WORKER / ASSIGNED RECEIPT controls, retaining UI accept and canonical status assertions.
- Cutting CLOSED tabs were removed by the established interface. Verify released E2E-CB-3 through its supported focused CB read-only history route, preserving backend release-history, canonical lifecycle and disabled-action checks.
- Workflow defaults to remaining gates only; explicit manual scope=all retains full regression option. Prior passed checkpoints are carried forward rather than recreated.
- Deployed verification of these continuation changes remains pending at commit time. Universal clean chit is not claimed.

- Deployed commit 0bea7e1803165530bbe0b430959feb8bdf80b0d5: both formerly failing Commercial checks PASS in run 38131480113/job114446535965. Directory guard is HTTP200 and byte-identical to the committed asset.
- Factory trace at that commit confirms the pending target card, both colours (6 PCS total), and visible ACCEPT & COUNT button in WORKER / ASSIGNED RECEIPT. The remaining assertion expected a retired anchor/iframe; the production interface uses data-receipt-accept and the inline receipt-count overlay. Adapt the test to visible controls, asserting one card, all colour counts, exact expected PCS total, popup closure and canonical assignment transition.
- Next continuation runs factory only; passed Commercial evidence is retained alongside earlier MC1/CB/Material results.
