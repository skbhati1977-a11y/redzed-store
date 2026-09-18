# V268 Role / Chat identity canonical migration
Applied role_chat_identity_canonical_v268.
Migrated live consumers:
- rr_owner_worker_directory_v8_4
- rr_worker_duplicate_name_guard_v776_7
- rr_real_chat_hybrid_identity_v94
Worker management now returns canonical rr_worker_directory_v1 IDs.
Duplicate-name guard checks canonical workers, not Auth-ID projection.
Real Chat direct/on-behalf identity resolves sender/login and requested context through rr_canonical_worker_id_v264.
No worker or old unified projection retired.
Remaining backend functions referencing old unified view: 82.
