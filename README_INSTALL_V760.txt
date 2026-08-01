REDZED UPM V760 — COSTING FOUNDATION

IMPORTANT
=========
V760 includes the complete approved V759.1 Damage UI plus Costing.
Do not load V759.1 and V760 together.

INSTALL ORDER
=============

1. Run complete SQL:
   REDZED_UPM_V760_COSTING_FOUNDATION.sql

2. Upload to GitHub root:
   real-universal-production-v760-costing.js

3. Remove previous V759.1 patch line.

4. Keep:
   <script src="real-universal-production-v729.js?v=741-dynamic-random-1"></script>
   <script src="real-universal-production-v760-costing.js?v=7601"></script>

5. Commit, wait for deployment, then Ctrl + Shift + R.

EXPECTED SQL RESULT
===================
ok = true
version = V760_COSTING_FOUNDATION

EXPECTED CONSOLE
================
V760_COSTING_FOUNDATION_UI

FEATURES
========

- COSTING button on every first-window Lot card.
- COSTING button inside Check-in.
- Central Lot Costing popup.
- One Lot + canonical Department = one Actual Rate.
- First Submit Actual Rate gate.
- Rate missing:
  Submit holds, costing popup opens on that department.
- Save rate:
  original Submit resumes.
- Department Head sees/edits own department only.
- Owner/Admin/Manager see all process rates.
- Material + Owner Margin are Owner-only.
- Standard Rate is fallback only.
- QC dedicated head.
- TH CUT aliases → THREAD_CUT.
- Kaaj/Btn spelling variations → KAJ_BUTTON.
- Tanki/Tack/Teak/Teek variations → TANKI_TACK.
- Universal Owner Margin applies only to unlocked Lots.
- Store/Web locked price is protected from future universal margin.
- Every Damage appears in Costing as Company Loss.
- Worker Recovery/Relaxation remains separate.
- Damage never rewrites Product Cost.

WHATSAPP
========
V760 creates secure one-time rate-request records with token and expiry.
Actual WhatsApp Business sending/CTA wiring is a separate connector step.
No visible raw website URL is required in the future message template.
