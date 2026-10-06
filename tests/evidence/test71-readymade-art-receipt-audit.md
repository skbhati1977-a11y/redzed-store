# TEST71 Readymade Art defaults and supplier receipt audit

2026-10-06. Scope: test71-real-chat-e2e-finalization only; existing stock and Accounts engines retained.

Art precedes Item Name, both searchable select-or-create lists. Confirmed purchases append Art defaults (item, photo, category, size, colours, purchase and sale rates) with effective timestamp. Existing purchases keep their snapshots. Stale Art revision is rejected atomically; explicit reload allows review. Rate approvals update future sale defaults. Live balances use canonical stock across all matching lots; Working and existing customer In Stock masking retained. Manufacturing Art masters are independent.

Preparing supplier JPG explicitly confirms purchase: received stock and original bill plus Short Debit Note / Excess Credit Note post atomically. Immutable receipt snapshot and stored JPG are reused. Native file sharing starts on user tap; user chooses WhatsApp/contact. OK records a share-app handoff, never asserts delivery. Cancellation creates no share record. Unsupported browsers offer JPG download. Upload/record retries do not repost purchases or notes.

Validation:
- 21 Readymade UI unit tests passed, including Art mapping, live balance and master creation regressions.
- 3 receipt tests passed: real JPEG bytes/rendered quantities and valuation; reuse and synchronous native share; retry event idempotency, cancellation and download fallback.
- Live rollback Art/share SQL passed: prospective defaults, original rates unchanged, stale version rollback, purchase/actual finalized CI sale/return balance, receipt/JPG metadata immutability, duplicate event and note prevention, private access.
- Live receipt/Accounts regression passed: Short/Excess/Matched, draft edits, stock, original bill, notes, supplier balances, P&L, Balance Sheet, Trial Balance, balanced journals, retries and returns.
- Both JS syntax checks passed; canonical SQL equals CLI-created migration.
- New private tables have RLS enabled and direct grants revoked; guarded operator RPCs. Advisor RLS-without-policy informational finding is intentional deny-all for direct access. Existing unrelated advisories were not changed.

Limits: native WhatsApp contact selection and actual delivery require a device check; automated tests verify file-share contract, not external delivery. Live storage fixture tests metadata ownership/path only; JPEG encoding and hash/reuse checked in frontend tests. Legacy broad rollback has an obsolete Market thumbnail assertion after readiness gating; targeted current receipt and Art checks are the acceptance evidence.

Backend migrations applied: test71_readymade_art_receipt and test71_readymade_art_registration_order. Repository migration combines final definitions for reproducible replay.
