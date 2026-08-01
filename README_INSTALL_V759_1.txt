REDZED UPM V759.1 — DAMAGE ENGINE + NO-CLAIM DAMAGE

IMPORTANT
=========
Do not install the older V759 package.
Install only V759.1.

DAMAGE MODES
============
1. WORKER CLAIM
   - Physical Damage registered
   - Damage Rate Upto This Stage frozen
   - Worker Ledger financial claim posted
   - Gross Claim recorded

2. NO CLAIM
   - Physical Damage registered
   - Production/Inventory balance reduced
   - Damage Rate Upto This Stage frozen
   - Factory Loss recorded
   - No worker financial recovery
   - Responsible Worker remains null
   - Reason is mandatory

NO-CLAIM REASONS
================
- Fabric / Cloth Defect
- Cutting Defect · No Identified Responsibility
- Machine / Technical Issue
- Natural Process Loss
- Unknown Cause
- Owner Approved · No Responsibility
- Other No-Claim Damage

EXISTING ARCHITECTURE
=====================
No parallel Worker Ledger is created.

Uses:
- rr_upm_save_damage_v731
- rr_upm_actions_v726
- rr_upm_entries
- rr_upm_worker_ledger_v726 view
- existing quantity balances
- existing cost snapshot logic

INSTALL
=======
1. Run:
   REDZED_UPM_V759_1_DAMAGE_ENGINE_NO_CLAIM.sql

2. Upload:
   real-universal-production-v7591-damage-engine.js

3. Remove previous V757/V759 patch script line.

4. HTML:
   <script src="real-universal-production-v7591-damage-engine.js?v=7591"></script>

5. Commit, wait for deployment, then Ctrl + Shift + R.

EXPECTED SQL RESULT
===================
ok = true
version = V759_1_DAMAGE_ENGINE_NO_CLAIM

EXPECTED CONSOLE
================
V759_1_DAMAGE_ENGINE_NO_CLAIM_UI
