REDZED UPM V754.4 — STITCHING ALIAS FINAL MERGE

CANONICAL RULE
--------------
Permanent department code:
STITCHING

Display name:
Karigar / Stitching

Aliases merged into STITCHING:
KR
KAJ
KARIGAR
KARIGAR / STITCHING
KARIGAR/STITCHING
STITCH

RESULT
------
- STITCHING and KR can no longer appear as separate departments.
- Existing alias references in assignments, colour state, handoffs,
  submit history, route locks, Alter journeys and Colour department locks
  are migrated to STITCHING.
- Alias department cards are retired from UPM assignment lists.
- First window groups all relevant Colours under one:
  Karigar / Stitching
- Check-in worker list resolves only from canonical STITCHING mapping.

EXAMPLE
-------
Before:
STITCHING · ASSIGNED C1 C2 C4 C5 C6
KR · WAITING WORKER C3

After:
Karigar / Stitching
ASSIGNED C1 C2 C4 C5 C6 · WAITING WORKER C3

INSTALL
-------
1. Run:
   REDZED_UPM_V754_FINAL_MERGED.sql

2. Replace GitHub file:
   real-universal-production-v754-qc-colour-open-status.js

3. HTML:
   <script src="real-universal-production-v754-qc-colour-open-status.js?v=7544"></script>

4. Commit and press Ctrl + Shift + R.

VERIFY
------
Run:
select public.rr_upm_v754_debug(
 'rr_cutting_lots_v3:f8bc9cb9-a487-4fff-89c5-a6a128e11ccc'
);

Expected:
active_stitching_alias_departments = []
stale_checking_departments = []
noncanonical_cb_colours = []
