# TEST67 Market Window implementation

Status: TEST-only implementation in progress. MAIN remains unchanged.

## Implemented in slice 1

- One REDZED-wide continuous human reference sequence across all customers in TEST mode.
- The Collection and its Requirement keep the same human reference.
- Collection/Requirement updates retain the same reference; the existing shared update counter remains authoritative.
- Existing UUID keys and legacy tables remain canonical and backward compatible.
- REAL-mode numbering is explicitly blocked from the TEST67 RPCs.

## Still to implement

- Recursive distributor workspace and private downstream Customer IDs.
- Selected multi-customer order batch.
- Customer-wise exact order sections and article-wise consolidated totals.
- Distributor Rate Enhancement.
- Customer-wise confirmation/cancellation and consolidated PI/CI allocation.
