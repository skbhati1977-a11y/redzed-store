REDZED UPM V725 — Integrated Dashboard

FILES TO UPLOAD TO GITHUB ROOT
1. real-universal-production-v725.html
2. real-universal-production-v725.js

EXISTING FILES THAT MUST REMAIN IN THE ROOT (UNCHANGED)
- real-cutting-master.html
- redzed-upm-smart-packing-v1.js
- config.js
- real-common.js

DATABASE
Run REDZED_UPM_V725_INTEGRATED.sql in Supabase SQL Editor after the earlier UPM core/V723 rate tables are installed.

WHAT V725 CHANGES
- Adds top-level UPM dashboard modules: Production, Cutting Module, Packing & Dispatch, Costing, Reports.
- Production remains the current lot-card/check-in workflow.
- Cutting Module is mounted unchanged through real-cutting-master.html.
- Existing Smart Packing Box Algorithm is mounted unchanged through redzed-upm-smart-packing-v1.js.
- All lot cards have a fixed equal height and fixed image/button zones.
- Responsive grid: 4 desktop, 3 laptop, 2 tablet/large mobile, 1 narrow mobile.
- Universal form first reads the canonical UPM cut-size map and only falls back to the direct Cutting tables.

OPEN
https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v725.html?build=725

IMPORTANT
The SQL does not rewrite the Cutting Module or Packing algorithm. It only supplies a safer production-form read adapter.
