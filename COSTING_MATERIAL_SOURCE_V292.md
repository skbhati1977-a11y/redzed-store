# V292 Canonical Material Source Resolver
Single priority per material component:
1. Lot-specific V9300 Actual input.
2. V261/V9083 weighted fallback only when no V9300 actual exists.
3. V289 future-effective Dash/Zero semantics when neither source supplies a cost.
Actual and weighted values are never additive for the same component.
Resolver RPCs:
- rr_costing_material_source_v292
- rr_costing_materials_resolved_v292
Current mapped components: Printing Chemical, Sticker Roll/Material, Gatta/Panni Packing Misc.
Process Actual Rate remains separate in V760 and is not a material source.
