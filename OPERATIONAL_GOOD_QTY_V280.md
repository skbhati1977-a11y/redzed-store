# V280 Operational Good Quantity
Applied operational_good_qty_v280.
Canonical rule: assigned_qty is historical assignment quantity; operational worker card quantity is resolved Good Qty.
rr_upm_assignment_operational_qty_v280 returns Good / Found / Confirmed Short / Recovery Pending and resolves a fully classified receipt dispute operationally to RESOLVED without deleting dispute history.
rr_upm_worker_operational_work_v280 exposes canonical worker IDs and operational quantities for App/Frontend/Real Chat.
Verified Lot 2622 Stitching:
Good 22, Found 1, Confirmed Short 1, Short/Excess Accept 1, Receipt RESOLVED.
Main card actions: SUBMIT / ALTER / RECTIFY on Good Qty.
