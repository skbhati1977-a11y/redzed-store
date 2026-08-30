# REAL CHAT IMPLEMENTATION — STEP 01 AUDIT / BASELINE

Status: AUDIT ONLY — NO RUNTIME/DB MUTATION
Date: 2026-08-30

## Purpose
Freeze the existing Real Chat / Collection / Requirement baseline before implementation. Step 01 makes no runtime code or schema change.

## Existing frontend baseline
- Customer chat: `real-customer-live-chat-v9434.js`.
- Customer collection page: `real-market-share-v9420.html` + `real-market-share-v9420.js`.
- Staff chat: `real-sales-live-chat-v9434.js`.
- Current customer chat is a bottom-sheet (`height:min(82dvh,760px)`), not full-screen.
- Customer identity is currently cached locally under `rr_market_customer_identity_v9423` with name/mobile and chat bootstrap uses share token + mobile.
- Existing browser alert layer `real-chat-bell-alert-v9443.js` requests Notification permission and can show `new Notification(...)` while the page is alive/hidden; this is not true closed-app/background Web Push.

## Existing backend baseline
Core tables found:
- `rr_customer_chat_v9433`
- `rr_customer_chat_messages_v9433`
- `rr_market_share_v9420`
- `rr_market_share_lots_v9420`
- `rr_market_requirements_v9420`
- `rr_market_requirement_lines_v9420`
- `rr_notifications`

Existing relation already available:
- Requirement -> Collection/Share through `rr_market_requirements_v9420.share_id`.
- Requirement lines -> Requirement through `requirement_id`.
- Chat messages -> permanent chat through `chat_id` and optional `order_session_id`.
- Market share already records `last_opened_at`, which can support NOT OPENED vs OPENED state.

## Baseline aggregate counts at audit time
- Customer chats: 3
- Chat messages: 81
- Market shares/collections: 80
- Share lots: 289
- Requirements: 17
- Requirement lines: 43

These counts are baseline-only and must not be used as business assumptions after this audit date.

## Security findings
1. Current customer-side local name/mobile cache is convenient but must not become the authentication authority for permanent chat history.
2. Secure re-entry must require server-validated entry/session binding; mobile alone must never reveal old chat.
3. Chat tables have RLS enabled. Market share/requirement tables currently do not have RLS enabled; customer access is therefore expected to remain behind controlled RPC contracts and must not be opened with direct anonymous table access.
4. True Web Push requires a separate service worker + device push subscription + backend sender. Existing `new Notification()` polling is only an in-page alert layer.
5. Push private/server keys must never live in GitHub Pages/browser code.

## Existing system pieces to preserve
- Staff inbox and staff Real Chat.
- Existing permanent chat/message records.
- Existing Collection/share records and lots.
- Existing Requirement records/lines and PI linkage RPCs.
- Existing PI cancellation invariants and audit behavior.

## New capabilities still needed after Step 01
- Explicit Collection number/cycle and cumulative update history.
- Same-Collection duplicate-style prevention with fresh eligibility for a NEW Collection.
- Lifecycle/state contract covering SENT, NOT OPENED, OPENED, NO RESPONSE, REQUIREMENT RECEIVED, PI, CI, CLOSED/CANCELLED.
- Server-authoritative read/unread state.
- Reminder schedule/state and Mr. Ranveer sender event creation.
- Secure customer session/device binding.
- Background Web Push subscription layer.
- Highest-stage cancellation orchestration linking Collection/Requirement/PI/CI.
- Separate Mrs. Bhati Reeka payment reminder layer.

## Safe implementation decision
Do not replace current tables or current stable RPCs. Add versioned extension/state tables and versioned RPCs around the existing system, then promote only after isolated tests.

## Step 01 verdict
PASS — baseline is understood and sufficiently mapped to begin Step 02 design/contract work. No production behavior was changed by this audit.

## Next controlled step
Step 02: design the Collection lifecycle/linkage data contract only. Before applying any schema migration, verify exact keys, uniqueness rules, statuses, backward compatibility and rollback plan.