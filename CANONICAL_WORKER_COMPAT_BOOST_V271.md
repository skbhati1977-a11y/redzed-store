# V271 Canonical Worker Compatibility Boost
Applied canonical_worker_compat_boost_v271.
The legacy rr_worker_directory_unified_v1 name is now a compatibility projection whose worker rows come from rr_worker_directory_v1 canonical IDs.
Auth/Login IDs no longer replace canonical worker IDs.
Profile-only users are preserved only when no linked canonical worker exists (for legitimate non-worker identities such as owner/login profiles).
UPM worker list V8.3/V8.4 explicitly use V264 canonical compatibility directory.
Verification: bad canonical worker links = 0.
This is a compatibility replacement, not deletion of worker/history.
Old Auth-ID-priority behavior is effectively superseded; final retirement audit is still required before dropping any legacy object/function.
