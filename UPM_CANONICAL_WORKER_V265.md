# V265 UPM canonical worker consumer migration
Applied backend migration upm_canonical_worker_consumers_v265.
Migrated live UPM identity consumers away from Auth-ID-priority unified directory:
- rr_upm_worker_list_v754
- rr_upm_worker_eligible_v726
- rr_upm_worker_candidates_v740
- rr_upm_department_line_men_v9110
They now use rr_worker_directory_compat_v264 and rr_canonical_worker_id_v264.
Compatibility verification: Imamul eligibility returns true for both canonical worker ID and linked Auth ID.
No old unified projection was retired in this commit.
