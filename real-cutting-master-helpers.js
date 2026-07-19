// ===== REDZED CUTTING MASTER PM — HELPER FUNCTIONS =====

/**
 * Global state for active unit/card
 */
let activeUnit = null;

/**
 * Get unit ID from active unit
 */
function unitId(unit) {
  if (!unit) return null;
  return (
    unit.id ||
    unit.division_id ||
    unit.cb_unit_id ||
    unit.unit_id ||
    null
  );
}

/**
 * Get purchase ID from active unit
 */
function unitPurchaseId(unit) {
  if (!unit) return null;
  return (
    unit.cb_id ||
    unit.purchase_id ||
    unit.parent_cb_id ||
    unit.fabric_purchase_id ||
    null
  );
}

/**
 * Get lot decision for active unit
 */
function lotDecisionForActiveUnit() {
  if (!activeUnit) {
    throw new Error("No active unit selected");
  }

  if (typeof activeCard === "undefined" || !activeCard) {
    return null;
  }

  const decision = cardDecision(activeCard);
  
  return decision;
}

/**
 * Get art number from art object
 */
function artNumber(art) {
  if (!art) return "";
  
  return (
    art.art_no ||
    art.art_code ||
    art.code ||
    ""
  );
}

/**
 * Get print number from print object
 */
function printNumber(print) {
  if (!print) return "";
  
  return (
    print.print_no ||
    print.print_code ||
    print.code ||
    ""
  );
}

/**
 * Get adjustment details for cost calculation
 */
function adjustmentDetails() {
  return [];
}

/**
 * Set active unit when a card is clicked
 */
function setActiveUnit(unit) {
  activeUnit = unit;
  console.info("Active unit set:", unit);
}

/**
 * Get current active unit
 */
function getActiveUnit() {
  return activeUnit;
}

/**
 * Clear active unit
 */
function clearActiveUnit() {
  activeUnit = null;
}

/**
 * Make these functions global
 */
window.unitId = unitId;
window.unitPurchaseId = unitPurchaseId;
window.lotDecisionForActiveUnit = lotDecisionForActiveUnit;
window.artNumber = artNumber;
window.printNumber = printNumber;
window.adjustmentDetails = adjustmentDetails;
window.setActiveUnit = setActiveUnit;
window.getActiveUnit = getActiveUnit;
window.clearActiveUnit = clearActiveUnit;
