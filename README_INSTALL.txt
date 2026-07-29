REDZED ERP — ALTER / REMAKE / DAMAGE V1

WHAT IS INCLUDED
1. REDZED_ALTER_REMAKE_DAMAGE_V1.sql
2. redzed-alter-v1.js
3. redzed-alter-v1.css
4. INTEGRATION_SNIPPET.html

FINAL FLOW IMPLEMENTED
- Worker or Department Head registers Alter.
- Worker self-registration binds himself and assigned Line Man/Cutting Master.
- Alter requires Colour, Size, Qty and live-camera image.
- Original Alter and evidence are locked after submit.
- Every Alter gets a unique ALT code.
- Cutting Master issues Remake only against that Alter, colour-size wise.
- Department Head registers/edits Damage only against that Alter, colour-size wise.
- Remake + Damage cannot exceed Alter quantity per colour-size.
- Pending balance is auto-calculated.
- Department Head controls status; CLOSED is blocked while pending > 0.
- All images show as thumbnails and open full-screen with arrows/swipe-compatible browser viewer.
- Evidence bucket is private; UI uses signed URLs.

INSTALL ORDER
1. Back up Supabase.
2. Run REDZED_ALTER_REMAKE_DAMAGE_V1.sql in Supabase SQL Editor.
3. Upload JS and CSS beside your Universal Production page.
4. Add INTEGRATION_SNIPPET.html content to the Lot detail view.
5. Map CURRENT_* placeholders to your actual logged-in user and lot variables.
6. Ensure the role is present in JWT app_metadata.role or user_metadata.role.

ROLE VALUES
WORKER
DEPARTMENT_HEAD
CUTTING_MASTER
ADMIN
OWNER

IMPORTANT INTEGRATION NOTE
This package is a clean add-on because the complete current Universal Production HTML/JS source was not present in the supplied files. The only manual work is mapping your existing variable names in INTEGRATION_SNIPPET.html. Database and workflow logic are complete.

TEST ORDER
1. Login as Worker and register 3 PCS in multiple colour-size rows with camera image.
2. Confirm card shows ALTER total, names, status, Remake, Damage and Balance.
3. Login as Cutting Master and issue a partial colour-size remake.
4. Login as Department Head and add colour-size Damage with fault worker/reason/evidence.
5. Verify Remake + Damage cannot exceed the original Alter line.
6. Click every thumbnail; confirm full-screen image opens.
7. Try closing while Balance > 0; it must fail.
8. Settle remaining quantity and close.
