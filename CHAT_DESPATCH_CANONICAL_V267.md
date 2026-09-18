# V267 Real Chat / Despatch canonical worker migration
Applied chat_packing_canonical_worker_v267.
Migrated:
- rr_real_chat_directory_v85 worker/staff projection
- rr_real_chat_membership_roster_v136
- rr_fg_despatch_line_men_v9361
All use rr_worker_directory_compat_v264 canonical worker IDs.
Old unified projection was not retired.
Post-migration backend dependency count: 85 functions still reference rr_worker_directory_unified_v1.
