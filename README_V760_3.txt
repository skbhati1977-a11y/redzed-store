REDZED UPM V760.3 — SUBMIT RESUME + CANCEL FIX

FIX 1 — RATE SAVE KE BAAD SUBMIT
================================
Old issue:
Rate save ho rahi thi, lekin direct hidden submitBtn click UI refresh se pehle
fire ho raha tha. Isliye Next Department / Submit confirmation open nahi hoti thi.

New flow:
Rate save
→ Costing popup close
→ Latest Colour table refresh
→ Department context restore
→ Colour reselect
→ Visible SUBMIT action one-time bypass ke saath fire
→ Existing Next Department / confirmation flow open

Rate gate sirf ek baar bypass hota hai. Permanent bypass nahi hai.

FIX 2 — ALTER CANCEL
====================
Old issue:
Inline Alter form Colour row ke andar nahi, next detail <tr> me insert hota tha.
Cancel Colour row ke andar panel dhoondh raha tha, isliye kuch remove nahi hota tha.

New flow:
Cancel
→ Next v756-inline-row remove
→ Focus/dim classes clear
→ Normal all-Colour table restore

INSTALL
=======
1. SQL run karne ki zarurat nahi.

2. GitHub root me upload:
   real-universal-production-v7603-costing.js

3. Old V760.2 script line replace karein:

   <script src="real-universal-production-v7603-costing.js?v=7603"></script>

4. V760.2 aur V760.3 ek saath load nahi honge.

5. Commit → deployment → Ctrl + Shift + R.

EXPECTED CONSOLE
================
V760_3_SUBMIT_RESUME_CANCEL_FIX_UI

TEST
====
A. First Submit Rate Gate:
   C3 Print → Submit → Rate fill → SAVE COSTING
   Expected: Next Department / existing Submit confirmation automatically open.

B. Alter Cancel:
   Kisi Colour par ALTER FILL → CANCEL
   Expected: Inline form turant close, full table normal.
