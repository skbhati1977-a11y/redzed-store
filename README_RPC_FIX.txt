REDZED UPM V740 RPC SIGNATURE FIX

Issue fixed:
- rr_upm_assign_colours_v8_3 was incorrectly called with Alter-only parameters.
- rr_upm_reassign_colours_v726 was incorrectly called with Alter-only parameters.

Correct assignment RPC arguments:
  p_canonical_lot_id
  p_lot_no
  p_department_code
  p_rows
  p_remarks

Correct reassignment RPC arguments:
  p_canonical_lot_id
  p_department_code
  p_rows
  p_remarks

Alter-only parameters remain exclusively on rr_upm_alter_stage_v740.

INSTALL:
Replace only:
- real-universal-production-v729.html
- real-universal-production-v729.js

No SQL rerun required for this specific PGRST202 fix.
Hard refresh after deployment: Ctrl+Shift+R
