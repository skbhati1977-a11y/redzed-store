REDZED ROLE & PERMISSION V773 — UI CONTROL UPGRADE

DEPENDENCIES
============
V769.1 installed
V771 installed
V772 installed

WORKER DIRECTORY
================
Each Worker card now shows:
- Device Mode
- Receive Auth Mode
- Identity readiness
- Linked Login
- Active Witness

New button:
Device / Login / Witness

SMARTPHONE:
- Explicit active Login User selection
- rr_set_worker_device_mode_v770
- rr_link_worker_login_v770
- optional explicit unlink

BASIC_PHONE / NO_PHONE:
- Explicit Self-Login Witness selection
- rr_assign_worker_witness_v770

No mobile auto-linking.

USERS & ACCESS
==============
OWNER card:
- Highest-role badge
- All security controls hidden
- Password reset hidden
- Protected notice

ADMIN card:
- Admin actor sees no Admin security buttons
- Owner actor sees:
  Block Admin
  Activate Admin
  Deactivate Admin
  Reset Admin Password

Owner status action uses:
rr_owner_set_admin_status_v772

Existing Edge Function is called only to sync auth-session access after
database approval. Database V772 remains final profile authority.

INSTALL
=======
Upload to GitHub root:

real-role-permission-v773.html
real-role-permission-v773.js

Open:
real-role-permission-v773.html

Or rename both to the existing V72054 filenames after backup.

Ctrl + Shift + R

EXPECTED CONSOLE
================
window.REDZED_ROLE_PERMISSION_VERSION
→ 773.0.0
