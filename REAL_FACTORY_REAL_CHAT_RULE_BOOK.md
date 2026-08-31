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