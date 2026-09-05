(() => {
  "use strict";
  if (window.__RR_PARTNER_COLLECTION_CORE_ADAPTER_V80__) return;
  window.__RR_PARTNER_COLLECTION_CORE_ADAPTER_V80__ = true;

  const directRpc = RF853.rpc.bind(RF853);
  const readMap = {
    rr_collection_current_state_v9633:
      "rr_market_partner_customer_current_state_v80",
    rr_collection_customer_pricing_v9637:
      "rr_market_partner_customer_pricing_v80",
    rr_collection_customer_requirement_summary_v9637:
      "rr_market_partner_customer_requirement_summary_v80",
    rr_collection_customer_ci_history_v9641:
      "rr_market_partner_customer_ci_history_v80",
    rr_collection_more_samples_request_v9630:
      "rr_market_partner_customer_more_samples_v80",
  };

  async function mappedRpc(name, args = {}) {
    if (name === "rr_collection_submit_requirement_v9588") {
      const result = await directRpc("rr_market_partner_submit_requirement_v67", {
        p_token: args.p_token,
        p_customer_name: null,
        p_mobile: null,
        p_message: args.p_message || null,
        p_lines: args.p_lines || [],
      });
      const session = await window.RR_CHAT_RELATION_ADAPTER_V67?.ctx?.();
      if (session?.t && result?.order_id) {
        try {
          await directRpc("rr_market_partner_requirement_chat_upsert_v82", {
            p_session_token: session.t,
            p_device_id: session.d,
            p_order_id: result.order_id,
            p_body: `[REQ:${result.order_id}] ${result.requirement_display_no || "REQUIREMENT"} · linked ${result.collection_display_no || "collection"}`,
          });
        } catch (error) {
          // The requirement is already committed. A temporary chat projection
          // failure must not invite the customer to submit the same order twice.
          console.warn("partner requirement chat projection failed", error);
        }
      }
      return result;
    }

    if (name === "rr_collection_customer_close_v9630") {
      return directRpc("rr_market_partner_customer_requirement_close_v67", {
        p_token: args.p_token,
      });
    }

    if (readMap[name]) return directRpc(readMap[name], args);
    return directRpc(name, args);
  }

  RF853.rpc = mappedRpc;
  window.RR_PARTNER_COLLECTION_CORE_ADAPTER_V80 = {
    relation: "DISTRIBUTOR_CUSTOMER",
    rpc: mappedRpc,
  };
})();
