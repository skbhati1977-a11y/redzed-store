REDZED UPM V765 — DEPARTMENT-INDEPENDENT ALTER

ROOT CAUSE
==========
The visible ALTER FILL action inherited an old hidden input whose maximum was
based on pending_qty. A downstream Department can have pending_qty=0 while it
still has full current Good Qty, so a genuinely new defect was blocked with:

"ALTER FILL ke liye koi pending Qty available nahi hai."

CORRECT RULE
============
Every currently assigned Department may raise a new Alter from its CURRENT
GOOD QTY.

Examples:
- Stitching Alter closes.
- Folding later finds 3 defects.
- Folding may create a separate new Alter journey.
- QC later finds 1 defect.
- QC may create another separate journey.

JOURNEY RULE
============
Every ALTER FILL save uses the existing rr_upm_alter_stage_v740 INSERT flow.

Therefore:
- old closed journey is never overwritten;
- an existing open journey does not block a newly discovered defect;
- each Department/Size save gets its own journey record;
- Cutting Master → Line Man → Karigar chain remains unchanged;
- evidence, physical piece confirmation and WhatsApp remain mandatory.

QUANTITY RULE
=============
New Alter max = current Good Qty for that Colour × Size in the assigned
Department.

It does not use:
- old Alter Pending Qty;
- Main/Cutting Qty as an unsafe fallback;
- another Department's journey balance.

INSTALL
=======
1. No SQL required. Existing backend already inserts a new journey for every
   ALTER_FILL.

2. Upload:
   real-universal-production-v765-independent-alter.js

3. Replace V764 script line with:
   <script src="real-universal-production-v765-independent-alter.js?v=7651"></script>

4. Keep base:
   <script src="real-universal-production-v729.js?v=741-dynamic-random-1"></script>

5. Do not load V764 and V765 together.

6. Commit → Pages deploy → Ctrl + Shift + R.

EXPECTED CONSOLE
================
V765_DEPARTMENT_INDEPENDENT_ALTER_UI

TEST
====
FOLDING assigned Colour:
ALTER FILL
→ all Sizes with current Good Qty appear
→ enter Qty
→ Continue
→ existing live evidence modal
→ physical piece confirmation
→ Save
→ separate Cutting Master Pending journey appears.
