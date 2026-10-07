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


## Admin OPEN customer permission cards — 7 October 2026

TEST71 Admin Department OPEN now retains one card per registered TEST customer, including approved, paused, rejected and revoked devices. Name/mobile search filters these cards in the existing chat search. The card has per-device verified approval/revoke and customer-wide Pause, Resume, Revoke All and allowed discount controls. Cards remain in OPEN after actions and are not forwarded to WORKING/CLOSE.

Pause is checked by the server session validator, including already-issued sessions; resume restores approved device access. Revoke All revokes TEST sessions and marks all device approvals revoked; verified reapproval is required. Customer waiting screens show PAUSED accurately.

Discount uses the existing rr_customers.allowed_discount_per_piece and audited setter, preserving the established ₹0–₹10 per-piece limit. It applies uniformly to all active item rates and quantity calculations; existing PI/CI snapshots are not rewritten. Readymade market snapshot is used only as a TEST pricing fallback when RRQ/universal rates are absent.

Pending login/reopen events enqueue existing targeted web pushes only to active Super Admin/Owner profiles. Five-second duplicate event coalescing prevents duplicate page/visibility notifications. Status polling sends no push. A service-only pending/recipient check prevents resolved request dispatch. Deep links select Admin GROUP OPEN and exact request focus; repeated reminders share a notification tag. Recipient device notification permission/subscription is required. Physical handset delivery is not claimed by automated tests.

## Permission safety and discount effective time
- Pause, Revoke All and Revoke Device require an explicit warning/confirmation. Cancel never mutates access.
- Cards remain in Admin GROUP OPEN after approval, pause and revoke; registered name/mobile search filters the permanent customer card.
- Discount remains editable through the existing Super Admin ₹0–₹10 per-piece authority. The card displays its latest effective timestamp. Canonical discount history records the edit; collection previews and newly saved bills use the current allowance. Existing PI header, lines and version snapshots are not updated by a discount edit.
- Registered REDZED customers, including registered distributors, use this same authority. Distributor private customer pricing retains its existing owner authority and now audits every TEST margin/discount edit with an effective timestamp; existing private collection and customer CI pricing snapshots remain untouched. This change does not replace the separate distributor private customer login authority.
- Poll refresh does not rerender unchanged cards or erase a focused discount draft. A queued login push is rejected after approval or a global pause.

### Verification of permission release (2026-10-07)
- Commit 6642d45751a5ecb6eb5d10cf386999919f6ac80c: 19 customer mobile/approval/readonly tests pass, including warning Cancel causing zero permission mutations.
- Database rollback checks pass for targeted pending-only push and exact Admin OPEN route, pause/resume/revoke with existing sessions, uniform discount and unchanged historic REDZED bill headers/lines/versions, and distributor discount timestamps with unchanged private collection/CI snapshots.
- Real Chat projection gate passes. The retained repository static suite remains red: both pre-change aef39e1409338461a17dd29040a1f29a49b0593e and release have 535 tests, 413 pass, 121 fail, 1 cancelled; identical failing test names, no new failures. Compared with full installed dependencies and a 15-second per-file timeout. Those existing failures are not silently disabled.
- Live customer Site published as version 21. Handset notification delivery is not verified. Active SUPER_ADMIN has zero enabled subscriptions; OWNER has two. Enable notifications on the intended Super Admin handset before expecting push there.

### Exact approval notification destination
- Login request identity is persisted independently of the notification URL. Push receipt and click both construct Admin GROUP OPEN with `rc_login_request`.
- Existing window navigation must succeed before it is focused. Missing, null or rejected WindowClient.navigate falls back to opening the exact destination.
- A request-only URL overrides stale department/status and clears unrelated search at Real Chat boot. The approval router waits for authenticated host readiness and card rendering, highlights the permanent customer card, and restores focus if startup rerender replaces the element. A real user pointer/key interaction ends automatic focus.
- Targeted tests cover main-page URLs, mobile navigation fallback, successful navigation, stale WORKING state, late card rendering and unaffected non-approval notification routes.
