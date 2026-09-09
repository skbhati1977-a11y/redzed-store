(() => {
  "use strict";
  if (window.RRMarketLifecycle?.version >= 9730) return;

  const upper = (value) => String(value || "").trim().toUpperCase();
  const terminal = new Set(["CI_FINAL", "FINAL", "CLOSED"]);

  function state(record = {}) {
    const status = upper(record.piStatus || record.pi_status || record.lifecycle_stage || record.status);
    const piRef = record.piRef || record.pi_ref || record.piNo || record.pi_no || record.distributor_pi_ref || record.pi || "";
    const ciRef = record.ciRef || record.ci_ref || record.ciNo || record.ci_no || record.customer_ci_ref || "";
    const ciFinal = Boolean(ciRef) || terminal.has(status) || upper(record.kind) === "CI";
    const hasPi = !ciFinal && (Boolean(piRef) || status === "PI_GENERATED" || status === "PI_PROPOSED" || status === "WAITING_CONFIRMATION" || status === "CONFIRMED" || status === "PARTIAL_CONFIRMED");
    return {
      status: ciFinal ? "CI_FINAL" : hasPi ? "PI_GENERATED" : status || "REQUIREMENT_RECEIVED",
      hasPi,
      ciFinal,
      piEditable: hasPi && !ciFinal,
      canPreparePi: !ciFinal
    };
  }

  window.RRMarketLifecycle = Object.freeze({ version: 9730, state });
})();
