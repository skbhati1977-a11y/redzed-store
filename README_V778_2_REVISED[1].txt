REDZED V778.2 REVISED — NET-MINUTE ATTENDANCE ENGINE

Run only this revised package. Do not run an older V778.2 draft.

INSTALL
1. REDZED_V778_2_REVISED_NET_MINUTE_ENGINE.sql
2. VERIFY_V778_2_REVISED.sql

LOCKED RULES
- L1 / L2 geofence
- Monday paid weekly holiday
- Manual paid holidays
- No 1.5 multiplier
- No OT multiplier
- No salary amount calculation in attendance
- Attendance output:
  net_deduction_minutes
  net_extra_work_minutes
  net_working_minutes

D/H/M DISPLAY
1 Day = 600 minutes = 10 hours
Hour remainder can only be 0 to 9.
255 min  -> 4 H 15 M
2415 min -> 4 D 15 M
2535 min -> 4 D 2 H 15 M

NEXT
V778.3 Attendance frontend and worker self-service details.
