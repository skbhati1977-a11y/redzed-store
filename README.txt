V808_2 F2 LOT LOAD FIX

ONLY FIX:
- RR.requireRoles compatibility fallback
- If current real-common.js has no requireRoles, authenticated Supabase session + rr_user_profiles is used.
- This allows boot to continue and loadPackLots() to run.

UNCHANGED:
- Packing assign/accept/algorithm/submit
- Box material
- Despatch/Store/Sales
- V808_2 media/AI workflow
- TEST mode

Replace BOTH files together.
Open:
real-finished-goods-v787.html?view=packing&v=8082F2
