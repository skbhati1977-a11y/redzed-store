# TEST67 Market Window implementation

Status: TEST-only functional foundation implemented. MAIN remains unchanged.

## Implemented in slice 1

- One REDZED-wide continuous human reference sequence across all customers in TEST mode.
- The Collection and its Requirement keep the same human reference.
- Collection/Requirement updates retain the same reference; the existing shared update counter remains authoritative.
- Existing UUID keys and legacy tables remain canonical and backward compatible.
- REAL-mode numbering is explicitly blocked from the TEST67 RPCs.

## Implemented in slices 2-3

- Distributor workspace is explicitly enabled by Super Admin with an owner prefix.
- Private downstream Customer IDs are generated and names/mobile stay hidden from REDZED staff.
- Every distributor uses one owner-wide continuous Order/Requirement sequence across all downstream customers.
- Authoritative TEST Market Window rates are snapshotted server-side; Rate Enhancement is stored separately and customer rate is calculated.
- Any selection of READY customer-wise orders can be sent together in one batch.
- Staff sees the exact customer-reference/order separation plus an article-wise consolidated summary.
- Staff proposes PI quantities; every order line waits for confirm, change request, or cancellation.
- Distributor and staff cancellation update the containing batch and preserve an audit event.
- Staff finalizes one upstream CI billed to the direct distributor.
- Distributor converts each confirmed allocation into a separate private-customer CI with enhanced rate.
- All eight TEST67 partner tables use RLS with no direct anon/authenticated table reads.
- Customer RPCs require the existing secure session token and trusted device; staff RPCs require the existing sales actor gate.

## TEST67 entry pages

- `real-market-distributor-test67.html`: private customers, orders, batching, confirmation, cancellation, customer CI conversion.
- `real-market-staff-batch-test67.html`: incoming batches, exact order detail, consolidation, PI proposal, CI finalization, cancellation.

## Deliberately not changed

- REAL-mode data and numbering.
- MAIN branch.
- Existing PI/CI accounting documents. TEST67 stores their references and allocation lifecycle; final integration into the canonical accounting PI/CI posting RPC must be rehearsed on the next test branch before MAIN approval.
