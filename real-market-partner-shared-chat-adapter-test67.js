(() => {
  "use strict";
  if (window.__RR_PARTNER_SHARED_CHAT_ADAPTER_V67__) return;
  window.__RR_PARTNER_SHARED_CHAT_ADAPTER_V67__ = true;
  // This TEST67 adapter supplies the same session contract as the direct
  // customer module. Prevent the production session loader from replacing it
  // with a REDZED-direct relation after the base page is mounted.
  window.__RR_CUSTOMER_SECURE_SESSION_V9592__ = true;

  const query = new URLSearchParams(location.search);
  const token = query.get("t") || query.get("c") || "";
  const keyTail = token.slice(-18).replace(/[^a-z0-9]/gi, "") || "unknown";
  const sessionKey = `rr_partner_customer_session_v67_${keyTail}`;
  const deviceKey = "rr_partner_customer_device_v67";
  let trusted = null;
  const rawRpc = RF853.rpc.bind(RF853);

  function device() {
    let id = localStorage.getItem(deviceKey);
    if (!id) {
      const bytes = new Uint8Array(24);
      crypto.getRandomValues(bytes);
      id = [...bytes].map((x) => x.toString(16).padStart(2, "0")).join("");
      localStorage.setItem(deviceKey, id);
    }
    return id;
  }

  function saved() {
    try {
      return JSON.parse(localStorage.getItem(sessionKey) || "null");
    } catch (_) {
      return null;
    }
  }

  async function call(name, args = {}) {
    return rawRpc(name, args);
  }

  function syncDirectCoreSession(sessionToken) {
    localStorage.setItem(
      "rr_customer_secure_session_v9592",
      JSON.stringify({
        session_token: sessionToken,
        relation: "DISTRIBUTOR_CUSTOMER",
        issued_at: new Date().toISOString(),
      }),
    );
    if (trusted?.customer_name)
      localStorage.setItem(
        "rr_market_customer_identity_v9423",
        JSON.stringify({ name: trusted.customer_name, mobile: "PRIVATE" }),
      );
  }

  async function validate(sessionToken) {
    return call("rr_market_partner_customer_session_validate_v67", {
      p_session_token: sessionToken,
      p_device_id: device(),
    });
  }

  async function ensure() {
    const old = saved();
    if (old?.session_token) {
      try {
        trusted = await validate(old.session_token);
        window.RR_PARTNER_CUSTOMER_TRUSTED_SESSION_V67 = trusted;
        syncDirectCoreSession(old.session_token);
        return trusted;
      } catch (_) {
        localStorage.removeItem(sessionKey);
      }
    }
    if (!token) throw Error("Distributor customer collection token missing.");
    const issued = await call("rr_market_partner_customer_session_issue_v67", {
      p_token: token,
      p_device_id: device(),
    });
    localStorage.setItem(
      sessionKey,
      JSON.stringify({
        session_token: issued.session_token,
        issued_at: new Date().toISOString(),
      }),
    );
    trusted = await validate(issued.session_token);
    window.RR_PARTNER_CUSTOMER_TRUSTED_SESSION_V67 = trusted;
    syncDirectCoreSession(issued.session_token);
    return trusted;
  }

  async function ctx() {
    await ensure();
    const session = saved();
    if (!session?.session_token)
      throw Error("Secure distributor chat session missing.");
    return { t: session.session_token, d: device() };
  }

  const rpcMap = {
    rr_chat_customer_messages_session_v9593:
      "rr_market_partner_customer_chat_messages_session_v67",
    rr_chat_customer_send_session_v9593:
      "rr_market_partner_customer_chat_send_session_v67",
    rr_chat_customer_upload_session_v9646:
      "rr_market_partner_customer_chat_upload_session_v67",
    rr_chat_customer_upload_session_v54:
      "rr_market_partner_customer_chat_upload_session_v67",
    rr_chat_customer_attachment_session_v9646:
      "rr_market_partner_customer_chat_attachment_session_v67",
    rr_chat_customer_image_thumbnail_session_v49:
      "rr_market_partner_customer_chat_attachment_session_v67",
    rr_chat_customer_image_thumbnail_session_v9647:
      "rr_market_partner_customer_chat_attachment_session_v67",
    rr_chat_customer_image_thumbnails_session_v48:
      "rr_market_partner_customer_chat_thumbnail_batch_session_v67",
    rr_chat_customer_delete_message_session_v59:
      "rr_market_partner_customer_chat_delete_message_session_v67",
    rr_chat_customer_disappearing_get_session_v59:
      "rr_market_partner_customer_chat_disappearing_get_session_v67",
    rr_chat_customer_disappearing_set_session_v59:
      "rr_market_partner_customer_chat_disappearing_set_session_v67",
    rr_chat_customer_disappearing_cleanup_session_v59:
      "rr_mp_customer_chat_disappear_cleanup_v67",
    rr_chat_customer_media_files_session_v59:
      "rr_market_partner_customer_chat_media_files_session_v67",
    rr_chat_customer_resend_attachments_session_v59:
      "rr_market_partner_customer_chat_resend_session_v67",
    rr_chat_customer_thumbnail_get_session_v51:
      "rr_market_partner_customer_chat_thumbnail_get_session_v67",
    rr_chat_customer_thumbnail_put_session_v51:
      "rr_market_partner_customer_chat_thumbnail_put_session_v67",
    rr_chat_customer_thumbnail_batch_session_v51:
      "rr_market_partner_customer_chat_thumbnail_batch_session_v67",
    rr_chat_customer_thumbnail_policy_session_v52:
      "rr_market_partner_customer_chat_thumbnail_policy_session_v67",
  };

  async function rpc(name, args = {}) {
    const clean = { ...args };
    const thumbBase64 =
      name === "rr_chat_customer_upload_session_v54"
        ? clean.p_thumb_base64
        : null;
    if (name === "rr_chat_customer_upload_session_v54")
      delete clean.p_thumb_base64;
    const out = await call(rpcMap[name] || name, clean);
    if (thumbBase64 && out?.attachment_id) {
      await call("rr_market_partner_customer_chat_thumbnail_put_session_v67", {
        p_session_token: clean.p_session_token,
        p_device_id: clean.p_device_id,
        p_attachment_id: out.attachment_id,
        p_mime_type: "image/jpeg",
        p_base64: thumbBase64,
      });
    }
    return out;
  }

  function identity() {
    const session =
      trusted || window.RR_PARTNER_CUSTOMER_TRUSTED_SESSION_V67;
    return session
      ? { name: session.customer_name || "Customer", mobile: "" }
      : null;
  }

  function applyLabels() {
    const session =
      trusted || window.RR_PARTNER_CUSTOMER_TRUSTED_SESSION_V67 || {};
    const owner = String(session.owner_name || "DISTRIBUTOR")
      .trim()
      .toUpperCase();
    const group = String(
      session.group_name || session.customer_name || "CUSTOMER GROUP",
    )
      .trim()
      .toUpperCase();
    const title = document.getElementById("fsTitle");
    const privateTab = document.getElementById("fsPrivate");
    const groupTab = document.getElementById("fsGroup");
    const info = document.getElementById("fsInfo");
    if (title) title.textContent = `${owner} ↔ ${group}`;
    if (privateTab)
      privateTab.textContent = `🔒 ${owner.replace(/ DISTRIBUTOR$/i, "")} DISTRIBUTOR`;
    if (groupTab) groupTab.textContent = "GROUP";
    if (info) info.textContent = "GROUP INFO";
  }

  window.RR_CHAT_RELATION_ADAPTER_V67 = {
    relation: "DISTRIBUTOR_CUSTOMER",
    ensure,
    ctx,
    rpc,
    identity,
    applyLabels,
  };
  window.RR_CUSTOMER_SECURE_SESSION_V9592 = {
    ensure,
    device,
    clear() {
      localStorage.removeItem(sessionKey);
      localStorage.removeItem("rr_customer_secure_session_v9592");
    },
  };
  RF853.rpc = rpc;

  async function boot() {
    try {
      await ensure();
      applyLabels();
      document.dispatchEvent(
        new CustomEvent("rr:partner-customer-secure-session-ready", {
          detail: trusted,
        }),
      );
      document.dispatchEvent(
        new CustomEvent("rr:customer-secure-session-ready", {
          detail: trusted,
        }),
      );
    } catch (error) {
      console.warn("partner customer secure chat", error.message);
    }
  }
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
  new MutationObserver(applyLabels).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
})();
