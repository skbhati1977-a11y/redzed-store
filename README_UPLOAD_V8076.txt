REAL FACTORY ACCOUNTS V8076 — ADD NEW WITH SUPER ADMIN APPROVAL

ORDER:
1. Run 01_RUN_ACCOUNTS_MATERIAL_ADD_NEW_APPROVAL_V8076.sql in Supabase SQL Editor.
2. Replace BOTH frontend files together:
   - real-accounts-v805.html
   - real-accounts-v805.js
3. Do NOT replace dashboard, config.js or real-common.js.
4. Open real-accounts-v805.html?v=8076 and Ctrl+Shift+R.

RULE:
- Type Material Name.
- Similarity >= 72% or normalized/existing match -> Add New hidden/blocked; select existing suggestion.
- No close match -> + Add New appears.
- Request goes PENDING to rr_name_creation_requests_v805.
- Super Admin can MAP EXISTING / APPROVE NEW / REJECT.
- Generic materials: APPROVE NEW creates rr_material_master_v805 row.
- REGULAR_CLOTH / MATCHING_CLOTH / STICKER / METAL_ID stay source-managed; approval is recorded but source master creation remains in canonical source module to prevent duplicate inventory/master paths.
