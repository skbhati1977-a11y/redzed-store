REAL FACTORY ACCOUNTS V8078 — FIELD-WISE + ADD NEW

BASE:
- Built directly from working V8075 exact-mapped frontend.
- Existing dropdown IDs and mapping loaders are preserved.

FIELD-WISE BUTTONS:
- Supplier / Party -> + Add Party
- Material Type -> + Add Type
- Material Name -> + Add Material
- Received From / Paid To -> + Add Ledger
- Cash / Bank -> + Add Cash/Bank

RULE:
1. Existing select remains primary.
2. + Add opens only that entity's form.
3. Check Existing performs spelling/similarity check.
4. Close match >=72% -> creation blocked, use existing.
5. No close match -> send approval request.
6. Super Admin approves/rejects in New Master Requests panel.
7. Approval creates the correct master. MATERIAL reuses V8076 material approval so source-managed material rules remain protected.

INSTALL:
1. V8076 approval SQL must already have been run (it was installed in the prior step).
2. Run 01_RUN_FIELDWISE_ADD_NEW_V8078.sql.
3. Replace BOTH real-accounts-v805.html + real-accounts-v805.js.
4. Do not replace dashboard/config.js/real-common.js.
5. Open real-accounts-v805.html?v=8078 and hard refresh once.
