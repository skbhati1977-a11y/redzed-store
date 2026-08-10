REAL FACTORY V805.31 — MATERIAL PURCHASE CLEAN MAPPED

1. Run RUN_MATERIAL_PURCHASE_POLISH_V80531.sql
2. Run VERIFY_MATERIAL_PURCHASE_POLISH_V80531.sql
3. Upload/replace real-material-master-v805.html
4. Upload/replace real-material-master-v805.js
5. Upload/replace real-accounts-v805.html

LOCKS:
- Core rr_material_source_search_v805_1 mapping is untouched.
- Regular Cloth stays outside generic Material Purchase.
- Matching Cloth / Sticker / Metal ID remain source-managed.
- Suggestions appear only after typing.
- Stock Qty / Consumption Qty / Consumption Method / Applicable To are not shown in Purchase UI.
- Generic Stock Qty and Consumption Equivalent are calculated in backend from saved configuration.
- Material Cost & Consumption table removed from Purchase entry page.
- Add New Material stores first-time units, conversions, consumption rule and preferred supplier.
- Add New Supplier creates canonical supplier ledger and maps immediately.
- Add New Type creates canonical Material Type.
- Supplier mapping supports preferred supplier and source-level supplier map.
- Krishna Material, Vinayak Material, Rishabh Material and Sunil Supplier are seeded.
- Matching Cloth purchase bridge is NOT enabled in this patch; its mapping source is deliberately not changed.
