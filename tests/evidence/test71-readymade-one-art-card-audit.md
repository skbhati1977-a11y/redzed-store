# TEST71 one Art, one Working card

2026-10-06. Targeted change: confirmed purchase records remain separate in supplier Accounts; Working groups cards by trimmed, case-insensitive Art No. Missing Art stays separate by lot so unrelated garments never merge.

The parent card shows summed canonical live available PCS for every purchase of its Art, including under lot search/category/mapping filters. Working department count uses unique Art identities. Purchase records are collapsed inside the card, retaining stock/bill-specific receipts, approvals and returns. Customer sharing expands selected Art into eligible original lots so existing sale/RRQ/FIFO/bill mapping is preserved. Rates remain per original purchase; there is no blended rate or new accounting engine.

Balances refresh every 10 seconds while visible, and on app resume. Open return forms and entered quantities survive refresh. Return validation uses the refreshed original-stock balance; server validation remains authoritative.

27 frontend tests passed, including new grouped balance, multiple underlying bill receipts, whole-Art selection, targeted second-bill return, filtered total, approval preservation and non-destructive live polling. Live rollback tests passed for two separate posted purchases, Short/Excess received balances, actual finalized CI sale, sales return and purchase return, plus total Art balance in the Working queue. Existing receipt regression passed including supplier accounts, P&L, Balance Sheet, Trial Balance and balanced journals.

Backend migration test71_readymade_one_art_card applied. TEST71 only. Manufacturing, Main and customer rendering untouched.
