# Customer mobile behavior

Run `node --test tests/customer-mobile-contract.test.cjs` before updating customer assets. The same suite runs on every TEST71 push and pull request.

Preserve these behaviors when adding features:

- Message direction uses the server-derived `payload.rr_customer_is_own`, with sent messages right and received messages left. Display names do not establish ownership.
- One collection button uses `collection_update_no` (U4), never the activity `update_no` (01). Customer history does not add update dropdowns; staff workflow history remains available.
- Collection rows, saved quantities and pricing resolve through the same authorized latest collection token. Requirement submission uses the collection token loaded by the panel.
- Every item has a full-width highlighted quantity row below its photos and specifications. Preserve numeric editing, stock limits and saved drafts.
- AVG RATE, TOTAL PCS, AMOUNT and ALL TIME AVG occupy a single four-column row above the chat/collection. Completed cycles keep the row visible. Missing rates/history remain unavailable rather than fabricated.

Layout ownership lives in the existing requirement-layout and collection-layout scripts. Update them directly rather than adding conflicting hiding rules or overrides. The secure message SQL migration preserves session validation, device binding and hidden-message filtering.

When publishing the installed public customer app, copy current TEST71 customer script sources and run the contract tests. Preserve the public app's own install gate and manifests and the repository's staff landing page. Bump edited asset versions together so iPhone and Android load the same source revision.

Automated tests validate rendering, token routing, rate calculations and layout contracts. Physical Safari layout remains a separate device check.
