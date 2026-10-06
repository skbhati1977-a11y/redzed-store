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

## Real Chat extension — 6 October 2026

Readymade Garments appears first before CB for Owner/Super Admin/Admin/Accounts/Sales/Manager. OPEN includes New Purchase and saved drafts. Modal fields: Supplier/Seller, bill/date, lot/item, category, sizes, colours, cloth, art, final photo/upload, final whole PCS, purchase rate/value, optional final sales rate and caption note. Save & Confirm posts through the same purchase engine, then moves to WORKING. Entered final sales rate is approved through existing RRQ only when complete costing and Owner authority allow it; otherwise it is retained for later approval.

WORKING provides image/caption cards, category filter, lot/item search, 1/2/3-column views, multi-select/Select All, existing customer collection SEND chooser, available stock balance, Owner costing/rate approval and purchase-role Return. SEND preserves collection-cycle/category/already-sent filtering and uses existing customer chat engine. Only approved in-stock garments can be selected. Return includes mandatory reason and retry key. Refresh, visibility recovery and the existing periodic refresh read canonical balances. Images/category/sizes/colours/caption mirror existing Market profiles/collection captions.

Verification: 11 focused tests pass, including the complete Real Chat shell (first placement, OPEN/WORKING and Back); Readymade live rollback transaction checks pass including purchase final RRQ approval and shared caption metadata. A real active Sales identity reports can_purchase=false and private_cost_visible=false. Full suite comparison shows the same 100 baseline failures, no new failed names in that run.

Visual limitation: agent-browser and Playwright Chromium could not start because the runtime denied socket creation. No live signed-in mobile visual check is claimed. jsdom checks exercise the actual HTML/JS shell; financial checks use live TEST SQL with rollback.
