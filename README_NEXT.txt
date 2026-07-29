1. Upload/replace these 4 files in the same GitHub folder:
   - real-universal-production-v72040.html
   - real-universal-production-v72040.js
   - redzed-alter-v1.js
   - redzed-alter-v1.css

2. Commit message:
   Integrate Alter Remake Damage into Universal Production

3. Open the Universal Production page and hard-refresh with Ctrl+Shift+R.

4. Test one lot:
   - Click Alter / Remake / Damage
   - Register Alter with colour, size, qty and live camera image
   - Confirm ALTER pending qty appears on the lot card
   - Login as Cutting Master and issue Remake
   - Login as Department Head and register Damage/update status
   - Click thumbnails to verify full-screen image viewer

Important:
The integration tries common field names from RR.requireRoles() for user/profile data. If Worker, Line Man, Cutting Master or Department is blank, share the console output/shape of state.auth or the real-common.js auth return object so those exact fields can be mapped.
