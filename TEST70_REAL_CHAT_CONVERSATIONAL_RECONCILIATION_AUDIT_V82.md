# TEST70 Real Chat Conversational UX + Reconciliation Audit V82

## Source-to-chat reconciliation counts

| Authoritative source | Existing records | TEST70 Real Chat records | Gap |
|---|---:|---:|---:|
| Finished-goods stock ledger | 116 | 0 | 116 |
| Collection activity | 63 | 0 | 63 |
| Market requirements | 47 | 0 | 47 |
| Distributor/partner orders | 2 | 0 | 2 |
| Raw attendance IN/OUT events | 0 current test rows | 0 | producer must be verified with a new test event |

The zero attendance count means the schema/flow exists but daily IN/OUT chat behavior cannot be claimed as working from current data. It requires a controlled role-wise TEST event after projection is installed.

## Current UX audit

The current TEST70 page provides:

- one inbox containing department rows
- static OPEN / WORKING / CLOSE tabs for every role
- static module drawer
- generic work cards
- direct anchor links to existing pages
- bridge polling and realtime refresh
- image viewer and delivery/read ticks

It does not yet provide:

- worker-specific WORKING/CLOSED-only surface
- one compact sticky current-action row
- conversational step prompts
- resume token/current-form-step
- grouped master thread for CB/Collection/Requirement
- latest-only payment summary
- issue-resolution prompt in the same conversation
- module-specific plain-language card layouts
- date-searchable hidden history
- exact pending-action prioritisation

## Conversational adapter rule

Real Chat must never copy or replace a module form. Each adapter will expose only:

1. current source record
2. completed required fields
3. next missing required field/action
4. exact existing form page and record/step parameters
5. validation or issue message from the source module
6. successful completion result and next workflow destination

Example CB flow:

`Start Purchase -> Supplier -> Bill -> Fabric -> Colours/Rolls -> Quantity/Rate -> Division -> Documents -> Existing validation -> Existing submit -> CB card -> Art Decide`

The final write remains the existing CB Purchase function. Real Chat stores only conversation state, receipt and audit metadata.

## Adapter inventory and intended prompt

| Adapter | Conversational prompt/action | Existing destination |
|---|---|---|
| CB Purchase | next missing purchase field; resume draft | existing CB New sheet/RPC |
| Art Decide | next missing Art/Print/Sticker/Metal decision | existing decision bundle form/RPC |
| Cutting | Ready, assign/start, size/colour entry, release | existing Cutting Master functions |
| Department work | Assign/accept/update/submit/deliver | existing UPM workflow |
| Alter/issue | current custodian and next resolution | existing Alter/Rectification workflow |
| Packing | assign/accept/generate/submit | existing Finished Goods packing workflow |
| Despatch/store | create/accept/verify/receive | existing Despatch/Store workflow |
| Stock | view movement/balance; authorised adjustment link | existing stock ledger/allocation workflow |
| Collection | send/update same master collection | existing Market Window workflow |
| Requirement | respond/update/close/Ready for PI | existing Requirement workflow |
| PI/CI | edit/confirm/verify/open document | existing Sales/Market PI/CI workflow |
| Return/RCI | return, verify, post/reverse | existing Return/RCI workflow |
| Accounts | party-locked ledger/entry/statement | existing Accounts page/RPC |
| Attendance | IN/OUT/correction/alert | existing Attendance action/RPC |
| Payroll/payment | latest settlement summary/detail | existing Payroll/Payment records |

## Compact conversation behavior

### Main surface

- Staff/head: OPEN, WORKING, CLOSED
- Worker: WORKING, CLOSED
- Customer/distributor/supplier: ACTION REQUIRED, IN PROGRESS, COMPLETED
- One compact current-action row immediately above the composer
- Tapping the row opens the exact current task sheet
- Multiple tasks collapse to `N OPEN TASKS` and a compact ordered list

### Timeline

- Important event becomes one compact message
- A state update edits/reprojects the same work card; it does not create a second business object
- Resolved alerts move to compact history
- Large cards are shown only in an opened detail sheet
- Closed history is date searchable

### Secondary menu

- Work summary
- Attendance
- Last payment summary
- Ledger/statement
- Issues
- Previous history

Salary and accounts never replace the work-first landing surface.

## Latest payment summary contract

Default worker chat shows only the newest final settlement summary. Previous summaries remain stored and searchable by date.

Detail grid:

- Lot number
- accepted pieces
- actual rate
- amount
- totals
- prior balance
- advance/deduction/payment
- closing balance

The summary is generated from the posted payment/settlement event, not as a daily wage message.

## Attendance conversation contract

- Daily IN and OUT must both be represented for the exact worker.
- A single attendance-day row may update from `IN recorded / OUT pending` to `IN + OUT / day completed` while preserving both audit events.
- Missing OUT, late, early, correction and geofence issues are alerts tied to the same day thread.
- Worker sees only own attendance; head sees own department; Accounts/Admin/Owner see permitted aggregate/detail.
- Existing normal Attendance button remains; actor identity chooses the personal thread.

## Legacy, present and future rules

### Legacy

- Backfill stable conversation/work keys from real business identifiers.
- Never display a UUID as CB/Lot/document number.
- Group duplicate update events under their master CB/Collection/Requirement/work key.
- Preserve old audit timestamps and actors.
- Do not manufacture missing IN/OUT or financial facts.
- Carry unresolved legacy work into OPEN/WORKING only when the authoritative source still says it is pending.

### Present

- Reconcile active source state before rendering.
- Remove stale actions from completed/cancelled/reversed records.
- Resolve receiver identity before exposing the record.
- Prioritise the exact current action in the sticky row.

### Future

- Source triggers/projectors update the same canonical thread.
- Unique source-event keys prevent duplicate events.
- Source completion automatically closes the action and alert.
- New departments automatically include Owner/Superadmin staff membership.
- New workers/customers/suppliers receive mappings through canonical identity rules.

## Pre-repair conclusion

The source application already contains most business capability. The missing system is a safe adapter layer joining authoritative state, exact action, receiver identity, conversational prompt, alert resolution and compact history.

Repair must begin identity-first, then lifecycle/action resolver, then missing source projections, then frontend. Adding new messages before those layers would amplify current routing and privacy errors.
