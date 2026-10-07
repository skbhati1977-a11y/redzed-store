# Collection audit and customer device approval — 7 October 2026

All times below are India time (Asia/Kolkata). Historical collection and requirement records were audited without renumbering or closing them.

| Record | Created | Closed | Most recent send | Saved requirement |
| --- | --- | --- | --- | --- |
| Collection 12 | 8 Sep, 18:20 | Still open / requirement received | U4: 7 Oct, 00:18 | RZ REQUIREMENT 23, 5 selected styles, 132 PCS |
| Collection 16 | 5 Oct, 19:29 | 5 Oct, 23:36; CUSTOMER CLOSE REQUIREMENT | U4: 5 Oct, 21:00 | RZ REQUIREMENT 22, 7 selected styles, 202 PCS |

Collection 12 is an older record. Four subsequent sends were appended to it on 6/7 October. Its number was not generated after 16, and 16 was not renamed to 12. The sales context falls back to an older still-open cycle when a newer cycle is closed; it does not close every previous open cycle automatically. That explains the apparent backward number. Do not silently rewrite historical identifiers or move these requirements between cycles.

Collection 12's sent lots are 1RR1, 2NSKB1, 2NSKB2, 2RSKB4, RM002, RM003, RM004 and RM006. Its positive saved quantities are 1RR1=36, 2NSKB1=18, 2NSKB2=24, 2RSKB4=18 and RM004=36 (132 PCS). RM002 and RM003 are zero. RM006 was added at U4 after the saved requirement at U3, and does not yet have a submitted required quantity.

Collection 16 separately stores 1RR1=18, 2NSKB1=18, 2RSKB4=36, 2SKB6=36, E2E-FRESH-01=18, E2E-FRESH-02=18 and E2E-FRESH-03=58 (202 PCS). Requirement records, share bindings and snapshot cycle IDs match their respective collection. Shared lot numbers do not merge quantities across cycles.

Refresh drafts previously identified only the URL, although that URL can resolve a later current collection. Draft quantity and note restoration now additionally require the loaded collection cycle ID. Older unscoped drafts cannot override another cycle's saved requirement.

## Approval scope and operation

The approval gate applies to TEST direct customer links. Production and distributor authorities retain their existing logic. A customer must enter the original registered mobile; alternate contact numbers cannot obtain a direct customer session. A new device creates one pending request. It receives no session token until an actual active Super Admin/Owner approves it. Approval binds to customer ID, device hash and registered mobile, and never transfers to another device.

Super Admin can open Customer Chats → LOGIN REQUESTS (or the admin page). The queue shows canonical name, entered name, registered/requested number, device label and timestamp. Verify the person's identity by contacting the original registered number, then choose VERIFY NUMBER & APPROVE. Reject and revoke are available. Revocation and registered-number changes invalidate access on the backend. Existing unapproved TEST sessions must also request approval.

The web app cannot identify the phone's SIM automatically. No automatic SMS OTP service is added. The approval records explicitly capture the Super Admin's registered-number verification; approval must not be mistaken for an automatic SIM/OTP check.

Direct TEST share, lot, requirement and requirement-line tables also enforce the approved customer scope on raw client reads and disallow customer direct writes. Non-TEST and distributor row authority is preserved. Private approval storage has RLS, a restrictive deny policy and no client table grants. Approval RPCs require the real active Super Admin/Owner identity. Both old and bound session issuers enforce approval. Token-only legacy chat and collection routes require an approved session header; customer hints expose only the name before login. Internal pre-session bootstrap is private. Production bootstrap behavior remains intact.

Run `node --test tests/customer-login-approval.test.cjs tests/customer-mobile-contract.test.cjs` and `tests/customer-login-approval-rollback.sql`. The SQL suite uses a transaction and rolls back every test request, approval and session. Never seed real device approvals for convenience.

Apply SQL files in order: `sql/test71_customer_login_approval.sql`, then `sql/test71_customer_approval_row_access.sql`. The second file also contains the explicit restrictive approval-table deny policy.

## One open collection rule correction

Allowing Collection 16 while 12 was open violated the intended business rule; the fallback behavior above explains the symptom but does not make it valid. Legacy first-create APIs and share-adoption APIs had no shared active-cycle guard. A database trigger now covers every insert and reopening of a TEST direct customer cycle. The active statuses are DRAFT, SENT_NOT_OPENED, OPENED_NO_RESPONSE and REQUIREMENT_RECEIVED with no closed_at. New creation is blocked until existing active cycles are closed. Existing open-cycle updates continue to work. PI_GENERATED, CI_GENERATED, CLOSED, CLOSED_NO_RESPONSE and CANCELLED are terminal for this active-collection rule.

The guard uses a private per-customer/mode UPSERT lock row to serialize competing creation requests. No history is renumbered or auto-closed. Subsequent authorized cleanup reconciled these historical duplicate opens. Reeka now has only Collection 12 open; 3, 5, 13, 14 and 15 are closed with an audit reason. Collection 16 remains closed.

Applied backend migration: `sql/test71_one_open_collection.sql`. Run `tests/customer-one-open-collection-rollback.sql` to verify all three legacy first-create APIs are blocked, existing open-cycle updates succeed, creation succeeds after closure and reopening is blocked while another cycle is active. All fixture closures and new records roll back.
