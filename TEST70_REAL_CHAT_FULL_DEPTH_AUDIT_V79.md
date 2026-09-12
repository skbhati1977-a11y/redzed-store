# TEST70 Real Chat Full-Depth Audit V79

Branch baseline: `074809a` (`test70-cb-purchase-real-chat-pilot`)

## Locked outcome

Real Chat must be a conversational control layer over the existing authoritative modules. It must not create parallel purchase, production, stock, sales, accounts, attendance, or payroll records.

Primary interface:

- Staff/head: OPEN, WORKING, CLOSED
- Worker: WORKING, CLOSED (no open pool)
- Owner/Superadmin: all permitted departments and all three states
- Secondary information (ledger, salary, history) stays inside the menu/detail sheet
- Daily attendance IN and OUT are visible in the worker's personal conversation
- Only the latest payment settlement summary is shown by default; older settlements remain date-searchable

## Measured current coverage

- Dashboard operational screens: 33
- Existing module RPC calls discovered in active frontend files: 159 unique RPCs
- Real Chat action registry: 11 actions
- Active bridge messages: 2,086 across 19 source modules
- High-volume bridge sources: UPM 847, UPM_RATE 302, NOTIFICATION 272, ACCOUNTS 210
- Entirely group/unmapped receiver streams: CB_PURCHASE 28, CUTTING 29, DESPATCH 18, MATCHING_PURCHASE 8, PRODUCT_MASTER 108, RCI 44, SALES 34, SALES_RETURN 6
- UPM receiver gap: 570 of 847 messages have neither receiver user nor receiver worker
- WORKER_PAYROLL receiver gap: 42 of 45

## Current defects confirmed

1. The frontend derives OPEN/WORKING/CLOSE using text regex instead of a canonical lifecycle contract.
2. Completed UPM records can still carry action codes, so CLOSED work can remain actionable.
3. Product Master emits separate ART/PRINT/STICKER/METAL events but has no aggregated `ART DECIDE` conversation state.
4. CB Purchase cards use purchase-row identifiers as lot identity when a real CB/lot display number is unavailable.
5. Cutting has ready/release/completed concepts, but chat only projects action history and released lots; it does not expose a truthful `ART DECIDE -> READY FOR CUTTING -> CUTTING DONE` state.
6. Daily attendance projection reads the day row but omits check-in time, check-out time, worked duration, late/early/OT, and missing-out alerts.
7. Attendance event/reminder/correction tables exist but are not bridged.
8. Stock ledger exists but is absent from Real Chat.
9. Collection/Requirement/partner order tables exist but are absent from this Real Chat bridge.
10. Purchase, stock, sales, and returns do not share one product/lot conversation identity.
11. Customer/supplier receiver mapping is incomplete; many commercial records are department-only.
12. Generic notification actions mostly open the dashboard instead of the exact source record.
13. Module drawer is a static list; it is not permission/action aware.
14. Financial history is mixed with the work surface instead of being a secondary, receiver-locked detail.
15. No common issue-resolution contract covers validation error, correction, approval, alter, damage, shortage, return, or reversal.

## Authoritative sources already available

### Product and purchase

- CB master/purchase/roll/colour/division/unit tables
- Art, Print, Sticker, Metal ID assignments and libraries
- Accessory requirement, allocation, purchase, and stock tables
- Matching cloth purchase, stock, and ledger

### Cutting and production

- Cutting draft/sheet/quantity/lot/action/damage sources
- UPM lot registry, open queue, assignments, submissions, handoffs
- Department and assignment rate logs
- Alter, rectification, remake, responsibility, transfer, and alert sources
- Media and audit sources

### Finished goods and commerce

- Packing assignment/plan/box sources
- Despatch, custody, acceptance, and receive correction
- Finished-goods stock ledger/balance
- PI/CI, verification, sales, returns, RCI, and commercial lot sources
- Market collection, requirement, partner collection/order/session/event sources

### People, attendance, payroll, and accounts

- Canonical worker directory and department maps
- Daily attendance, raw IN/OUT events, calculated minutes, reminders, corrections, audits
- PCS and monthly payroll runs/lines
- Salary/PCS/advance payment batches and worker balances
- Account transactions/postings/ledgers/statements
- Worker salary ledger map and supplier account map

## Required canonical conversation contract

Every projected item must contain:

- `conversation_key`: stable party/group/thread identity
- `work_key`: stable CB, D-card, lot, collection, requirement, PI/CI, voucher, attendance-day, or payroll-settlement identity
- `source_module`, `source_record_id`, `source_event_id`
- real display number (never a UUID as Lot/CB number)
- `canonical_state`: OPEN, WORKING, CLOSED
- `display_stage`: module-specific plain-language stage
- `current_actor`, `current_owner`, `receiver_user`, `receiver_worker`, `receiver_party`
- `allowed_roles` and server-enforced action permission
- `action_code`, exact button label, exact source page/deep link
- issue/alert severity, due time, resolution action, resolved time
- sender, receiver, performed-by, on-behalf-of audit
- created, delivered, read, acted, completed timestamps

## Required lifecycle adapters

| Area | OPEN | WORKING | CLOSED |
|---|---|---|---|
| Product/CB | Art Decide | Decision Running / Ready for Cutting | Cutting Done for this stage |
| Cutting | Ready for Cutting | Cutting | Lot Released |
| Production dept | Assignment Due | Accepted/Working | Submitted/Delivered |
| Alter/repair | Resolution Due | Repair/Transit | Resolved and merged |
| Packing | Ready for Packing | Packing | Packed |
| Despatch/store | Receive/Pick Due | In Transit/Verifying | Received/Delivered |
| Collection | Send/Update Due | Response/Requirement Running | Collection Closed |
| Requirement/order | Response Due | PI/CI Running | Order/CI Closed |
| Accounts | Posting/approval due | Verifying | Posted/reversed final state |
| Attendance | OUT/Correction Due | Checked In | Day Completed |

## Repair order

1. Create a canonical module/action/alert contract registry.
2. Add lifecycle adapters without changing source workflows.
3. Bridge missing authoritative sources and backfill legacy rows.
4. Resolve receiver mapping and privacy before exposing new streams.
5. Replace regex state inference with canonical state.
6. Render one compact current-action row and compact history.
7. Keep financial/payroll details in receiver-locked secondary sheets.
8. Add conversational step prompts that deep-link to the exact existing form step.
9. Add role-wise automated tests for owner, admin, accounts, department head, worker, customer, distributor, and supplier.
10. Verify TEST70 end-to-end; MAIN remains untouched.

## Non-negotiable verification

- No UUID displayed as a CB or Lot number.
- No action visible after its source step is complete.
- No worker can browse an open work pool.
- No financial record leaks across workers/customers/suppliers.
- IN and OUT both appear daily for the exact worker.
- One source event creates one canonical event; role views are projections, not duplicate business records.
- Existing module validation and writes remain authoritative.
- Legacy, present, and future records resolve through the same adapters.
