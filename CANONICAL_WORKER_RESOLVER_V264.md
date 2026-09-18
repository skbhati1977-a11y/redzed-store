# V264 Canonical Worker Resolver
Backend migration canonical_worker_resolver_v264 is applied.
- rr_canonical_worker_id_v264(identity): canonical worker ID stays unchanged; auth/login ID resolves through linked_auth_user_id.
- rr_worker_identity_v264(identity): returns canonical worker identity metadata.
- rr_worker_directory_compat_v264: compatibility directory exposes only rr_worker_directory_v1 canonical worker IDs.
- rr_costing_salary_allocation_guard_v264: salary guard resolves canonical IDs before allocation.
Verification: July TEST salaried workers CHOTU, Baldev and Ali = READY; unmapped 0.
No old unified projection or worker was retired in V264. Consumer migration must complete before retirement.
