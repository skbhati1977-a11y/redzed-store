REDZED UPM V760.4 — DIRECT SUBMIT + IDENTITY DISPLAY FIX

ROOT CAUSE CONFIRMED
====================
The V760.3 visible Colour table came from currentMatrix, but Submit still
depended on the hidden legacy .colour-card engine.

This failed in two ways:

1. Some Lots had matrix rows but no legacy state.context rows/cards:
   "Colour C1 ka hidden action engine nahi mila."

2. Some Lots had a hidden card but the programmatic checkbox/button state was
   stale or disabled, so hidden submitBtn.click() silently did nothing.

FIX
===
SUBMIT no longer uses:
- hidden .colour-card
- hidden .work-pick
- hidden #submitBtn
- click timing/polling

New Submit flow:
Visible Colour row
→ First Submit Actual Rate gate
→ dedicated Colour confirmation
→ Next Department view selection
→ direct rr_upm_submit_colours_v741 RPC
→ refresh matrix
→ open selected next Department view

ALTER / DAMAGE / REMAKE
=======================
Their existing quantity engines are unchanged.

1RR1 DISPLAY
============
V761 identity check is used after Check-in rendering.

When identity_complete=true and no Print exists:
PRINT NO = NOT APPLICABLE
FRAME NO = NOT APPLICABLE

If Print exists but Frame is missing:
FRAME NO = MAPPING REQUIRED

INSTALL
=======
1. No SQL required.

2. Upload to GitHub root:
   real-universal-production-v7604-costing.js

3. Replace V760.3 HTML line with:
   <script src="real-universal-production-v7604-costing.js?v=7604"></script>

4. Do not load V760.3 and V760.4 together.

5. Commit → Pages deployment → Ctrl + Shift + R.

EXPECTED CONSOLE
================
V760_4_DIRECT_SUBMIT_IDENTITY_DISPLAY_FIX_UI

TEST
====
A. 2RSKB4:
   C1 Submit
   Expected: no hidden-engine error; confirmation opens.

B. 2SKB4 / 2SKB6:
   Colour Submit
   Expected: confirmation → direct RPC → success.

C. 1RR1:
   Print/Frame should show NOT APPLICABLE when V761 identity is complete and
   no Print is mapped.
