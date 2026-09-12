(() => {
  "use strict";
  if (window.__RR_REQUIREMENT_OPEN_STABLE_V9727__) return;
  window.__RR_REQUIREMENT_OPEN_STABLE_V9727__ = true;

  const RX = /\[REQ:([0-9a-f-]{36})\]/i;
  const $ = (id) => document.getElementById(id);
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
  })[char]);
  let openingId = "";
  let openingAt = 0;
  let requestSerial = 0;
  let touchTap = null;
  const TAP_SLOP_PX = 14;

  // Keep vertical chat scrolling native, while removing the browser's delayed
  // double-tap gesture from requirement cards.
  const touchCss = document.createElement("style");
  touchCss.textContent = ".rrReqCard9508{touch-action:manipulation}";
  document.head.appendChild(touchCss);

  const chatId = () => window.__RR_CURRENT_CHAT_ID__
    || document.querySelector("#inboxRows .chatrow.on")?.dataset.chat
    || localStorage.getItem("rr_real_chat_last_group_v9507") || "";

  function requirementId(card) {
    return card?.dataset?.requirementId
      || (card?.closest(".msg")?.textContent || card?.parentElement?.textContent || "").match(RX)?.[1]
      || "";
  }

  function timeout(promise, milliseconds, message) {
    let timer;
    return Promise.race([
      promise,
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), milliseconds); })
    ]).finally(() => clearTimeout(timer));
  }

  function image(line) {
    const card = line?.card || {};
    const media = Array.isArray(card.media) ? card.media : [];
    return media[0]?.image_url || media[0]?.storage_path || card.primary_image_url || "";
  }

  function stage(value) {
    return ({
      READY_FOR_PI: "READY FOR PI",
      PI_GENERATED: "PI GENERATED",
      CI_FINAL: "CI FINAL",
      PI_CANCELLED: "PI CANCELLED · READY FOR PI",
      SUPERSEDED: "EARLIER UPDATE"
    })[String(value || "").toUpperCase()] || String(value || "REQUIREMENT RECEIVED").replaceAll("_", " ");
  }

  function openSheet() {
    const sheet = $("rrReqBack9508");
    if (!sheet) throw new Error("Requirement viewer unavailable. Page refresh karein.");
    sheet.classList.add("on");
    $("rrReqTitle9508").textContent = "📋 REQUIREMENT";
    $("rrReqBody9508").innerHTML = '<div class="muted">Loading requirement…</div>';
    const add = $("rrReqAdd9508");
    const pi = $("rrReqPi9508");
    if (add) { add.disabled = true; add.style.display = ""; }
    if (pi) { pi.disabled = true; pi.textContent = "LOADING…"; }
  }

  function render(data, id) {
    const lines = Array.isArray(data?.lines) ? data.lines : [];
    const usable = lines.filter((line) => Number(line?.accepted_qty || line?.requested_qty || 0) > 0);
    const total = lines.reduce((sum, line) => sum + Number(line.accepted_qty || 0), 0);
    const req = data?.requirement_display_no || data?.requirement_no || "REQUIREMENT";
    const collection = data?.collection_display_no || "COLLECTION";
    const update = Number(data?.collection_update_no || 0);
    $("rrReqTitle9508").textContent = `📋 ${req}`;
    $("rrReqBody9508").innerHTML = `
      <div class="rrReqIdentity9682">
        <b>${esc(req)}</b>
        <small>SOURCE: ${esc(collection)} · ${update > 0 ? `UPDATE ${update}` : "ORIGINAL"}</small>
        <small class="rrReqStage9682">${esc(stage(data?.status))}</small>
      </div>
      <div style="padding:4px 0 10px">
        <b>${esc(data?.customer_name || $("chatTitle")?.textContent || "Customer")}</b>
        <div class="muted">${lines.length} styles · ${total} accepted pcs${data?.message ? ` · ${esc(data.message)}` : ""}</div>
      </div>
      ${lines.map((line) => {
        const src = image(line);
        return `<div class="rrReqLine9508">
          ${src ? `<img src="${esc(src)}" loading="lazy">` : "<div>👕</div>"}
          <div><b>${esc(line.lot_no || "-")}</b><small>Requested ${Number(line.requested_qty || 0)} · Accepted ${Number(line.accepted_qty || 0)}</small></div>
          <div><b>${Number(line.accepted_qty || 0)}</b><small>PCS</small></div>
        </div>`;
      }).join("") || '<div class="muted">No items saved in this requirement.</div>'}`;

    const add = $("rrReqAdd9508");
    if (add) {
      add.disabled = data?.can_add_update === false;
      add.style.display = data?.can_add_update === false ? "none" : "";
      add.onclick = () => {
        const url = new URL("real-web-window-v9329.html", location.href);
        url.searchParams.set("v", "9727");
        url.searchParams.set("from_chat", "1");
        url.searchParams.set("chat_id", chatId());
        url.searchParams.set("customer_name", data?.customer_name || $("chatTitle")?.textContent || "Customer");
        url.searchParams.set("append_requirement_id", id);
        const lots = lines.map((line) => String(line.lot_no || "").trim()).filter(Boolean);
        if (lots.length) url.searchParams.set("exclude_lots", lots.join(","));
        location.href = url.href;
      };
    }
    const pi = $("rrReqPi9508");
    if (pi) {
      const lifecycle = window.RRMarketLifecycle.state({ ...data, ...data?.pi, pi: data?.pi });
      const ciFinal = lifecycle.ciFinal;
      const existingPi = lifecycle.piEditable;
      pi.disabled = ciFinal || !usable.length || (!existingPi && data?.can_prepare_pi === false);
      pi.textContent = ciFinal ? `CI FINAL · ${data?.pi?.ci_no || ""}`
        : existingPi ? `EDIT PI · ${data.pi.pi_no || ""}`
          : usable.length ? "PREPARE PI" : "NO ITEMS SAVED";
    }
  }

  async function open(id) {
    const chat = chatId();
    if (!chat) return;
    const serial = ++requestSerial;
    openSheet();

    try {
      const data = await timeout(
        RF853.rpc("rr_chat_requirement_detail_v9508", { p_chat_id: chat, p_requirement_id: id }),
        12000,
        "Requirement loading timeout. Network check karke RETRY karein."
      );
      if (serial === requestSerial) render(data, id);
    } catch (error) {
      if (serial !== requestSerial) return;
      $("rrReqBody9508").innerHTML = `<div class="muted">${esc(error?.message || "Requirement open nahi hui.")}</div>`;
      const pi = $("rrReqPi9508");
      if (pi) { pi.disabled = true; pi.textContent = "RETRY FROM CARD"; }
    }
  }

  function activate(event, forcedCard, forcedId) {
    const card = forcedCard || event.target.closest?.(".rrReqCard9508");
    if (!card) return;
    const id = forcedId || requirementId(card);
    if (!id) return;
    const now = Date.now();
    event.preventDefault();
    event.stopImmediatePropagation();
    // A phone may emit touchstart, pointerdown, pointerup and click for one
    // physical tap. Own the earliest event and suppress its synthetic copies.
    if (id === openingId && now - openingAt < 1200) return;
    openingId = id;
    openingAt = now;
    card.dataset.requirementId = id;
    try { sessionStorage.setItem("rr_active_requirement_v9515", id); } catch (_) {}
    open(id).catch((error) => {
      const body = $("rrReqBody9508");
      if (body) body.textContent = error?.message || "Requirement open failed.";
    });
  }

  function beginTouch(event) {
    if (event.touches.length !== 1) { touchTap = null; return; }
    const card = event.target.closest?.(".rrReqCard9508");
    const id = requirementId(card);
    if (!card || !id) { touchTap = null; return; }
    const point = event.touches[0];
    touchTap = { card, id, x: point.clientX, y: point.clientY, moved: false };
  }

  function moveTouch(event) {
    if (!touchTap || event.touches.length !== 1) return;
    const point = event.touches[0];
    if (Math.hypot(point.clientX - touchTap.x, point.clientY - touchTap.y) > TAP_SLOP_PX) {
      touchTap.moved = true;
    }
  }

  function endTouch(event) {
    const tap = touchTap;
    touchTap = null;
    if (!tap || tap.moved || event.changedTouches.length !== 1) return;
    const point = event.changedTouches[0];
    if (Math.hypot(point.clientX - tap.x, point.clientY - tap.y) > TAP_SLOP_PX) return;
    activate(event, tap.card, tap.id);
  }

  // A tap inside a scroll container can end as pointercancel when the card is
  // away from the scroll boundary. Touch-end + movement threshold makes the
  // result independent of the card's vertical position without hijacking swipes.
  document.addEventListener("touchstart", beginTouch, { capture: true, passive: true });
  document.addEventListener("touchmove", moveTouch, { capture: true, passive: true });
  document.addEventListener("touchend", endTouch, { capture: true, passive: false });
  document.addEventListener("touchcancel", () => { touchTap = null; }, true);
  document.addEventListener("pointerup", (event) => {
    if (event.pointerType !== "touch") activate(event);
  }, true);
  document.addEventListener("click", activate, true);
})();
