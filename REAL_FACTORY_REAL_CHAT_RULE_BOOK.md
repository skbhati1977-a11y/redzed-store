# REAL FACTORY — REAL CHAT / COLLECTION / REQUIREMENT RULE BOOK

Status: LOCKED REFINED RULES — 2026-08-31

1. WhatsApp is only the entry gate. Staff shares a secure REDZED URL; continuing business conversation runs inside REDZED Real Chat. No direct WhatsApp-to-Real-Chat inbound mirroring is required for this design.
2. First customer entry: secure URL -> Name + Mobile -> PROCEED -> verified/bound customer identity -> permanent Real Chat contact -> full-screen Real Chat.
3. One Party = one permanent Real Chat contact. Future collections, requirements, PI/CI and messages continue inside the same permanent contact/history.
4. Customer-side MESSAGE/chat must be full-screen WhatsApp-like Real Chat. The current customer half-screen/group-chat sheet is to be replaced. Staff Real Chat full interface is not changed merely for this customer-side requirement.
5. Customer should not need back-and-forth navigation: a Collection/Update card opens from Real Chat, requirement is filled/submitted, and the customer remains/returns directly in the same Real Chat timeline.
6. Collection and Requirement are connected stages of the same sales chain: staff sends RZ Collection 01; customer response from that collection becomes Requirement 01. Requirement is not an unrelated case.
7. Permanent relation: RZ Collection 01 -> Requirement 01 -> PI -> CI -> CLOSED. Next fresh cycle: RZ Collection 02 -> Requirement 02 -> PI -> CI -> CLOSED.
8. Within the SAME Collection Number, any style/item already sent in the first send or any update becomes hidden/blocked for later UPDATE sends of that same Collection Number. Duplicate prevention is cumulative within that collection cycle.
9. The duplicate restriction applies only to UPDATE inside the same Collection Number. Starting NEW Collection 02 resets send eligibility: styles/items sent in Collection 01 may be sent again in Collection 02.
10. Collection 02 then maintains its own fresh cumulative sent/update history; items sent once in Collection 02 cannot be repeated in later Collection 02 updates.
11. Exact eligibility principle: duplicate restriction = same party + same Collection Number + that Collection's sent/update history; it is not a lifetime party restriction.
12. Real Chat is the master customer-facing timeline for lifecycle events: Collection SENT/OPENED/UPDATED, Requirement RECEIVED/UPDATED, PI GENERATED, CI GENERATED, CLOSED/CANCELLED.
13. Old/closed collection chains remain permanent history. Starting a new Collection does not delete or renumber previous history.
14. Customer Directory/Chats switch: keep a small always-available directory button in full-screen chat. If messages arrive from other customer contacts, show unread count badge (1, 2, 3...).
15. Directory list is sorted by latest activity, with unread contacts prioritized. Each row may show party/customer name, latest message preview, time and unread count. Opening a contact switches directly to that full-screen chat and updates unread state.
16. Open Requirement reminder persists until the linked flow reaches CLOSED or CANCELLED. Merely reading a message does not clear the business reminder.
17. Requirement cancellation is linked to PI/CI cancellation. Cancellation starts only from the highest stage already reached and cascades backward automatically.
18. Highest-stage cancellation rule: if only Requirement exists, cancel Requirement; if PI exists, cancel PI and auto-cancel linked Requirement; if CI exists, cancel CI and auto-cancel linked PI and Requirement. The linked Collection chain becomes CLOSED/CANCELLED.
19. Do not start cancellation from a lower stage when a higher stage exists. UI should direct the authorized user to cancel from the highest reached stage.
20. Cancellation must retain mandatory reason, actor, timestamp and linked Collection/Requirement/PI/CI references in audit/history.
21. Collection with no customer response: if not opened, status remains SENT / NOT OPENED; if opened but no requirement submitted, status is OPENED / NO RESPONSE. Requirement number is not created until customer actually submits a requirement.
22. Staff may manually remind or eventually CLOSE - NO RESPONSE. CLOSED - NO RESPONSE is distinct from CANCELLED. A later NEW Collection starts a fresh cycle with full eligible collection pool.
23. Time-based automated follow-up: after Collection SENT, system checks whether customer opened it. If not opened by configured time, send a template reminder from sender name Mr. Ranveer.
24. Once customer opens the Collection, NOT OPENED reminders stop. A separate OPENED BUT NO REQUIREMENT timer begins. If requirement is still not submitted by configured time, Mr. Ranveer sends the configured follow-up template.
25. Mr. Ranveer reminder scheduling supports configurable delay/interval, pause/resume and maximum reminder policy. All Collection/Requirement reminder timers stop when the required response is received or the chain is CLOSED/CANCELLED.
26. Main chat sender display for these automated follow-ups is Mr. Ranveer; do not add Bot/Assistant labels in the normal chat message UI. Do not invent false personal history/details for the sender identity.
27. Payment reminder automation uses a separate sender identity: Mrs. Bhati Reeka. Payment reminders stop/update according to confirmed payment/balance state; they are independent from Mr. Ranveer Collection/Requirement reminders.
28. Reminder templates are controlled system templates, while real available staff can continue the same group chat naturally when the customer responds.
29. Reminder message must always be stored in Real Chat, so if chat is closed it remains unread and appears on next open.
30. For actual floating/device notifications while Real Chat is closed, implement customer-authorized browser/PWA push: notification permission + service worker/push subscription + backend subscription mapping to the permanent customer/contact.
31. Push notification should deep-link to the same permanent Real Chat and preferably the exact active Collection/Requirement context. If notification permission is absent, Real Chat unread delivery still remains valid.
32. Trigger transition: SENT -> timer -> NOT OPENED reminder; OPENED -> stop not-opened timer -> no-requirement timer; REQUIREMENT RECEIVED -> stop collection/requirement response reminders.
33. Security: typing a mobile number alone must never expose an existing customer's chat history. First entry/re-entry must use secure URL/token plus appropriate verification/session binding; trusted-device re-entry may be made seamless after secure binding.
34. Core architecture: WhatsApp Entry Gate -> Secure Customer Identity -> Permanent Real Chat Contact -> Collection/Requirement linked cycle -> PI -> CI -> CLOSED/CANCELLED -> next NEW Collection cycle in the same permanent contact.
35. Implementation discipline: preserve currently stable staff Real Chat and unrelated modules. Implement customer full-screen UI, lifecycle linkage, directory/unread, reminder engine and push notification layer surgically; do not silently alter unrelated PI/CI/stock/business rules.

## LOCKED ACTIVE COLLECTION CONVERSATION RULES — 2026-08-31

36. One Party + one active commercial conversation = one Collection Number. A Collection Number identifies the complete active commercial cycle, not an individual sample send.
37. Fresh send starts the number, e.g. RZ COLLECTION 01. Every continuation before terminal close remains under RZ COLLECTION 01: customer more-sample requests, staff additional sample sends, Collection updates, Requirement submissions/revisions, PI and CI.
38. Updates are versions/events inside the same Collection Number. They may be displayed as Update 01, Update 02, etc., but they MUST NOT create Collection 02 or a new business-cycle identity.
39. Customer active-cycle actions shall include SEND MORE SAMPLES, SEND REQUIREMENT and CLOSE REQUIREMENT.
40. SEND MORE SAMPLES opens all valid configured product categories with multi-select checkboxes. Customer may select multiple categories and submit the request without leaving the permanent Real Chat.
41. A customer SEND MORE SAMPLES action is an update/request inside the current Collection; it does NOT create a new Collection and does NOT create a new Requirement merely by requesting more samples.
42. Customer-selected category IDs/values must be stored server-side against the current Collection update. Staff opening that request must see those same categories automatically preselected; staff must not be required to re-enter or re-tick the customer's requested categories.
43. Staff sample selection for a customer more-samples request must be scoped to the customer-selected categories. Staff then selects the actual eligible samples/lots to send from that scoped pool.
44. Same-Collection cumulative duplicate blocking still applies to additional sample sends: a style/item already sent anywhere in that Collection's first send/update history cannot be sent again in a later update of that same Collection.
45. When staff sends additional samples, customer receives UPDATE COLLECTION inside the same Real Chat/current Collection. Customer opens the update, fills required quantities/details and may SEND REQUIREMENT.
46. SEND REQUIREMENT creates/updates the Requirement linked to the current Collection and permanent customer/chat chain. Additional sample/requirement conversation must not break or replace that Collection identity.
47. After Requirement is received, staff may either continue the same Collection with more samples/updates or convert the Requirement to PI. Both paths remain under the same Collection Number.
48. Customer CLOSE REQUIREMENT before PI is a terminal customer-side abandonment/closure of that active commercial cycle. No PI is created from that closed Requirement. The next fresh commercial conversation starts the next Collection Number.
49. Staff PI creation is the commercial conversion closure of the Requirement: when PI is generated, the linked Requirement is considered closed/converged into PI automatically; a separate manual Requirement-close action is not required.
50. PI creation does NOT final-close the Collection cycle. The same Collection Number remains the lifecycle identity through PI -> CI.
51. CI generation is the normal successful terminal close of the Collection cycle. After CI, that Collection becomes final historical CLOSED and any later fresh business requirement/sample conversation starts the next Collection Number.
52. Therefore the normal successful chain is: Collection 01 -> initial send -> Update 01/02/... -> Requirement -> PI -> CI -> FINAL CLOSED. The abandoned chain is: Collection 01 -> updates/Requirement -> customer CLOSE REQUIREMENT -> CLOSED WITHOUT PI. Only after terminal close may Collection 02 begin.
53. A closed Collection must never be silently revived for a new commercial conversation. Previous Collection number, updates, selected categories, sent samples, Requirement/PI/CI references and closure reason/state remain permanent history.
54. Staff/customer UI labels and backend relationships must preserve this invariant: More Samples and Updates are continuation events; Collection Number changes only when a genuinely new cycle begins after the prior cycle reaches its permitted terminal close.
55. Safe implementation order for these rules: preserve approved customer/staff UI first; add server-side lifecycle/update/category data contract; verify current Collection identity and duplicate rules; then add customer actions; then staff auto-prefill/sample-send flow; then Requirement/PI/CI terminal transitions. Each step is isolated and verified before the next, with no unrelated module changes.

## LOCKED PI / CI STOCK QUANTITY RULE — 2026-08-31

56. PI generation freezes/reserves the exact approved PI quantity against stock. PI does NOT physically deduct that quantity from stock; it makes that quantity unavailable for any other party/order while the PI reservation is active.
57. CI generation is the physical/commercial stock deduction point. When CI is generated from the linked PI, the CI quantity is deducted from stock and the corresponding PI freeze/reservation is consumed/released as part of the same controlled transition.
58. Therefore stock accounting must distinguish AVAILABLE, PI-FROZEN/RESERVED and CI-DEDUCTED quantities. The same pieces must never be double-counted as both available and reserved, and CI must never deduct the same reserved quantity twice.
59. If a PI is validly cancelled before CI, its frozen/reserved quantity must be released back to available stock through the authorized PI cancellation transaction and audit trail. If CI already exists, cancellation/reversal must follow the highest-stage CI cancellation rules rather than directly releasing the PI reservation.
60. Core inventory invariant: Requirement alone does not freeze stock; PI freezes quantity; CI lessens/deducts stock. All freeze, release and deduction transitions must be transactional, linked to the same Collection -> Requirement -> PI -> CI chain, and auditable.

## LOCKED PI VALIDITY / AUTO-CANCEL / RESERVATION CONFLICT RULE — 2026-08-31

61. A newly generated PI may remain in AWAITING PARTY CONFIRMATION under automated Real Chat/bot-assisted follow-up for a maximum of five WORKING DAYS while its PI quantity remains frozen/reserved.
62. The five-day period is calculated using the configured business working-day calendar, not simple calendar days. Configured weekly offs and holidays do not consume a working day.
63. If valid party confirmation has not been recorded by the sixth working day, the system must automatically cancel the unconfirmed PI with reason AUTO CANCEL - NO PARTY CONFIRMATION and transactionally restore all still-frozen PI pieces to AVAILABLE stock.
64. PI auto-cancellation must permanently audit PI, Party, Collection/Requirement chain, frozen quantity released, reason, trigger timestamp and resulting stock state. The cancelled PI/history is retained and is not deleted or silently reused.
65. During the five-working-day validity window, automated assistance may send configured confirmation reminders in the same permanent Real Chat. Confirmation must stop the expiry path; reminder delivery/read state alone is not confirmation.
66. A new Requirement may legitimately request a Lot whose physical stock is partly or wholly frozen in another active PI. The system must not silently steal that reservation and must not hide the conflict from staff.
67. At the relevant next PI/CI preparation point, a Lot-level RESERVATION CONFLICT popup must show enough context to act safely: Lot No., physical stock, already PI-frozen quantity, currently available quantity, new requested quantity, shortage against available stock, and the affected existing PI/reservation reference(s).
68. From that conflict popup, authorized staff may directly open the existing frozen reservation and explicitly modify/reduce its PI-frozen quantity when business judgment permits. Released pieces become AVAILABLE transactionally and can then be reserved by the new PI.
69. Existing PI frozen quantity is never automatically reduced merely because another Party requested the same Lot. Reallocation requires an explicit authorized staff action.
70. Every reservation modification/reallocation must audit old frozen quantity, new frozen quantity, released quantity, affected Lot, source PI/Party, destination/new PI or Requirement context where applicable, actor, timestamp and mandatory reason.
71. Reservation modification must preserve stock arithmetic atomically: physical stock = available + active PI-frozen/reserved + already CI-deducted/accounted stock according to the authoritative inventory model; no piece may be simultaneously available and frozen or deducted twice.
72. Once quantity has reached CI, it is no longer a modifiable PI reservation. Any change/reversal of CI-deducted quantity must follow the highest-stage CI cancellation/reversal rules; staff must not bypass CI by editing the old PI freeze.
73. The conflict popup is a controlled decision surface, not an automatic allocation engine. Its purpose is to expose existing reservations and allow authorized, audited modification without forcing staff to hunt through unrelated screens.
74. Final invariant: Requirement = demand only; PI = temporary frozen reservation for up to five working days pending party confirmation; sixth working day without confirmation = auto-cancel + restore; competing demand = visible reservation conflict + optional authorized reallocation; CI = actual stock deduction.

## LOCKED SINGLE LIVING COLLECTION CARD / UNIFIED UPDATE RULE — 2026-08-31

75. One active Collection is represented in normal Real Chat by ONE living Collection card/conversation object. More Samples, Requirement submissions/revisions and staff Collection updates update this same object; they must not create a growing stack of technical lifecycle messages in the customer chat timeline.
76. Every successful commercial continuation inside the same Collection uses ONE shared monotonic update sequence. MORE SAMPLES and REQUIREMENT are not separate counters. Example: More Samples = Update 01, Requirement = Update 02, More Samples = Update 03, Requirement revision = Update 04.
77. The current displayed Update number must always be resolved from server-side Collection state/history. UI must not keep an independent stale/local counter. If backend records Update 06, returning to chat must show Update 06 on the same Collection card.
78. SEND MORE SAMPLES flow: select categories -> SEND REQUEST -> persist successfully -> category/request panel exits automatically -> return directly to the same Real Chat. No success browser alert/OK confirmation screen is allowed in the normal successful path.
79. SEND REQUIREMENT flow follows the same principle: successful submit returns directly to the same chat and advances the same shared Collection update sequence.
80. Technical events remain fully stored in backend/audit history, but routine Collection/Requirement update events must not each be inserted as ordinary customer-visible chat bubbles. Normal timeline remains clean; the single Collection card shows current lifecycle state and latest Update number.
81. User-written chat messages, authorized staff/customer conversation and genuinely required reminder/payment messages remain normal chat messages. The no-message-spam rule applies to technical lifecycle/update notifications, not genuine human conversation.
82. Collection card identity remains stable from first send through updates, Requirement and PI/CI lifecycle. It is updated in place until terminal CLOSED/CANCELLED; a new card/Collection Number is created only for the next fresh commercial cycle.
83. Backend audit must retain each action type, update number, actor, timestamp, selected categories/requirement references and state transition even though those events are not rendered as separate chat bubbles.
84. Final UX invariant: ONE PARTY -> ONE ACTIVE COLLECTION -> ONE LIVING CHAT CARD -> ONE SHARED UPDATE COUNTER -> MANY AUDITED INTERNAL EVENTS -> PI -> CI -> TERMINAL CLOSE.

Rules 85+ are locked in REAL_FACTORY_REAL_CHAT_RULE_BOOK_V9635_ADDENDUM.md and form part of this master rule book.