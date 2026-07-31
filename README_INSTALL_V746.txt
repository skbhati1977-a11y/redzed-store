REDZED UPM V746 — ASSIGNED ACTION CHECKBOX FIX

This is a FRONTEND-ONLY fix. Do not run SQL.

Replace in GitHub root:
1. real-universal-production-v729.html
2. real-universal-production-v729.js

Then deploy and press Ctrl+Shift+R.

Behaviour:
- Open Queue Colour checkbox = Assignment only.
- Assigned/Running Colour checkbox stays blue and active.
- Assigned checkbox is used for Alter, Damage and Submit.
- Assign Selected cannot reassign an already assigned Colour.
- Submitted Colour is disabled only when actual submit history marks it completed here.
- SELECT ALL selects assigned/actionable Colours when the current department has running jobs; otherwise it selects open Colours for assignment.
- Identity and all CB/Art/Print/Frame mappings are untouched.
