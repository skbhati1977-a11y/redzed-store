REDZED UNIVERSAL PRODUCTION — WORK ASSIGNMENT V8
================================================

FINAL CONCLUSION IMPLEMENTED
----------------------------
1. Work Assign is a common production feature, not a Department Head-only form.
2. Department is selected first.
3. Single, multiple, or ALL colours can be selected.
4. Tap colours, then press OK.
5. Cutting colour-size PCS display side-by-side:
      Colour R | L 40 PCS | XL 40 PCS | XXL 40 PCS | Total 120 PCS
6. Quantity is auto-filled from rr_upm_lot_cut_size_map_v5.
7. Worker is selected once; the same worker is copied to all selected colours.
8. Any individual row can still be changed to another worker before saving.
9. Worker display includes Name + stable Worker ID:
      Mohd. Salman — WRK-AB12CD34
10. Same Lot + Department + Colour cannot have two active assignments.
11. Already-assigned colours appear locked and cannot be selected.
12. ALL selects only currently unassigned colours.
13. Existing Production Submit is blocked at database level until that
    Department + Colour has an active assignment.
14. Submit ledger stores assignment ID, Worker ID, Worker Code and Worker Name.
15. Existing Cutting, Alter, Repair, Damage, Remake, Rate and reversal functions
    are not rewritten.

FILES
-----
1. REDZED_UPM_WORK_ASSIGNMENT_V8.sql
2. redzed-upm-work-assignment-v8.js

INSTALL
-------
1. Take a Supabase backup.
2. Run REDZED_UPM_WORK_ASSIGNMENT_V8.sql.
3. Upload redzed-upm-work-assignment-v8.js into the same GitHub folder.
4. In the CURRENT real-universal-production-v72040.html, add this line
   immediately after real-universal-production-v72040.js and before </body>:

   <script src="redzed-upm-work-assignment-v8.js?v=720801"></script>

5. Commit and wait for GitHub Pages deployment.
6. Hard refresh: Ctrl + Shift + R.

TEST
----
A. Open a Lot and click Assign Work.
B. Select Department.
C. Tap one colour and OK: one worker row must appear.
D. Select two colours and OK: two rows must appear.
E. Select worker once: worker must copy to both rows.
F. Confirm size-wise PCS are horizontal and quantity is auto-filled.
G. Save assignment.
H. Reopen same Lot + Department: assigned colour must be locked.
I. Try assigning locked colour through direct RPC: SQL must reject it.
J. Open Production Submit for assigned colour: assigned Worker Name + ID must show.
K. Try submit on an unassigned colour: database must block it.

IMPORTANT
---------
This patch uses the existing rr_user_assignments_v2 as Worker Master.
Populate active workers there before testing. worker_code is generated
automatically when missing.
