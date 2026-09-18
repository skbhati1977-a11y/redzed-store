# V263 Canonical Worker Identity
Canonical worker identity is rr_worker_directory_v1.id.
linked_auth_user_id is login/auth identity only and must never replace worker_id.
V263 salary guard uses the canonical worker directory and verified July TEST salaried mappings:
- CHOTU -> printing -> print worker
- Baldev -> KAJ_BUTTON -> kaj/btn karigar
- Ali -> fabrication -> line man
Guard result: READY, 3 salaried workers, 0 unmapped.
No worker/profile/function was retired in this commit.
Retirement of the old Auth-ID-as-Worker-ID unified projection must be separately approved before any destructive/replace action.
