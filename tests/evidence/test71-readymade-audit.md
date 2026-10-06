# Readymade Garments wiring audit — TEST71

Scope: Readymade only. Database migrations applied to hruartsemierwhtzonei. Financial fixtures and reconciliation are TEST mode; existing REAL activation guard remains. No main deployment.

## Completed

- Purchase draft/reopen/post with role checks, whole PCS validation, fixed ₹22/PCS margin, canonical stock and supplier Accounts, retry protection.
- Monthly Sales/Admin/Accounts salary allocated by readymade share of combined inward purchase value, then divided by readymade inward PCS. Missing manufacturing values block approval.
- Electricity/water/rent and applicable shared admin, selling, finance/bank, freight/packing and configured other overhead heads. Explicit expense pool takes precedence over Accounts actuals, then configured fixed provisions. Salary excluded from overhead to prevent double counting. Existing provision amounts unchanged.
- Base rate = purchase cost + weighted salary + overhead + ₹22, rounded to whole rupees. Owner-private cost breakdown, frozen base on first approval, later revisions on remaining stock.
- Existing RRQ core retained. Approval increase/decrease changes RRQ; PI drafts do not. Saved bill fluctuation survives stock refresh and posts once on FINAL CI.
- Sales Return/RCI reverses original invoice RRQ difference. Purchase Return reverses purchase-valued stock, posts supplier Accounts and releases approved quota. Duplicate posting protected.
- Market Window image fallback and approved rates only.
- Missing stock/Accounts postings reconciled for historical POSTED TEST purchases RMP-T1 and RMP-T2.

## Verification and limits

Five focused UI/regression tests pass. Live transactional rollback test passes purchase, fixed22 despite legacy16 input, Accounts/stock idempotency, overhead, Market pending rate/image, RRQ approval/revision, PI draft, CI fluctuation, Sales Return, Purchase Return/retry, RCI, stock balance and remaining-stock revision. Fixtures rolled back.

Original static suite has 100 failures on both original HEAD and changed code; failed names matched with no new failures in that comparison. Existing failures remain. UI behavior tested with jsdom; signed-in browser/mobile behavior has not been verified.

## Pending

August 2026 existing RM lots report PENDING_MANUFACTURING_VALUE because historical manufacturing STORE_RECEIVE rows have missing/nonpositive valuations. Correct business-approved source values are required before weighted rates can be finalized. No zero substitutions or invented values applied. Business must maintain actual salary, expense and provision amounts.

REAL activation/production deployment were not performed. Generic purchase-return reversal/cancellation for Readymade was not added; normal purchase-return posting is wired and tested.
