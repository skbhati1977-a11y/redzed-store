# V272 Final Worker Identity Retirement Audit
Post-V271 verification completed.
- Canonical worker source remains rr_worker_directory_v1.id.
- rr_worker_directory_unified_v1 is now compatibility-only and no longer uses Auth ID as Worker ID for linked workers.
- Bad canonical identity links verified: 0.
- Worker/history deletion is NOT required.
Retirement candidates identified, but NOT retired in V272:
1. rr_costing_salary_allocation_guard_v262 — false-unmapped guard based on old identity behavior.
2. rr_costing_salary_allocation_guard_v263 — superseded by V264 resolver guard.
3. rr_costing_salary_department_v260 / v263 direct old salary paths should be superseded by a final V264+ department salary projection before removal.
The compatibility view name must remain until legacy callers are proven no longer dependent; its old Auth-ID-priority behavior is already retired by V271.
No destructive retirement was executed in this commit.
