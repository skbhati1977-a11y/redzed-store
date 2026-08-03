REDZED V778.1.1 — MULTI-LOCATION SECURE MANAGEMENT

INSTALL
=======
1. Run REDZED_V778_1_1_MULTI_LOCATION_SECURE_MANAGEMENT.sql
2. Run VERIFY_V778_1_1.sql

WORKER LOCATION ACCESS
======================
ALL_ACTIVE
- Worker may attend from any currently active premise.
- Future premises automatically become available.
- Best for workers who can move between all branches.

SELECTED_ONLY
- Owner/Admin selects one or more exact premises.
- Worker may attend only at those premises.
- Best for restricted workers.

FUTURE LOCATION MANAGEMENT
==========================
Owner/Admin uses secure RPC:
rr_save_attendance_premise_v778_1_1

Premises are never hard-deleted.
Use is_active=false to retire a location.
Historical attendance remains preserved.

MULTIPLE LOCATIONS
==================
The same worker can be assigned:
- Location 1
- Location 2
- any future Location 3/4/etc.

The geofence engine always matches the nearest allowed active premise.
