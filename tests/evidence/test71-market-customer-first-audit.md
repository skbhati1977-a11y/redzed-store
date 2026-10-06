# TEST71 Market collection sharing: customer first

Scope: Readymade WORKING Send selected and Market Window share chooser; existing manufacturing collection rules remain the authority.

## Verified rules and wiring

- Generic internal sharing asks for recipient(s) before listing or choosing Market cards. No global stock listing is loaded in this step.
- Each recipient's existing `rr_sales_collection_cards_test71` contract removes lots already sent in that collection and enforces requested categories before pagination.
- For several recipients, the picker displays the union of eligible designs. Send checks eligibility again for each recipient and sends only their eligible subset. A lot already sent to one recipient can still be new for another.
- Search, category, stock filtering and refresh continue to call the same recipient scoped contract; the filter survives page reload through recipient query parameters.
- Readymade selection is a candidate selection only. Customer scoped loading removes ineligible preselected lots before final selection. Every Working card's Send selected uses this Market flow.
- Outside / WhatsApp is an explicit separate mode using the existing Market share token and device share picker. It does not impersonate an internal customer send or increment internal update counters.
- Existing chat specific entry already knows the recipient and therefore opens the filtered collection directly. Its send return now includes the confirmed message ID for focus.
- Internal send confirmation comes from `rr_sales_collection_send_test71`. Errors do not redirect as successes; duplicate or no-new-design attempts do not increment counters.
- Existing numbering is retained: the original collection is followed by U1, U2, etc. Card headings now use U rather than UPDATE; the live strip already uses U.
- Latest default live status uses the latest actual send timestamp. Explicit successful-send return uses the exact cycle from the backend response. Older CLOSED history cards remain history.
- Backend role, customer membership, closed-cycle, requested-category and duplicate-lot checks remain in the existing collection engine. No alternate purchase, stock, accounts, pricing or RRQ engine is introduced.

## Validation

- Integration tests execute customer-first adapter, actual Market core and chooser together: no stock before recipient choice; already sent preselection removed; refresh retains scope; multiple-recipient union and individual send subsets; outside mode.
- Readymade tests cover navigation from any card and full selection transfer, private heads, read-only approved rate, stock balances and returns.
- Existing internal-send and live-strip tests cover success, failure, skipped sends, exact-cycle focus and wrong-party rejection.
- Earlier live rollback audit (`test71-collection-latest-send-rollback.sql`) confirmed new message, U1 to U2, already sent lot exclusion and duplicate rejection, with all test writes rolled back.
- Real signed-in Android/browser interaction has not been performed in this runtime.
