# TEST71 action queue audit — 9 October 2026

## Original audit result (before the remediation below)

Requested regular workflow: newly ready or accepted goods awaiting assignment belong in OPEN; a worker's submitted handover awaiting one atomic Accept & Count belongs in STAFF WORKING; assigned, physically received goods awaiting Submit belong in WORKER WORKING. Save of a complete handover must remove it from STAFF WORKING and expose next assignment in OPEN. Alter and Rectification follow their own current action. Read status never changes pending work.

This audit inspected the TEST71 frontend, actual Supabase function definitions, authenticated read-only projections and canonical records. Transition tests used a transaction which was rolled back. No business counts, assignments or receiver selection were changed by the audit.

## Verified results

- Normal Submit controls: six distinct assignments across all twelve post-cutting production departments. Printing: 2 (2NSKB2, 2625); Sticker: 1 (2633); Stitching: 1 (2635); QC: 1 (2601); Press: 1 (2608). Other departments: 0. These are genuinely pending Submit work, not six unread messages.
- Pending submitted handovers: 14. Fabrication STAFF projection returns 13. Eleven legacy LM_ACCEPTED requests have no counted_at and no count rows; TEST71 correctly describes them as Not Accepted / Accept & Count pending.
- Atomic Accept & Count passed twelve rollback checks, including invalid counts, authorization, late-failure rollback, full completion, disappearance from Working, next-stage assignment visibility in Open and repeat-save idempotency.
- Thirty-five frontend tests pass, including previous action / next action / read, filters, count-screen navigation and preserving existing cards when simply opening/backing out of a screen. Browser computed yellow color was verified separately.

## Queue discrepancies

1. **Missing handover:** lot 2639 / OVERLOCK is WAITING_LM with null target department and null selected receiver. Fabrication's mirror filters an explicit FABRICATION target, so this request is absent. The count form defaults a null target to Fabrication, but the list does not. This is a coverage inconsistency; an actor must never be invented or automatically accepted.
2. **OPEN contains assigned receipt work:** 26 receipt rows are already assigned but awaiting initial worker receipt/count. By department: Stitching 9, Folding 2, Kaaj/Button 6, Teak/Tanki 2, Thread Cut 1, QC 6. These come from operational OPEN/ACCEPT_PENDING, not assignment-due goods. Counts are colour/assignment rows, not necessarily 26 rendered cards after consolidation.
3. **Two different count workflows share the same label:** initial assigned-goods receipt is authorized to the assigned worker by rr_upm_confirm_worker_lot_receipts_v692. Submitted handover count is authorized to the receiver/staff. Moving the former into a staff section alone would not change the backend authority and would falsely promise a staff action. This requires explicit workflow alignment, not a text-only relabel.
4. **Fabrication outer WORKING count has a different source from its opened list:** departmentVisibleProjectionV763 uses only Fabrication's own receipt projection. openChat additionally appends cross-department worker rows, Alter and Rectification. Consequently a root WORKING total cannot be assumed to equal the complete opened action list.
5. **Unread totals are action-message counts:** several actions can refer to one card; read work remains pending. An Unread 3 badge cannot assert Submit pending 3. Badges now say Unread explicitly; card-screen totals say pending cards.
6. **OPEN source inconsistency:** Fabrication aggregates V9109 assignment-due candidates for all twelve departments, while individual department OPEN uses V9107 plus route/applicability filtering and assigned receipt rows. The snapshot has six raw Fabrication department candidates for one lot (2640), consolidated to one Fabrication lot card; routed V9109 assignment rows select Folding only. Individual Sticker OPEN also returns six rows for lot 2609 although V9167 says Sticker is not applicable. The assignment route policy and applicability authority must be shared before declaring every Open card valid. This audit does not impose a new route order.
7. **Resolved physical quantity inconsistency:** Stitching lot 2622 / Imamul has a RESOLVED receipt with confirmed_qty 22, but rr_upm_assignment_operational_qty_v280 recognizes only CONFIRMED/CONFIRMED_SHORT and emits good_qty 0 with no Submit action. A pending recovery of 1 is also present. This requires checking the final recovery decision before restoring a normal Submit card; the audit did not substitute historical assigned quantities.
8. **Alter coverage depends on loaded work-search lots:** alterMirrorV684 discovers journeys only for canonical lots currently in S.cards and only aggregates into Fabrication or personal chats. It is not an independent all-journeys completeness query. Current-action lane mapping is tested; global Alter completeness is not established.
9. **Rectification:** the canonical table contains one CLOSED case and no current active cases in this snapshot. Closed cases are excluded; active lane behavior is tested, but no active case was created for this audit.

## Scope limits

All twelve post-cutting manufacturing department OPEN/WORKING projections were queried. Cutting's frontend adapter was inspected: it uses its own canonical cutting/history cards and cutting-open guard rather than the production receipt adapter. Its current signed-in rendered feed, live Android screens, every actor's authorization and a complete live Alter chain were not tested. The audit therefore does not certify all departments and actors end to end.

## Changes completed during the audit

The footer separates named previous action (red ticks), actual next pending action (yellow), and Read (blue) / All read (green). Unread badges and pending-card totals are explicitly named. Selecting a different action filter clears the previous list while loading; simply opening the current screen preserves its cards and read ticks. These display changes do not resolve the queue discrepancies listed above.

## Remediation and latest display contract

TEST71 adapters now use one queue source for department/root totals and opened group lists, including Alter, Rectification and recovery. Unread action-message totals remain explicitly separate from pending-card totals. Submitted source assignments no longer remain in Worker Submit. Initial receipt rows no longer remain in Open or in Staff submitted Accept & Count.

| Current regular queue | Previous completed action (red) | Required action (yellow) |
| --- | --- | --- |
| Open / ready to assign | Lot released or final Accept & Count, actual actor | Assign Worker / Staff |
| Worker Working / Submit | Assigned by staff | Submit / assigned worker |
| Staff Working / Accept & Count | Submitted by worker, with actual delegate if applicable | Accept & Count / selected receiver or shared Fabrication Staff |
| Alter / Rectify | Actual latest journey event and actor | Current journey action / current responsible person |

Each current card has one stage footer: previous action, next named action with yellow double tick, then own Read blue / All read green. Old partial receiver claims cannot replace Submit as the last completed action of an uncounted submitted handover. Assignment receipt confirmation cannot replace staff assignment as the last stage action of a Worker Submit card. On-behalf submissions retain both the worker subject and actual performing staff; a missing legacy auth mapping is not replaced with the current viewer. Source receipt identity includes the last actor/action/time so a new stage action does not inherit an earlier action's read state.

All 14 pending handovers are covered, including lot 2639 with a null target/receiver. Opening the form does not mutate a claim. Full valid Save is atomic; cancellation, invalid counts, rate failure and late material failure do not leave partial acceptance. Completed handovers leave Working and generate next-stage assignment in Open. Existing Short/Excess final-decision authority remains intact; disputed counts are Not Accepted until that decision completes. Existing Actual Rate prerequisite remains intact (lot 2639 requires the real rate before Save).

Live consolidated regular counts: **Open 1 lot; Staff handover Accept & Count 14; Worker Submit 6.** There are additionally **14 legacy assigned-receipt cards from 26 colour rows**. These have not yet been physically received/count-confirmed by their assigned workers; they are separately labeled Assigned receipt / Count in Worker Working and do not increase the Staff Accept & Count or Worker Submit count. No assigned quantity was silently accepted or used as a saved physical count. Their explicit atomic receipt form requires every pending colour. Authorized staff may assist while preserving the assigned worker custody and the actual saving actor.

Alter discovery now starts from all active canonical journeys, not whichever lots happened to be loaded in S.cards. The snapshot contains seven active journeys (four remake-issue, two receive-from-master, one karigar-submit stages). Fabrication aggregates all; individual groups select their current responsible department. Rectification uses the canonical active-case RPC; current snapshot still has no active cases. Closed cases remain excluded.

Validation: **43 frontend tests; 18 database transaction/rollback checks**, covering queue completeness, true stage actors, authorization, full-count validation, rollback, idempotent retry and next Open transition. Desktop Chromium with a 390px viewport checks three footer lines and computed red/yellow/blue colors. Business test mutations are rolled back. Changes apply only to TEST71 wrapper functions and the TEST71 preview branch, with legacy production function definitions preserved.

Remaining data exception: Imamul lot 2622 has a RESOLVED receipt that the legacy operational quantity engine does not recognize as normal received stock, plus an existing recovery. It remains on its recovery journey; this change does not invent a final decision or enable a normal Submit against zero operational stock. Signed-in Android and every live actor's full Alter chain are not certified by these checks.

## Tab-switch loading regression remediation (9 October, late evening)

The Android screenshots exposed two defects missed by the earlier suite: the final V318 presentation filter accepted only ACCEPT_PENDING in Open and removed the new READY_TO_ASSIGN rows; changing tabs retained old Working controls while waiting for the unrelated global work-search projection. The two-screen CSS hid the loading message inside #messages, making pending loads appear as empty screens.

Open now retains READY_TO_ASSIGN; Working retains WORKING and DECISION_PENDING. Manufacturing group status changes request the selected queue immediately, clear previous controls/counts, and display loading outside the hidden card list. Late responses cannot replace a newer tab. Projection errors and a 20-second queue deadline expose Retry. Root and chat reuse one scoped in-flight/15-second cached projection; mutation/cache invalidation clears it. Optional Art/photo enrichment yields after 1.5 seconds and can update only its original current view. Repeated canonical Rectification and Fabrication identity requests were removed from the opened group path.

Validation: 48 targeted frontend tests, including the actual openChat Working→Open→Working flow with deliberately delayed responses, ready-to-assign visibility, failed-request Retry, in-flight deduplication, timeout retry, and late Art enrichment. No backend/business records changed in this correction. Live Android network latency is not asserted by these synthetic delayed-response tests.
