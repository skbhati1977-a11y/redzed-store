REDZED UNIVERSAL PRODUCTION V767 — EVIDENCE BUTTON FREEZE FIX

CAUSE FIXED
- Old V766 script observed the full page DOM.
- Opening Alter Evidence changed modal/select/message DOM.
- Every DOM change started another RPC and another DOM change.
- This recursive loop made Chrome show Page Unresponsive.

WHAT CHANGED
- Full-page MutationObserver removed.
- Only Alter Evidence modal's own class transition is observed.
- Line Man mapping loads only once per modal opening.
- Duplicate/in-flight RPC calls are blocked.
- Wrong production worker is cleared while active Line Man list loads.
- Mandatory active Line Man validation remains.
- Existing responsibility engine and SQL remain unchanged.

UPLOAD THESE TWO FILES TO GITHUB ROOT
1. real-universal-production-v767.html
2. real-universal-production-v767-alter-evidence-fix.js

NEW LINK AFTER COMMIT
https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v767.html?v=7671

TO KEEP CURRENT V766 LINK WORKING
- Rename real-universal-production-v766-stable-replacement.html to:
  real-universal-production-v766.html
- Upload/replace it in GitHub root.

CURRENT LINK AFTER REPLACEMENT
https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v766.html?v=7671

NO NEW SQL IS REQUIRED.
Do not run Rollback SQL.
After GitHub Commit, press Ctrl + F5 once.
