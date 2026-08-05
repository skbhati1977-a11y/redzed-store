REDZED GLOBAL GOOGLE SHEETS TABLE PLATFORM V775.1
================================================

PURPOSE
-------
One global table system for the complete REDZED web app:
- Past modules
- Present modules
- Future modules

WHY real-common.js
------------------
REDZED module pages already load real-common.js.
The new real-common.js loads the table platform globally.
Any current or future page that contains a <table> and loads real-common.js
receives all controls automatically. No database/Supabase SQL is required.

MANDATORY TABLE FEATURES
------------------------
1. Every column header gets its own ▼ filter button.
2. Column filter menu:
   - Search values
   - Select All
   - Clear Selection
   - Apply
   - Clear Filter
   - Sort A → Z
   - Sort Z → A
3. Freeze Top Rows:
   - NONE / 1 / 2 / 3 / 4 / 5
4. Freeze Left Columns:
   - NONE through up to 8 columns
5. Clear All Filters
6. Visible row count
7. Bottom horizontal slider always remains visible when needed.
8. Works on dynamically created tables and nested evaluation tables.
9. Filter/freeze settings are remembered in that browser.
10. iPhone, iPad and Android safe-area and touch support.

UPLOAD TO GITHUB ROOT
---------------------
Mandatory global files:
- real-common.js
- real-mobile-compat-v775.js
- real-google-sheet-table-v775.js

Compatibility files:
- real-table-freeze-v773.js
- real-mobile-compat-v774.js

The compatibility files prevent old module HTML references from breaking.

Matching current module files are also included:
- real-pcs-rate-payroll-v779.html
- real-pcs-rate-payroll-v779.js
- real-universal-production-v769.html
- real-universal-production-v772-submitted-work-link.js
- real-upm-submitted-work-v772.html
- real-upm-submitted-work-v772.js

TEST
----
Open:
VERIFY_REDZED_GLOBAL_TABLE_V775.html

Then test:
- Each header ▼ filter
- Sort
- Freeze 1/2 rows
- Freeze 1/2 columns
- Bottom horizontal slider

IMPORTANT
---------
Pages that do not load real-common.js are outside the global bootstrap.
Such pages should add:
<script src="real-common.js?v=7751"></script>

No Supabase SQL is needed.
