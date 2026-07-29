REDZED USER ADMIN V720.38 — INSTALL ORDER

FILES
1. REDZED_USER_ADMIN_V72038.sql
2. supabase/functions/rr-owner-user-admin/index.ts
3. real-role-permission-v72038.html
4. real-role-permission-v72038.js

STEP 1 — DATABASE
Open Supabase Dashboard > SQL Editor.
Run REDZED_USER_ADMIN_V72038.sql once.

STEP 2 — EDGE FUNCTION
Using Supabase CLI from your project folder:

  supabase login
  supabase link --project-ref hruartsemierwhtzonei
  supabase functions deploy rr-owner-user-admin

The standard SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY
function secrets are supplied by Supabase. Never place service_role in HTML/JS.

STEP 3 — FRONTEND
Upload these files beside config.js and real-common.js:

  real-role-permission-v72038.html
  real-role-permission-v72038.js

Open:
  /redzed-store/real-role-permission-v72038.html

STEP 4 — DASHBOARD LINK
In real-dashboard-v720372.html change:

  real-role-permission-v72037.html?v=720372

to:

  real-role-permission-v72038.html?v=720380

STEP 5 — TEST
A. Login as owner/admin.
B. Open Users & Access.
C. Confirm email, Auth User ID, Profile ID, last login and created date appear.
D. Create a test user with a temporary password of 8+ characters.
E. Login as the test user.
F. Block the user and confirm future authentication/app access is rejected.
G. Activate the user again.
H. Reset the temporary password and test login.
I. Check rr_user_admin_audit_v1 for audit rows.

SECURITY NOTES
- Existing passwords are never readable or returned.
- service_role stays only inside the Edge Function.
- Owner/Admin authorization is checked server-side.
- The code blocks self-deactivation/self-archive.
- Keep at least two owner accounts before testing access blocking.
