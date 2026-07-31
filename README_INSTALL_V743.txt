REDZED UPM V743 — V742 + First Window Live Status (Merged)

1. Run REDZED_UPM_V742_V743_MERGED.sql in Supabase SQL Editor.
   This includes the V742 department-colour aggregation and V743 first-window board status.
2. Replace in GitHub root:
   - real-universal-production-v729.html
   - real-universal-production-v729.js
3. Commit/deploy and hard refresh Ctrl+Shift+R.

Locked identity source:
- The first-window CB/Art/Print/Frame values are read from the same immutable V740 Cutting identity snapshot used inside CHECK IN.
- Blank/MAPPING REQUIRED board values cannot overwrite a locked identity.

First-window live rows:
- ORANGE: partial assigned/running/submitted; colour codes are shown.
- GREEN: all colours assigned/running.
- RED: all colours submitted from that department.
- Up to 4 department rows are shown; additional rows show +N MORE.

No existing identity, Alter journey, worker mapping, or assignment logic is changed by V743.
