# TEST61 — REDZED Group + Market Workspace final architecture

Status: TEST foundation only. MAIN G must remain untouched until runtime PASS.

## Locked identity/UI rules
1. One customer relationship = one REDZED group/data source, not duplicate chat systems.
2. Common group heading: `REDZED` + `[CUSTOMER NAME] GROUP`; same group profile identity on both sides.
3. Staff messages remain LEFT; customer messages remain RIGHT for both viewers.
4. Normal staff login lands on customer/group list. Push deep-link may open the exact group directly.
5. Customer/group list is membership-driven, never hardcoded; avatar, name, last-message preview/time and unread badge are presentation fields.

## Market workspace / recursive seller rule
A person can be CUSTOMER in one relationship and SELLER/OWNER in another. Permissions are relationship/workspace based, not a single fixed human role.
Example: REDZED -> Hitesh (Hitesh is customer); Hitesh -> Shyam (Hitesh is seller, Shyam is customer).
Seller workspace reuses the REDZED staff/seller interface; downstream customer reuses the REDZED customer interface. No forked fake UI/data system.

## Super Admin controls
Server-authoritative controls per STAFF or CUSTOMER:
- menu_enabled
- seller_workspace_enabled
- customer_groups_enabled
- send_collection_enabled
- receive_requirement_enabled
- forward_requirement_enabled
- pi_convert_enabled
- ci_convert_enabled
Frontend hiding alone is not authorization.

## Collection / Requirement identity
Collection and its Requirement carry the SAME originating business reference. Requirement creation must not allocate a new reference.
Each seller/owner has its own independent sequence and prefix, e.g. REDZED `RZ-412`, Hitesh `HT-5`.
If Hitesh sends HT-5 upstream to REDZED, origin remains HT-5. REDZED sees Hitesh as its counterparty; Hitesh's downstream customer identity remains private.
Database UUIDs remain canonical relational keys; human reference is immutable business identity, not the database primary key.

## Privacy boundary
REDZED must not receive downstream customer name/mobile/address/private chat merely because an upstream Requirement is forwarded. Upstream receives only the permitted order/business payload and originating seller reference. Private downstream mapping stays in originating seller scope.

## PI / CI conversion direction
A forwarded Requirement retains its origin reference through upstream PI/CI. The originating seller can later convert permitted upstream PI/CI data into its downstream customer document without re-keying quantities/items, while its own commercial fields remain seller-controlled.

## Preservation
Do not alter MAIN G stable media/thumbnail/delete files as part of this foundation. Existing Collection/Requirement/PI lifecycle remains authoritative until each new versioned TEST61 RPC is separately implemented and runtime verified. No destructive rewrite of current customer flow.