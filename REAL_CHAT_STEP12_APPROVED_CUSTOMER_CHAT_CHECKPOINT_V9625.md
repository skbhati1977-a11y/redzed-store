# REAL CHAT — STEP 12 APPROVED CUSTOMER CHAT CHECKPOINT V9625

Status: APPROVED ISOLATED CUSTOMER FLOW CHECKPOINT
Date: 2026-08-31

## Approved customer-facing flow
REDZED COLLECTION → GROUP / SUPER ADMIN → Real Chat timeline → VIEW / UPDATE COLLECTION inside chat → SEND REQUIREMENT → remain inside the same Real Chat.

## Approved UI
- compact single customer header: REDZED COLLECTION
- Z rendered red by the approved header addon
- GROUP and SUPER ADMIN tabs directly below header
- no REAL FACTORY MAIN MENU / internal hamburger on customer face
- collection opens in-chat, not as the old standalone market-share page
- wider main product image with squeezed right-side information panel
- bold information values/labels for visibility
- compact BACK TO CHAT and SEND REQUIREMENT actions
- customer stock privacy remains IN STOCK rather than numeric available pieces

## Universal collection field mapping
Backend migration: `real_chat_universal_lot_field_resolver_v9624`.
Resolver: `rr_web_lot_fields_resolve_v9624`.
Existing `rr_market_share_view_v9420` now overlays universally resolved lot fields for every share/customer rather than customer-specific hardcoding.

Mapped fields:
- Cloth Name → web lot profile → ERP/fabric master fallback
- GSM → web lot profile → UPM costing input → fabric master fallback
- Size → web profile → FG product → cutting lot size set → art/ERP fallback
- Category → web profile → art/category master → ERP fallback
- Item Name → web profile → art/product/style/ERP/FG fallback

Rule: if the mapped source field exists but its value is NULL/blank/empty, customer display must show `-`. Do not substitute Lot No. or an unrelated field.

Frontend placeholder addon: `real-customer-chat-field-placeholder-v9625.js`.

## Current isolated test page
`real-customer-step11-chat-first-v9622.html`
Expected query version: `v=9625`.

## Frozen behavior
Do not change the approved customer header, chat-first routing, GROUP/SUPER ADMIN tab arrangement, in-chat collection presentation, stock privacy, image/info proportions, or universal blank-field rule while moving to the next controlled integration step.

## Next controlled step
Integrate this approved isolated customer flow into the actual customer entry/share route with the smallest possible routing change, while keeping staff/internal Real Chat unchanged and preserving the existing secure-session gate.
