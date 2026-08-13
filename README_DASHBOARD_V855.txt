REAL FACTORY DASHBOARD LATEST V855
=================================

PURPOSE
Merged canonical main dashboard + latest frontend sync from the recent backend build chain.

WHAT CHANGED
- Keeps the complete main dashboard structure: Product, Cutting, Production, Finished Goods, Accounts, Payroll, Control.
- Routes latest Production/Open Queue to real-upm-v853.html.
- Routes Packing, Despatch, Store, Stock, Sales, Verify and Returns to real-finished-goods-v853.html views.
- Adds Mapped Print/Sticker/Metal ID Due (V839).
- Adds Lot Media + AI Approval (V808).
- Adds Universal Sales/ReadyMade (V849).
- Adds Master Costing (V850).
- Adds Reports + AI Search (V807).
- Adds Communication / WhatsApp (V853).
- Adds Access / Backend Health.
- Keeps Despatch separate from Production.
- Preserves stable Product/Cutting/Payroll/Attendance/Roles/Data Mode module links.
- TEST remains default; REAL remains protected.
- Existing canonical config.js and real-common.js MUST remain in GitHub root. They are not included.

UPLOAD
Upload ALL files from this package to the same GitHub Pages root.
Do NOT delete older stable module files because the merged dashboard still links to them.
Do NOT overwrite config.js or real-common.js.

FIRST OPEN
real-dashboard.html


WHATSAPP FINAL V855
- Outbox rows now have direct OPEN WHATSAPP buttons.
- Queued open reserves a browser tab immediately to avoid async popup blocking.
- Exact recipient + prefilled message open through wa.me.
- No auto-send; user presses Send in WhatsApp.
- Open action is marked through rr_comm_mark_whatsapp_opened_v853.
- Communication Dashboard link returns to real-dashboard.html.
