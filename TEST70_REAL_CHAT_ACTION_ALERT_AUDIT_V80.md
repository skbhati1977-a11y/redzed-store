# TEST70 Real Chat Action + Alert Audit V80

Baseline code: TEST70 commit `436f7f9` (audit phase; MAIN untouched)

## Executive comparison

| Layer | Available in source app | Present in Real Chat | Result |
|---|---:|---:|---|
| Dashboard operational screens | 33 | 32 static drawer entries | Partial: list exists, contracts do not |
| Unique RPCs referenced by active module frontends | 159 | 11 action-registry rows | Critical action gap |
| Bridge source modules | many authoritative sources | 19 modules | Major source gap |
| Canonical lifecycle status | module-specific source states | regex-derived OPEN/WORKING/CLOSE | Wrong foundation |
| Exact receiver mapping | worker, user, party, department sources exist | many group-only/unmapped rows | Major routing gap |
| Alert engines | UPM alert, attendance reminder, notifications exist | only generic notification stream populated | Major alert gap |

## Module and submodule audit

Legend: **Mapped** = useful end-to-end projection exists; **Partial** = data/history exists but actions, identity, receiver, or lifecycle are incomplete; **Missing** = no canonical Real Chat source.

| Area | Existing authoritative functions/actions | Real Chat status | Required mapping |
|---|---|---|---|
| CB New | Create CB, add purchase, rolls, colours, division allocation | Partial | Conversational field-step adapter; real CB identity; draft/resume; Purchase staff receiver |
| CB Purchase ledger | GR, exchange, damage, bills, material add | Partial | Supplier/Accounts routing; GR/damage actions; no UUID display |
| Art Decide | Art/Print/Sticker/Metal ID select/NA/edit/submit | Partial | Aggregate four decisions into one Art Decide state and next missing action |
| Art Master | Create/edit art, captions, cost/process | Partial | Exact art actions and permission contract |
| Print Master | Frames, placement, captions, costs | Partial | Print due/decision/action deep link |
| Sticker Master | Select/create/instruction/due | Partial | Sticker due/action/NA lifecycle |
| Metal ID Master | Select/create/instruction/due | Partial | Metal due/action/NA lifecycle |
| Accessory material | Requirement, allocation, purchase, consume | Missing | Shortage/purchase/allocate/consume alerts and actions |
| Matching cloth | Purchase, stock, lot match, reserve/confirm/cancel/recover | Partial | Full lifecycle and supplier/lot receiver mapping |
| Cutting readiness | decision gate, ready cards, D cards | Partial | ART DECIDE -> READY FOR CUTTING contract |
| Cutting lot | equal split, child CB, release single/multiple lot | Partial | Cutting working state, real lot count/identity, completion rule |
| Cutting damage/GR | report, evidence, admin/owner/vendor decisions | Partial | Correct approver receiver and exact pending action |
| UPM open queue | available lot, assign worker | Partial | Staff-only OPEN; worker must never browse pool |
| UPM assignment | assign, accept/start, update | Partial | Separate Assigned/Working ownership and exact actor |
| UPM submit | actual-rate gate, submit, accept/refuse | Partial | Clear action after completion; next department handoff |
| Department production | Print, Sticker, Metal, Stitching, OV, FLD, Kaaj/Btn, Teak, Thread, QC, Press | Partial | Per-department stage labels, route order, ownership and completion |
| Alter/repair | fill, line-man accept, remake, transit, receive, repair, merge | Partial | One issue thread, current custodian action, resolved close |
| Rectification | open, assign, resolve | Partial | Exact issue receiver/action/status |
| Rate/RRQ | department rate, assignment rate, packing final rate | Partial | Pending-only action; financial role privacy; resolved close |
| Packing | assign, accept, generate, submit | Partial | Ready/Working/Packed lifecycle and packer receiver |
| Media/AI | source, regenerate, approve/reject/publish | Partial | Exact approver, media task state, no unrelated worker mapping |
| Despatch | create challan, box allocation | Partial | Despatch owner and exact challan identity |
| Store Receive | custody, dual acceptance, correction, receive | Partial | Receiver-specific pending action; completion closes sticky row |
| Stock | inward/outward/transfer/sale/return/adjustment ledger | Missing | Lot conversation stock events and current balance summary |
| Webstore/physical store | saleable stock and allocation | Missing | Location-aware availability and reservation actions |
| PI/CI sale | add lines, save PI, final CI, verify qty | Partial | Customer/Accounts/Staff views; correct action and document identity |
| Sale Return | post return, RCI, reverse | Partial | Customer/Accounts mapping and return resolution lifecycle |
| Market Collection | send/update, global collection number, lines | Missing in this bridge | Single-card collection thread and correct customer/distributor receiver |
| Requirement/Order | requirement updates, close/push, PI/CI progression | Missing in this bridge | Single-card requirement thread, Ready for PI action and receiver boundary |
| Accounts | voucher, posting, statement, receipt/payment, reversal | Partial | Party-locked ledger/detail/share actions; compact language |
| Worker accounts | salary ledger mapping and personal chat link | Partial | Latest settlement summary/detail/date search; receiver lock |
| Attendance | save day, IN/OUT timestamps | Partial | Daily IN+OUT message content and personal receiver |
| Attendance alerts | missing OUT, correction, geofence, late/early/OT | Missing | Personal alert template, exact attendance action, head/accounts summary |
| PCS payroll | work lines, rates, claims, payment | Partial | Payment-time latest summary; lot/pieces/rate/amount detail |
| Monthly payroll | calculate, adjustment, approve/reopen, payment | Partial | Attendance-derived settlement; Accounts-only actions |
| Advance/expense | preview/post/void/balance | Partial | Payment summary adjustment and worker receiver |
| Notifications | generic notification records | Partial/wrong | Exact module/record deep link, dedupe, resolve/close |
| Roles/permissions | role, department, action and field permissions | Source available | Server-enforced action resolver required |

## Exact action registry audit

Current registry covers only:

- UPM: assign worker, submit, alter, rectification, remake/receive/deliver stages, damage
- UPM costing: department rate
- Packing: final sale rate/RRQ

It does **not** register most active source actions, including CB creation/purchase, Art/Print/Sticker/Metal decisions, Cutting release, Packing assign/accept/submit, Despatch receive, PI/CI, returns, collection, requirement, attendance IN/OUT/correction, payroll approval/payment, advance, account share/posting, and stock actions.

## Alert audit

### Available source engines

- `rr_upm_alert_events_v794`: recipient, recipient role, request, lot, alert code, routing scope
- `rr_attendance_reminder_state_v778_2`: worker/day/reminder/status/repeat/resolved state
- `rr_attendance_reminders_due_v778_2`: due reminders with worker and department
- `rr_attendance_corrections_v778_2`: correction lifecycle
- `rr_notifications`: user/role/department/action item/title/message/read state

### Current production data observed

- Generic notifications: 272, all packing rate related
- UPM alert-event rows: none currently populated
- Attendance reminder-state rows: none currently populated

Therefore schema presence must not be reported as working alert coverage. Producers/triggers/templates and delivery verification are still required.

## Required alert contract

Every alert must have:

- canonical alert key and source record
- target user/worker/party/department and permitted escalation roles
- plain-language title/message
- severity and due time
- one exact primary resolution action
- source-page deep link with record context
- dedupe key
- delivered/read/acted/resolved timestamps
- automatic closure when the source issue is resolved

## Critical security and correctness findings

1. Group visibility cannot substitute for receiver mapping.
2. Frontend-hidden buttons are insufficient; the action resolver must verify role, department, ownership, and current source state server-side.
3. Financial payloads must never use broad department/global visibility.
4. Customer, distributor, supplier, and worker conversation identities must remain separate.
5. Completion must be read from the source record, not inferred from label text.
6. A new source event may update a conversation card but must not create a second business record.

## Next repair package

1. Canonical lifecycle resolver and action resolver.
2. Complete module/action contract registry.
3. Attendance IN/OUT + reminder/correction projection.
4. Stock, Collection, Requirement, and market-order projections.
5. Receiver/party/privacy reconciliation.
6. Role-aware frontend with staff OPEN/WORKING/CLOSED and worker WORKING/CLOSED.
7. Compact sticky current-action row, contextual prompt, issue resolution, and secondary detail menu.
