(() => {
  "use strict";
  if (window.__RR_CHAT_BOUNDARY_STABILITY_V9728__) return;
  window.__RR_CHAT_BOUNDARY_STABILITY_V9728__ = true;

  function protectMessageDom() {
    const box = document.getElementById("msgs");
    if (!box || box.__rrStableHtml9728) return false;
    const descriptor = Object.getOwnPropertyDescriptor(Element.prototype, "innerHTML");
    if (!descriptor?.get || !descriptor?.set) return false;
    let lastRaw = null;
    Object.defineProperty(box, "innerHTML", {
      configurable: true,
      enumerable: false,
      get() { return descriptor.get.call(this); },
      set(value) {
        const raw = String(value ?? "");
        if (raw === lastRaw) return;
        lastRaw = raw;
        descriptor.set.call(this, raw);
      }
    });
    box.__rrStableHtml9728 = true;
    window.addEventListener("rr:chat-selected", () => { lastRaw = null; });
    return true;
  }

  function protectRpc() {
    if (!window.RF853?.rpc || RF853.rpc.__rrBoundary9728) return false;
    const original = RF853.rpc.bind(RF853);
    const wrapped = async (name, args = {}) => {
      const isTimeline = name === "rr_chat_staff_messages_v9434" || name === "rr_chat_staff_messages_v9479";
      if (!isTimeline) return original(name, args);
      const requestedChat = String(args?.p_chat_id || "");
      const requestedChannel = String(args?.p_channel || "GROUP");
      const result = await original(name, args);
      const activeChat = String(window.__RR_CURRENT_CHAT_ID__ || "");
      if (!requestedChat || !activeChat || requestedChat === activeChat) return result;
      return original(name, { ...args, p_chat_id: activeChat, p_channel: requestedChannel });
    };
    // Preserve marker flags used by reply/media adapters so wrappers do not
    // repeatedly wrap each other during their startup retry windows.
    Object.assign(wrapped, RF853.rpc);
    wrapped.__rrBoundary9728 = true;
    wrapped.__rrBoundaryBase = original;
    RF853.rpc = wrapped;
    return true;
  }

  function trackSelection() {
    document.addEventListener("click", (event) => {
      const row = event.target.closest?.("#inboxRows .chatrow[data-chat]");
      if (!row) return;
      window.__RR_CURRENT_CHAT_ID__ = row.dataset.chat || "";
      document.dispatchEvent(new CustomEvent("rr:chat-selected", {
        detail: { chat_id: window.__RR_CURRENT_CHAT_ID__ }
      }));
    }, true);
  }

  function boot() {
    protectMessageDom();
    protectRpc();
    trackSelection();
    let tries = 0;
    const timer = setInterval(() => {
      protectMessageDom();
      protectRpc();
      if (++tries > 40) clearInterval(timer);
    }, 250);
  }

  document.readyState === "loading"
    ? document.addEventListener("DOMContentLoaded", boot, { once: true })
    : boot();
})();
