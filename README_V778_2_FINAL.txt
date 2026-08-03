REDZED V778.2 FINAL — ATTENDANCE + LEAVE + WORK-PROOF OT CORE

IMPORTANT
=========
Do not run the earlier draft V778.2.
This package supersedes it.

INSTALL
=======
1. Run REDZED_V778_2_FINAL_ATTENDANCE_LEAVE_OT_CORE.sql
2. Run VERIFY_V778_2_FINAL.sql

REGULAR SALARIED ATTENDANCE
===========================
- Check-In outside geofence: blocked
- Check-Out inside geofence: valid
- Outside-geofence Check-Out:
  first 4/month accepted
  ₹50 proposed penalty event each time
  fifth+ blocked
- 10:10 Check-In reminder
- 8:10 Check-Out reminder
- repeat reminder every 15 minutes
- forgotten Check-Out = OT hard zero

TIME-BASED SALARY
=================
Positive minutes:
- Early Check-In before 10:00
- Verified OT
- Verified Holiday work

Negative minutes:
- Late Check-In after 10:10
- Early Check-Out before 8:00

Final salary:
Base Monthly Salary
+ Net Minutes × Per-Minute Rate
- Claims
+ Incentives

OT / HOLIDAY WORK
=================
SALARIED workers only.

OT Start video:
- live camera only
- 10–30 seconds
- inside geofence
- GPS and server timestamp

OT End video:
- live camera only
- 10–45 seconds
- inside geofence
- GPS and server timestamp

Holiday work uses OT CHECK-IN / OT CHECK-OUT buttons.
Holiday rate multiplier = 1.0, not 1.5.

LEAVE
=====
- Simple worker message
- Owner/Admin approval
- Approved leave suppresses attendance reminders
- Return after inactive status requires reactivation approval

NOT INCLUDED YET
================
- Frontend HTML/JS camera and buttons
- Actual video upload Edge Function / signed storage upload
- Browser passkey/WebAuthn registration
- Push notification delivery worker
- Payroll ledger posting
- V778.2A ARD actor/availability bridge
