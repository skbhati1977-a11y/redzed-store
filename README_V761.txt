REDZED UPM V761 — IDENTITY MAPPING FIX

ROOT CAUSE
==========
rr_upm_resolve_identity_v740 was blocking Production with:

Art No mapping missing in released Cutting Lot.

The old function mainly depended on:
- rr_cutting_lots_v3.art_no
- rr_upm_lot_registry.art_no

It also returned an already-created incomplete lock without rebuilding it.

FIXED MAPPING PRIORITY
======================

ART
---
1. Cutting Lot art_no
2. Lot Registry art_no
3. Registry art_id → Art Master
4. Product Master art_id → Art Master
5. Registry metadata art_no

PRINT
-----
1. Cutting Lot print_no
2. Lot Registry print_no
3. Registry print_id → Print Master
4. Product Print Links
5. Registry metadata print_no

CB
--
1. Fabric Purchase cb_no
2. CB Unit cb_base_no
3. CB Unit cb_code
4. Registry metadata CB fields

FRAME
-----
Final resolved Print No → Print Frames
then Registry metadata fallback.

LOCK RULE
=========
- Existing complete immutable identity lock remains untouched.
- Existing incomplete lock is rebuilt automatically.
- Force re-sync remains Owner/Admin only with mandatory reason.

INSTALL
=======
Run the complete SQL file in Supabase:

REDZED_UPM_V761_IDENTITY_MAPPING_FIX.sql

No JS or HTML change is required for this backend fix.

EXPECTED FINAL RESULT
=====================
The query returns one JSON object for Lot 2SKB6 containing:

canonical_lot_id
lot_no
cb_no
art_no
print_no
frame_no

art_no should no longer be blank/MAPPING REQUIRED.

AFTER SUCCESS
=============
Ctrl + Shift + R

Then test:
C3 Print → Submit → Next Department flow.
