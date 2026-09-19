# V289 Future-Effective Costing Components
TEST71 costing rule.
Universal display/impact contract:
- Dash (—): no source/value existed for that lot; no costing impact.
- Zero (0): mapping/value exists but component is not applicable/consumed for that lot.
- Actual: source exists and component applies; calculated actual cost is used.
Rules are effective-from and future-only. A component introduced later must not retrospectively change legacy lot costing.
Initial future-ready component rules: BOX, GATTA_PANNI, PRINT_CHEMICAL, OVERHEAD.
Canonical helper: rr_costing_component_value_v289.
Legacy presentation: “— · Future-ready; no legacy impact”.
Future source missing presentation: “— · Ready when mapped”.
