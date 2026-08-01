REDZED UPM V757.7 — DIRECT SINGLE COLOUR ASSIGN RPC

EXACT ROOT CAUSE
================
V729 assignWork() uses its private state.context.

Even if visible #dept was changed to PRINTING, the legacy hidden
Colour groups were still created from OPEN_NEXT context.

Therefore the V729 assignment RPC continued sending:
p_department_code = OPEN_NEXT

FIX
===
Individual Colour row assignment no longer clicks V729 assignBtn.

It directly calls:
rr_upm_claim_colours_v741

with:
- canonical Lot ID
- Lot No
- exact Colour ID
- exact Colour Code
- selected mapped Worker ID
- exact active department from the Colour matrix
- full Colour Qty across all Sizes
- Actual Rate currently present in the form

For C3:
p_department_code = PRINTING
p_rows = [C3 only]

CUSTOM CONFIRMATION
===================
CONFIRM COLOUR ASSIGNMENT

क्या आप पूरा Colour C3 assign करना चाहते हैं?
Department: Print
Worker: selected worker
Colour: C3
Sizes: L 26 · XL 26 · XXL 26

YES · ASSIGN C3

UNTOUCHED
=========
- Bulk Assign remains on original workflow
- First window
- Check-in table
- Alter
- Damage
- Submit
- Journey
- Rates
- Existing backend RPC definition

INSTALL
=======
Replace:
real-universal-production-v757-final-approved.js

HTML:
<script src="real-universal-production-v757-final-approved.js?v=7577"></script>

Console:
V757_7_DIRECT_SINGLE_COLOUR_ASSIGN_RPC
