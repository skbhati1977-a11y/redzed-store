REDZED UPM V741 — DYNAMIC RANDOM COLOUR ASSIGNMENT

BASE REQUIRED
- Current V740 SQL must already be installed and working.
- Identity lock (CB / Art / Print / Frame) is not changed.
- Alter / Line Man / WhatsApp flow is not changed.

INSTALL ORDER
1. Run REDZED_UPM_V741_DYNAMIC_RANDOM_ASSIGN.sql in Supabase SQL Editor.
2. Replace in GitHub root:
   real-universal-production-v729.html
   real-universal-production-v729.js
3. Commit/deploy.
4. Open the existing real-universal-production-v729.html URL.
5. Hard refresh: Ctrl + Shift + R.

V741 RULES
- Cutting release does not hard-own a Colour in Printing.
- The mapped Print department remains eligible, but all eligible leaf production departments can claim an OPEN Colour.
- First Assignment Wins: one Colour can have only one active department owner across the whole Lot.
- Submit completes that department assignment and returns the Colour to OPEN random queue.
- A department that already completed that Colour cannot claim the same Colour again.
- Department dropdown states:
  BASE   = no Colour in that department
  ORANGE = partial Colours; option includes Colour codes, e.g. C1 C3 C6
  GREEN  = all Lot Colours currently running there
  RED    = all Lot Colours submitted/completed there
- Older duplicate active Colour assignments are migrated: latest remains active, older duplicates become RELEASED.

EXPECTED FRONTEND CONSOLE
REDZED UPM V741_DYNAMIC_RANDOM_ASSIGN
