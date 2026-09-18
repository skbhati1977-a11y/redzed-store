# V269 UPM action identity canonical migration
Applied upm_action_identity_canonical_v269.
Migrated:
- rr_upm_actor_worker_id_v771
- rr_upm_worker_identity_v767
- rr_upm_effective_identity_v200
Signed-in Auth ID and on-behalf worker context now resolve through rr_canonical_worker_id_v264.
Operational sender/worker IDs remain canonical rr_worker_directory_v1 IDs.
No retirement in this batch.
Remaining backend functions referencing old unified view: 79.
