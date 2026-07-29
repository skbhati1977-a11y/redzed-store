REDZED UNIVERSAL PRODUCTION V720.40 — INSTALL ORDER

1) Supabase SQL Editor में REDZED_UNIVERSAL_PRODUCTION_V72040.sql पूरा run करें.
2) GitHub root में upload करें:
   - real-universal-production-v72040.html
   - real-universal-production-v72040.js
   - redzed-cutting-upm-bridge-v72040.js
3) Dashboard/menu में link add करें:
   <a href="real-universal-production-v72040.html">Universal Production</a>
4) Cutting page में current Cutting JS के बाद bridge include करें:
   <script src="redzed-cutting-upm-bridge-v72040.js?v=72040"></script>
5) Cutting lot release की successful Supabase RPC/insert के तुरंत बाद यह call लगाएँ:
   await window.RR_UPM.registerReleasedLot(savedLot, savedBreakupRows);
   savedLot = release के बाद मिला lot object
   savedBreakupRows = उस lot की colour/size breakup rows
6) पुरानी tables delete/rename न करें. यह migration additive है.

MANUAL TEST
- Universal Production खोलें और owner/admin login करें.
- Register Lot से एक test lot बनाएं.
- GOOD entry डालें; planned quantity पूरी होने पर colour next department में auto-forward होगा.
- Partial qty पर status PARTIAL रहेगा.
- Alter बनाएं; ALTER_OUT entry और open alter request बनेगी.
- Supabase में rr_upm_* tables verify करें.

IMPORTANT
- Actual production rates eRate से capture होते हैं; amount generated column है.
- Department order rr_upm_departments.sequence_no से बदल सकते हैं.
- New department insert करके workflow configurable है.
- Existing rr_lots/rr_production_lots/rr_cutting_lots_v3 remain untouched.
- First production registration uses a canonical text identity so existing UUID/text legacy IDs दोनों safely map हो सकें.
