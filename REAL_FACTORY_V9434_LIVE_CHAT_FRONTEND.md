# REAL FACTORY V9434 — Targeted Live Chat Frontend

Applied without rewriting unrelated Market/Receive/Stock/Packing modules.

## Backend API
- Supabase migration `customer_live_chat_frontend_api_v9434`
- Supabase migration `customer_live_chat_staff_directory_v9434`
- Supabase migration `customer_live_chat_member_visibility_hardening_v9434`
- Customer token/mobile-scoped group/private chat RPCs
- Active group-member call selector RPC
- Attachment upload/download up to 6 MB
- Staff inbox/messages/upload/call RPCs
- Super Admin-only staff directory/member-management path
- Group member visibility hardened to active membership or Super Admin

## Customer UI
- `s.html` + `real-market-share-v9420.html` load `real-customer-live-chat-v9434.js`
- Bottom `CALL | MESSAGE`
- Clean single-column call list
- Single selected member + explicit second CALL confirmation
- Group message composer
- Customer <-> Super Admin private tab only
- Gallery, Camera, Document, Location, Voice attachment support
- Sender names shown without role/category labels

## Staff UI
- `real-sales-live-chat-v9434.html`
- `real-sales-live-chat-v9434.js`
- Permanent customer inbox
- Group and Super Admin-only private conversation
- Group Info
- Clean Call selector
- Super Admin row may open Private Chat
- Super Admin can add/remove group members
- Gallery, Camera, Document, Location, Template, Link, Voice support

## Call recording boundary
The V9434 browser UI stores call context and recording-consent state, then opens the device dialer. A normal `tel:` dialer cannot expose or record both sides of the call from a browser/PWA. Actual call-audio recording therefore requires the planned in-app WebRTC/VoIP/telephony layer; V9434 does not falsely mark dialer audio as recorded.
