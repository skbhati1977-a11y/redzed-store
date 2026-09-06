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
  const collectionPreviewCache = new Map();
  let trusted = null;
  const rawRpc = RF853.rpc.bind(RF853);

  function setText(node, value) {
    if (node && node.textContent !== value) node.textContent = value;
  }

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

  function ensureCollectionCardStyle() {
    if (document.getElementById("rrPartnerCustomerCollectionCardCss89"))
      return;
    const style = document.createElement("style");
    style.id = "rrPartnerCustomerCollectionCardCss89";
    style.textContent = `
      #fsMsgs .rrPartnerCustomerCollectionMessage89 .fsbody{display:none!important}
      #fsMsgs .rrPartnerCustomerCollectionCard89{display:grid;width:100%;grid-template-columns:58px minmax(0,1fr) auto;gap:10px;align-items:center;box-sizing:border-box;margin:7px 0 2px;padding:10px;border:1px solid #536b88;border-radius:13px;background:#101923;color:#fff;text-align:left}
      #fsMsgs .rrPartnerCustomerCollectionIcon89{display:flex;width:58px;height:66px;align-items:center;justify-content:center;overflow:hidden;border-radius:9px;background:#09111b;font-size:27px}
      #fsMsgs .rrPartnerCustomerCollectionIcon89 img{display:block!important;width:58px!important;height:66px!important;min-width:58px!important;min-height:66px!important;max-width:58px!important;max-height:66px!important;margin:0!important;border-radius:9px!important;object-fit:cover!important}
      #fsMsgs .rrPartnerCustomerCollectionCopy89{min-width:0}
      #fsMsgs .rrPartnerCustomerCollectionCopy89 b{display:block;font-size:14px;line-height:1.1}
      #fsMsgs .rrPartnerCustomerCollectionCopy89 small{display:block;margin-top:5px;color:#aeb9c7;font-size:11px;line-height:1.2}
      #fsMsgs .rrPartnerCustomerCollectionOpen89{color:#8fc4ff;font-size:12px;font-weight:900;white-space:nowrap}
      #fsMsgs .rrPartnerCustomerCollectionMessage89>.fsattbtn,#fsMsgs .rrPartnerCustomerCollectionMessage89>.fsattimg{display:none!important}
      #fsMsgs .rrPartnerCustomerPiCard89{display:grid;width:100%;grid-template-columns:58px minmax(0,1fr) auto;gap:10px;align-items:center;box-sizing:border-box;margin:7px 0 2px;padding:10px;border:1px solid #536b88;border-radius:13px;background:#101923;color:#fff;text-align:left}
      #fsMsgs .rrPartnerCustomerPiCard89 b,#fsMsgs .rrPartnerCustomerPiCard89 small{display:block}.rrPartnerCustomerPiCard89 small{margin-top:5px;color:#aeb9c7}.rrPartnerCustomerPiCard89 strong{color:#8fc4ff}
    `;
    document.head.appendChild(style);
  }

  function collectionUrlFrom(message) {
    const body = message?.querySelector(".fsbody")?.textContent || "";
    const absolute = body.match(/https:\/\/[^\s<]+\/s\.html\?[^\s<]+/i);
    const relative = body.match(/\/s\.html\?[^\s<]+/i);
    const raw = (absolute?.[0] || relative?.[0] || "").replace(
      /[),.;]+$/,
      "",
    );
    if (!raw) return "";
    try {
      return new URL(raw, location.href).href;
    } catch (_) {
      return "";
    }
  }

  function syncCollectionPoster(message, card) {
    const source = [...message.querySelectorAll("img.fsattimg")].find(
      (image) => !card.contains(image),
    );
    const icon = card.querySelector(".rrPartnerCustomerCollectionIcon89");
    if (!source || !icon || icon.querySelector("img")) return;
    const image = document.createElement("img");
    image.src = source.src;
    image.alt = source.alt || "Collection";
    icon.textContent = "";
    icon.appendChild(image);
    source.style.display = "none";
  }

  async function hydrateCollectionPreview(card, url) {
    const icon = card.querySelector(".rrPartnerCustomerCollectionIcon89");
    if (!icon || icon.querySelector("img") || card.dataset.rrPreview89) return;
    card.dataset.rrPreview89 = "loading";
    try {
      const parsed = new URL(url, location.href);
      const shareToken =
        parsed.searchParams.get("t") || parsed.searchParams.get("c") || "";
      if (!shareToken) throw Error("Collection token missing.");
      if (!collectionPreviewCache.has(shareToken)) {
        collectionPreviewCache.set(
          shareToken,
          call("rr_market_share_view_v9420", { p_token: shareToken }),
        );
      }
      const share = await collectionPreviewCache.get(shareToken);
      const displayNo = String(share?.collection_display_no || "COLLECTION");
      const match = displayNo.match(/^COLLECTION\s+(\d+)(?:\s*·\s*UPDATE\s+(\d+))?/i);
      const title = card.querySelector(".rrPartnerCustomerCollectionCopy89 b");
      const detail = card.querySelector(".rrPartnerCustomerCollectionCopy89 small");
      setText(title, displayNo);
      if (match) setText(detail, `COLLECTION NO. ${match[1]} · UPDATE NO. ${match[2] || 0}`);
      const row = Array.isArray(share?.rows) ? share.rows[0] : null;
      const media = Array.isArray(row?.media) ? row.media : [];
      const imageUrl =
        row?.primary_image_url ||
        media
          .map((item) => item?.image_url || item?.storage_path)
          .find(Boolean);
      if (!imageUrl || !card.isConnected || icon.querySelector("img"))
        throw Error("Collection preview unavailable.");
      const image = document.createElement("img");
      image.src = imageUrl;
      image.alt = row?.lot_no || "Collection";
      image.loading = "eager";
      image.decoding = "async";
      icon.textContent = "";
      icon.appendChild(image);
      card.dataset.rrPreview89 = "ready";
    } catch (_) {
      card.dataset.rrPreview89 = "unavailable";
    }
  }

  function decorateCollectionMessages() {
    ensureCollectionCardStyle();
    document.querySelectorAll("#fsMsgs .fsm").forEach((message) => {
      const url = collectionUrlFrom(message);
      if (!url) return;
      let card = message.querySelector(".rrPartnerCustomerCollectionCard89");
      if (!card) {
        message.classList.add("rrPartnerCustomerCollectionMessage89");
        card = document.createElement("button");
        card.type = "button";
        card.className = "rrPartnerCustomerCollectionCard89";
        card.innerHTML =
          '<span class="rrPartnerCustomerCollectionIcon89">🛍️</span><span class="rrPartnerCustomerCollectionCopy89"><b>COLLECTION</b><small>Loading collection number…</small></span><span class="rrPartnerCustomerCollectionOpen89">OPEN ›</span>';
        card.addEventListener("click", () => {
          const current = new URL(url, location.href);
          const currentToken = query.get("t") || query.get("c") || "";
          const cardToken =
            current.searchParams.get("t") || current.searchParams.get("c") || "";
          if (currentToken && cardToken === currentToken) {
            const openButton =
              document.getElementById("fcReopen") ||
              document.getElementById("fcOpen");
            if (openButton) {
              openButton.click();
              return;
            }
          }
          current.searchParams.set("open", "collection");
          location.href = current.href;
        });
        const time = message.querySelector("time");
        message.insertBefore(card, time || null);
      }
      syncCollectionPoster(message, card);
      hydrateCollectionPreview(card, url);
    });
  }

  function openPiArtifact() {
    document.querySelectorAll("[data-artifact]").forEach((button) =>
      button.classList.toggle("on", button.dataset.artifact === "pi"),
    );
    document.querySelectorAll(".artifact").forEach((node) =>
      node.classList.toggle("on", node.id === "artifact-pi"),
    );
    document.getElementById("artifact-pi")?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }

  function decoratePiMessages() {
    ensureCollectionCardStyle();
    document.querySelectorAll("#fsMsgs .fsm").forEach((message) => {
      if (message.querySelector(".rrPartnerCustomerPiCard89")) return;
      const body = message.querySelector(".fsbody");
      const match = (body?.textContent || "").match(/\[DPI:([0-9a-f-]{36})\]\s*([^·\n]+)?/i);
      if (!match) return;
      if (body) body.style.display = "none";
      const card = document.createElement("button");
      card.type = "button";
      card.className = "rrPartnerCustomerPiCard89";
      card.innerHTML = '<span>📄</span><span><b>PI</b><small>Distributor PI received · tap to review and respond</small></span><strong>OPEN ›</strong>';
      setText(card.querySelector("b"), String(match[2] || "PI").trim());
      card.onclick = openPiArtifact;
      message.insertBefore(card, message.querySelector("time") || null);
    });
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
    const collectionHeader = document.querySelector(
      "#rrCustomerCollectionHeaderV9619 .rzname",
    );
    setText(title, `${owner} ↔ ${group}`);
    setText(
      privateTab,
      `🔒 ${owner.replace(/ DISTRIBUTOR$/i, "")} DISTRIBUTOR`,
    );
    setText(groupTab, "GROUP");
    setText(info, "GROUP INFO");
    setText(collectionHeader, `${owner} COLLECTION`);
    decorateCollectionMessages();
    decoratePiMessages();
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
