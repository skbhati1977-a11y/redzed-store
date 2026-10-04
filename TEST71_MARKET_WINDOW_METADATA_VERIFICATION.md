# Market Window targeted metadata fix — 2026-10-04

Scope: Market Window metadata projection and display only. Stock ledger, quantity calculation, packing, pricing approval, costing formulas, media records and share actions unchanged.

- Existing cards RPC keeps its return signature. Approved RRQ sale rate is resolved independently of nonzero stock, then product sale rate; missing rates remain null, explicit zero remains zero.
- Released Cutting/Production lot sizes precede legacy marketing sizes. Existing profile category remains first; missing category falls back to the released lot Art category. Item name is no longer displayed as category.
- Authenticated batched colour metadata uses the existing canonical lot breakup source; missing colours display a dash. This describes released lot colours, not colour-wise current stock balances.
- Existing GSM source and media retained; no values inferred from garment photographs.
- Before/after rollback proof preserved every card's available/pipeline pcs, media and GSM. Restored E2E9036-D2-V10 rate 125 and 2NSKB2 sizes 2XL / 3XL / 4XL. Missing rates for 2614 and RMTST-102A/B remain null.
- Installed database audit: 15 cards, 2297 available pcs, zero raw-ledger quantity or approved/product rate mismatches. Missing source values remain: 3 rates, 3 size sets, 4 categories, 15 GSM.
- Two focused frontend renderer tests plus five costing compatibility tests passed; JavaScript syntax passed. Live authenticated Codespaces browser verification remains blocked by Cloud Browser policy. No full TEST71 release-gate claim.
