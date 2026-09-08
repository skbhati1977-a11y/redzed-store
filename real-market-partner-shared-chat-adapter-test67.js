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
  let piImageRouting = false;
  const rawRpc = RF853.rpc.bind(RF853);

  function routePiImage(event) {
    const image = event.target?.closest?.("#fsMsgs .fsattimg,#fsMsgs .rrMediaThumb9664,#fsMsgs .rrAutoImg9651");
    if (!image) return;
    const card = image.closest(".fsm")?.querySelector(".rrPartnerCustomerPiCard89");
    if (!card) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (piImageRouting) return;
    piImageRouting = true;
    card.click();
    setTimeout(() => { piImageRouting = false; }, 1000);
  }
  document.addEventListener("touchend", routePiImage, { capture: true, passive: false });
  document.addEventListener("pointerup", routePiImage, true);
  document.addEventListener("click", routePiImage, true);

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
    rr_chat_customer_delete_v9712:
      "rr_market_partner_customer_chat_delete_v9712",
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
      #fsMsgs .rrPartnerCustomerPiCard89{display:grid;width:100%;min-height:96px;grid-template-columns:42px minmax(0,1fr);gap:10px;align-items:center;box-sizing:border-box;margin:7px 0 2px;padding:12px;border:1px solid #536b88;border-radius:13px;background:#101923;color:#fff;text-align:left;overflow:hidden}
      #fsMsgs .rrPartnerCustomerPiCard89>span:first-child{font-size:28px;text-align:center}.rrPartnerCustomerPiCard89>span:nth-child(2){min-width:0}.rrPartnerCustomerPiCard89 b,#fsMsgs .rrPartnerCustomerPiCard89 small{display:block;overflow-wrap:anywhere}.rrPartnerCustomerPiCard89 small{margin-top:5px;color:#aeb9c7;font-size:11px;line-height:1.25}.rrPartnerCustomerPiCard89 strong{grid-column:1/-1;display:block;padding-top:9px;border-top:1px solid #34475d;color:#8fc4ff;font-size:12px;line-height:1.2;text-align:center;white-space:normal}
      #fsMsgs .rrPartnerCustomerPiMessage89>.fsattbtn,#fsMsgs .rrPartnerCustomerPiMessage89>.fsattimg,#fsMsgs .rrPartnerCustomerPiMessage89>.rrMediaThumb9664,#fsMsgs .rrPartnerCustomerPiMessage89>.rrAutoImg9651{display:none!important}
      .rrPartnerDocs89{position:fixed;inset:0;z-index:10220;display:none;align-items:flex-end;background:#000c}.rrPartnerDocs89.on{display:flex}
      .rrPartnerDocsCard89{width:min(760px,100%);max-height:88dvh;display:flex;flex-direction:column;overflow:hidden;border:1px solid #40516a;border-radius:22px 22px 0 0;background:#10161f;color:#fff}
      .rrPartnerDocsHead89{display:flex;align-items:center;gap:8px;padding:11px;border-bottom:1px solid #334154}.rrPartnerDocsHead89 b{flex:1}.rrPartnerDocsHead89 button,.rrPartnerDocsBody89 button{border:1px solid #465a73;border-radius:10px;background:#182535;color:#fff;font-weight:900;padding:10px}
      .rrPartnerDocsBody89{overflow:auto;padding:10px}.rrPartnerDoc89{border:1px solid #35475d;border-radius:13px;padding:11px;background:#131d29}.rrPartnerDoc89+.rrPartnerDoc89{margin-top:9px}.rrPartnerDoc89>small{display:block;margin:4px 0 9px;color:#a2afbf}
      .rrPartnerDocLine89{display:grid;grid-template-columns:58px minmax(0,1fr) 92px;gap:8px;align-items:center;padding:8px 0;border-top:1px solid #2b394a}.rrPartnerDocLine89 img{width:58px;height:66px;object-fit:cover;border-radius:8px;background:#09111b}.rrPartnerDocLine89 small{display:block;color:#aeb9c7}.rrPartnerDocLine89 select,.rrPartnerDocLine89 input,.rrPartnerDocs89 textarea{width:100%;box-sizing:border-box;margin-top:5px;padding:8px;border:1px solid #43536b;border-radius:8px;background:#0c141e;color:#fff}.rrPartnerDocs89 textarea{min-height:58px}.rrPartnerDocsSend89{width:100%;margin-top:10px;background:#fff!important;color:#111!important}.rrPartnerDocsEmpty89{padding:24px 8px;text-align:center;color:#9ba9ba}
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

  function esc(value) {
    return String(value ?? "").replace(
      /[&<>"']/g,
      (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[char],
    );
  }

  function ensureDocumentsSheet() {
    if (document.getElementById("rrPartnerDocs89")) return;
    document.body.insertAdjacentHTML(
      "beforeend",
      '<div id="rrPartnerDocs89" class="rrPartnerDocs89"><section class="rrPartnerDocsCard89"><div class="rrPartnerDocsHead89"><b>INVOICES · VIEW / RESPOND ONLY</b><button id="rrPartnerDocsClose89" type="button">×</button></div><div id="rrPartnerDocsBody89" class="rrPartnerDocsBody89">Loading…</div></section></div>',
    );
    document.getElementById("rrPartnerDocsClose89").onclick = closeDocuments;
    document.getElementById("rrPartnerDocs89").onclick = (event) => {
      if (event.target.id === "rrPartnerDocs89") closeDocuments();
    };
  }

  function closeDocuments() {
    document.getElementById("rrPartnerDocs89")?.classList.remove("on");
  }

  function documentLine(line, editable) {
    const quantity = Number(line.customer_qty ?? line.proposed_qty ?? line.qty ?? 0);
    const decision = String(line.decision || "WAITING");
    return `<div class="rrPartnerDocLine89">${line.image_url ? `<img src="${esc(line.image_url)}" alt="${esc(line.lot_no)}">` : '<span>👕</span>'}<span><b>${esc(line.lot_no || "-")}</b><small>${esc(line.category || "-")} · ${esc(line.size_text || "-")}</small><small>Required ${Number(line.requested_qty ?? line.qty ?? 0)} PCS</small></span>${editable ? `<span><select data-rrpi-action89="${esc(line.id)}"><option value="CONFIRM" ${decision === "CONFIRM" ? "selected" : ""}>CONFIRM</option><option value="CHANGE" ${decision === "CHANGE" ? "selected" : ""}>CHANGE</option><option value="CANCEL" ${decision === "CANCEL" ? "selected" : ""}>CANCEL</option></select><input data-rrpi-qty89="${esc(line.id)}" type="number" min="0" value="${quantity}"></span>` : `<b>${quantity} PCS</b>`}</div>`;
  }

  async function submitPiResponse(pi) {
    const decisions = (pi.lines || []).map((line) => ({
      line_id: line.id,
      action: document.querySelector(`[data-rrpi-action89="${CSS.escape(String(line.id))}"]`)?.value || "CONFIRM",
      qty: Math.max(0, Math.floor(Number(document.querySelector(`[data-rrpi-qty89="${CSS.escape(String(line.id))}"]`)?.value || 0))),
    }));
    const button = document.getElementById("rrPartnerPiSend89");
    try {
      if (button) button.disabled = true;
      const result = await call("rr_market_partner_customer_distributor_pi_response_v67", {
        p_token: token,
        p_decisions: decisions,
        p_note: document.getElementById("rrPartnerPiNote89")?.value.trim() || null,
      });
      await openPiArtifact();
      const flash = document.getElementById("flash");
      if (flash) {
        flash.textContent = `PI ${result.distributor_pi_status || "RESPONSE"} · DISTRIBUTOR को भेजी ✓`;
        flash.style.display = "block";
        setTimeout(() => (flash.style.display = "none"), 2400);
      }
    } catch (error) {
      alert(error.message);
    } finally {
      if (button) button.disabled = false;
    }
  }

  async function openPiArtifact() {
    ensureCollectionCardStyle();
    ensureDocumentsSheet();
    const sheet = document.getElementById("rrPartnerDocs89");
    const body = document.getElementById("rrPartnerDocsBody89");
    sheet.classList.add("on");
    body.textContent = "Loading PI / CI…";
    try {
      const [pi, share] = await Promise.all([
        call("rr_market_partner_customer_pi_view_v67", { p_token: token }),
        call("rr_market_share_view_v9420", { p_token: token }),
      ]);
      const ci = share?.ci || null;
      body.innerHTML = `${pi ? `<article class="rrPartnerDoc89"><b>${esc(pi.ref || "PI")}</b><small>PI FROM DISTRIBUTOR · STATUS ${esc(pi.status || "WAITING")}</small>${(pi.lines || []).map((line) => documentLine(line, true)).join("")}<textarea id="rrPartnerPiNote89" placeholder="Optional note to distributor">${esc(pi.note || "")}</textarea><button id="rrPartnerPiSend89" class="rrPartnerDocsSend89" type="button">SEND PI RESPONSE</button></article>` : '<div class="rrPartnerDocsEmpty89">Distributor PI अभी प्राप्त नहीं हुई।</div>'}${ci ? `<article class="rrPartnerDoc89"><b>${esc(ci.ref || "CI")}</b><small>FINAL CI FROM DISTRIBUTOR</small>${(ci.lines || []).map((line) => documentLine(line, false)).join("")}</article>` : ''}`;
      const send = document.getElementById("rrPartnerPiSend89");
      if (send) send.onclick = () => submitPiResponse(pi);
    } catch (error) {
      body.innerHTML = `<div class="rrPartnerDocsEmpty89">${esc(error.message)}</div>`;
    }
  }

  function decoratePiMessages() {
    ensureCollectionCardStyle();
    document.querySelectorAll("#fsMsgs .fsm").forEach((message) => {
      const existingCard = message.querySelector(".rrPartnerCustomerPiCard89");
      if (existingCard) {
        message.classList.add("rrPartnerCustomerPiMessage89");
        message.querySelectorAll(".fsattimg,.rrMediaThumb9664,.rrAutoImg9651").forEach((image) => {
          image.onclick = (event) => { event.preventDefault(); event.stopImmediatePropagation(); existingCard.click(); };
        });
        return;
      }
      const body = message.querySelector(".fsbody");
      const match = (body?.textContent || "").match(/\[DPI:([0-9a-f-]{36})\]\s*([^·\n]+)?/i);
      if (!match) return;
      message.classList.add("rrPartnerCustomerPiMessage89");
      if (body) body.style.display = "none";
      const card = document.createElement("button");
      card.type = "button";
      card.className = "rrPartnerCustomerPiCard89";
      card.innerHTML = '<span>📄</span><span><b>PI</b><small>Distributor PI received · full PDF-format JPG</small></span><strong>OPEN COMPLETE JPG ›</strong>';
      setText(card.querySelector("b"), String(match[2] || "PI").trim());
      card.onclick = () => {
        const url = new URL("real-market-shared-invoice-test67.html", location.href);
        url.searchParams.set("role", "CUSTOMER");
        url.searchParams.set("order", match[1]);
        url.searchParams.set("t", token);
        url.searchParams.set("mode", "jpeg");
        url.searchParams.set("v", "15");
        location.href = url.href;
      };
      message.insertBefore(card, message.querySelector("time") || null);
      message.querySelectorAll(".fsattimg,.rrMediaThumb9664,.rrAutoImg9651").forEach((image) => {
        image.onclick = (event) => {
          event.preventDefault();
          event.stopImmediatePropagation();
          card.click();
        };
      });
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
    const ownerShort = owner.replace(/\s+DISTRIBUTOR$/i, "").trim().split(/\s+/)[0] || "DISTRIBUTOR";
    const customerShort = group.replace(/\s+GROUP$/i, "").trim().split(/\s+/)[0] || "CUSTOMER";
    const groupTitle = `${customerShort} ${ownerShort} GROUP`;
    const title = document.getElementById("fsTitle");
    const privateTab = document.getElementById("fsPrivate");
    const groupTab = document.getElementById("fsGroup");
    const info = document.getElementById("fsInfo");
    const collectionHeader = document.querySelector(
      "#rrCustomerCollectionHeaderV9619 .rzname",
    );
    setText(title, groupTitle);
    setText(
      privateTab,
      `🔒 ${owner.replace(/ DISTRIBUTOR$/i, "")} DISTRIBUTOR`,
    );
    setText(groupTab, "GROUP");
    setText(info, "GROUP INFO");
    setText(collectionHeader, groupTitle);
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
