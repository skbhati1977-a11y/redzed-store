REDZED UPM V724 WORKING FIX

Why V723 failed:
1. It read rr_upm_lot_cut_size_map_v5, while your live Cutting Master uses rr_cutting_lots_v3 + rr_cutting_breakup_v3.
2. V723 image extraction only checked lot metadata; your project already has rr_upm_get_lot_visuals_v6.
3. Worker assignment backend is colour-level with size_breakup, but V723 UI treated every size as an independent assignment.
4. Good input was incorrectly prefilled with Pending quantity.

INSTALL ORDER
1. Keep and run the original V723 SQL once (for standard-rate and margin tables/functions).
2. Run REDZED_UPM_V724_WORKING_FIX.sql in Supabase SQL Editor.
3. Upload real-universal-production-v724.html and real-universal-production-v724.js to repository root.
4. Open: real-universal-production-v724.html?build=724
5. Hard refresh: Ctrl+Shift+R.

WORKING IN V724
- Clean Lot cards
- Art/Print images through rr_upm_get_lot_visuals_v6
- Fullscreen swipe gallery
- Live colour-size Cutting rows
- Department worker dropdown
- Full-colour worker assignment with correct size breakup
- Actual/Standard Rate and Owner Margin visibility
- Good production submit
- Alter registration through Good/Alter row inputs
- Live totals refresh

IMPORTANT CURRENT BACKEND RULE
rr_upm_assign_colours_v8 assigns one worker per complete colour. Therefore select every size row of a colour and the same worker. True different-worker-per-size assignment needs a new assignment table/RPC migration and is not falsely simulated here.

Remake/Damage/Reassign remain dependent on the existing approved Alter workflow and assignment transfer RPCs. This package does not invent unsafe writes where the current repository has no single verified RPC contract.
