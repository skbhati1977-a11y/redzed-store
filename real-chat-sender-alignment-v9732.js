(() => {
  "use strict";
  if (window.__RR_CHAT_SENDER_ALIGNMENT_V9732__) return;
  window.__RR_CHAT_SENDER_ALIGNMENT_V9732__ = true;

  const REQUIREMENT_RX = /\[REQ:[0-9a-f-]{36}\]/i;

  function isRequirement(message) {
    const payload = message?.payload || {};
    return String(message?.message_type || "").toUpperCase() === "REQUIREMENT"
      || String(payload.source || "").toUpperCase().includes("REQUIREMENT")
      || REQUIREMENT_RX.test(String(message?.body || ""));
  }

  function normalize(message) {
    if (!message || !isRequirement(message)) return message;
    const payload = message.payload || {};
    // Partner adapters know the exact local actor. Preserve that authoritative
    // decision; it covers distributor -> REDZED and customer -> distributor.
    if (typeof payload.__rr_is_mine === "boolean") return message;

    // This script runs in the REDZED staff chat. A requirement is authored by
    // the opposite customer/distributor, even when a legacy upsert retained an
    // old staff sender_name. Normalize display + alignment without rewriting DB.
    const oppositeParty = String(
      payload.customer_name
      || document.getElementById("chatTitle")?.textContent
      || "CUSTOMER / DISTRIBUTOR",
    ).trim();
    return {
      ...message,
      sender_name: oppositeParty || "CUSTOMER / DISTRIBUTOR",
      payload: { ...payload, __rr_is_mine: false },
    };
  }

  function hook() {
    if (!window.RF853?.rpc || RF853.rpc.__rrSenderAlignment9732) return;
    const original = RF853.rpc.bind(RF853);
    const wrapped = async (name, args = {}) => {
      const result = await original(name, args);
      if ((name === "rr_chat_staff_messages_v9434" || name === "rr_chat_staff_messages_v9479") && Array.isArray(result)) {
        return result.map(normalize);
      }
      return result;
    };
    wrapped.__rrSenderAlignment9732 = true;
    RF853.rpc = wrapped;
  }

  hook();
})();
