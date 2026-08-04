REDZED UNIVERSAL PRODUCTION V770
ALTER RECEIVER LINE MAN · PER JOURNEY ROUTING

FINAL BEHAVIOUR
1. Every Alter Fill Save creates a new independent Alter journey.
2. Karigar/worker/non-Line-Man:
   - Alter Receiver Line Man searchable dropdown is mandatory.
   - Dropdown starts blank on every new Alter Fill.
   - Previous journey or permanent Lot LM is not silently reused.
   - Selected active Line Man becomes holder of that Alter journey.
3. Logged-in active Line Man:
   - Their own Line Man worker ID is auto-selected.
   - Selection remains locked to self.
   - The new journey is automatically assigned to that Line Man.
4. Permanent Lot LM enrolment is NOT changed by this selection.
5. Existing responsibility stage engine is unchanged.
6. Existing completed/submitted department assignment compatibility is retained.
7. Existing WhatsApp/outbox receives the effective selected/self p_line_man_id.

INSTALL ORDER
A. SUPABASE SQL EDITOR
   Run complete file:
   REDZED_V770_ALTER_RECEIVER_ROUTING.sql

B. GITHUB ROOT
   Upload/replace:
   - real-universal-production-v770.html
   - real-universal-production-v729.html
   - real-universal-production-v770-alter-routing-fix.js

   Ensure these already-uploaded dependencies remain present:
   - real-universal-production-v765-independent-alter.js
   - real-universal-production-v768-damage-balance-fix.js
   - real-universal-production-v769-worker-claim-warning-fix.js

C. TEST LINK
   https://skbhati1977-a11y.github.io/redzed-store/real-universal-production-v770.html?v=7701

D. AFTER COMMIT
   Press Ctrl + F5 once.

TESTS
1. Log in as Karigar/worker:
   - Open a new Alter Fill.
   - Dropdown must be blank and mandatory.
   - Select Dhiraj or another active Line Man.
   - Save; that selected LM must appear as Alter journey holder.
   - Open another new Alter Fill; dropdown must again start blank.

2. Log in as active Line Man:
   - Open Alter Fill.
   - Own name must auto-select and lock.
   - Save; journey must be assigned to self.

3. Verify permanent Lot LM:
   - Alter receiver selection must not silently change Change Lot LM enrolment.

4. Submitted department:
   - Latest completed assignment worker history must still allow a new Alter Fill.

IMPORTANT
- Do not run an old rollback SQL.
- V770 replaces the old V767 frontend LM lock behaviour.
- The V770 HTML intentionally does not load real-universal-production-v767-alter-evidence-fix.js.
