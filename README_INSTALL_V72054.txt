REDZED ROLE & PERMISSION V720.54 — UNIFIED WORKER DIRECTORY

PURPOSE
- Login user created in Users & Access -> automatically appears in Worker Directory and UPM Assign Work (when active and department/role eligible).
- Manual worker added from Role & Permission or Assign Work -> appears in both places.
- Manual worker does not receive login access automatically.

INSTALL ORDER
1. Ensure REDZED_UPM_WORK_ASSIGNMENT_V8_3_UNIFIED_WORKER_DIRECTORY.sql is already installed.
2. Run REDZED_ROLE_PERMISSION_V72054_UNIFIED_WORKERS.sql in Supabase.
3. Upload both files to GitHub root:
   real-role-permission-v72054.html
   real-role-permission-v72054.js
4. Open /real-role-permission-v72054.html and Ctrl+F5.

IMPORTANT
- Keep the existing Edge Function rr-owner-user-admin for login creation/reset.
- Role Directory login access remains managed in Users & Access.
- Manual worker status is managed in Worker Directory.
