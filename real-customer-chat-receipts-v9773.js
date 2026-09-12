(() => {
  "use strict";
  if (window.__RR_CUSTOMER_CHAT_RECEIPTS_V9773__) return;
  window.__RR_CUSTOMER_CHAT_RECEIPTS_V9773__ = true;
  let busy = false;

  async function acknowledge() {
    if (busy || !window.RF853?.rpc || !window.RR_CUSTOMER_SECURE_SESSION_V9592) return;
    let session;
    try {
      session = JSON.parse(localStorage.getItem("rr_customer_secure_session_v9592") || "null");
    } catch (_) {
      return;
    }
    if (!session?.session_token) return;
    busy = true;
    try {
      const chatOpen = document.getElementById("rrFSChat")?.classList.contains("on");
      await RF853.rpc("rr_chat_customer_ack_session_v9773", {
        p_session_token: session.session_token,
        p_device_id: RR_CUSTOMER_SECURE_SESSION_V9592.device(),
        p_mark_read: Boolean(chatOpen && document.visibilityState === "visible"),
      });
    } catch (_) {
      // Session refresh/expiry is handled by the existing secure-session layer.
    } finally {
      busy = false;
    }
  }

  document.addEventListener("rr:customer-secure-session-ready", acknowledge);
  document.addEventListener("visibilitychange", acknowledge);
  setInterval(acknowledge, 2500);
  setTimeout(acknowledge, 300);
})();
