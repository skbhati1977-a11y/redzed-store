# Costing V260 canonical rules
1. Actual Rate + Standard fallback come only from canonical Costing V760.
2. Assignment/Working Rate is not a costing authority; salary-derived cost is named Salaried Cost.
3. Real Chat Costing mirrors canonical UPM_RATE, one Lot card with consolidated alerts.
4. Owner Margin (currently ₹22 setting) is Super Admin/Owner view+edit only; non-owner backend payload is redacted.
5. Box codes: 1309 Regular ₹27, 1311 Medium ₹32, 1313 Large ₹36; future codes are Material-Master driven.
6. Packing requires box-code-wise split; multiple codes per Lot allowed; split total must equal algorithm box count.
7. Box Cost/PCS = sum(code boxes × effective code rate) / actual packed PCS, including Mix.
8. Audit: 1309/1311/1313 currently have no purchase rows; Purchase must display —. Reference rate is planning fallback, never a purchase claim.
9. Gatta/Panni and untrackable consumables remain weighted material costs; printing chemicals keep mapped drivers.
10. Salaried Cost pools payable salary by canonical department / department production PCS; piece-rate workers excluded.
11. Support/common salary and Manufacturing vs Readymade need explicit scope drivers before activation; factory salary must not silently hit Readymade.
12. Readymade future rule: Purchase Rate + explicitly decided Sale Rate = derived margin; Manufacturing protected ₹22 is not mandatory.
