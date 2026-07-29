REDZED UNIVERSAL PRODUCTION V2 — INSTALL ORDER

1. Take a Supabase backup / use a test project.
2. Confirm REDZED_ALTER_REMAKE_DAMAGE_V1.sql has already run successfully.
3. Run REDZED_UPM_SUBMIT_V2.sql in Supabase SQL Editor.
4. Populate public.rr_user_assignments_v2 for every production user.
   User category and department are locked from this table.
5. Upload/replace these four web files in the same GitHub folder:
   - real-universal-production-v72040.html
   - real-universal-production-v72040.js
   - redzed-alter-v1.js
   - redzed-alter-v1.css
6. Commit and hard refresh the page.

FINAL BUSINESS RULES INCLUDED
- Worker / Department Head can register Alter.
- Remake and Damage are always against the same Alter ID, colour-size wise.
- Damage is controlled only by Department Head.
- Cutting Master issues remake only.
- Production Submit has no Reject option and no manual quantity field.
- Cutting Qty, Alter, Remake, Damage, Pending and Submit Ready Qty are fetched/calculated.
- Actual Rate is filled only by the assigned Department Head (Owner/Admin override).
- Worker cannot submit until rate exists.
- Printer/Stitching require at least one camera work image.
- Work image is bound to submit ID, Lot, Department, Colour, Size, user and timestamp.
- Submit posts approved quantity as GOOD through existing rr_upm_post_entry_v1.
- User ID, category and department are taken from locked rr_user_assignments_v2.

IMPORTANT DATA SETUP
The application cannot guess user UUIDs. Add each user to rr_user_assignments_v2.
Example SQL is included at the end of REDZED_UPM_SUBMIT_V2.sql.

NOTE ABOUT CAMERA
HTML uses capture="environment" and disables ordinary quantity editing. Browser/phone behaviour can vary; on supported mobile browsers it opens the rear camera. Server records the uploaded evidence as live-capture evidence.
