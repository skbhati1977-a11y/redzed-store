(() => {
  "use strict";
  const Q = new URLSearchParams(location.search);
  if (!document.querySelector('script[data-rr-mobile-back-step="67"]')) {
    const backScript = document.createElement("script");
    backScript.src = "real-mobile-back-step-test67.js?v=75";
    backScript.dataset.rrMobileBackStep = "67";
    document.head.appendChild(backScript);
  }
  const token = Q.get("t") || Q.get("c"),
    $ = (s) => document.querySelector(s),
    $$ = (s) => [...document.querySelectorAll(s)],
    esc = (v) =>
      String(v ?? "").replace(
        /[&<>"']/g,
        (c) =>
          ({
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            '"': "&quot;",
            "'": "&#39;",
          })[c],
      ),
    money = (v) =>
      Number(v || 0).toLocaleString("en-IN", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
  let metrics = null,
    lane = "CUSTOMER_GROUP",
    attachment = null,
    recorder = null,
    stream = null,
    parts = [],
    started = 0;
  function flash(t) {
    const e = $("#flash");
    e.textContent = t;
    e.style.display = "block";
    clearTimeout(flash.t);
    flash.t = setTimeout(() => (e.style.display = "none"), 2600);
  }
  function css() {
    const s = document.createElement("style");
    s.textContent = `.head{display:grid!important;grid-template-columns:minmax(0,1fr) 66px 66px!important;gap:6px!important;align-items:stretch!important}.head>b,.head>#sub{grid-column:1!important}.head>b{grid-row:1!important}.head>#sub{grid-row:2!important}.rr67metric{border:1px solid #40536b;border-radius:9px;background:#121c29;text-align:center;display:flex;flex-direction:column;justify-content:center;min-width:0}.rr67metric small{font-size:7px;color:#aeb8c6;font-weight:800}.rr67metric b{font-size:10px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.rr67headMetric{grid-row:1/3!important}.rr67headMetric.req{grid-column:2!important}.rr67headMetric.all{grid-column:3!important}.rr67control{max-width:760px;margin:6px auto;display:grid;grid-template-columns:minmax(0,.75fr) minmax(0,1.35fr) 66px 66px;gap:6px;padding:0 10px}.rr67control button{border:1px solid #40536b;border-radius:9px;background:#121c29;color:#fff;font-size:9px;font-weight:900}.rr67control button.on{background:#fff;color:#111}.rr67chat{display:grid;gap:8px}.rr67msg{max-width:88%;border:1px solid #33465d;border-radius:13px;padding:9px;background:#0d1722}.rr67msg.mine{justify-self:end;background:#143550}.rr67msg small{display:block;color:#aeb8c6}.rr67msg img{max-width:220px;max-height:260px;border-radius:8px;margin-top:6px}.rr67compose{display:grid;grid-template-columns:44px 1fr 44px 44px;gap:6px;position:sticky;bottom:0;padding:8px 0;background:#131923}.rr67compose button,.rr67attach{height:44px;border:1px solid #46566d;border-radius:50%;background:#162536;color:#fff;display:grid;place-items:center}.rr67compose input{min-width:0;border:1px solid #46566d;border-radius:22px;background:#0d1219;color:#fff;padding:0 12px}.rr67askbar{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin:7px 0}.rr67askbar button{min-height:40px;border:1px solid #46566d;border-radius:9px;background:#162536;color:#fff;font-weight:850;font-size:11px}.journeyNav{grid-template-columns:repeat(var(--rr67-tabs,2),1fr)!important}.journeyNav [data-artifact="requirement"],.journeyNav [data-artifact="pi"],.journeyNav [data-artifact="ci"]{display:none!important}.journeyNav [data-artifact="pi"].rr67docReady,.journeyNav [data-artifact="ci"].rr67docReady{display:block!important}#rrChatBar,#rrChatBack,#rrCallBack{display:none!important}@media(max-width:410px){.head{grid-template-columns:minmax(0,1fr) 62px 62px!important}.rr67control{grid-template-columns:minmax(0,.7fr) minmax(0,1.25fr) 62px 62px}.journeyNav button{font-size:10px!important}}`;
    document.head.appendChild(s);
  }
  function metric(label, id, cls = "") {
    return `<div id="${id}" class="rr67metric ${cls}"><small>${label}</small><b>—</b></div>`;
  }
  function inject() {
    if ($("#rr67ReqAvg")) return;
    window.__RR_TEST67_PARTNER_CUSTOMER__ = true;
    css();
    $(".head").insertAdjacentHTML(
      "beforeend",
      metric("REQ AVG", "rr67ReqAvg", "rr67headMetric req") +
        metric("ALL AVG", "rr67AllAvg", "rr67headMetric all"),
    );
    $(".head").insertAdjacentHTML(
      "afterend",
      `<div class="rr67control"><button id="rr67Group" class="on">GROUP</button><button id="rr67Direct">DISTRIBUTOR</button>${metric("REQ QTY", "rr67ReqQty")}${metric("REQ AMT", "rr67ReqAmt")}</div>`,
    );
    $(".journeyNav").insertAdjacentHTML(
      "beforeend",
      '<button id="rr67ChatTab" type="button">CHAT</button>',
    );
    $(".journeyNav").insertAdjacentHTML(
      "afterend",
      '<div class="rr67askbar"><button id="rr67HoldGroup" type="button">HOLD / ASK GROUP</button><button id="rr67AskDistributor" type="button">ASK DISTRIBUTOR</button></div>',
    );
    $(".journey").insertAdjacentHTML(
      "beforeend",
      `<div id="artifact-chat" class="artifact"><div id="rr67Messages" class="rr67chat"></div><form id="rr67Composer" class="rr67compose"><label class="rr67attach">＋<input id="rr67File" type="file" hidden></label><input id="rr67Text" placeholder="Message to distributor"><button id="rr67Mic" type="button">🎙</button><button type="submit">➤</button></form></div>`,
    );
    $("#rr67Group").onclick = () => switchLane("CUSTOMER_GROUP");
    $("#rr67Direct").onclick = () => switchLane("CUSTOMER_DIRECT");
    $("#rr67HoldGroup").onclick = () => askCollection("CUSTOMER_GROUP");
    $("#rr67AskDistributor").onclick = () => askCollection("CUSTOMER_DIRECT");
    $("#rr67ChatTab").onclick = () => showChat();
    $("#rr67Composer").onsubmit = send;
    $("#rr67File").onchange = chooseFile;
    $("#rr67Mic").onclick = record;
    $("#identityFields")?.classList.add("hidden");
    $("#reqModal .voicebox")?.classList.add("hidden");
    $("#send").onclick = openPartnerRequirement;
    $("#confirmSend").onclick = submitPartnerRequirement;
    syncDocumentTabs();
    const docs = $("#artifact-pi")?.parentElement;
    if (docs)
      new MutationObserver(syncDocumentTabs).observe(docs, {
        childList: true,
        subtree: true,
      });
    document.addEventListener("input", (e) => {
      if (e.target.matches?.("[data-qty]")) paintDraft();
    });
    $("#confirmSend")?.addEventListener("click", () =>
      setTimeout(refreshMetrics, 700),
    );
  }
  function syncDocumentTabs() {
    const piReady = !!$("#artifact-pi #sendPiResponse"),
      ciText = $("#artifact-ci")?.textContent || "",
      ciReady = /^\s*CI\s+\S+/i.test(ciText.trim());
    $('[data-artifact="pi"]')?.classList.toggle("rr67docReady", piReady);
    $('[data-artifact="ci"]')?.classList.toggle("rr67docReady", ciReady);
    $(".journeyNav")?.style.setProperty(
      "--rr67-tabs",
      String(2 + Number(piReady) + Number(ciReady)),
    );
  }
  function selectedRequirementLines() {
    return (window.__RR_MARKET_SHARE_ROWS_V67 || [])
      .map((row) => {
        const input = document.querySelector(
            `[data-qty="${CSS.escape(String(row.lot_no))}"]`,
          ),
          qty = Math.max(0, Math.floor(Number(input?.value || 0))),
          max = Math.max(0, Math.floor(Number(row.available_qty || 0)));
        if (input && qty > max) input.value = max;
        return { lot_no: row.lot_no, qty: Math.min(qty, max) };
      })
      .filter((line) => line.qty > 0);
  }
  function openPartnerRequirement() {
    if (!selectedRequirementLines().length)
      return flash("SELECT QTY FIRST");
    $("#identityFields")?.classList.add("hidden");
    $("#reqModal .voicebox")?.classList.add("hidden");
    $("#note").value = "";
    $("#reqModal").classList.add("open");
    $("#reqModal").setAttribute("aria-hidden", "false");
    setTimeout(() => $("#note")?.focus({ preventScroll: true }), 100);
  }
  async function submitPartnerRequirement() {
    const lines = selectedRequirementLines();
    if (!lines.length) return flash("SELECT QTY FIRST");
    try {
      $("#confirmSend").disabled = true;
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
      flash(
        `${result.requirement_display_no || "REQUIREMENT"} DISTRIBUTOR को भेजी ✓`,
      );
      setTimeout(() => location.reload(), 650);
    } catch (e) {
      flash(e.message);
    } finally {
      $("#confirmSend").disabled = false;
    }
  }
  function showChat() {
    $$("[data-artifact]").forEach((b) => b.classList.remove("on"));
    $$(".artifact").forEach((x) => x.classList.remove("on"));
    $("#rr67ChatTab").classList.add("on");
    $("#artifact-chat").classList.add("on");
    loadMessages();
  }
  function set(id, v, type) {
    const b = $(`#${id} b`);
    if (!b) return;
    b.textContent =
      v == null
        ? "—"
        : type === "qty"
          ? `${Math.floor(Number(v))} PCS`
          : `₹${money(v)}`;
  }
  function paint(m) {
    metrics = m || metrics || {};
    set("rr67ReqQty", metrics.req_qty, "qty");
    set("rr67ReqAmt", metrics.req_amount);
    set("rr67ReqAvg", metrics.req_average);
    set("rr67AllAvg", metrics.all_average);
    ["#rr67ReqQty", "#rr67ReqAmt", "#rr67ReqAvg"].forEach(
      (id) =>
        ($(id).style.display = metrics.req_visible === false ? "none" : "flex"),
    );
  }
  function paintDraft() {
    if (!metrics || metrics.req_visible === false) return;
    let qty = 0,
      amt = 0;
    $$("[data-qty]").forEach((i) => {
      const r = (window.__RR_MARKET_SHARE_ROWS_V67 || []).find?.(
          (x) => String(x.lot_no) === String(i.dataset.qty),
        ),
        q = Math.max(0, Math.floor(Number(i.value || 0)));
      qty += q;
      amt += q * Number(r?.sale_rate || 0);
    });
    const reqAvg = qty ? amt / qty : null,
      hq = Number(metrics.history_qty || 0),
      ha = Number(metrics.history_amount || 0),
      all = hq > 0 && qty ? (ha + amt) / (hq + qty) : metrics.all_average;
    paint({
      ...metrics,
      req_qty: qty || null,
      req_amount: qty ? amt : null,
      req_average: reqAvg,
      all_average: all,
    });
  }
  async function refreshMetrics() {
    try {
      metrics = await RF853.rpc(
        "rr_market_partner_customer_metrics_by_token_v67",
        { p_token: token },
      );
      paint(metrics);
    } catch (e) {
      console.warn(e);
    }
  }
  function switchLane(next) {
    lane = next;
    $("#rr67Group").classList.toggle("on", lane === "CUSTOMER_GROUP");
    $("#rr67Direct").classList.toggle("on", lane === "CUSTOMER_DIRECT");
    $("#rr67Text").placeholder =
      lane === "CUSTOMER_GROUP"
        ? "Message to customer group"
        : "Private message to distributor";
    showChat();
  }
  function askCollection(next) {
    switchLane(next);
    const collection =
      ($("#sub")?.textContent || "COLLECTION").split("·")[0].trim() ||
      "COLLECTION";
    const input = $("#rr67Text");
    input.value = `HOLD / ASK — ${collection}: `;
    input.focus();
  }
  function attachmentHtml(a) {
    if (!a?.data_url) return "";
    if (String(a.type).startsWith("image/"))
      return `<img src="${esc(a.data_url)}">`;
    if (String(a.type).startsWith("audio/"))
      return `<audio controls src="${esc(a.data_url)}"></audio>`;
    return `<a href="${esc(a.data_url)}" download="${esc(a.name || "attachment")}">📎 ${esc(a.name || "Attachment")}</a>`;
  }
  async function loadMessages() {
    try {
      const rows = await RF853.rpc(
        "rr_market_partner_customer_chat_messages_lane_v67",
        { p_token: token, p_lane: lane },
      );
      $("#rr67Messages").innerHTML =
        (rows || [])
          .map(
            (m) =>
              `<div class="rr67msg ${m.actor === "CUSTOMER" ? "mine" : ""}"><b>${esc(m.actor === "CUSTOMER" ? "YOU" : "DISTRIBUTOR")}</b>${m.message ? `<small>${esc(m.message)}</small>` : ""}${attachmentHtml(m.attachment)}</div>`,
          )
          .join("") || "<p>No direct messages yet.</p>";
    } catch (e) {
      $("#rr67Messages").textContent = e.message;
    }
  }
  function fileData(f) {
    return new Promise((ok, no) => {
      if (!f) return no(Error("File missing."));
      if (f.size > 1350000) return no(Error("Attachment 1.35 MB से कम रखें."));
      const r = new FileReader();
      r.onload = () =>
        ok({ name: f.name, type: f.type, data_url: String(r.result || "") });
      r.onerror = no;
      r.readAsDataURL(f);
    });
  }
  async function chooseFile(e) {
    try {
      attachment = await fileData(e.target.files?.[0]);
      flash(`${attachment.name} ready`);
    } catch (x) {
      flash(x.message);
    } finally {
      e.target.value = "";
    }
  }
  async function send(e) {
    e.preventDefault();
    const message = $("#rr67Text").value.trim();
    if (!message && !attachment) return;
    try {
      await RF853.rpc("rr_market_partner_customer_chat_send_lane_v67", {
        p_token: token,
        p_lane: lane,
        p_message: message || null,
        p_attachment: attachment,
      });
      $("#rr67Text").value = "";
      attachment = null;
      flash("Message sent ✓");
      await loadMessages();
    } catch (x) {
      flash(x.message);
    }
  }
  async function record() {
    if (recorder?.state === "recording") {
      recorder.stop();
      return;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      parts = [];
      started = Date.now();
      recorder = new MediaRecorder(stream);
      recorder.ondataavailable = (e) => {
        if (e.data.size) parts.push(e.data);
      };
      recorder.onstop = async () => {
        const blob = new Blob(parts, {
            type: recorder.mimeType || "audio/webm",
          }),
          file = new File([blob], `voice-${Date.now()}.webm`, {
            type: blob.type,
          });
        try {
          attachment = await fileData(file);
          attachment.duration = Math.max(
            1,
            Math.round((Date.now() - started) / 1000),
          );
          flash("Voice ready · send arrow दबाएँ");
        } catch (e) {
          flash(e.message);
        }
        stream.getTracks().forEach((t) => t.stop());
        recorder = null;
        $("#rr67Mic").textContent = "🎙";
      };
      recorder.start();
      $("#rr67Mic").textContent = "■";
      flash("Recording…");
    } catch (e) {
      flash(
        e.name === "NotAllowedError" ? "Mic permission Allow करें." : e.message,
      );
    }
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
    setTimeout(refreshMetrics, 900);
  }
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();
