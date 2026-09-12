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
      const isMessageList = name === "rr_chat_staff_messages_v9434" || name === "rr_chat_staff_messages_v9479";
      let requestArgs = args;
      let result = await original(name, requestArgs);
      if (isMessageList) {
        // A previous chat request can finish after another inbox row has been
        // opened. Never let that late response paint inside the new territory.
        // Re-fetch against the currently active chat; cap retries so rapid taps
        // cannot create an unbounded request chain.
        for (let retry = 0; retry < 2; retry += 1) {
          const activeChatId = String(window.__RR_CURRENT_CHAT_ID__ || "");
          const requestedChatId = String(requestArgs?.p_chat_id || "");
          if (!activeChatId || activeChatId === requestedChatId) break;
          requestArgs = { ...requestArgs, p_chat_id: activeChatId };
          result = await original(name, requestArgs);
        }
        const finalActiveId = String(window.__RR_CURRENT_CHAT_ID__ || "");
        if (finalActiveId && finalActiveId !== String(requestArgs?.p_chat_id || "")) return [];
        if (Array.isArray(result)) return result.map(normalize);
      }
      return result;
    };
    wrapped.__rrSenderAlignment9732 = true;
    RF853.rpc = wrapped;
  }

  hook();
})();
