# V266 Attendance / Payroll canonical worker migration
Applied attendance_payroll_canonical_worker_v266.
Migrated:
- rr_payroll_worker_is_self_v779_1
- rr_attendance_actor_allowed_v778_2
- rr_attendance_actor_v778_2
- rr_get_my_payroll_history_v779_3
All now resolve Auth/Login identity through V264 and retain canonical rr_worker_directory_v1 worker IDs.
No old unified view retirement yet. Dependency scan after this batch still finds 88 backend functions referencing rr_worker_directory_unified_v1, so retirement is not safe.
