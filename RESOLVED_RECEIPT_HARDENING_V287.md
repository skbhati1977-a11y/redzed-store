# V287 Resolved Receipt Hardening
Raw assignment receipt status now supports RESOLVED.
Universal rule: when a disputed mismatch is fully classified (unresolved_short_qty=0 and Found/Confirmed Short accounts for it), current receipt status becomes RESOLVED. Original DISPUTED state is preserved in rr_upm_receipt_resolution_audit_v287.
Verified Lot 2622:
C1 raw receipt RESOLVED; Good 22, Found 1, Confirmed Short 1, Recovery Pending 1, Unresolved 0.
C2/C6 remain independent PENDING fresh 24-piece assignments with no missing/recovery row.
This prevents legacy raw-receipt readers from resurrecting a resolved dispute.
