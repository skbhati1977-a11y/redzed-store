REAL FACTORY FRONTEND SYNC V853
================================

PURPOSE
This package synchronizes the frontend once against the latest backend work found in the recent build chain, while preserving stable database object names and stable working modules.

IMPORTANT DEPLOYMENT RULES
1. KEEP your existing canonical config.js and real-common.js. They are intentionally NOT included.
2. Upload HTML + matching JS together.
3. TEST remains default. Do not switch the system default to REAL until explicit go-live approval.
4. Do not upload old placeholder config files over the canonical config.
5. Cloud API WhatsApp send is NOT used by the new communication page. It uses the same wa.me prefilled-message opener pattern that already worked in the Damage module.
6. Despatch remains a separate module/flow inside Finished Goods; do not merge unrelated Despatch logic into Production modules.

FILES / BACKEND MAP
- real-dashboard-v853.html/js
  Central entry point for all synchronized modules.

- real-upm-v853.html/js
  Existing UPM home kept as the stable production shell.

- real-finished-goods-v853.html/js
  Canonical V787/V788 flow retained:
  Ready Packing -> Assign -> Accept -> Generate Pack -> Submit Packing
  -> Despatch -> Store Receive -> Webstore Stock -> PI/CPI -> Return.
  Uses rr_fg_* V787/V788 contracts and V805.2 material box/auto-consumption calls.

- real-production-due-v853.html/js
  V837/V838/V839 read frontend:
  rr_cut_qty_source_audit_v839
  rr_print_due_activation_v839
  rr_sticker_due_activation_v839
  rr_metal_id_due_activation_v839

- real-lot-media-v853.html/js
  V808:
  rr_lot_media_v808
  rr_lot_media_events_v808
  rr_lot_media_notifications_v808

- real-material-master-v853.html/js
  Existing latest V805.2-compatible Material frontend retained.

- real-accounts-v853.html/js
  Existing latest Accounts frontend retained; backend V847 auto-voucher rules remain backend-owned.

- real-commerce-v853.html/js
  V849 universal manufactured + traded lot visibility:
  rr_sale_universal_lot_search_v849
  rr_universal_sale_lot_v849
  rr_live_commercial_binding_v849
  rr_rm_stock_v849_2c6

- real-costing-v853.html/js
  V850:
  rr_cost_fixed_rule_v850
  rr_cost_expense_pool_v850
  rr_cost_rule_effective_v850
  rr_cost_test_result_v850

- real-reports-v853.html/js
  V807:
  rr_report_search_bridge_v807
  rr_report_bootstrap_v807

- real-communications-v853.html/js
  V853 outbox + WA-LINK:
  rr_comm_outbox_v853
  rr_comm_delivery_log_v853
  rr_comm_mark_whatsapp_opened_v853
  No Meta Cloud API /messages call.

- real-security-v853.html/js
  Backend-first build visibility:
  rr_system_migration_registry_v1
  rr_system_rulebook_v1
  rr_user_profiles

SHARED
- rf-v853.css
- rf-v853-core.js

NOT RECREATED
Stable modules that did not need a new backend-only frontend are not rewritten just to change a version number. This avoids breaking already-working payroll/attendance/product/cutting logic. They should remain available from the main deployment alongside this sync package.

FIRST OPEN
real-dashboard-v853.html
