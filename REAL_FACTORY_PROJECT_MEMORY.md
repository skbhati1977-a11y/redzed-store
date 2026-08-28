# REAL FACTORY Project Memory

## Matching Cloth Master — verified behavior (2026-08-18)

This note records the verified, already-existing Matching Cloth behavior so future work should consult this file before re-researching or changing code.

### Destination files for the dedicated Matching Cloth child master
- Final destination HTML: `real-matching-cloth-master.html`
- Final destination JS: `real-matching-cloth-master-v9235.js`
- Slice Menu link source/wiring file: `real-global-slice-menu-v9190.js`
- Product Master -> Matching Cloth child menu points to `real-matching-cloth-master.html`.
- Future Matching Cloth UI/mapping work should normally be implemented only in the destination HTML/JS above unless an existing shared backend rule genuinely requires a different file.

### Approved behavior source files / historical references
- PRIMARY latest refined searchable Fabric + Vendor UI source: `real-mc-searchable-mapping-v9140.js` (internal VERSION 9148 behavior).
  - Fabric RPC: `rr_get_mc1_fabric_options_v9134`
  - Vendor RPC: `rr_get_mc_vendor_options_v9135`
  - Search overlay, real Fabric id mapping, Vendor `supplier_ledger_id`, stock/rate context, and Add New behavior are sourced from this file.
- Earlier searchable source: `real-mc-searchable-mapping-v9136.js`
  - Historical commit: `4771689a97c80c030fda00f2717fdf8681aa2dfd`
- Earlier mapped dropdown source: `real-mc-mapped-dropdowns-v9135.js`
  - Historical commit: `abf4cbafac2d20f9e515401317bac6243662af5c`
  - Confirms vendor option -> `supplier_ledger_id` mapping.
- Existing Product Master MC entry/save behavior source: `real-product-master-v720.js`
  - Reuse its MC purchase field behavior and `rr_post_mc_fabric_purchase_v3` posting contract; do not invent a parallel purchase flow.
- Accounts/backend source: `REAL_FACTORY_V9076_MC_PURCHASE_ACCOUNT_MAPPING.sql`
  - Purchase RPC: `rr_post_mc_fabric_purchase_v3`
  - Accounts RPC: `rr_get_mc1_purchase_account_v9076()`
  - Purchase account name: `Matching Cloth Purchase`

### Verified Fabric mapping
- Existing Matching Fabric options come from RPC `rr_get_mc1_fabric_options_v9134`.
- Fabric selection is tied to the real MC1 fabric record/id, not just free text.
- Existing option labels can include Fabric Name + Available Qty + Avg Rate.
- New fabric must reuse the existing MC1 fabric create/upsert flow; do not create a parallel fabric store.

### Verified Vendor mapping
- Existing Vendor options come from RPC `rr_get_mc_vendor_options_v9135`.
- Approved mapping includes `supplier_ledger_id` on vendor options.
- Searchable Vendor selection can show purchase history context such as bill count, total qty and total value.
- Therefore Vendor mapping already exists and must be reused. Do not replace it with an unrelated free-text-only system.

### Verified Purchase / Accounts mapping
- Purchase posting uses `rr_post_mc_fabric_purchase_v3`.
- Purchase posts to the exact MC1 fabric account, updates fabric qty/value/avg rate, updates consolidated MC1 qty/value/avg rate, creates `PURCHASE_IN` ledger entry, and stores vendor/bill details.
- Accounts exposure uses `rr_get_mc1_purchase_account_v9076()` and purchase account name `Matching Cloth Purchase`.

### UI direction agreed with user
- Dedicated Matching Cloth child page remains: Header -> Entry Form -> Available Matching Cloth Stock.
- CB / Art Due / Art Decide cards must not appear on this page.
- Fabric and Vendor selection must reuse the approved mapped/searchable behavior above.
- `+ Add New Fabric` and `+ Add New Vendor` are separate red buttons outside the selection fields.
- Do not change unrelated modules, database schema, or existing approved save/account behavior unless explicitly required.

### Implementation rule
Before changing Matching Cloth code, read this memory note and `REAL_FACTORY_RULE_BOOK.md` first. Source behavior from the approved files/RPCs listed above, then apply only the required UI/integration changes to the destination files. Do not re-create mappings from scratch when these verified sources already exist.


## Customer Live Sales / Permanent Chat — locked project memory (2026-08-29)

This memory is the implementation checkpoint for the finalized customer live-sales architecture. The detailed point-by-point authority and behavior source of truth is `REAL_FACTORY_RULE_BOOK.md`, section `Customer Live Sales, Chat, Billing & Payment — LOCKED RULES (2026-08-29)`.

1. One Customer = one permanent continuous Sales Chat; CPI closes only that Order Session, never the customer chat.
2. No-order conversations stay open and can receive future collection/message pushes.
3. Each order remains a distinct Requirement -> PI -> CPI session inside the permanent conversation.
4. Sales chat is team/group-owned; Super Admin alone can Join/Remove authorized staff IDs.
5. Super Admin alone can BLOCK/UNBLOCK staff app access; block is backend-wide and history remains attributed.
6. Customer-facing normal group messages show sender name only, never internal Salesman/Admin/Worker/Sales Team category labels.
7. Chat supports text, voice, image/file/PDF, product cards, reply/quote, timestamps and read/unread.
8. Universal sales attach/share panel: Gallery, Camera, Document, Location, verified Payment QR, Visiting Card, Collection, PI/Bill, Dispatch, Contact, Template and secure Link.
9. Customer has relevant attachment options such as Gallery/Camera/Document/Location; controlled official templates remain staff-authorized.
10. Live-stock collections/more designs can be pushed into the same permanent chat; requirement quantities synchronize to structured Requirement data and backend stock revalidation prevents overselling.
11. Supported own-app/PWA/browser push deep-links customers back to the same conversation/message/product.
12. Super Admin alone applies/releases PAYMENT/ACCOUNT/BILLING HOLD; active HOLD backend-blocks CPI.
13. Private messaging is ONLY Customer <-> Super Admin. No private chat is allowed with Salesman, Admin, Accountant or any other group member. The Super Admin private channel can be used for confidential/direct communication and is not limited only to HOLD cases.
14. Private content is backend-restricted from unauthorized group members; Accountant does not automatically see the private conversation.
15. Private communication supports chat/voice/attachments/reply and permitted calls; recorded calls require disclosure/consent and restricted storage.
16. Payment Commitment authority is Super Admin; commitment operational data is shared with Super Admin + Accountant, while Admin gets operational follow-up alert/status only.
17. Payment due/follow-up alerts go internally to Accountant + Admin + Super Admin; customer gets scheduled reminder message/notification without confidential internal details.
18. Commitment history is preserved; changed/missed promises are not overwritten and partial payments continue balance follow-up.
19. Payment slip/customer `paid` message is not official payment confirmation.
20. Actual payment verification/recording is Accountant authority. Salesman/Admin cannot officially confirm payment; Accountant cannot release Super Admin HOLD.
21. Accountant confirmation updates paid/balance state and reminders; Super Admin then reviews HOLD release; release leads to READY FOR CPI, not automatic CPI.
22. Customer can clear/hide only their own chat view by Last 7/30/90 Days, custom range or all-view; this never deletes REDZED company master history.
23. Company-side Conversation Archive/Restore/Permanent Delete belongs ONLY to Super Admin; other staff have no company-history archive/delete authority.
24. Company permanent-delete is distinct from archive, requires stronger confirmation/reason, and leaves immutable audit metadata.
25. Financial/statutory/audit records remain independently protected from chat clear/delete operations.
26. Sales Conversation and Private Conversation archives remain separate by access control.
27. Main Customer Group Chat bottom UI has `CALL | MESSAGE` quick controls plus the normal attachment/message/voice/send composer.
28. CALL opens a clean single-column list of ONLY current active/authorized members of that exact Customer Group. Removed, blocked, inactive or unrelated names must never appear.
29. Group member names are backend-driven, not permanently hard-coded. Super Admin, Lukman, Kishan, Shailender, Reeka Ji, Anuj and Customer are examples only when actually in that group.
30. Call target selection is single-select. Selecting a member does not immediately call; UI first shows `Selected: <name>` and requires a second explicit `CALL <name>` confirmation.
31. Wrong-recipient prevention is mandatory: separate full-width name rows, adequate spacing, one selected target, visible selected-name confirmation and explicit second call action.
32. Recording-enabled call flow: choose member -> confirm member -> disclosure/consent -> connect -> recording starts only after required disclosure/consent.
33. Group-context call metadata links caller, selected recipient, customer/group, time, duration and answered/missed status; permitted recording is linked to that same call/context under retention/access rules.
34. Normal MESSAGE means Group Chat. There is no generic private-member selector and no Customer private chat with normal group members.
35. Group Info: eligible members get `Call`; ONLY Super Admin row gets `Call | Private Chat`, with Private Chat next to Call.
36. Super Admin Private Chat button reopens the one existing Customer <-> Super Admin private conversation; do not create duplicate threads.
37. Call permission never implies private-message permission.
38. Super Admin group membership/block state controls call eligibility; removed/blocked/inactive members disappear from new call choices according to effective backend state.
39. Final communication principle: normal customer communication = transparent Group Chat; calls = safely selected group-context calls; private messaging = Customer <-> Super Admin only.
40. Final business flow: Collection -> Permanent Chat -> Requirement/More Designs -> Order Session -> PI -> optional Super Admin HOLD/Private Communication -> Commitment/Reminders -> Accountant Payment Confirmation -> Super Admin Release -> READY FOR CPI -> CPI -> Session Closed -> Same Chat Continues -> Future Collection/New Order.
41. Before implementation, read the locked Rule Book section first and preserve existing Market/Receive/Stock modules unless a required shared integration is explicitly needed.
