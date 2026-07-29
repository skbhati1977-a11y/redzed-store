REDZED UNIVERSAL PRODUCTION — FINAL V4
======================================

THIS PACKAGE REPLACES THE UNUPLOADED OWNER/ADMIN FIX AND V3 WEB FILES.
Do not upload the old Owner/Admin fix separately.

FILES
-----
1. REDZED_UPM_FINAL_CONSOLIDATED_V4.sql
2. real-universal-production-v72040.html
3. real-universal-production-v72040.js
4. redzed-alter-v3.js
5. redzed-alter-v1.css

FINAL ALTER FORM
----------------
- Lot No is prominently highlighted.
- Colour is a dropdown populated from all colours attached to the selected Lot.
- Size is manual entry.
- Qty is manual entry.
- + Add Next Colour creates another Colour + Size + Qty row.
- Worker, Line Man, Department Head, Owner and Admin can register Alter according to SQL permissions.
- One live Fault Image is mandatory only while registering the Alter.
- No repair image is requested.
- No remake/damage action image is requested in this UI version.
- The original Alter fault image stays attached to the immutable Alter record.

INSTALL
-------
1. Take a Supabase backup.
2. Ensure the earlier base files have already been run:
   - REDZED_ALTER_REMAKE_DAMAGE_V1.sql
   - REDZED_UPM_SUBMIT_V2.sql
3. Run REDZED_UPM_FINAL_CONSOLIDATED_V4.sql in Supabase SQL Editor.
4. Replace these GitHub files:
   - real-universal-production-v72040.html
   - real-universal-production-v72040.js
   - redzed-alter-v1.css
5. Upload new file redzed-alter-v3.js.
6. The HTML loads redzed-alter-v3.js; old redzed-alter-v2.js is no longer needed.
7. Wait for GitHub Pages deployment and hard refresh with Ctrl + Shift + R.

TEST
----
1. Open a Lot with multiple colours.
2. Open Alter / Remake / Damage > Register Alter.
3. Confirm highlighted Lot No.
4. Confirm Colour dropdown contains all Lot colours.
5. Enter Size and Qty manually.
6. Add a second colour row and enter another Size and Qty.
7. Capture one live fault image.
8. Submit & Lock.
9. Confirm the Alter card shows both colour-size lines and the fault image.
10. Assign/submit repair and confirm no image is requested.
