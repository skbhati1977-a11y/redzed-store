# TEST71 independent financial role checkpoint

The focused runner is ready; independent live financial authority is **BLOCKED**, not cleared. Existing 35-profile SQL role simulation remains carried evidence and was not rerun.

- Seven local mocked runner tests passed. These establish fail-closed behavior, not real account authority.
- All six credential pairs were absent; the actual runner issued zero network requests and recorded six BLOCKED roles.
- Fresh read-only profile inventory: 35 active linked profiles across 11 roles. No active ACCOUNT/ACCOUNTS profile exists.
- No user was created, no password/role was changed, no business transaction was written, and no production deployment changed.

Run `node scripts/test71-independent-role-financial.cjs` after securely supplying `TEST71_ROLE_<ROLE>_EMAIL` and `TEST71_ROLE_<ROLE>_PASSWORD` for WORKER, LINE_MANAGER, MANAGER, ADMIN, ACCOUNTS and SALES. Use existing dedicated TEST accounts. The runner checks password login against Auth `/user`, active profile role, effective role, matching authenticated/operator/effective IDs, distinct users across roles and absence of on-behalf context, then only TEST trial balance and Accounts OPEN reads. Worker, LM, Manager and Sales must receive PostgreSQL permission denial; Admin and Accounts must succeed. It signs out only the session it created, prints no token/credential or financial payload, and exits nonzero for any blocked/failed role.

Independent browser journeys, scoped salary visibility, approval/pay/reverse journeys and other department role behavior are outside this read-only runner's claim. They remain pending.
