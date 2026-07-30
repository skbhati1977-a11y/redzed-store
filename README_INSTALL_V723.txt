REDZED UPM V723 — UNIFIED LOT FORM

1. Supabase SQL Editor में run करें:
   REDZED_UPM_V723_UNIFIED_LOT_FORM.sql

2. GitHub repository root में upload करें:
   real-universal-production-v723.html
   real-universal-production-v723.js

3. URL:
   https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v723.html

WHAT CHANGED
- First screen only compact Lot cards: Lot No, Art No, Total Cutting PCS, Art/Print thumbnails.
- Single tap or CHECK IN opens one Universal Lot Form.
- No separate Assign/Submit/Alter/Remake/Damage popup architecture.
- Lot remains fixed; Department selector changes the full colour-size-worker summary.
- Actual Rate is Lot + Department.
- Standard Rate and Owner Margin are Owner/Admin only.
- Mobile-friendly image gallery: thumbnails, full-screen, swipe, double-click/tap zoom behavior.
- Colour-size cutting rows come from existing rr_upm_lot_cut_size_map_v5.
- Worker list comes from existing rr_upm_worker_list_v8.
- Existing Assign and production RPCs are reused.

IMPORTANT
- Keep V720.55 files until V723 is verified.
- Alter/Remake/Damage/Reassign buttons now stay inside the same unified form. The UI context is complete; existing project-specific approved RPC names may be wired after live verification where schemas differ.
- Standard-rate and margin history is additive and immutable through audit/history rows.
