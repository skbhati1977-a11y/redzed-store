REAL FACTORY · ACCOUNTS V8074 · CONSOLIDATED FRONTEND

UPLOAD / REPLACE THESE 2 FILES TOGETHER:
1. real-accounts-v805.html
2. real-accounts-v805.js

DO NOT REPLACE:
- config.js
- real-common.js
- real-dashboard.html / dashboard JS

INCLUDED IN ONE JS:
- Ledger mapping + ledger dropdowns
- Supplier / party / cash-bank ledger mapping
- Material Type mapping
- Material Name mapping
- UOM sync
- Qty × Rate live Total
- Canonical Accounts bootstrap mapping (including source-managed material mappings exposed by backend)
- Generic material-master fallback
- Report search
- Trial Balance
- Profit & Loss
- Balance Sheet
- Day Book
- Ledger Statement
- Universal Purchase Return view
- TEST / REAL mode preservation

IMPORTANT:
The frontend does not invent source-specific material schemas. Regular Cloth / Matching Cloth / Sticker / Metal ID
are expected from the existing canonical Accounts bootstrap mapping. Generic rr_material_master_v805 is only a fallback.

OPEN AFTER DEPLOY:
real-accounts-v805.html?v=8074
Then Ctrl+Shift+R once.
