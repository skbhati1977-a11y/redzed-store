# REAL FACTORY Rule Book

## Matching Cloth Master — source-of-truth rules

### Scope boundary
- Destination HTML: `real-matching-cloth-master.html`
- Destination JS: `real-matching-cloth-master-v9235.js`
- Slice Menu wiring file: `real-global-slice-menu-v9190.js`
- Matching Cloth work should stay in the destination HTML/JS unless a shared backend change is explicitly required.
- Do not alter CB Master, Art Decide, Cutting, Dashboard, other Product Master children, or database schema for Matching Cloth UI refinements.

### Approved UI mapping source
- Latest refined searchable mapping reference: `real-mc-searchable-mapping-v9140.js` (VERSION 9148 behavior).
- Earlier approved references: `real-mc-searchable-mapping-v9136.js` and `real-mc-mapped-dropdowns-v9135.js`.
- Fabric options RPC: `rr_get_mc1_fabric_options_v9134`.
- Vendor options RPC: `rr_get_mc_vendor_options_v9135`.
- Vendor option mapping carries `supplier_ledger_id` when available.

### Fabric rules
- Existing Fabric must resolve to the real MC1 fabric id, never just a disconnected label.
- Search/suggestion label may show Fabric Name + Available Qty + Avg Rate.
- `+ Add New Fabric` must be a separate red button outside the mapped selection field.
- New Fabric must use the existing MC1 create/upsert behavior through the approved purchase flow; never create a parallel fabric store.

### Vendor rules
- Vendor selection must be sourced from `rr_get_mc_vendor_options_v9135` and remain searchable.
- Preserve `supplier_ledger_id` on the selected vendor in UI state when returned by the RPC.
- Vendor suggestion context may show bill count, total qty, and total value.
- `+ Add New Vendor` must be a separate red button outside the mapped selection field.
- Do not replace mapped vendor selection with a plain free-text-only system.

### Purchase / Accounts rules
- Purchase posting contract: `rr_post_mc_fabric_purchase_v3`.
- Existing Product Master MC save behavior source: `real-product-master-v720.js`.
- Accounts exposure: `rr_get_mc1_purchase_account_v9076()`.
- Purchase account name: `Matching Cloth Purchase`.
- Posting must continue to update exact fabric qty/value/avg rate, consolidated MC1 qty/value/avg rate, and `PURCHASE_IN` ledger behavior.

### Dedicated page layout rule
The Matching Cloth child page order is fixed:
1. Matching Cloth Master header
2. Matching Cloth Entry Form
3. Available Matching Cloth Stock

CB cards, Art Due cards, Art Decide cards, or crafting decision controls must never render on this dedicated Matching Cloth page.

### Change discipline
Before coding Matching Cloth, read `REAL_FACTORY_PROJECT_MEMORY.md` and this rule book. Reuse approved mappings and RPCs first. Change only the minimum required destination UI/JS and do not touch unrelated modules.


## Packing — approved actual-leftover rule (V9365)

Source of truth: user-entered box capacity -> equal size split -> colour split -> same-size colour shortage adjustment -> actual leftover.

- Build only the full Fresh/ASST boxes that every active size can supply. Within each size, use maximum distinct colours first, then duplicate the colour with the highest remaining stock.
- Fresh remains the balanced one-per-colour-size repeat; ASST remains a full adjusted balanced box.
- When another balanced box cannot be formed, all remaining colour-size stock is leftover. Do not substitute another size to force an ASST box and do not throw a shortage error for valid leftover.
- Apply the half-capacity rule to that actual leftover, never merely `total % capacity`:
  - Positive leftover <= half capacity: merge with the previous full box and mark the resulting box MIX.
  - Leftover > half capacity: separate MIX with its complete leftover composition, even if that quantity equals/exceeds one capacity.
  - No previous full box: retain the leftover as its own MIX.
  - Zero leftover: no MIX.
- Preserve every source colour-size quantity exactly; box numbering starts at 1 for each lot.
- Fresh count and ASST/MIX composition views use backend marks. Never infer MIX from `qty > 18`.
- Example: capacity 12, L24/XL18/XXL18 -> four ASST boxes of L4/XL4/XXL4 plus one MIX of L8/XL2/XXL2 = five boxes / 60 PCS.
- Backend implementation: `rr_fg_generate_pack_v787(text,jsonb,text,integer)`, version `LOCKED_CAPACITY_SIZE_COLOUR_ACTUAL_LEFTOVER_V9365`.
- Feasibility calculation: balanced-box count = minimum across sizes of floor(size stock / per-box size quota); actual leftover = total minus balanced-box count times capacity. Reserving the preceding box when leftover <= half produces the same merge without writing a partial failed box.
- Frontend: `real-finished-goods-v787.js` displays backend `pack_mark` (FRESH/ASST/MIX), with existing stock-type fallback for legacy unmarked records.
- Scope: no changes to photos, AI removal, approval, WhatsApp, submit, permissions, stock categories, despatch, or other departments. Existing plans are not automatically rewritten; normal authorized rerun applies the rule to an open lot.


## Customer Live Sales, Chat, Billing & Payment — LOCKED RULES (2026-08-29)

### A. Permanent customer relationship and order sessions
1. One Customer = One Continuous/Permanent Sales Chat. CPI completion must never close the customer relationship/chat.
2. Each commercial order is a separate Order Session inside that permanent chat: Collection -> Requirement -> PI -> CPI -> Order Session Closed.
3. If no order is received, the customer chat remains open in its current position and the sales team can continue pushing future collections/messages.
4. After CPI, show an order-completed boundary/marker, keep the chat live, and allow the next collection/new Order Session in the same conversation.
5. A customer may reply to an old product/message to request it again; the reference remains old but any new quantity/order belongs to a new active Order Session.
6. Chat and structured Requirement/PI/CPI records must remain linked, not become disconnected parallel data.

### B. Group ownership, identity and security
7. Customer Sales Chat is team/group-owned, not dependent on one primary salesman.
8. Join/Remove authority for authorized staff IDs in a customer group belongs ONLY to Super Admin. Admin cannot control membership.
9. BLOCK/UNBLOCK of any staff ID belongs ONLY to Super Admin. A blocked ID loses the entire protected app/backend/RPC/API/realtime ability, not merely group visibility; existing sessions must be rejected promptly.
10. Blocking never erases historical messages/actions; prior activity remains attributed to the original sender.
11. Customer-facing main Sales Group shows only the actual sender name (for example Lukman/Imran/Rakesh). Do not show Salesman/Admin/Worker/Sales Team role/category labels on normal staff messages.
12. Product shares may show `Shared by <name>`.

### C. WhatsApp-like chat and universal attachments
13. Main chat supports Text, Voice, Images, PDFs/Files, Product Cards, Reply/Quote, read/unread and timestamps.
14. Long-press/select any message, voice, image, file or product can Reply/Quote it. Do not use visible Voice 1/2/3 numbering.
15. Sales-side composer provides `Attach | Message | Voice | Send` with a universal attach/share panel.
16. Attach/share panel options are: Gallery, Camera, Document, Location, Payment QR, Visiting Card, Collection, PI/Bill, Dispatch, Contact, Template and Link.
17. Sales Team can use Gallery/Camera/File to send bills, garment/design references, colour/sample photos, screenshots, PDFs, size/reference charts and other customer-related material.
18. Location sharing must support tappable map/location cards; Sales Team can send showroom/factory/store/dispatch location and Customer can send shop/delivery location.
19. Payment QR must be a controlled/verified company payment QR/template; do not rely on unrestricted personal/wrong QR sharing for official payment requests.
20. Digital Visiting Card uses approved public REDZED/business details only.
21. Collection sharing sends live-stock/product cards into the same permanent chat; Sales Team can send more styles/designs without starting a new chat.
22. Official PI/CPI/Bill should be shareable as authorized clean system card/PDF rather than requiring screenshots.
23. Dispatch sharing may use a standardized card for permitted challan/transport/box/tracking details.
24. Contact sharing exposes only approved business/service contact information, not private/internal contacts automatically.
25. Quick templates may include New Collection, Please Confirm Qty, PI Ready, Dispatch Update, Please Check Designs and Thank You; staff can edit before send.
26. Secure collection/catalog/app deep links can be shared as proper link cards.
27. Customer-side attachment choices include relevant Gallery, Camera, Document and Location. Controlled official Payment QR/PI/Bill/Visiting Card templates remain authorized staff-side actions.
28. Voice remains a quick composer action and need not be hidden inside the attach panel.

### D. Requirement, quantity, collection and notification rules
29. Product Qty/requirement selected in chat must synchronize to the structured Requirement workspace.
30. Sales Team can `SEND MORE DESIGNS` from live physical stock into the existing conversation.
31. Requested Qty cannot silently oversell stock; UI clamps to max available and backend revalidates availability at submit/PI/final stages.
32. Own-app/PWA/browser push may notify supported/permissioned customers about new messages/collections and deep-link back to the same conversation/message/product.
33. Ongoing messaging is through the REDZED app/chat; WhatsApp is not required for the continuing conversation.

### E. Super Admin HOLD and private billing
34. PAYMENT/ACCOUNT/BILLING HOLD may be applied/released ONLY by Super Admin; HOLD must backend-block CPI generation with no Admin/Salesman bypass.
35. A held PI can use the Customer <-> Super Admin private channel. Private communication is allowed ONLY between Customer and Super Admin; no Customer<->Salesman, Customer<->Admin, Customer<->Accountant or other member private chat is permitted.
36. The Customer <-> Super Admin private channel is not restricted only to HOLD/billing; it is the single authorized private channel whenever confidential/direct Customer-Super Admin communication is needed.
37. Private content is backend-private from Salesman/Admin and other unauthorized members: no private text, voice, attachments, hold reason, payment negotiation, notes or recordings may be returned to them.
38. Accountant does not automatically receive Private Conversation access.
39. Private channel supports Text, Voice, generic Attachments, Reply and permitted call actions.
40. Recorded calls require an appropriate recording disclosure/consent flow and restricted private storage; no secret recording.
41. Hold release changes operational state to READY FOR CPI; release does not automatically create CPI.

### F. Payment commitment, alerts and reminders
42. Payment Commitment is created/changed/cancelled under Super Admin authority and includes expected date, expected amount, Full/Partial and private note/history.
43. Payment Commitment operational data is shared with Super Admin + Accountant. Accountant can see payment-follow-up fields such as Customer, PI/CPI, committed amount, due date, paid amount, balance and status without seeing the confidential Private Chat.
44. Admin receives operational payment follow-up alerts/status but not the confidential Private Conversation or private notes.
45. Internal due/follow-up alerts go to Accountant + Admin + Super Admin, including due-soon, due-today, overdue and partial-balance states.
46. Customer receives scheduled own-app reminder messages/notifications; internal hold reason, credit discussion and confidential notes must never be exposed in customer reminders.
47. Commitment history is append/history based; changed or missed commitments are not overwritten. Partial payment leaves a remaining balance commitment/follow-up.
48. Customer saying `paid` or uploading a payment slip is not an actual payment confirmation.

### G. Accountant payment authority
49. Actual payment verification/recording is Accountant ID authority, with Amount, Date, Mode, UTR/Reference, Against PI/CPI and supporting evidence as applicable.
50. Salesman/Admin cannot officially confirm payment.
51. Only a successful accounting entry generates the official payment-confirmation event/message. Partial payment must show confirmed amount and pending balance.
52. Accountant payment confirmation updates/stops reminders for the confirmed amount; remaining balance reminders continue.
53. Accountant cannot release Super Admin HOLD. After Accounts confirmation, Super Admin reviews and decides HOLD release.
54. Official accounting confirmation may be emitted as a verified REDZED Accounts system event; normal human Sales Group messages still follow the sender-name-only rule.

### H. Customer-side history clear vs company master record
55. Customer may clear/hide their own chat view/history by date/day range such as Last 7 Days, Last 30 Days, Last 90 Days, Custom Date Range or Clear All My Chat View.
56. Customer-side clear affects ONLY the customer's own visible chat history. It must not delete REDZED/company master conversation, business records, attachments, order history or audit records.
57. Customer must be clearly warned that clearing their view does not erase required company/business records.
58. Company-side Conversation Archive, Restore or Permanent Delete authority belongs ONLY to Super Admin. Admin, Accountant, Salesman or other staff cannot perform company master archive/delete.
59. Archive and Permanent Delete are distinct operations. Permanent Delete requires stronger confirmation and a reason.
60. Every company-side archive/delete action must leave an immutable audit record: who, what, customer/conversation, date range, reason and timestamp.
61. Financial/statutory/audit records such as accounting ledger, PI/CPI/invoice/payment confirmation remain protected independently and are not erased merely because chat content is cleared/deleted.
62. Customer-side attachment clear follows the same view-only principle; company master attachment retention/deletion follows Super Admin-controlled policy and applicable record-retention requirements.
63. Sales Conversation archive and Private Conversation archive remain logically/access-control separated.

### I. Group call and message controls — locked
64. Main Customer Group Chat mobile UI has bottom-aligned quick communication controls: `CALL | MESSAGE`, alongside/above the normal `Attach | Message composer | Voice | Send` composer.
65. CALL opens a clean single-column member selector. Every eligible member appears on a separate full-width row with adequate spacing; avoid dense chips or horizontal name lists that can cause wrong-person selection.
66. Call selector contains ONLY currently active/authorized members of that exact Customer Group. Removed, blocked, inactive and unrelated IDs must never be pushed into the list.
67. Member names are backend-resolved from the current group membership. Do not hard-code a permanent person list; names such as Super Admin, Lukman, Kishan, Shailender, Reeka Ji, Anuj and the Customer are examples of group members when actually present/authorized.
68. Only one call target can be selected at a time. Selecting another member automatically deselects the previous target.
69. Tapping/selecting a name must NOT immediately place the call. First show a clear confirmation state such as `Selected: Lukman`, followed by an explicit `CALL LUKMAN` action.
70. Call initiation flow is: open selector -> select exactly one member -> show selected name -> explicit call confirmation -> recording disclosure/consent where recording is enabled -> connect call -> start recording only after required disclosure/consent.
71. A group-context call record links Customer/Group, caller, selected recipient, start/end time, duration and answered/missed status. Where recording is permitted/enabled, recording also links to the selected call/member/context under applicable access and retention rules.
72. Normal MESSAGE action means Group Chat/group composer. It must never open a one-to-one private chat with Lukman/Kishan/Shailender/Reeka Ji/Anuj/Admin/Accountant/other normal members.
73. Private Chat is permitted ONLY Customer <-> Super Admin. This is the single exception to the Group-Only messaging rule and must be backend-enforced, not merely hidden in UI.
74. Group Info member rows expose `Call` for eligible callable group members. ONLY the Super Admin row may additionally expose `Private Chat`, positioned next to Call.
75. Super Admin Group Info row: `Call | Private Chat`. Other member rows: `Call` only; no private-chat button.
76. Opening Super Admin Private Chat reuses the existing Customer <-> Super Admin private conversation. Do not create duplicate private threads each time the button is pressed.
77. Bottom MESSAGE may focus the normal Group composer; a distinct clearly-labelled `Private Chat / Message Super Admin` action may open the authorized Super Admin private channel, but no generic private-member picker is allowed.
78. Call permission does not grant private-message permission. A member may be callable from the group while still having no private chat with the customer.
79. Super Admin membership/remove/block rules remain authoritative for the call selector. Once a member is removed/blocked/inactive, they must disappear from new call choices according to the effective permission state.
80. The UX must prioritize wrong-recipient prevention: clean one-column names, single selection, visible selected-name confirmation and a second explicit CALL action before connection.

### J. Core locked architecture
81. Main flow: Collection -> Permanent Customer Live Chat -> Requirement/More Designs -> Order Session -> PI -> optional Super Admin HOLD/Private Communication -> Payment Commitment/Reminders -> Accountant Payment Confirmation -> Super Admin Hold Release -> READY FOR CPI -> CPI -> Order Session Closed -> Permanent Chat Continues -> Future Collection/New Order Session.
82. Core authority split: Super Admin controls group membership, staff block/unblock, Customer-Super Admin private channel authority, private billing HOLD/release and company chat archive/delete; Accountant controls official payment verification; Admin gets permitted operational PI/CPI/follow-up functions but not those Super Admin-only controls; customer controls only their own chat view clear, not company master records.
83. Communication principle: normal customer communication is Group Chat; member calls are group-context calls selected safely from current authorized membership; private messaging exists only Customer <-> Super Admin.
84. Implementation discipline: this section is the functional source of truth for the planned live-chat/customer-sales system. Do not silently weaken privacy, authority, wrong-recipient prevention, audit, payment-confirmation or permanent-chat rules when implementing it.
