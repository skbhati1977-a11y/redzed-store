(() => {
  "use strict";
  if (window.__RR_CUSTOMER_CYCLE_STATE_V9675__) return;
  window.__RR_CUSTOMER_CYCLE_STATE_V9675__ = true;
  const query = new URLSearchParams(location.search);
  const token = query.get("t") || query.get("c") || "";
  const $ = (id) => document.getElementById(id);
  const terminal = (status) => ["PI_GENERATED", "CI_GENERATED", "CLOSED", "CLOSED_NO_RESPONSE", "CANCELLED"].includes(String(status || "").toUpperCase());
  let last = null;
  const hasRequirement = (summary) => (summary?.lines || []).some((line) => Number(line.requested_qty || 0) > 0);
  function closeActiveUi(state) {
    $("fcPanel")?.classList.remove("on");
    if ($("fsCollectionCard")) $("fsCollectionCard").style.display = "none";
    if ($("rrCommercialActions9630")) $("rrCommercialActions9630").style.display = "none";
    document.body.classList.add("rrCustomerRequirementClosed58");
    document.dispatchEvent(new CustomEvent("rr:v9675-cycle-closed", { detail: state }));
  }
  function paint(state, sent) {
    last = { state, sent };
    if (!state || terminal(state.collection_status)) return closeActiveUi(state);
    document.body.classList.remove("rrCustomerRequirementClosed58");
    const card = $("fsCollectionCard"), actions = $("rrCommercialActions9630");
    if (card) card.style.display = "block";
    if (actions) actions.style.display = "grid";
    const display = state.collection_display_no || "COLLECTION";
    const collectionButton = $("fcOpen") || $("fcReopen"), send = $("rrSendReq9630"), close = $("rrCloseReq9630");
    if (sent) {
      if (collectionButton) { collectionButton.disabled = true; collectionButton.textContent = `${display} · REQUIREMENT SENT ✓`; }
      if (send) { send.disabled = true; send.textContent = "REQUIREMENT SENT ✓"; }
      if (close) { close.disabled = false; close.textContent = "CLOSE REQUIREMENT"; }
    } else {
      if (collectionButton) collectionButton.disabled = false;
      if (send) { send.disabled = false; send.textContent = "SEND REQUIREMENT"; }
      if (close) { close.disabled = true; close.textContent = "SEND REQUIREMENT FIRST"; }
    }
  }
  async function refresh() {
    try {
      const [state, summary] = await Promise.all([
        RF853.rpc("rr_collection_current_state_v9633", { p_token: token }),
        RF853.rpc("rr_collection_customer_requirement_summary_v9637", { p_token: token }),
      ]);
      paint(state, hasRequirement(summary));
    } catch (error) { console.warn("V9675 cycle state unavailable", error); }
  }
  function bind() {
    document.addEventListener("rr:v9605-requirement-sent", () => setTimeout(refresh, 120));
    document.addEventListener("rr:v9630-customer-closed", () => closeActiveUi(last?.state));
    document.addEventListener("click", (event) => {
      if (event.target.closest?.("#rrSendReq9630") && last?.sent) { event.preventDefault(); event.stopImmediatePropagation(); }
    }, true);
    let tries = 0;
    const timer = setInterval(() => {
      if ($("rrCommercialActions9630") && $("fsCollectionCard")) { clearInterval(timer); refresh(); }
      else if (++tries > 60) clearInterval(timer);
    }, 120);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bind, { once: true }); else bind();
})();
