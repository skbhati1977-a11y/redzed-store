# TEST70 Real Chat Identity, Permission and Lifecycle Audit V81

## Identity inventory

- Active user profiles: 34
- Roles present: OWNER 1, ADMIN 1, CUTTING_MASTER 2, LINE_MANAGER 21, PACKING_OPERATOR 2, PRINTING_OPERATOR 2, SALES 2, STICKER_OPERATOR 3
- No active `ACCOUNTS` role profile is present.
- Canonical workers: 36
- Worker login mappings: 34/36
- Missing worker logins: Accounts/anuj and Sales/lukman
- Worker salary-ledger mappings: 36/36
- Supplier-ledger mappings: 19/19
- Canonical customer identity maps: 12/12 with mobile
- Worker direct-chat maps physically created: 1 (current implementation lazily creates the rest)
- Customer chats: 25; customer chat members: 82
- Distributor/customer relation chats: 12

## Department membership findings

1. Owner/Superadmin is correctly overlaid as staff across 18 current department groups.
2. There is no `PURCHASE` department group in the Real Chat membership matrix.
3. Shailender is currently mapped to home department `ADMIN`, not `PURCHASE`.
4. Accounts has one worker without login and no active Accounts-role user profile.
5. Department aliases are inconsistent:
   - membership uses `DISPATCH`; bridge/UI also uses `DESPATCH`
   - worker directory uses `KAJ_BUTTON`; membership uses `KAAJ_BUTTON`
6. These aliases can split counts, visibility, messages and alert routing into separate chats.

## Receiver mapping findings

| Receiver type | Available identity | Current Real Chat result |
|---|---|---|
| Worker | 36 canonical worker + salary ledger maps | Strong base; 2 missing logins and only 1 materialized direct chat |
| Department | explicit membership matrix | Purchase missing; aliases split groups |
| Owner/Superadmin | canonical auth/profile + global overlay | Correctly present in current groups; must auto-cover future groups |
| Accounts | worker exists, but no login/Accounts profile | Cannot safely route actionable financial work to an Accounts actor |
| Supplier | 19 supplier-ledger maps | Ledger identity exists; no complete supplier chat/receiver contract |
| Customer | 12 canonical sales maps + 25 chats | Identities exist; TEST70 bridge does not join commercial events to them |
| Distributor relation | 12 relation chats | Separate model exists; not integrated into TEST70 workflow bridge |

## Privacy audit

- Real Chat bridge tables have RLS and authenticated SELECT policies.
- Financial modules are specially restricted to sender/receiver or OWNER/ADMIN/ACCOUNTS checks.
- However, no Accounts profile currently exists, so intended Accounts access cannot operate as designed.
- 44 WORKER_PAYROLL financial bridge rows have no receiver user; these must not fall back to broad department visibility.
- Department/global visibility must never be used for worker salary, personal attendance, customer ledger or supplier ledger payloads.
- Personal finance must require exact receiver identity or explicit OWNER/ADMIN/ACCOUNTS authorization.
- Customer direct chat and distributor-customer chat must remain separate identities.

## Lifecycle truth audit

- Real Chat frontend currently infers lifecycle from words using regex.
- Bridge has 729 UPM rows whose event names are completion-like while an `action_code` is still stored.
- The frontend currently hides many of these because its regex calls them CLOSED, but stale action data remains and can reappear when labels/status rules change.
- Product Master decisions are separate events; no aggregate source-of-truth stage identifies the next missing Art/Print/Sticker/Metal decision.
- Cutting readiness, active cutting and released-lot completion are not represented by one canonical lifecycle adapter.
- Attendance day status does not encode the full conversation state without checking IN, OUT, reminder and correction sources.
- Notification read/unread is not business lifecycle completion.

## Correct role surface

| Actor | Main tabs | Work visibility | Financial visibility |
|---|---|---|---|
| Worker | WORKING, CLOSED | own assigned/current/completed work only | own latest settlement/detail only |
| Department Head/Line Manager | OPEN, WORKING, CLOSED | own department and permitted staff | no unrelated worker salary |
| Purchase staff | OPEN, WORKING, CLOSED | Purchase/CB tasks | bill/rate only if field permission allows |
| Cutting Master | OPEN, WORKING, CLOSED | Art-decision read summary + Cutting | no Purchase ledger beyond permitted summary |
| Accounts | OPEN, WORKING, CLOSED | accounts/payroll/ledger tasks | authorised finance scope |
| Sales | OPEN, WORKING, CLOSED | customer/collection/order/sales scope | permitted sales values, not worker payroll |
| Customer | ACTION REQUIRED, IN PROGRESS, COMPLETED | own collection/requirement/order only | own invoice/payment/balance |
| Distributor | ACTION REQUIRED, IN PROGRESS, COMPLETED | own RedZ and customer relation threads | only permitted margins/documents |
| Supplier | ACTION REQUIRED, IN PROGRESS, COMPLETED | own purchase/GR/replacement | own ledger/payment/balance |
| Owner/Superadmin | OPEN, WORKING, CLOSED | all departments and escalation | all authorised finance |

## Required canonical alias and membership repair

- Add `PURCHASE` as a canonical department.
- Map Shailender's verified worker/auth identity to Purchase staff without cloning identity.
- Keep Owner/Superadmin auto-enrolled as staff in every existing and future department.
- Canonicalize `DESPATCH` to one code while accepting `DISPATCH` as alias.
- Canonicalize `KAAJ_BUTTON` while accepting KAJ/BUTTON/BTN aliases.
- Resolve Accounts operational identity before enabling Accounts actions.
- Preserve worker home department separately from cross-department staff memberships.

## Required lifecycle resolver

Lifecycle must be returned by a server-side resolver using the source record:

- `OPEN`: valid pending action exists and work has not started
- `WORKING`: accepted/started/in-progress or unresolved issue is owned
- `CLOSED`: required source completion is final; no executable action remains

The resolver must return `canonical_state`, `display_stage`, `next_action`, `next_receiver`, `is_actionable`, and `closed_at`. It must not infer state from display text.

## Required action authorization

Before opening or executing an action, server-side checks must verify:

1. authenticated actor
2. active profile/worker identity
3. role and department permission
4. exact receiver/assignee or authorised head/escalation role
5. current authoritative source state
6. action not already completed/cancelled/reversed
7. financial/party boundary
8. record-specific deep link

## Security-advisor note

The project-wide Supabase advisor reports a large amount of historical RLS-without-policy and executable `SECURITY DEFINER` debt outside this TEST70 layer. TEST70 repairs must not widen grants. New functions must use invoker semantics where possible, or explicit auth/role checks plus revoked PUBLIC/anon execution where definer rights are necessary.

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy

## Repair gate

Identity and privacy must be repaired before missing commercial/payroll/attendance streams are exposed. Otherwise adding more bridge sources would increase cross-party leakage risk.
