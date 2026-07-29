REDZED UPM V7 FINAL MOUNT

FINAL RULE:
- Existing working flow is not rewritten.
- Cloth Manager enters CB.
- Owner assigns Art and Print.
- Existing Cutting Module receives mapping.
- Cutting Master generates/releases Lot No.
- From Cutting onward, Lot No is permanent identity.
- Existing Submit, Alter, Repair, Damage, Remake, Rate, Reversal and Audit remain unchanged.

INSTALL:
1. Backup Supabase.
2. Run REDZED_UPM_V7_FINAL_MOUNT.sql.
3. Upload:
   - real-universal-production-v72040-mounted.html
   - redzed-upm-v7-final-mount.js
   - real-dashboard-v720372-upm.html
4. Keep existing real-cutting-master.html and real-universal-production-v72040.html unchanged.
5. Open the new dashboard and test Universal Production.
6. Hard refresh.

IMAGE NOTE:
PTST9 currently has artwork_url and garment_preview_url as NULL.
Therefore no image will display until Print Master contains those URLs.

VENDOR BILL NOTE:
External vendor Alter/Damage/Repair requires mandatory Vendor Bill No.
Not added in this patch to avoid disturbing current focus and flow.
