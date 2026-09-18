# V270 Real Chat base canonical worker migration
Applied real_chat_base_canonical_worker_v270.
Migrated:
- rr_real_chat_directory_v71
- rr_real_chat_assignment_membership_guard_v136
Directory actor, people, membership rows and assignment activity resolve to canonical worker IDs.
Assignment membership guard canonicalizes worker_id before membership write.
No retirement.
Remaining backend functions referencing old unified view: 77.
