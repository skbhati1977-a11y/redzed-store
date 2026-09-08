(() => {
  "use strict";
  if (window.__RR_CHAT_REQUIREMENT_IDENTITY_V9682__) return;
  window.__RR_CHAT_REQUIREMENT_IDENTITY_V9682__ = true;
  const RX = /\[REQ:([0-9a-f-]{36})\]/i;
  const cache = new Map();
  let activeId = "";
  const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[char]);
  const chatId = () => document.querySelector("#inboxRows .chatrow.on")?.dataset.chat || localStorage.getItem("rr_real_chat_last_group_v9507") || "";
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
    if (!cache.has(id)) cache.set(id, RF853.rpc("rr_chat_requirement_detail_v9508", { p_chat_id: chatId(), p_requirement_id: id }));
    return cache.get(id);
  }

  function label(data) {
    const req = data?.requirement_display_no || data?.requirement_no || "REQUIREMENT";
    const collection = data?.collection_display_no || "COLLECTION";
    const cu = Number(data?.collection_update_no || 0);
    return { req, collection: collection + (cu > 0 ? ` · UPDATE ${cu}` : "") };
  }

  async function decorateCard(node) {
    const match = (node.textContent || "").match(RX);
    if (!match || node.dataset.rrIdentity9682) return;
    node.dataset.rrIdentity9682 = "1";
    try {
      const data = await detail(match[1]);
      const button = node.querySelector(".rrReqCard9508");
      if (!button) return;
      const x = label(data);
      button.querySelector("b").textContent = `📋 ${x.req}`;
      button.querySelector("small").innerHTML = `${esc(x.collection)} · <span data-rr-stage>${esc(stage(data.status))}</span>`;
      button.addEventListener("click", () => { activeId = match[1]; showSheet(); }, { capture: true });
    } catch (_) {}
  }

  async function showSheet() {
    if (!activeId) return;
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
        pi.disabled = data.can_prepare_pi === false;
        pi.textContent = data?.pi?.status === "CI_FINAL" ? `CI FINAL · ${data.pi.ci_no || ""}` :
          data?.pi ? `PI CREATED · ${data.pi.pi_no || ""}` : "PREPARE PI";
      }
    } catch (_) {}
  }

  function scan() {
    document.querySelectorAll("#msgs .msg").forEach(decorateCard);
    if (document.getElementById("rrReqBack9508")?.classList.contains("on")) showSheet();
  }
  function init() {
    css();
    scan();
    new MutationObserver(scan).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
