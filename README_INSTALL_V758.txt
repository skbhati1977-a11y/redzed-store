REDZED UPM V758 — UNIVERSAL RANDOM DEPARTMENT ELIGIBILITY

EXACT ERROR FIXED
=================
Department is not eligible for random Colour assignment. — P0001

FINAL UNIVERSAL RULE
====================
Every ACTIVE production department may claim any currently OPEN Colour.

Examples:
- Print
- Karigar / Stitching
- Overlock
- Folding
- Sticker
- QC
- Press / Finishing
- Thread Cutting
- Packing
- Other future active departments

STILL REQUIRED
==============
- Selected worker must be active.
- Selected worker must be mapped to the selected department.
- Colour must be OPEN.
- One Colour cannot have two active owners at the same time.
- Full Colour + all Cutting Sizes remain bound to one worker.
- Duplicate assignment and Cutting Qty checks remain.

WHAT THE SQL CHANGES
====================
Only the hard-coded department eligibility rejection inside:

rr_upm_claim_colours_v741(text,text,text,jsonb,text)

The existing function is backed up first in:

rr_upm_function_backup_v758

INSTALL
=======
1. Open REDZED_UPM_V758_UNIVERSAL_RANDOM_DEPARTMENT_ELIGIBILITY.sql.
2. Copy the complete SQL code.
3. Paste it into Supabase SQL Editor.
4. Press Run.
5. Expected final result:
   ok: true
   version: V758_UNIVERSAL_RANDOM_DEPARTMENT_ELIGIBILITY

FRONTEND
========
Keep the current V757.7 JS temporarily:

<script src="real-universal-production-v757-final-approved.js?v=7577"></script>

After SQL succeeds:
Ctrl + Shift + R

Then assign C3 → Print → mapped Print worker again.
