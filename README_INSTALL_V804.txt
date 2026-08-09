REAL FACTORY V804 — STICKER + METAL ID MASTER / INVENTORY / PRODUCT MAPPING

INSTALL ORDER
1. Run REAL_FACTORY_V804_ACCESSORY_FRONTEND_BACKEND.sql in Supabase.
2. If SUCCESS, run VERIFY_REAL_FACTORY_V804_ACCESSORY_FRONTEND.sql.
3. Upload these files to GitHub root:
   - real-accessory-master-v804.js
   - real-sticker-master-v804.html
   - real-metal-id-master-v804.html
   - real-product-master-v804.html
   - real-product-master-v804.js
4. Open Product Master V804 and Ctrl+Shift+R.

WHAT V804 ADDS
- Sticker Master: Sticker No, Name, Image, Quality (HD/DTF/VINYL/OTHER).
- Metal ID Master: Metal ID No, Name, Image, Size (SMALL/MEDIUM/BIG).
- Inventory cards: Available, Reserved, Free, Req Now, weighted-average cost.
- Purchase entry updates stock and shortage automatically through verified V804 triggers.
- Product Master tabs stay ART | PRINT | STICKER | METAL ID.
- Product Master selects reusable Sticker / Metal ID Masters, while backend preserves the existing Art Instruction -> CB Assignment chain.
- Released lot requirement auto-sync uses rr_upm_cut_size_rows_v726(lot_no).
- Low-stock alert flow remains the already verified V804 global alert flow.

NUMERIC UI RULE
- Manual Qty / Cost / Rate fields look clean: no forced 0.0000 text while typing.
- Clicking/focusing a zero-like field clears it for direct typing.
- Cost / Rate display is max 2 decimals.

IMPORTANT
- TEST / REAL inventory remains separated by data_mode.
- Existing fake TEST opening / purchase data is intentionally kept.
- No legacy assignment tables are replaced.
