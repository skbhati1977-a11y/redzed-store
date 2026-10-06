# TEST71 saved bill blocks receipt before picker

2026-10-06. User video 1003830502.mp4 shows the purchase form remaining open throughout, with 'Supplier bill already exists. Open its saved purchase.' while Save & Confirm / Send Receipt is pressed. The native share handler is never reached in this recording.

Targeted repair: on a new purchase confirmation, a guarded read-only RPC checks the same canonical normalized supplier + trimmed bill number identity used by the existing save engine. An existing POSTED bill opens its authoritative receipt and share panel before new-entry validation/upload. It does not create, overwrite or repost purchase/stock/Accounts/notes. An existing DRAFT offers an explicit Open saved bill draft button with original saved fields. A duplicate-save race also resolves to the saved receipt. Non-duplicate failures remain errors and do not repost automatically.

Backend migration test71_readymade_saved_bill_receipt applied. Function is TEST-only, uses existing operator guard and receipt/draft engines, with public/anon execution revoked.

38 automated tests passed, including posted bill recovery without calling save, safe draft reopening, concurrent duplicate recovery and existing picker/stock/Art regressions. Receipt preparation test wait now observes ready state instead of assuming hash completion in 10 ms. Live rollback passed posted receipt/debit voucher lookup, normalized supplier matching, absent bill, draft fields, anon deny, Art/stock/sale/returns, frozen files and note/share idempotency. Existing receipt sharing browser fallbacks are retained. No actual Android WhatsApp delivery is claimed from automated tests.
