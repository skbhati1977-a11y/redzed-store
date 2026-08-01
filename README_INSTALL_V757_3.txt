REDZED UPM V757.3 — FINAL CONCLUDED SEARCHABLE WORKER

THIS PACKAGE ALREADY INCLUDES
=============================
1. First window:
   - Short Colour-wise summary
   - Size-wise PCS
   - Department + current worker
   - ACTIVE status
   - Alter Qty + mapped responsible person

2. Check-in window:
   - All Colours always visible
   - Independent row actions
   - No visible checkbox
   - No legacy single-Colour card
   - No duplicate/global action interface

3. Single Colour Worker Assignment:
   - Only the clicked Colour enters the assignment payload
   - Current locked department is used
   - Every active mapped worker of that department is available
   - No worker name is hard-coded

4. Bulk Assignment:
   - Search Department
   - Search mapped Worker
   - Assign all eligible OPEN Colours of that department

SEARCHABLE DROPDOWN RULE
========================
All selection controls created by V757 use a Search-first combobox:
- Search by Worker Name
- Search by Worker Code
- Filter list immediately
- Select from filtered results
- No long native dropdown scrolling

The global REDZED rule remains:
All current and future dropdowns must be searchable.

INSTALL
=======
1. Upload/replace this GitHub root file:
   real-universal-production-v757-final-approved.js

2. Remove the previous V757 script line.

3. Keep only:
   <script src="real-universal-production-v757-final-approved.js?v=7573"></script>

4. Commit and wait for GitHub Pages deployment.

5. Press Ctrl + Shift + R.

CONSOLE EXPECTED
================
V757_3_FINAL_CONCLUDED_SEARCHABLE_WORKER
