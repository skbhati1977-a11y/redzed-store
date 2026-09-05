(() => {
  "use strict";
  const query = new URLSearchParams(location.search);
  if (query.has("rr_partner_mode")) return;
  if (window.__RR_REDZED_DISTRIBUTOR_CHAT_BRIDGE_V83__) return;
  window.__RR_REDZED_DISTRIBUTOR_CHAT_BRIDGE_V83__ = true;

  const rawRpc = RF853.rpc.bind(RF853);
  const relations = new Map();
  let activeChatId = "";
  let activeBatch = null;
  let currentView = "REQ";
  let loaded = false;

  const $ = (id) => document.getElementById(id);
  const esc = (value) =>
    String(value ?? "").replace(
      /[&<>"']/g,
      (char) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#039;",
        })[char],
    );

  function distributorLabel(name) {
    const clean = String(name || "Distributor")
      .replace(/\s+DISTRIBUTOR$/i, "")
      .trim();
    return `${clean || "Distributor"} DISTRIBUTOR`;
  }

  function relation() {
    return relations.get(String(activeChatId)) || null;
  }

  function setText(node, value) {
    if (node && node.textContent !== value) node.textContent = value;
  }

  function flash(message, bad = false) {
    const box = $("flash");
    if (!box) return;
    box.textContent = message;
    box.style.display = "block";
    box.style.color = bad ? "#ffb7bd" : "#fff";
    clearTimeout(flash.timer);
    flash.timer = setTimeout(() => (box.style.display = "none"), 2600);
  }

  function ensureUi() {
    if (!$("rrRzStaffCss83")) {
      const style = document.createElement("style");
      style.id = "rrRzStaffCss83";
      style.textContent = `
        .rrRzBadge83{display:inline-block;margin-top:4px;padding:2px 6px;border:1px solid #3e6281;border-radius:999px;color:#8dccff;font-size:9px;font-weight:900}
        .rrRzDock83{position:fixed;left:320px;right:0;bottom:70px;z-index:10018;display:none;grid-template-columns:repeat(3,1fr);gap:7px;padding:8px;background:#0b0f15ef;border-top:1px solid #334154}
        .rrRzDock83.on{display:grid}.rrRzDock83 button{min-height:48px;border:1px solid #43536b;border-radius:11px;background:#182535;color:#fff;font-weight:900}.rrRzDock83 button:first-child{background:#197d51}.rrRzDock83 button:last-child{background:#167bc0}
        .chat.rrRzPartner83 .msgs{padding-bottom:160px!important}
        .rrRzBack83{z-index:10190!important}.rrRzSheet83{width:min(780px,100%);max-height:90dvh;overflow:auto;background:#10161f;border:1px solid #43536b;border-radius:20px 20px 0 0;padding:0;color:#fff}
        .rrRzHead83{position:sticky;top:0;z-index:2;display:flex;align-items:center;gap:8px;padding:11px;background:#10161f;border-bottom:1px solid #334154}.rrRzHead83 b{flex:1}.rrRzHead83 button{width:44px;height:44px}
        .rrRzBody83{padding:10px}.rrRzBatch83{border:1px solid #35475d;border-radius:13px;padding:11px;margin-bottom:9px;background:#131d29}.rrRzBatch83 small{display:block;color:#a2afbf;margin:3px 0 8px}.rrRzBatch83>button,.rrRzActions83 button{width:100%;min-height:44px;margin-top:8px;border:1px solid #49647f;border-radius:10px;background:#176ca8;color:#fff;font-weight:900}
        .rrRzOrder83{margin:9px 0;padding:9px;border:1px solid #2f4054;border-radius:11px}.rrRzLine83{display:grid;grid-template-columns:64px minmax(0,1fr) 85px;gap:7px;align-items:center;padding:7px 0;border-top:1px solid #2b394a}.rrRzLine83 img{width:60px;height:70px;object-fit:cover;border-radius:7px}.rrRzLine83 input,.rrRzActions83 input{width:100%;padding:9px;background:#0c141e;color:#fff;border:1px solid #43536b;border-radius:8px}.rrRzActions83{display:grid;gap:7px;margin-top:11px}.rrRzEmpty83{padding:28px 10px;text-align:center;color:#9ba9ba}.rrRzCard83{width:100%;display:block;margin:7px 0;padding:11px;border:1px solid #49627d;border-radius:12px;background:#101923;color:#fff;text-align:left}.rrRzCard83 b,.rrRzCard83 small{display:block}.rrRzCard83 small{color:#9fb0c2;margin-top:3px}
        @media(max-width:760px){.rrRzDock83{left:0}.rrRzLine83{grid-template-columns:52px minmax(0,1fr) 76px}.rrRzLine83 img{width:50px;height:60px}}
      `;
      document.head.appendChild(style);
    }
    if (!$("rrRzDock83")) {
      const dock = document.createElement("nav");
      dock.id = "rrRzDock83";
      dock.className = "rrRzDock83";
      dock.innerHTML =
        '<button data-rz-view="REQ">REQUIREMENTS</button><button data-rz-view="PI">PI</button><button data-rz-view="CI">CI</button>';
      document.querySelector(".chat")?.appendChild(dock);
      dock.querySelectorAll("[data-rz-view]").forEach(
        (button) =>
          (button.onclick = () => openList(button.dataset.rzView)),
      );
    }
    if (!$("rrRzBack83")) {
      document.body.insertAdjacentHTML(
        "beforeend",
        '<div id="rrRzBack83" class="sheetback panelBack rrRzBack83"><section class="rrRzSheet83"><div class="rrRzHead83"><b id="rrRzTitle83">Distributor Journey</b><button id="rrRzClose83" data-close="rrRzBack83">×</button></div><div id="rrRzBody83" class="rrRzBody83"></div></section></div>',
      );
      $("rrRzClose83").onclick = closeSheet;
      $("rrRzBack83").onclick = (event) => {
        if (event.target === $("rrRzBack83")) closeSheet();
      };
    }
  }

  function openSheet(title, html) {
    ensureUi();
    $("rrRzTitle83").textContent = title;
    $("rrRzBody83").innerHTML = html;
    $("rrRzBack83").classList.add("on");
  }

  function closeSheet() {
    $("rrRzBack83")?.classList.remove("on");
    activeBatch = null;
  }

  function batchStatus(batch) {
    return String(batch.status || "").replaceAll("_", " ");
  }

  function batchesFor(view) {
    const rows = relation()?.batches || [];
    if (view === "REQ")
      return rows.filter((item) =>
        ["SUBMITTED", "PI_PROPOSED", "WAITING_CONFIRMATION"].includes(
          item.status,
        ),
      );
    if (view === "PI")
      return rows.filter((item) =>
        [
          "SUBMITTED",
          "PI_PROPOSED",
          "WAITING_CONFIRMATION",
          "CONFIRMED",
          "PARTIAL_CONFIRMED",
        ].includes(item.status),
      );
    return rows.filter((item) =>
      ["WAITING_CONFIRMATION", "CONFIRMED", "PARTIAL_CONFIRMED", "CI_FINAL"].includes(
        item.status,
      ),
    );
  }

  function openList(view) {
    currentView = view;
    const rows = batchesFor(view);
    const title =
      view === "REQ" ? "DISTRIBUTOR REQUIREMENTS" : view === "PI" ? "DISTRIBUTOR PI" : "DISTRIBUTOR CI";
    openSheet(
      title,
      rows.length
        ? rows
            .map(
              (batch) =>
                `<article class="rrRzBatch83"><b>${esc(batch.batch_ref)}</b><small>${Number(batch.order_count || 0)} requirement(s) · ${esc(batchStatus(batch))}${batch.pi_ref ? ` · PI ${esc(batch.pi_ref)}` : ""}${batch.ci_ref ? ` · CI ${esc(batch.ci_ref)}` : ""}</small><button data-rz-batch="${esc(batch.id)}">OPEN IN THIS CHAT</button></article>`,
            )
            .join("")
        : '<div class="rrRzEmpty83">No item in this stage.</div>',
    );
    document.querySelectorAll("[data-rz-batch]").forEach(
      (button) =>
        (button.onclick = () => openBatch(button.dataset.rzBatch, view)),
    );
  }

  function lineHtml(line, editable) {
    const qty = Number(line.proposed_qty ?? line.requested_qty ?? 0);
    return `<div class="rrRzLine83">${line.image_url ? `<img src="${esc(line.image_url)}" loading="lazy" alt="">` : "<span>👕</span>"}<span><b>${esc(line.lot_no || "-")}</b><small>${esc(line.category || line.article_name || "-")} · ${esc(line.size_text || "-")}<br>Requested ${Number(line.requested_qty || 0)}</small></span>${editable ? `<input data-rz-line="${esc(line.id)}" type="number" min="0" value="${qty}">` : `<b>${qty} PCS</b>`}</div>`;
  }

  function renderBatch(detail, view) {
    activeBatch = detail;
    const canPi = ["SUBMITTED", "PI_PROPOSED", "WAITING_CONFIRMATION"].includes(
      detail.status,
    );
    const canCi = ["WAITING_CONFIRMATION", "CONFIRMED", "PARTIAL_CONFIRMED"].includes(
      detail.status,
    );
    const editable = view !== "CI" && canPi;
    const orders = (detail.orders || [])
      .map(
        (order, index) =>
          `<section class="rrRzOrder83"><b>REQUIREMENT ${index + 1}</b><small>${esc(String(order.status || "").replaceAll("_", " "))}</small>${(order.lines || []).map((line) => lineHtml(line, editable)).join("")}</section>`,
      )
      .join("");
    const actions = `<div class="rrRzActions83">${canPi ? `<input id="rrRzPiRef83" placeholder="PI reference" value="${esc(detail.pi_ref || "")}"><button id="rrRzSendPi83">MAKE / SEND PI TO DISTRIBUTOR</button>` : ""}${canCi ? `<input id="rrRzCiRef83" placeholder="CI reference (blank = auto)" value="${esc(detail.ci_ref || "")}"><button id="rrRzSendCi83">GENERATE CI · CONFIRMATION OPTIONAL</button>` : ""}</div>`;
    openSheet(
      `${detail.batch_ref} · ${batchStatus(detail)}`,
      `<p><b>${esc(distributorLabel(detail.direct_customer_name))}</b><br><small>Downstream customer identity is private.</small></p>${orders || '<div class="rrRzEmpty83">No requirement lines.</div>'}${actions}`,
    );
    if ($("rrRzSendPi83")) $("rrRzSendPi83").onclick = sendPi;
    if ($("rrRzSendCi83")) $("rrRzSendCi83").onclick = sendCi;
  }

  async function openBatch(batchId, view = currentView) {
    try {
      openSheet("DISTRIBUTOR JOURNEY", '<div class="rrRzEmpty83">Loading…</div>');
      const detail = await rawRpc("rr_market_staff_batch_detail_v67", {
        p_batch_id: batchId,
      });
      renderBatch(detail, view);
    } catch (error) {
      openSheet("DISTRIBUTOR JOURNEY", `<div class="rrRzEmpty83">${esc(error.message)}</div>`);
    }
  }

  async function sendNotice(body) {
    if (!activeChatId) return;
    await rawRpc("rr_chat_send_staff_v9433", {
      p_chat_id: activeChatId,
      p_channel: "GROUP",
      p_message_type: "TEXT",
      p_body: body,
      p_payload: { relation_scope: "DISTRIBUTOR_REDZED", ui: "TEST67_V83" },
      p_reply_to: null,
      p_order_session_id: null,
    });
  }

  async function sendPi() {
    if (!activeBatch) return;
    try {
      const proposals = [...document.querySelectorAll("[data-rz-line]")].map(
        (input) => ({
          line_id: input.dataset.rzLine,
          proposed_qty: Math.max(0, Math.floor(Number(input.value || 0))),
        }),
      );
      const detail = await rawRpc("rr_market_staff_propose_batch_v67", {
        p_batch_id: activeBatch.id,
        p_line_proposals: proposals,
        p_pi_ref: $("rrRzPiRef83")?.value.trim() || "",
      });
      await sendNotice(
        `[PBATCH:${detail.id}] ${detail.batch_ref} · PI ${detail.pi_ref} SENT TO DISTRIBUTOR`,
      );
      await loadRelations(true);
      renderBatch(detail, "PI");
      flash("PI distributor को भेजी ✓");
    } catch (error) {
      flash(error.message, true);
    }
  }

  async function sendCi() {
    if (!activeBatch) return;
    try {
      const detail = await rawRpc("rr_market_staff_finalize_ci_v67", {
        p_batch_id: activeBatch.id,
        p_ci_ref: $("rrRzCiRef83")?.value.trim() || "",
      });
      await sendNotice(
        `[PBATCH:${detail.id}] ${detail.batch_ref} · CI ${detail.ci_ref} SENT TO DISTRIBUTOR`,
      );
      await loadRelations(true);
      renderBatch(detail, "CI");
      flash("CI distributor को भेजी ✓");
    } catch (error) {
      flash(error.message, true);
    }
  }

  function decorateMessages() {
    if (!relation()) return;
    document.querySelectorAll("#msgs .msg[data-msg-id]").forEach((message) => {
      if (message.querySelector(".rrRzCard83")) return;
      const match = (message.textContent || "").match(
        /\[PBATCH:([0-9a-f-]{36})\]/i,
      );
      if (!match) return;
      [...message.children].forEach((child) => {
        if (child.tagName === "DIV" && /\[PBATCH:/i.test(child.textContent || ""))
          child.style.display = "none";
      });
      const card = document.createElement("button");
      card.type = "button";
      card.className = "rrRzCard83";
      card.innerHTML =
        "<b>📋 DISTRIBUTOR REQUIREMENT / PI / CI</b><small>Open the private REDZED–Distributor journey</small>";
      card.onclick = () => openBatch(match[1], "REQ");
      message.insertBefore(card, message.querySelector("time"));
    });
  }

  function applyActive() {
    ensureUi();
    const selected = document.querySelector("#inboxRows .chatrow.on");
    if (selected) activeChatId = selected.dataset.chat || activeChatId;
    const item = relation();
    const chat = document.querySelector(".chat");
    const dock = $("rrRzDock83");
    chat?.classList.toggle("rrRzPartner83", !!item);
    dock?.classList.toggle("on", !!item);
    document.querySelectorAll("#inboxRows .chatrow[data-chat]").forEach((row) => {
      const mapped = relations.get(row.dataset.chat || "");
      let badge = row.querySelector(".rrRzBadge83");
      if (mapped && !badge) {
        badge = document.createElement("span");
        badge.className = "rrRzBadge83";
        badge.textContent = "DISTRIBUTOR";
        row.appendChild(badge);
      }
    });
    if (item) {
      setText(
        $("chatTitle"),
        `REDZED ↔ ${distributorLabel(item.distributor_name).toUpperCase()}`,
      );
      setText($("groupTab"), "REDZED");
      if ($("privateTab")) $("privateTab").style.display = "none";
      setText($("groupInfo"), "RELATION INFO");
      decorateMessages();
    } else {
      setText($("groupTab"), "GROUP");
      setText($("privateTab"), "🔒 SUPER ADMIN");
      setText($("groupInfo"), "GROUP INFO");
    }
  }

  async function loadRelations(force = false) {
    if (loaded && !force) return;
    const rows = await rawRpc("rr_market_redzed_staff_distributor_relations_v83", {});
    relations.clear();
    (Array.isArray(rows) ? rows : []).forEach((row) =>
      relations.set(String(row.chat_id), row),
    );
    loaded = true;
    applyActive();
  }

  document.addEventListener(
    "click",
    (event) => {
      const row = event.target.closest?.("#inboxRows .chatrow[data-chat]");
      if (row) {
        activeChatId = row.dataset.chat || "";
        setTimeout(applyActive, 80);
      }
      if (event.target.closest?.("#groupInfo") && relation()) {
        event.preventDefault();
        event.stopImmediatePropagation();
        alert(`${$("chatTitle")?.textContent || "REDZED ↔ DISTRIBUTOR"}\n\nDownstream customers are private.`);
      }
    },
    true,
  );

  const observer = new MutationObserver(() => {
    applyActive();
    decorateMessages();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });

  async function boot(attempt = 0) {
    try {
      await loadRelations();
    } catch (error) {
      if (attempt < 30) setTimeout(() => boot(attempt + 1), 200);
      else console.warn("TEST67 REDZED distributor relation load failed", error);
    }
  }
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", () => boot(), { once: true });
  else boot();
})();
