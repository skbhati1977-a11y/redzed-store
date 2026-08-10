REAL FACTORY V805 FRONTEND PACKAGE

UPLOAD TO SAME GITHUB FOLDER:
1. real-dashboard.html
2. real-dashboard-v805.js
3. real-accounts-v805.html
4. real-accounts-v805.js
5. real-material-master-v805.html
6. real-material-master-v805.js
7. real-common.js
8. config.js

IMPORTANT CONFIG
- Open config.js.
- Paste the SAME Supabase Project URL and anon/public key already used by REAL FACTORY.
- Never put service_role key in frontend.

ROLE DISPLAY
- Internal OWNER remains canonical.
- UI displays OWNER as "Super Admin".
- ADMIN remains "Admin".

GLOBAL ENTER RULE
- Entry forms: Enter moves to next eligible field.
- Search/file/hidden fields keep normal behavior.
- Last eligible control can trigger the form action.

HTML + JS PAIR RULE
- real-dashboard.html + real-dashboard-v805.js
- real-accounts-v805.html + real-accounts-v805.js
- real-material-master-v805.html + real-material-master-v805.js
Always replace/deploy matching pair together.

FIRST TEST
After config.js is filled and files deployed:
1. Login as current OWNER/Super Admin.
2. Open real-material-master-v805.html
3. Create TEST PASTING ROLL.
4. Then continue weighted-cost purchase test.
