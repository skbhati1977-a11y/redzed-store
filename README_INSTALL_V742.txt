REDZED UPM V742 — Department Colour Status

Purpose
- Detect existing active and submitted Colour assignments department-wise.
- Partial assigned or partial submitted department = ORANGE, showing Colour codes (C1 C3 C6).
- All Colours currently running in one department = GREEN.
- All Lot Colours submitted by one department = RED.
- Submitted Colours remain visible when that department is selected.
- BASE departments appear only while at least one Colour is truly OPEN for random claim.

Install
1. Run REDZED_UPM_V742_DEPARTMENT_COLOUR_STATUS.sql in Supabase SQL Editor AFTER V741.
2. Replace GitHub root files:
   real-universal-production-v729.html
   real-universal-production-v729.js
3. Commit/deploy and press Ctrl+Shift+R.

Identity CB/Art/Print/Frame and Alter journey functions are not changed.
