REDZED Universal Production V769
Worker Claim Reason + Warning Gate + Alter/Remake-to-Damage

WHAT IS FIXED
-------------
1. V768 Damage balance fix stays active:
   PENDING is current worker/state hold, not global Good Qty.
2. WORKER CLAIM now has its own mandatory searchable reason dropdown.
3. NO CLAIM keeps its existing mandatory searchable reason dropdown.
4. Worker Claim reasons include:
   - Making Fault
   - Stitching Center Out
   - Short Receive
   - Short Submit
   - Wrong Size / Colour Mixing
   - Quality Reject
   - Physical Piece Lost
   - Alter not completed before Dispatch
   - Remake not completed before Dispatch
   - No Response within 24 Hours
   - Other Worker Fault
5. No Response within 24 Hours rule:
   - Attempt 1 records Warning 1; Damage save is blocked.
   - Attempt 2 records Warning 2; Damage save is blocked.
   - Attempt 3 before 24 hours is blocked and shows remaining hours.
   - Attempt 3 after 24 hours shows final alert and allows ALTER hold to save as Worker Claim Damage.
6. Alter not completed before Dispatch:
   - Requires 2 warnings.
   - Third attempt allows ALTER hold to save as Worker Claim Damage.
7. Remake not completed before Dispatch:
   - Requires 2 warnings.
   - Third attempt allows REMAKE hold to save as Worker Claim Damage.
8. Existing responsibility feature is not changed.
   The existing backend source-bucket and holder responsibility remain authoritative.
9. Existing rr_upm_save_damage_v731 stays unchanged and performs the final Damage save.

INSTALL ORDER
-------------
A. Supabase SQL Editor
Run once:
REDZED_V769_WORKER_CLAIM_WARNING_GATE.sql

B. GitHub repository root
Upload/replace:
- real-universal-production-v729.html               (replace current page)
- real-universal-production-v769.html               (new versioned page)
- real-universal-production-v767-alter-evidence-fix.js
- real-universal-production-v768-damage-balance-fix.js
- real-universal-production-v769-worker-claim-warning-fix.js

Do not run any rollback SQL.

OPEN AFTER COMMIT
-----------------
Current/replacement link:
https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v729.html?v=7691

New versioned link:
https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v769.html?v=7691

Press Ctrl + F5 once after GitHub Pages updates.

IMPORTANT TEST
--------------
For No Response within 24 Hours:
- Select WORKER CLAIM.
- Select No Response within 24 Hours.
- Select source ALTER only.
- First Save = Warning 1 only.
- Second Save = Warning 2 only.
- Third Save before 24 hours = blocked with remaining-time alert.
- After 24 hours = final alert, then existing Damage engine registers ALTER balance as Damage.
