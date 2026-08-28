# REAL FACTORY V9435 — In-App WebRTC Call + Recording

Targeted scope only. Existing Market, Receive, Stock, Packing, PI/CPI and unrelated modules were not rewritten.

## Live pieces
- `real-inapp-webrtc-call-v9435.js`
- Customer pages `s.html` and `real-market-share-v9420.html` load V9435 after the existing V9434 chat UI.
- Staff page `real-sales-live-chat-v9434.html` loads V9435 after the existing V9434 staff chat UI.
- Supabase migrations: `customer_in_app_webrtc_recording_v9435` and `staff_webrtc_start_mode_v9435`.

## Behavior
- Existing clean member selector and explicit second CALL confirmation remain the entry point.
- Calls are now in-app WebRTC audio instead of automatically opening `tel:`.
- Recording disclosure/consent is shown before the caller starts and again before the recipient answers.
- Signaling is scoped to the existing call/chat identity and active staff authorization.
- Caller records a mixed local + remote audio stream only after the remote stream is connected.
- Recording is stored as bounded database chunks linked to the existing call id; `recording_ref=DB_CHUNKS_V9435` marks calls with stored audio.
- Hangup/decline/connected state is written through the call signaling RPCs.
- Incoming staff calls are surfaced only to the selected active recipient. Customer incoming support is also present for customer-targeted WebRTC calls.

## Network boundary
V9435 uses WebRTC with STUN. This removes the browser `tel:` recording limitation, but peer-to-peer WebRTC can still fail on restrictive carrier/NAT/firewall networks. Carrier-grade reliability across those networks requires a TURN relay (or a managed VoIP/telephony provider) with project-owned credentials. No fake TURN credentials or secret call recording were added.
