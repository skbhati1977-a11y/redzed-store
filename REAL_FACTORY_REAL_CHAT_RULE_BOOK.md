# REAL FACTORY — REAL CHAT / COLLECTION / REQUIREMENT RULE BOOK

Status: LOCKED REFINED RULES — 2026-08-31

[Rules 1-84 remain locked exactly as previously approved.]

## LOCKED CONSOLIDATED PENDING BATCH / REQUIREMENT UX RULE — 2026-08-31

85. Before staff starts processing, customer may submit multiple More Samples and Requirement updates inside the same active Collection. Every action remains individually audited, but staff must receive one consolidated actionable pending snapshot rather than a confusing list of separate requests.
86. Pending More Samples categories are cumulative/unioned until staff processing cutoff. Repeated category values appear once. A later More Samples request adds pending categories; it does not silently erase earlier still-unprocessed categories.
87. For Requirement quantities within the same unprocessed pending window, SAME LOT = LATEST CONFIRMED QTY WINS. Earlier quantities remain audit history but are not added to the latest quantity and must never be interpreted as duplicate demand.
88. When staff explicitly starts PROCESSING the pending snapshot, the system records a cutoff/update number and freezes that batch for staff action. Customer updates arriving after the cutoff form the NEXT PENDING BATCH and must not silently alter the batch staff is already processing.
89. Staff actionable view therefore represents: union of pending categories + latest confirmed quantity per Lot up to the processing cutoff. Raw historical events remain available for audit/history only.
90. Requirement edit UX must prevent accidental duplicate entry. After a Lot quantity has been saved, every later customer open/update of that same active Collection must prefill the latest confirmed saved quantity instead of presenting a misleading blank/zero field.
91. If customer changes a previously saved quantity, SEND REQUIREMENT must show an explicit change confirmation summary before persistence, e.g. Previous Qty 12 -> New Qty 2. For multiple changed Lots, show only changed rows in the confirmation.
92. If no Requirement quantity changed, SEND REQUIREMENT must not create a new Requirement/update event; show NO QUANTITY CHANGES FOUND (or equivalent) and leave current state unchanged.
93. Changing a previously saved non-zero quantity to zero is an explicit removal action and requires confirmation, e.g. Remove Lot A from current Requirement? 12 -> 0. On confirmation, latest actionable qty becomes zero while prior values remain in audit.
94. Requirement screen ordering on every staff-sent Collection Update: LATEST STAFF-SENT NEW SAMPLES appear first/top and prominently. Below them show CURRENT/SAVED ACTIVE REQUIREMENT items with their latest confirmed quantities prefilled.
95. Customer Requirement UI maintains running TOTAL QTY and TOTAL AMOUNT across the entire current active Requirement, not merely the latest staff update. Totals update live as quantities are edited.
96. A sample/Lot whose latest confirmed Requirement quantity is zero is treated as NOT REQUIRED for customer display. From the next Collection update onward it is hidden from the continuing saved Requirement list, while its sent/zero-demand history remains permanently auditable.
97. A previously non-zero saved Lot continues to appear prefilled on subsequent updates until customer explicitly changes/removes it or the lifecycle reaches its terminal state. Same-Collection duplicate-sample blocking remains unchanged: a zero-demand sample is not silently re-sent as a new sample within the same Collection merely to make it visible again.
98. Customer-facing rate calculation uses authoritative customer-specific NET RATE: NET RATE = APPROVED SALE RATE - CUSTOMER ALLOWED DISCOUNT. Customer cannot manually edit approved rate, allowed discount or calculated net rate.
99. Every Lot Rate field must visibly show the APPROVED SALE RATE struck through and, immediately below/alongside it, the resulting customer NET RATE in bold/prominent form. Example: Approved 100 struck through; NET RATE 95 bold when allowed discount is 5.
100. Line AMOUNT must be calculated and displayed prominently from NET RATE x latest current Required Qty. Running TOTAL AMOUNT must sum these net-rate line amounts only; gross/approved rate must never be used for the customer payable Requirement total.
101. Customer allowed discount and approved sale rate must come from authoritative server-side mappings. Missing/invalid pricing must not be invented client-side; the affected line must be blocked or clearly unresolved according to the authoritative pricing rule before commercial confirmation.
102. Final customer Requirement UX invariant: NEW STAFF SAMPLES FIRST -> SAVED ACTIVE REQUIREMENT PREFILLED BELOW -> ONLY REAL CHANGES CONFIRMED -> ZERO DEMAND HIDES ON NEXT UPDATE -> RUNNING TOTAL QTY + NET-RATE TOTAL AMOUNT -> backend retains complete audit history.
103. Final staff concurrency invariant: CUSTOMER MAY CONTINUE UPDATING -> EVENTS AUDITED -> STAFF SEES ONE CONSOLIDATED PENDING SNAPSHOT -> STAFF PROCESS CREATES CUTOFF/FREEZE -> LATER CUSTOMER CHANGES BECOME NEXT PENDING BATCH.