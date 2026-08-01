REDZED UPM V757.4 — REFRESH + ENGINE WORKER BRIDGE

ONLY TWO FIXES
==============

1. FIRST-WINDOW REFRESH
-----------------------
The original V729 Refresh button rebuilds board cards.

V757.4 now:
- allows original Refresh/load to run,
- clears V757 card signatures and caches,
- removes stale summary nodes,
- re-renders the approved Colour summaries after 250ms, 800ms and 1600ms.

Refresh no longer leaves the old combined V729 status bar as the final view.

2. SINGLE COLOUR MAPPED WORKER
------------------------------
The searchable mapped-worker list can be newer than the hidden V729
Colour worker select.

V757.4 now:
- validates worker from department mapping,
- safely adds the selected worker option to the stale hidden Colour select,
- adds the same option to the hidden bulkWorker engine when needed,
- continues through the existing APPLY WORKER / ASSIGN SELECTED flow.

No worker is hard-coded.

NOT CHANGED
===========
- First-window layout
- Check-in table layout
- Bulk Assign logic
- Alter / Damage / Submit
- Next Department confirmation
- Size / PCS
- Alter journey
- Backend assignment RPCs

INSTALL
=======
Replace:
real-universal-production-v757-final-approved.js

HTML:
<script src="real-universal-production-v757-final-approved.js?v=7574"></script>

Console:
V757_4_REFRESH_AND_ENGINE_WORKER_BRIDGE
