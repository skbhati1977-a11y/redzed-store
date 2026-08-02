REDZED ROLE & PERMISSION V773.1 — WITNESS DROPDOWN FIX

ROOT CAUSE
==========
V773 allowed Witness candidates only when:

identity_status = LINKED_SELF_LOGIN

Existing Role Directory Owner/Worker may already have linked_auth_user_id,
while Device Mode has not yet been configured. Such a valid active login-linked
worker was incorrectly hidden.

FIXED ELIGIBILITY
=================
Witness dropdown now shows a Worker when:

- Worker is active
- access_status is ACTIVE
- Worker is not the same physical receiver
- linked_auth_user_id exists in either:
  rr_worker_identity_board_v770
  OR current unified Worker row
- that auth user is an active Login User

No mobile-number matching is used.

SECURITY
========
This UI fix does not bypass backend verification.

rr_assign_worker_witness_v770 / v768 still validates:
- active Worker
- active Login link
- active lifecycle
- explicit Owner/Admin assignment

INSTALL
=======
Upload:

real-role-permission-v773-1.html
real-role-permission-v773-1.js

Open:
real-role-permission-v773-1.html

Ctrl + Shift + R

Expected console:
window.REDZED_ROLE_PERMISSION_VERSION
→ 773.1.0
