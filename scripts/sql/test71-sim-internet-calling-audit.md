# TEST71 SIM and internet calling audit — 2026-10-07

Changed the existing Sales/Customer Real Chat calling entry points only. The previous SIM handler called a WebRTC-start RPC that never returned a mobile number. The old WebRTC poll consumed the offer before an incoming call was answered, and dropped ICE before the remote description. The secure customer fullscreen chat did not load the old calling adapter.

The new adapter offers SIM dialer links (no call-start RPC or microphone) and internet audio using the existing call and signalling tables. Customers authenticate with their existing device-bound secure session; staff use authenticated active profiles and group membership. The new RPC accepts TEST chats only. No SMS provider, Twilio integration, recording, or billing is added. Existing message Web Push and OTP settings are unchanged.

Verification: 6/6 targeted tests pass, covering SIM routing, early offer/ICE, duplicate taps, microphone cancellation/cleanup and existing voice messages. Database rollback tests passed for unauthenticated/invalid-session rejection, authorized contact and phone lookup, unknown-call rejection, two-member start/incoming/offer/answer/hangup, and own-signal exclusion. Syntax and diff checks passed.

Broader static suite has 30 pre-existing failures, also reproduced at unchanged HEAD b81ecaba; no additional failure found. Some existing asynchronous tests keep the broad runner alive, so the baseline run was bounded to 30 seconds. This is not a clean full-regression gate.

Push audit: 2 enabled CUSTOMER and 2 enabled STAFF subscriptions. 8 message outbox jobs processed in the last 24 hours, 0 pending. These counts do not prove delivery to every device. No incoming-call push trigger exists. Calls ring visually while Real Chat is open; background/closed-app call notifications are not implemented. Two physical phones, microphone permissions, Wi-Fi/mobile interoperability and audio quality remain unverified. Direct STUN connections can fail on restricted networks; the UI offers SIM fallback. No paid TURN service is configured.

Apply scripts/sql/test71-sim-internet-calling.sql to provision the TEST-only RPC; it was applied and verified on hruartsemierwhtzonei. Production/Main frontend remains unchanged.
