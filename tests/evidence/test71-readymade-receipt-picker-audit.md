# TEST71 supplier receipt picker repair

2026-10-06. Screenshot showed a successfully prepared JPG followed by a file-share capability guard that stopped the send flow. Repair is limited to Readymade receipt sharing and confirm-button guidance.

Receipt send panel now appears above the receipt body. Save & Confirm still posts the purchase exactly once and opens the receipt. The next explicit Send Receipt tap preserves browser user activation after async confirmation/JPG upload. On that tap:
- Native JPEG sharing is attempted when permitted; missing canShare alone no longer suppresses it.
- If only text/URL sharing is available, the native chooser receives the immutable receipt page link, clearly labelled as a link.
- If native sharing is absent or policy-blocked, a WhatsApp wa.me link without a phone number opens manual contact selection; no supplier is silently chosen.
- A separate browser-tab receipt view allows JPEG sharing outside inherited frame policy. It provides verified saved JPEG files, downloads and the same manual WhatsApp link fallback. Browser/OS restrictions can still block attachments; no promise of attachment delivery is made.

Standalone page is receipt-only, requires no app session and exposes no stock totals, costing, supplier ledger navigation or app controls. It validates the fixed Supabase receipt-image namespace and SHA-256 before enabling file sharing. Original frozen files are reused. Returning and pressing OK uses the existing idempotent share-event RPC; opening a chooser never automatically marks delivery or generates another note.

35 automated tests passed: existing Art/stock/Accounts UI regressions, real JPEG rendering, native file sharing on synchronous tap, native link fallback, absent canShare, denied policy/missing share API, rejection/cancellation, immutable-file reuse, OK retry identity, save-confirm receipt transition, and standalone session-free verification/URL rejection. JS syntax checks passed. Actual Android WhatsApp delivery has not been observed by automation.

Reference contracts: https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share (transient activation and web-share policy); https://faq.whatsapp.com/5913398998672934/ (wa.me message link without a specified phone number).
