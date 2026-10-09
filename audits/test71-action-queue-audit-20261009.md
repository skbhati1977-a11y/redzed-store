# TEST71 action queue audit — 9 October 2026

## Result: the current implementation does not fully satisfy the requested queue contract

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
