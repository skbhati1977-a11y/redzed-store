REDZED ROLE & PERMISSION V774.4

FRONTEND-ONLY FIX — NO SQL REQUIRED

Problem:
SMARTPHONE was blocked when no unlinked Login User existed, even though
Development Test Phone Mode was enabled.

New rule:
- SMARTPHONE + Login selected:
  Real Self Login link saves normally.

- SMARTPHONE + no Login + Test Phone enabled:
  Save is allowed for development.
  Real identity remains LINK PENDING.
  Test communication may route through V775 to 8368849128.

- SMARTPHONE + no Login + Test Phone disabled:
  Save remains blocked.

Security unchanged:
Real/production SMARTPHONE communication still requires a unique real mobile
and active linked Self Login. Owner login cannot be reused.

Upload:
real-role-permission-v774-4.html
real-role-permission-v774-4.js

Expected:
window.REDZED_ROLE_PERMISSION_VERSION
→ 774.4.0
