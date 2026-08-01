REDZED UPM V760.4.1 — SIZE HELPER FIX

ERROR FIXED
===========
sizeTextForColour is not defined

ROOT CAUSE
==========
V760.4 direct Submit confirmation called:

sizeTextForColour(rowData.colour_code)

But the existing size engine in the same file is:

colourSizeInfo(colourCode)

and returns:
{
  summary,
  alterQty,
  alterSizes
}

FIX
===
The confirmation now uses:

colourSizeInfo(rowData.colour_code).summary

No SQL change.
No backend change.
No Rate Gate change.
No Alter/Damage/Remake change.

INSTALL
=======
1. Upload to GitHub root:
   real-universal-production-v76041-costing.js

2. Replace the V760.4 script line with:

   <script src="real-universal-production-v76041-costing.js?v=76041"></script>

3. Do not load V760.4 and V760.4.1 together.

4. Commit → GitHub Pages deployment → Ctrl + Shift + R.

EXPECTED CONSOLE
================
V760_4_1_SIZE_HELPER_FIX_UI

TEST
====
2SKB6 / C3:
SUBMIT
→ confirmation opens
→ Sizes display
→ Next Department select
→ direct Submit RPC fires.
