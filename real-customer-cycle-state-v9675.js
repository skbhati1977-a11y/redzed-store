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
    // Collection mode hides chat. Closing a completed collection must restore
    // both messages and composer, rather than leave an invisible chat behind.
    document.querySelectorAll('#rrFSChat .fc-hide').forEach(node => node.classList.remove('fc-hide'));
    document.querySelector('#rrFSChat .fscompWrap')?.classList.remove('rrReqMode9634');
    if ($("fsCollectionCard")) $("fsCollectionCard").style.display = "block";
    if ($("rrCommercialActions9630")) $("rrCommercialActions9630").style.display = "none";
    const button=$("fcOpen")||$("fcReopen");
    if(button){button.disabled=false;button.textContent=`${state?.collection_display_no||"COLLECTION"} · U${Number(state?.collection_update_no||0)} · CLOSED · VIEW ONLY`;}
    document.body.classList.add("rrCustomerRequirementClosed58");
    document.dispatchEvent(new CustomEvent("rr:v9675-cycle-closed", { detail: state }));
  }
  function paint(state, sent) {
    last = { state, sent };
    if (!state) return;
    if (terminal(state.collection_status)) return closeActiveUi(state);
    document.body.classList.remove("rrCustomerRequirementClosed58");
    const card = $("fsCollectionCard"), actions = $("rrCommercialActions9630");
    if (card) card.style.display = "block";
    if (actions) actions.style.display = "grid";
    const display = state.collection_display_no || "COLLECTION";
    const collectionButton = $("fcOpen") || $("fcReopen"), send = $("rrSendReq9630"), close = $("rrCloseReq9630");
    if (sent) {
      if (collectionButton) { collectionButton.disabled = false; collectionButton.textContent = `UPDATE ${display} · U${Number(state.collection_update_no||0)} · VIEW COLLECTION`; }
      if (send) { send.disabled = true; send.textContent = "REQUIREMENT SENT ✓"; }
      if (close) { close.disabled = false; close.textContent = "CLOSE REQUIREMENT"; }
    } else {
      if (collectionButton) {collectionButton.disabled = false;collectionButton.textContent=`UPDATE ${display} · U${Number(state.collection_update_no||0)}`;}
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
      paint(state, hasRequirement(summary) && Number(state.collection_update_no||0) <= Number(state.requirement_response_collection_update_no ?? -1));
    } catch (error) { console.warn("V9675 cycle state unavailable", error); }
  }
  function bind() {
    document.addEventListener("rr:v71-cycle-state", ({detail:state}) => {
      const response=Number(state?.requirement_response_collection_update_no ?? -1);
      paint(state,response>=0 && response>=Number(state?.collection_update_no||0));
    });
    document.addEventListener("rr:v9605-requirement-sent", () => setTimeout(refresh, 120));
    document.addEventListener("rr:v9630-customer-closed", () => closeActiveUi({...last?.state,collection_status:"CLOSED"}));
    document.addEventListener("click", (event) => {
      if (event.target.closest?.("#fcOpen,#fcReopen") && terminal(last?.state?.collection_status)) {event.preventDefault();event.stopImmediatePropagation();window.RRCustomerCollectionViewer71?.open(last.state);return;}
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
