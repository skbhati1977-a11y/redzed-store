REDZED UPM V740 FINAL TARGETED

INSTALL ORDER
1. Supabase backup.
2. Run REDZED_UPM_V740_INSTALL.sql once.
3. Replace ONLY real-universal-production-v729.html and real-universal-production-v729.js in GitHub root.
4. Keep using the existing real-universal-production-v729.html URL.
5. Deploy and hard refresh Ctrl+Shift+R.

LOCKED FEATURES
- Identity is resolved from released Cutting Lot and permanently locked. Empty later mappings cannot overwrite it.
- Line Man candidates come from active Worker Directory role + Fabrication/current/parent department mapping.
- First Alter enrols one Lot Line Man. With multiple candidates, selection is mandatory.
- Enrolled LM cannot escape the Lot stream; transfer/leave/force replacement creates immutable history.
- Alter chain: LM Alter -> CM Remake Issue -> LM Receive Master -> LM Deliver Karigar -> LM Receive Karigar -> Good/None.
- Karigar gets responsibility on delivery; no Karigar confirmation button. Responsibility clears only on LM final receive.
- Short blinking summary shows actual mapped responsible name, role short code, quantity, colour/size.
- WhatsApp is an alert only; backend stage is the responsibility source of truth.
- First Colour Submit asks Next Department. That route is locked for all remaining Colours from the same department.
- Department dropdown shows only running/current relevant departments.
- Untraceable items require Manager investigation and Owner/Admin decision: approve company loss, deny manager debit, or recheck.

VALIDATION
- No sample names or UUIDs are hardcoded.
- JS syntax checked with Node.
- SQL uses existing exact REDZED table/function names from the supplied repository/export.
- Live Supabase execution is the final schema validation.
