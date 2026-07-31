REDZED UNIVERSAL PRODUCTION V732 — ACTUAL SOURCE INTEGRATION

FILES TO REPLACE IN GITHUB ROOT
1. real-universal-production-v729.html
2. real-universal-production-v729.js

SUPABASE FIRST
Run REDZED_UPM_V732_INSTALL.sql in Supabase SQL Editor.
The SQL expects the existing V726/V727 and V729 Alter/Remake objects already installed.

WHAT CHANGED
- Screen now calls rr_upm_universal_form_v731 and rr_upm_debug_lot_flow_v731.
- Alter Fill calls rr_upm_alter_fill_v731.
- Remake Issue / Delivered / Submit call rr_upm_remake_stage_v731.
- Remake Delivered has its own quantity input; it no longer reuses Remake Issue input.
- Saved Damage is displayed separately from Add Damage input.
- Damage save uses rr_upm_save_damage_v731 and validates PENDING/ALTER/REMAKE buckets separately.
- Worker dropdown is filtered again in the browser to the exact currently opened department.
- Identity is returned by Product Master -> Cutting resolver, with CB joined through Cutting cb_purchase_id/cb_unit_id.
- HTML loads JS with ?v=732 to avoid stale GitHub Pages/browser cache.

INSTALL ORDER
A. Take a Supabase backup.
B. Run REDZED_UPM_V732_INSTALL.sql.
C. Replace only the two v729 files above in GitHub root and commit.
D. Wait for GitHub Pages deployment.
E. Open real-universal-production-v729.html and press Ctrl+Shift+R.
F. Run Flow Debug. It should call rr_upm_debug_lot_flow_v731 and show the corrected context.

IMPORTANT
Do not upload the SQL file to GitHub as a substitute for running it in Supabase.
The supplied v732-named HTML/JS are optional copies only; the live URL uses the v729 filenames.
