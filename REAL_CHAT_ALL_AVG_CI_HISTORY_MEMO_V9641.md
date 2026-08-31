# REAL CHAT — ALL AVG / REQ AVG / UNIVERSAL DASH MEMO V9641

Status: SAFE ISOLATED CHECKPOINT — 2026-08-31

## Business conclusion

- ALL AVG is a FINAL-CI-only customer purchase metric. Requirement and PI never enter permanent purchase history.
- Direct shop/physical FINAL CI and Real Chat-originated FINAL CI are treated equally when mapped to the same Party/Customer identity.
- Historical per-piece value uses FINAL CI line net/final rate x net sold qty; freight, GST and round-off are not part of the per-piece average-rate base.
- During an active Requirement, ALL AVG is only a live projected blend of finalized CI history plus current Requirement net value/qty. The Requirement is not persisted into history until FINAL CI.
- REQ AVG is current Requirement net amount / current Requirement qty.
- If no FINAL CI history exists, ALL AVG is still rendered and shows —.
- Universal field contract: rendered field + authoritative value; missing/unresolved = —; actual authoritative zero = 0. Missing data never becomes fake zero.

## Identity mapping safety

`rr_collection_customer_ci_history_v9641` resolves the token/customer and maps FINAL CI history using this precedence:
1. Explicit FINAL CI snapshot `contact_customer_id` match.
2. Authoritative normalized mobile match between customer and buyer.
3. Exact normalized buyer/customer name only when the normalized name is unique on both buyer and customer sides.

Ambiguous records are not guessed. Data mode is kept isolated so TEST/REAL history does not silently mix.

## UI / lifecycle

Header: `REDZED COLLECTION | ALL AVG | REQ AVG`.
Chat control row: `GROUP | SUPER ADMIN | REQ QTY | REQ AMT`.

- Before Requirement data exists: Requirement metrics show — while applicable.
- Active confirmed Requirement: confirmed server quantities/amounts/REQ AVG display.
- Requirement edit: saved quantities prefill; draft edits update REQ metrics and projected ALL AVG live.
- BACK TO CHAT: unsaved draft is discarded and confirmed metrics return immediately.
- SEND REQUIREMENT: only real changes proceed after Previous -> New confirmation; no-change duplicate submit is blocked.
- Requirement terminal/PI conversion: REQ AVG/QTY/AMT hide by explicit lifecycle rule; ALL AVG reverts to finalized-CI-only history.
- FINAL CI later enlarges historical ALL AVG naturally.

## Stability / anti-stuck rule

V9641 uses bounded finite retries only for delayed header/row readiness. No unbounded MutationObserver repaint loop, no endless recursive refresh, and no continuous DOM-write watcher is used in the V9641 state addon. If readiness is not achieved within the bounded attempt limit, UI keeps the last authoritative value or — rather than spinning indefinitely.

## Implemented objects

Backend read-only display RPC: `rr_collection_customer_ci_history_v9641(text)`.
Isolated customer addon: `real-customer-requirement-state-v9641.js`.
Isolated test harness: `real-customer-collection-to-frozen-test-v9630.html?v=9641`.
Rule Book continuation: Rules 109–120 in `REAL_FACTORY_REAL_CHAT_RULE_BOOK_V9635_ADDENDUM.md`.

## Current test-token expectation

For the current isolated test token, server CI-history resolver currently returns `NO_CI_HISTORY`, therefore `ALL AVG` must display `—`. Existing current Requirement remains independently mapped to its confirmed Requirement quantities and authoritative Net Rates.

## Promotion rule

Do not promote V9641 to the stable production customer route until isolated behavior is visually/functionally approved. No production PI/CI/stock/accounting mutation was introduced by this checkpoint.