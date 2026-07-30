REDZED UPM V721.00 — LOT-CENTRIC PATCH

FILES
1. REDZED_UPM_V721_LOT_CENTRIC_CORE.sql
2. real-universal-production-v721.html
3. real-universal-production-v721.js
4. redzed-upm-work-assignment-v9.js
5. redzed-alter-v6.js

INSTALL ORDER
1. Supabase SQL Editor: run REDZED_UPM_V721_LOT_CENTRIC_CORE.sql once.
2. Upload the four HTML/JS files to the same web folder as config.js, real-common.js and existing CSS files.
3. Open real-universal-production-v721.html.
4. Keep old V720 files until V721 is verified; this patch does not delete them.

LOCKED BEHAVIOUR
- Lot No is the hard parent identity.
- CB No, Art No, Print No, Art images and Print images remain bound to the lot.
- Every Lot Card has: Assign Work | Submit Work | Alter | Remake | Damage.
- The clicked card's canonical_lot_id is passed to the action; Lot cannot be changed inside the popup.
- Actual Rate is saved once through existing rr_upm_department_rates_v2 using Lot + Department.
- Assignment asks for worker; rate is auto-filled after first save.
- Alter mapping resolves from assignment first, then saved cutting map; it no longer asks the operator to create manual JSON mapping.
- Image thumbnails open a mobile-friendly swipe viewer.
- Quantity corrections are immutable verification transactions.
- Worker ledger and transfer tables are additive foundations for the next worker-reassignment UI.

IMPORTANT
Run existing base SQL migrations first if this database does not already contain:
rr_upm_lot_registry, rr_upm_department_rates_v2, rr_upm_work_assignments_v8,
rr_upm_lot_cut_size_map_v5 and Alter V4/V5 objects.
