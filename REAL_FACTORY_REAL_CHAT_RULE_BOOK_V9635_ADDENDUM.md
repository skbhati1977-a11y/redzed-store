# REAL FACTORY REAL CHAT RULE BOOK — V9635 LOCKED ADDENDUM

Status: LOCKED — 2026-08-31
This addendum is part of REAL_FACTORY_REAL_CHAT_RULE_BOOK.md and continues from Rule 84.

85. Before staff starts processing, customer may submit multiple More Samples and Requirement updates inside the same active Collection. Every action remains individually audited, but staff receives one consolidated actionable pending snapshot rather than separate confusing requests.
86. Pending More Samples categories are cumulative/unioned until staff processing cutoff. Repeated categories appear once. A later More Samples request adds pending categories; it does not erase earlier still-unprocessed categories.
87. For Requirement quantities within the same unprocessed pending window, SAME LOT = LATEST CONFIRMED QTY WINS. Earlier quantities remain audit history but are not added to current demand.
88. When staff explicitly starts PROCESSING, system records a cutoff/update number and freezes that actionable batch. Customer updates after cutoff form NEXT PENDING BATCH and do not silently alter the batch staff is processing.
89. Staff actionable snapshot = union of pending categories + latest confirmed quantity per Lot up to cutoff. Raw events remain audit/history.
90. Once a Lot quantity has been saved, later customer opens/updates of the same active Collection prefill the latest confirmed saved quantity; do not show a misleading blank/zero field.
91. If customer changes a saved quantity, SEND REQUIREMENT shows explicit confirmation: Previous Qty -> New Qty. Multiple changes show only changed rows.
92. If no quantity changed, SEND REQUIREMENT creates no new Requirement/update event and reports NO QUANTITY CHANGES FOUND or equivalent.
93. Changing saved non-zero qty to zero is explicit removal and requires confirmation. After confirmation latest actionable qty is zero; old values remain audit history.
94. Requirement screen ordering: LATEST STAFF-SENT NEW SAMPLES first/top; CURRENT/SAVED ACTIVE REQUIREMENT items below with latest confirmed qty prefilled.
95. Customer UI shows live running TOTAL QTY and TOTAL AMOUNT across the whole current active Requirement, not only the latest staff update.
96. A Lot whose latest confirmed Requirement qty is zero is NOT REQUIRED and is hidden from the continuing saved Requirement list from the next Collection update onward. Its sample-send/zero-demand history remains auditable.
97. Previously non-zero saved Lots remain prefilled on subsequent updates until explicitly changed/removed or lifecycle terminal close. Existing same-Collection duplicate-sample blocking remains unchanged.
98. Customer pricing uses authoritative NET RATE = APPROVED SALE RATE - CUSTOMER ALLOWED DISCOUNT. Customer cannot edit approved rate, allowed discount or net rate.
99. Each Lot Rate field visibly shows APPROVED SALE RATE struck through and the customer NET RATE directly below/alongside in bold/prominent form.
100. Line AMOUNT = NET RATE x latest current Required Qty and is displayed prominently. Running TOTAL AMOUNT sums net-rate line amounts only; approved/gross rate is never used for customer payable Requirement total.
101. Approved rate and customer allowed discount come only from authoritative server mappings. Missing/invalid pricing is never invented client-side and must be resolved/blocked before commercial confirmation.
102. Final customer Requirement UX: NEW STAFF SAMPLES FIRST -> SAVED ACTIVE REQUIREMENT PREFILLED BELOW -> ONLY REAL CHANGES CONFIRMED -> ZERO DEMAND HIDES NEXT UPDATE -> RUNNING TOTAL QTY + NET-RATE TOTAL AMOUNT -> COMPLETE BACKEND AUDIT.
103. Final staff concurrency invariant: CUSTOMER MAY CONTINUE UPDATING -> EVENTS AUDITED -> STAFF SEES ONE CONSOLIDATED PENDING SNAPSHOT -> STAFF PROCESS CREATES CUTOFF/FREEZE -> LATER CUSTOMER CHANGES BECOME NEXT PENDING BATCH.
104. Universal customer pricing resolution for Collection/Requirement must be server-side and token/customer scoped. Approved Rate is resolved from the authoritative approved lot-rate record when available, with the universal sale-lot rate used only as the approved-rate fallback; customer Allowed Discount is resolved from the authoritative customer master.
105. The universal pricing response must expose per Lot: approved_rate, allowed_discount, net_rate and pricing_status. NET RATE is calculated server-side as APPROVED RATE - ALLOWED DISCOUNT and must never be guessed from a legacy customer-facing Sale Rate label.
106. Customer Real Chat top control strip must keep GROUP, SUPER ADMIN, TOTAL QTY and TOTAL AMOUNT aligned in one compact row where device width permits. TOTAL QTY and TOTAL AMOUNT are separate bordered boxes positioned immediately after SUPER ADMIN and use compact typography so the row does not unnecessarily wrap.
107. The same top TOTAL QTY / TOTAL AMOUNT boxes remain visible both in normal Real Chat view and while the Requirement panel is open. They show the current consolidated active Requirement, not merely the latest screen fragment.
108. Legacy standalone/bottom running-total box is superseded by the compact top boxes in the approved V9637 UX. Per-Lot Rate shows Approved Rate struck through, bold NET Rate and bold line Amount; overall TOTAL AMOUNT is the sum of those NET-rate line amounts.

SAFE IMPLEMENTATION ORDER: first add read-only/consolidation server contract and latest-qty state; then isolated customer prefill/change-confirmation UI; then net-rate display/running totals using authoritative pricing; then staff PROCESS cutoff. Do not alter stable production customer/staff routes until each isolated step passes.

V9637 SAFE CHECKPOINT: server functions rr_collection_customer_pricing_v9637 and rr_collection_customer_requirement_summary_v9637 provide token-scoped authoritative pricing/current Requirement summary. Isolated frontend addon real-customer-pricing-summary-v9637.js applies compact header totals and Net Rate display. Stable production routes remain untouched pending isolated verification.