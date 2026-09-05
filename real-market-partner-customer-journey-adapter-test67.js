(() => {
  "use strict";
  if (window.__RR_PARTNER_CUSTOMER_JOURNEY_ADAPTER_V67__) return;
  window.__RR_PARTNER_CUSTOMER_JOURNEY_ADAPTER_V67__ = true;

  const query = new URLSearchParams(location.search);
  const token = query.get("t") || query.get("c") || "";
  const $ = (selector) => document.querySelector(selector);
  const $$ = (selector) => [...document.querySelectorAll(selector)];
  const money = (value) =>
    Number(value || 0).toLocaleString("en-IN", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  let metrics = null;

  function flash(text) {
    const box = $("#flash");
    if (!box) return;
    box.textContent = text;
    box.style.display = "block";
    clearTimeout(flash.timer);
    flash.timer = setTimeout(() => (box.style.display = "none"), 2800);
  }

  function metric(label, id, className = "") {
    return `<div id="${id}" class="rr67metric ${className}"><small>${label}</small><b>—</b></div>`;
  }

  function injectStyle() {
    if ($("#rr67JourneyStyle")) return;
    const style = document.createElement("style");
    style.id = "rr67JourneyStyle";
    style.textContent = `.head{display:grid!important;grid-template-columns:minmax(0,1fr) 66px 66px!important;gap:6px!important;align-items:stretch!important}.head>b,.head>#sub{grid-column:1!important}.head>b{grid-row:1!important}.head>#sub{grid-row:2!important}.rr67metric{border:1px solid #40536b;border-radius:9px;background:#121c29;text-align:center;display:flex;flex-direction:column;justify-content:center;min-width:0;min-height:46px}.rr67metric small{font-size:7px;color:#aeb8c6;font-weight:800}.rr67metric b{font-size:10px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.rr67headMetric{grid-row:1/3!important}.rr67headMetric.req{grid-column:2!important}.rr67headMetric.all{grid-column:3!important}.rr67control{max-width:760px;margin:6px auto;display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:0 10px}.journeyNav{grid-template-columns:repeat(var(--rr67-tabs,2),1fr)!important}.journeyNav [data-artifact="requirement"],.journeyNav [data-artifact="pi"],.journeyNav [data-artifact="ci"]{display:none!important}.journeyNav [data-artifact="pi"].rr67docReady,.journeyNav [data-artifact="ci"].rr67docReady{display:block!important}#rrChatBar,#rrChatBack,#rrCallBack{display:none!important}@media(max-width:410px){.head{grid-template-columns:minmax(0,1fr) 62px 62px!important}.journeyNav button{font-size:10px!important}}`;
    document.head.appendChild(style);
  }

  function setMetric(id, value, type) {
    const box = $(`#${id} b`);
    if (!box) return;
    box.textContent =
      value == null
        ? "—"
        : type === "qty"
          ? `${Math.floor(Number(value))} PCS`
          : `₹${money(value)}`;
  }

  function paint(next) {
    metrics = next || metrics || {};
    setMetric("rr67ReqQty", metrics.req_qty, "qty");
    setMetric("rr67ReqAmt", metrics.req_amount);
    setMetric("rr67ReqAvg", metrics.req_average);
    setMetric("rr67AllAvg", metrics.all_average);
    ["#rr67ReqQty", "#rr67ReqAmt", "#rr67ReqAvg"].forEach((id) => {
      const box = $(id);
      if (box) box.style.display = metrics.req_visible === false ? "none" : "flex";
    });
  }

  function paintDraft() {
    if (!metrics || metrics.req_visible === false) return;
    let qty = 0;
    let amount = 0;
    $$("[data-qty]").forEach((input) => {
      const row = (window.__RR_MARKET_SHARE_ROWS_V67 || []).find(
        (item) => String(item.lot_no) === String(input.dataset.qty),
      );
      const lineQty = Math.max(0, Math.floor(Number(input.value || 0)));
      qty += lineQty;
      amount += lineQty * Number(row?.sale_rate || 0);
    });
    const historyQty = Number(metrics.history_qty || 0);
    const historyAmount = Number(metrics.history_amount || 0);
    paint({
      ...metrics,
      req_qty: qty || null,
      req_amount: qty ? amount : null,
      req_average: qty ? amount / qty : null,
      all_average:
        qty && historyQty
          ? (historyAmount + amount) / (historyQty + qty)
          : metrics.all_average,
    });
  }

  function selectedLines() {
    return (window.__RR_MARKET_SHARE_ROWS_V67 || [])
      .map((row) => {
        const input = document.querySelector(
          `[data-qty="${CSS.escape(String(row.lot_no))}"]`,
        );
        const qty = Math.max(0, Math.floor(Number(input?.value || 0)));
        const max = Math.max(0, Math.floor(Number(row.available_qty || 0)));
        if (input && qty > max) input.value = max;
        return { lot_no: row.lot_no, qty: Math.min(qty, max) };
      })
      .filter((line) => line.qty > 0);
  }

  function openRequirement() {
    if (!selectedLines().length) return flash("SELECT QTY FIRST");
    $("#identityFields")?.classList.add("hidden");
    $("#reqModal .voicebox")?.classList.add("hidden");
    $("#note").value = "";
    $("#reqModal").classList.add("open");
    $("#reqModal").setAttribute("aria-hidden", "false");
  }

  async function submitRequirement() {
    const lines = selectedLines();
    if (!lines.length) return flash("SELECT QTY FIRST");
    const button = $("#confirmSend");
    try {
      button.disabled = true;
      const result = await RF853.rpc(
        "rr_market_partner_submit_requirement_v67",
        {
          p_token: token,
          p_customer_name: null,
          p_mobile: null,
          p_message: $("#note").value.trim() || null,
          p_lines: lines,
        },
      );
      $("#reqModal").classList.remove("open");
      $("#reqModal").setAttribute("aria-hidden", "true");
      flash(`${result.requirement_display_no || "REQUIREMENT"} DISTRIBUTOR को भेजी ✓`);
      setTimeout(() => location.reload(), 650);
    } catch (error) {
      flash(error.message);
    } finally {
      button.disabled = false;
    }
  }

  function syncDocumentTabs() {
    const piReady = !!$("#artifact-pi #sendPiResponse");
    const ciReady = /^\s*CI\s+\S+/i.test(
      String($("#artifact-ci")?.textContent || "").trim(),
    );
    $('[data-artifact="pi"]')?.classList.toggle("rr67docReady", piReady);
    $('[data-artifact="ci"]')?.classList.toggle("rr67docReady", ciReady);
    $(".journeyNav")?.style.setProperty(
      "--rr67-tabs",
      String(2 + Number(piReady) + Number(ciReady)),
    );
  }

  function openSharedChat() {
    const chat =
      window.RR_FULL_SECURE_CHAT_V9648 || window.RR_FULL_SECURE_CHAT_V9597;
    if (!chat?.open) return flash("Secure chat loading… फिर दबाएँ");
    window.RR_CHAT_RELATION_ADAPTER_V67?.applyLabels?.();
    chat.open();
  }

  function inject() {
    if ($("#rr67ReqAvg")) return;
    window.__RR_TEST67_PARTNER_CUSTOMER__ = true;
    injectStyle();
    $(".head").insertAdjacentHTML(
      "beforeend",
      metric("REQ AVG", "rr67ReqAvg", "rr67headMetric req") +
        metric("ALL AVG", "rr67AllAvg", "rr67headMetric all"),
    );
    $(".head").insertAdjacentHTML(
      "afterend",
      `<div class="rr67control">${metric("REQ QTY", "rr67ReqQty")}${metric("REQ AMT", "rr67ReqAmt")}</div>`,
    );
    $(".journeyNav").insertAdjacentHTML(
      "beforeend",
      '<button id="rr67ChatTab" type="button">CHAT</button>',
    );
    $("#rr67ChatTab").onclick = openSharedChat;
    $("#identityFields")?.classList.add("hidden");
    $("#reqModal .voicebox")?.classList.add("hidden");
    $("#send").onclick = openRequirement;
    $("#confirmSend").onclick = submitRequirement;
    document.addEventListener("input", (event) => {
      if (event.target.matches?.("[data-qty]")) paintDraft();
    });
    syncDocumentTabs();
    const documents = $("#artifact-pi")?.parentElement;
    if (documents)
      new MutationObserver(syncDocumentTabs).observe(documents, {
        childList: true,
        subtree: true,
      });
  }

  async function boot() {
    if (!token) return;
    try {
      metrics = await RF853.rpc(
        "rr_market_partner_customer_metrics_by_token_v67",
        { p_token: token },
      );
    } catch (_) {
      return;
    }
    inject();
    paint(metrics);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();
