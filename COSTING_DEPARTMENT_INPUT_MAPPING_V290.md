# V290 Costing Department Input Mapping
Canonical separation for Printing / Sticker / Metal ID:
1. Process Actual Rate / PCS -> rr_upm_set_department_rate_v760.
2. Material/Input cost -> rr_upm_save_cost_input_v9300.
These engines must never duplicate each other.

Context RPC: rr_costing_department_input_context_v290.
PRINTING material type: PRINT_CHEMICAL.
STICKER material type: STICKER_ROLL (existing KG->MTR conversion remains in V9300).
METAL_ID: no invented material input; process Actual Rate only until a real mapped material rule exists.

Permission: Department Head may edit own department rate through existing V760 scope; ordinary worker submit does not grant rate-edit permission. Admin/Manager retain rate authority. Sensitive owner costing remains separate.

Submit gate concerns Actual Process Rate only. Missing future material source uses V289 dash semantics and must not fabricate a cost or block submit merely because no source value exists.
