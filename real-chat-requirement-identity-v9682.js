(() => {
  "use strict";
  if (window.__RR_CHAT_REQUIREMENT_IDENTITY_V9682__) return;
  window.__RR_CHAT_REQUIREMENT_IDENTITY_V9682__ = true;
  const RX = /\[REQ:([0-9a-f-]{36})\]/i;
  const cache = new Map();
  let activeId = "";
  let renderedKey = "";
  let rendering = false;
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[char]);
  const chatId = () => window.__RR_CURRENT_CHAT_ID__ || document.querySelector("#inboxRows .chatrow.on")?.dataset.chat || localStorage.getItem("rr_real_chat_last_group_v9507") || "";
  const stage = (value) => ({
    READY_FOR_PI: "READY FOR PI",
    PI_GENERATED: "PI GENERATED",
    CI_FINAL: "CI FINAL",
    PI_CANCELLED: "PI CANCELLED · READY FOR PI",
    SUPERSEDED: "EARLIER UPDATE"
  })[String(value || "").toUpperCase()] || String(value || "REQUIREMENT RECEIVED").replaceAll("_", " ");

  function css() {
    if (document.getElementById("rrReqIdentityCss9682")) return;
    const style = document.createElement("style");
    style.id = "rrReqIdentityCss9682";
    style.textContent = ".rrReqIdentity9682{margin:0 0 10px;padding:9px 10px;border:1px solid #3f536b;border-radius:11px;background:#14202d}.rrReqIdentity9682 b,.rrReqIdentity9682 small{display:block}.rrReqIdentity9682 small{color:#9fb0c2;margin-top:3px}.rrReqStage9682{color:#7de3a1!important;font-weight:900}.rrReqCard9508 [data-rr-stage]{color:#7de3a1}";
    document.head.appendChild(style);
  }

  async function detail(id) {
    const chat = chatId();
    if (!chat) throw new Error("Current customer chat missing. List se chat dobara open karein.");
    const key = `${chat}|${id}`;
    if (!cache.has(key)) {
      cache.set(key, RF853.rpc("rr_chat_requirement_detail_v9508", { p_chat_id: chat, p_requirement_id: id })
        .catch((error) => { cache.delete(key); throw error; }));
    }
    return cache.get(key);
  }

  function queueSheet(attempt = 0) {
    if (!activeId) return;
    if (document.getElementById("rrReqBack9508")?.classList.contains("on")) {
      showSheet();
      return;
    }
    if (attempt < 20) setTimeout(() => queueSheet(attempt + 1), 100);
  }

  function label(data) {
    const req = data?.requirement_display_no || data?.requirement_no || "REQUIREMENT";
    const collection = data?.collection_display_no || "COLLECTION";
    const cu = Number(data?.collection_update_no || 0);
    return { req, collection: `SOURCE: ${collection}` + (cu > 0 ? ` · UPDATE ${cu}` : " · ORIGINAL") };
  }

  async function decorateCard(node) {
    const match = (node.textContent || "").match(RX);
    if (!match || node.dataset.rrIdentity9682) return;
    node.dataset.rrIdentity9682 = "1";
    try {
      const data = await detail(match[1]);
      const button = node.querySelector(".rrReqCard9508");
      if (!button) return;
      button.dataset.requirementId = match[1];
      button.setAttribute("aria-label", "Open requirement");
      const x = label(data);
      button.querySelector("b").textContent = `📋 ${x.req}`;
      button.querySelector("small").innerHTML = `${esc(x.collection)} · <span data-rr-stage>${esc(stage(data.status))}</span>`;
      // Keep identity decoration passive. The canonical requirement-flow owns
      // navigation; this listener only records which card was selected and
      // enriches the sheet after that flow has opened it.
      button.addEventListener("click", () => {
        activeId = match[1];
        renderedKey = "";
        queueSheet();
      }, { capture: true });
    } catch (error) {
      const body = document.getElementById("rrReqBody9508");
      if (body) body.innerHTML = `<div class="muted">${esc(error?.message || "Requirement open nahi hui. Chat list se dobara open karein.")}</div>`;
    }
  }

  async function showSheet() {
    if (!activeId || rendering) return;
    const sheet = document.getElementById("rrReqBack9508");
    if (!sheet?.classList.contains("on")) return;
    const key = `${chatId()}|${activeId}`;
    if (renderedKey === key) return;
    rendering = true;
    try {
      const data = await detail(activeId);
      const body = document.getElementById("rrReqBody9508");
      if (!body) return;
      let meta = document.getElementById("rrReqIdentity9682");
      if (!meta) {
        meta = document.createElement("div");
        meta.id = "rrReqIdentity9682";
        meta.className = "rrReqIdentity9682";
        body.prepend(meta);
      }
      const x = label(data);
      meta.innerHTML = `<b>${esc(x.req)}</b><small>${esc(x.collection)}</small><small class="rrReqStage9682">${esc(stage(data.status))}</small>`;
      const title = document.getElementById("rrReqTitle9508");
      if (title) title.textContent = `📋 ${x.req}`;
      const add = document.getElementById("rrReqAdd9508");
      const pi = document.getElementById("rrReqPi9508");
      if (add) {
        add.disabled = data.can_add_update === false;
        add.style.display = data.can_add_update === false ? "none" : "";
      }
      if (pi) {
        const hasLines = Array.isArray(data?.lines) && data.lines.some((line) => Number(line?.accepted_qty || line?.requested_qty || 0) > 0);
        pi.disabled = data.can_prepare_pi === false || !hasLines;
        pi.textContent = data?.pi?.status === "CI_FINAL" ? `CI FINAL · ${data.pi.ci_no || ""}` :
          data?.pi ? `PI CREATED · ${data.pi.pi_no || ""}` : hasLines ? "PREPARE PI" : "NO ITEMS SAVED";
      }
      renderedKey = key;
    } catch (_) {
      renderedKey = "";
    } finally {
      rendering = false;
    }
  }

  function scan() {
    document.querySelectorAll("#msgs .msg").forEach(decorateCard);
  }
  function init() {
    css();
    scan();
    // Observe only newly rendered chat messages. Watching sheet attributes and
    // then mutating that same sheet caused an endless mobile render loop.
    new MutationObserver(scan).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
