REDZED V778.1 — ATTENDANCE CORE FOUNDATION

INSTALL
=======
1. Run REDZED_V778_1_ATTENDANCE_CORE_FOUNDATION.sql
2. Run VERIFY_V778_1.sql

THIS PHASE INCLUDES
===================
- Multiple attendance premises
- Location 1 and Location 2, each with 100-meter radius
- Workforce Type separate from Attendance Type
- Factory Worker / Field Worker / Commission Agent / Remote Staff
- Factory Geofence / Field Event / Visit Based / Production Activity
- No continuous location requirement
- Commission-agent Start/End Day session foundation
- Automatic business-event location snapshot foundation
- Geofence audit foundation
- Server-side distance calculation
- TEST/REAL isolation
- Direct table writes blocked

COMMISSION AGENT UX
===================
Target: maximum two attendance taps daily.
- Start Day
- End Day

Normal business actions can automatically create location evidence:
- Customer Visit
- Order
- Collection
- Invoice Activity
- Follow-up
- New Customer

NOT INCLUDED YET
================
- Start Day / End Day final RPC
- Factory salaried Check-In / Check-Out final RPC
- Daily minute calculation
- Attendance UI
- Witness adapter
- Device/test-phone adapter
- Payroll posting
