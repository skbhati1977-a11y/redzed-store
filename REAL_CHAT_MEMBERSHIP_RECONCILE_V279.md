# V279 Global Real Chat Membership Reconciliation
Applied real_chat_membership_reconcile_v279.
Legacy Auth/Alias memberships are preserved in an audit log, merged onto canonical V264 worker IDs, then operationally inactivated with reason V279_RETIRED_LEGACY_AUTH_ALIAS_MEMBERSHIP.
Canonical view: rr_real_chat_department_membership_canonical_v279.
No worker/history deleted. Unresolved profile-only identities are not converted into workers.
Verification after reconciliation shows canonical active memberships for Imamul, Javed, Akhtar, Yashpal, Nasim, Sanju, Kartik, Vinod and Shamim.
Backend identity source: V264 canonical worker.
Frontend/App/Real Chat must consume canonical worker/work projections; no Auth ID should be treated as Worker ID.
