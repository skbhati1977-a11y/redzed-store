(() => {
  "use strict";

  const params = new URLSearchParams(location.search);
  const requested = String(params.get("dept") || "").trim().toUpperCase();
  const label = String(params.get("label") || requested || "UNIVERSAL PRODUCTION").trim();
  if (!requested) return;

  const aliases = {
    CUTTING: ["CUTTING", "CUT"], PRINTING: ["PRINTING", "PRINT"],
    STICKER: ["STICKER", "STICKER_WORK"], ID: ["ID", "ID_WORK", "IDENTITY"],
    KR: ["STITCHING", "KARIGAR", "KR"], OVERLOCK: ["OVERLOCK", "OV"],
    FOLDING: ["FOLDING", "FLD", "FLATLOCK"],
    KAAJ_BUTTON: ["KAAJ_BUTTON", "KAAJ", "KAJ", "BUTTON", "BTN"],
    TEAK_TANKI: ["TEAK_TANKI", "TEAK", "TACK", "TANKI"],
    THREAD_CUT: ["THREAD_CUT", "THREAD_CUTTING", "TH_CUT"],
    QC: ["QC", "CHECKING", "QUALITY_CHECK"], PRESS: ["PRESS", "FINISHING"],
    PACKING: ["PACKING", "PACK"], DESPATCH: ["DESPATCH", "DISPATCH"]
  };
  const route = ["CUTTING", "PRINTING", "STICKER", "ID", "KR", "OVERLOCK", "FOLDING", "KAAJ_BUTTON", "TEAK_TANKI", "THREAD_CUT", "QC", "PRESS", "PACKING", "DESPATCH"];
  const accepted = aliases[requested] || [requested];
  const cache = new Map();
  const lastSubmitCache = new Map();
  let filterMode = "submit";
  const upper = value => String(value || "").trim().toUpperCase();
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const canonical = code => route.find(key => (aliases[key] || [key]).includes(upper(code))) || upper(code);
  const matchesCurrent = code => accepted.includes(upper(code)) || canonical(code) === requested;
  const client = () => window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;

  async function statusFor(lot) {
    const lotId = typeof lot === "string" ? lot : lot?.canonical_lot_id;
    const fallback = typeof lot === "object" ? (lot.__boardMeta || {}) : {};
    const old = cache.get(lotId);
    if (old && Date.now() - old.at < 2500) return old.data;
    const sb = client();
    if (!sb) return fallback;
    const { data, error } = await sb.rpc("rr_upm_board_lot_status_v743", { p_canonical_lot_id: lotId });
    if (error) {
      console.warn("Queue live status fallback", lotId, error);
      cache.set(lotId, { data: fallback, at: Date.now() });
      return fallback;
    }
    cache.set(lotId, { data: data || {}, at: Date.now() });
    return data || {};
  }

  async function lastSubmittedDepartment(lot) {
    const lotId = typeof lot === "string" ? lot : lot?.canonical_lot_id;
    const fallbackStatuses = (typeof lot === "object" ? lot.__boardMeta?.department_statuses : []) || [];
    const fallbackLast = fallbackStatuses
      .filter(row => row.submitted_at || row.last_submitted_at || row.status === "SUBMITTED")
      .sort((a, b) => String(b.submitted_at || b.last_submitted_at || "").localeCompare(String(a.submitted_at || a.last_submitted_at || "")))[0];
    const old = lastSubmitCache.get(lotId);
    if (old && Date.now() - old.at < 2500) return old.code;
    const sb = client();
    if (!sb) return canonical(fallbackLast?.department_code || "");
    const { data, error } = await sb.from("rr_upm_dynamic_submit_history_v741")
      .select("department_code,submitted_at")
      .eq("canonical_lot_id", lotId)
      .order("submitted_at", { ascending: false })
      .limit(1);
    if (error) {
      console.warn("Queue last-submitted fallback", lotId, error);
      const code = canonical(fallbackLast?.department_code || "");
      lastSubmitCache.set(lotId, { code, at: Date.now() });
      return code;
    }
    const code = canonical(data?.[0]?.department_code || "");
    lastSubmitCache.set(lotId, { code, at: Date.now() });
    return code;
  }

  function activeInCurrent(statuses) {
    const row = statuses.find(s => matchesCurrent(s.department_code));
    return (row?.assigned_codes?.length || 0) + (row?.running_codes?.length || 0) > 0;
  }

  function lockDepartment() {
    const select = document.getElementById("homeDept");
    if (!select?.options?.length) return;
    const option = [...select.options].find(o => matchesCurrent(o.value) || matchesCurrent(o.textContent));
    if (!option) return;
    if (select.value !== option.value) {
      select.value = option.value;
      select.dispatchEvent(new Event("change", { bubbles: true }));
    }
    select.disabled = true;
  }

  function openAction(card, targetId) {
    card.querySelector("[data-open-lot]")?.click();
    let tries = 0;
    const timer = setInterval(() => {
      const target = document.getElementById(targetId);
      const traveller = document.getElementById("traveller");
      if (target && traveller && !traveller.classList.contains("hidden")) {
        clearInterval(timer);
        target.scrollIntoFilter({ behavior: "smooth", block: "center" });
      } else if (++tries > 40) clearInterval(timer);
    }, 100);
  }

  function enhanceRunningCards() {
    document.querySelectorAll(".lot-card").forEach(card => {
      if (card.querySelector(".rf-card-actions")) return;
      const old = card.querySelector(".checkin");
      if (old) old.hidden = true;
      const actions = document.createElement("div");
      actions.className = "rf-card-actions";
      actions.innerHTML = '<button type="button" data-rf-action="alter">RECTIFICATION</button><button type="button" data-rf-action="submit">SUBMIT DUE</button>';
      actions.onclick = event => {
        event.stopPropagation();
        const action = event.target.closest("[data-rf-action]")?.dataset.rfAction;
        if (action) openAction(card, action === "submit" ? "submitBtn" : "alterBtn");
      };
      card.append(actions);
    });
  }

  async function filterRunningCards() {
    const cards = [...document.querySelectorAll(".lot-card[data-lot]")];
    await Promise.all(cards.map(async card => {
      card.classList.add("rf-running-hidden");
      try {
        const meta = await statusFor(card.dataset.lot);
        if (!activeInCurrent(meta.department_statuses || [])) return card.remove();
        card.classList.remove("rf-running-hidden");
      } catch (error) { card.remove(); }
    }));
    const count = String(document.querySelectorAll(".lot-card[data-lot]:not(.rf-running-hidden)").length);
    document.getElementById("rfSubmitDueCount")?.replaceChildren(document.createTextNode(count));
    document.getElementById("rfSubmitDueCountTop")?.replaceChildren(document.createTextNode(count));
  }

  function specialChoice(identity) {
    const text = upper([identity?.work_type, identity?.print_work_type, identity?.decoration_type, identity?.selected_department_code, identity?.print_department_code].filter(Boolean).join(" "));
    if (text.includes("STICKER")) return "STICKER";
    if (/\bID\b|IDENTITY/.test(text)) return "ID";
    if (text.includes("PRINT")) return "PRINTING";
    return "";
  }

  function eligibleTargets(departments, identity, lastSubmitted) {
    const special = specialChoice(identity);
    return departments.map(d => ({ ...d, canonical: canonical(d.department_code) })).filter(d => {
      if (!route.includes(d.canonical) || d.canonical === "CUTTING" || d.canonical === lastSubmitted) return false;
      if (["PRINTING", "STICKER", "ID"].includes(d.canonical) && special && d.canonical !== special) return false;
      return d.is_active !== false && upper(d.department_type || "PRODUCTION") === "PRODUCTION";
    }).sort((a, b) => route.indexOf(a.canonical) - route.indexOf(b.canonical));
  }

  async function chooseTarget(lotId, target) {
    const currentRank = route.indexOf(requested);
    const targetRank = route.indexOf(target.canonical);
    if (targetRank < currentRank) {
      const ok = confirm(`WARNING: ${target.department_name || target.department_code} production order में ${label} से ऊपर है. क्या आप फिर भी इस Lot को वहाँ Assign करने के लिए खोलना चाहते हैं?`);
      if (!ok) return;
    }
    try {
      await window.RealFactoryUPM.openLotAtDepartment(lotId, target.department_code);
      document.getElementById("selectAllBtn")?.scrollIntoFilter({ behavior: "smooth", block: "center" });
    } catch (error) { alert(error?.message || error); }
  }

  async function renderQueue() {
    const api = window.RealFactoryUPM;
    const host = document.getElementById("rfDepartmentQueue");
    if (!host) return;
    if (!api?.snapshot) {
      host.innerHTML = `<div class="msg">UPM engine loading. Queue 1 second me retry hogi.</div>`;
      setTimeout(sync, 1000);
      return;
    }
    const snap = api.snapshot();
    if (!snap.lots?.length) {
      host.innerHTML = `<div class="msg">No UPM lots loaded. TEST source me released/running/open lot rows verify karein.</div>`;
      return;
    }
    const cards = [];
    let dueTargets = 0;
    for (const lot of snap.lots) {
      const meta = await statusFor(lot);
      const statuses = meta.department_statuses || [];
      const active = new Set(statuses.flatMap(s => [...(s.assigned_codes || []), ...(s.running_codes || [])]));
      const total = Math.max(0, ...statuses.map(s => Number(s.total_colours || 0)), Array.isArray(lot.colours) ? lot.colours.length : 0);
      if (total > 0 && active.size >= total) continue;
      const lastSubmitted = await lastSubmittedDepartment(lot);
      const targets = eligibleTargets(snap.departments, meta.identity || {}, lastSubmitted)
        .filter(target => target.canonical === requested || matchesCurrent(target.department_code) || matchesCurrent(target.department_name));
      if (!targets.length) continue;
      dueTargets += targets.length;
      cards.push(`<article class="rf-queue-card"><div><b>${esc(lot.lot_no)}</b><span>CB ${esc(meta.identity?.cb_no || lot.cb_no || "—")} · ART ${esc(meta.identity?.art_no || lot.art_no || "—")}</span></div><p class="rf-worker-rule">ASSIGN DUE · एक या multiple Colours select · हर Colour की सभी Sizes एक Worker</p><div class="rf-due-column-head"><span>Department</span><span>Assign Due</span><span>Submit Due</span></div><div class="rf-route-chart">${targets.map(t => `<button type="button" data-lot="${esc(lot.canonical_lot_id)}" data-dept="${esc(t.department_code)}" class="${route.indexOf(t.canonical) >= route.indexOf(requested) ? "rf-direct" : "rf-warning"}"><b>${esc(t.department_name || t.canonical)}</b><small>${route.indexOf(t.canonical) >= route.indexOf(requested) ? "ASSIGN DUE · SELECT COLOURS" : "⚠ WARNING ASSIGN DUE"}</small><em>Submit Due after worker ready</em></button>`).join("")}</div></article>`);
    }
    document.getElementById("rfAssignDueCount")?.replaceChildren(document.createTextNode(String(dueTargets)));
    document.getElementById("rfAssignDueCountTop")?.replaceChildren(document.createTextNode(String(dueTargets)));
    host.innerHTML = cards.join("") || `<div class="msg">No ASSIGN DUE lots available for ${esc(label)}. Agar Universal page me lots dikh rahe hain to current department/last submitted mapping verify karein.</div>`;
    host.querySelectorAll("[data-lot][data-dept]").forEach(button => button.onclick = () => {
      const department = snap.departments.find(d => upper(d.department_code) === upper(button.dataset.dept));
      if (department) chooseTarget(button.dataset.lot, { ...department, canonical: canonical(department.department_code) });
    });
  }

  function setMode(mode) {
    filterMode = mode === "submit" ? "submit" : "assign";
    document.querySelectorAll("[data-rf-due-mode]").forEach(button => {
      button.classList.toggle("active", button.dataset.rfDueMode === filterMode);
    });
    const board = document.getElementById("board");
    const queue = document.querySelector(".rf-queue-section");
    if (board) board.classList.toggle("hidden", filterMode !== "submit");
    if (queue) queue.classList.toggle("hidden", filterMode !== "assign" || requested === "CUTTING");
    if (filterMode === "assign") document.getElementById("rfDepartmentQueue")?.scrollIntoFilter({ behavior: "smooth", block: "start" });
  }

  function applyShell() {
    document.title = `REAL FACTORY — ${label} Dashboard`;
    document.querySelector(".top small.art-no").textContent = "REAL FACTORY · UPM";
    document.querySelector(".top h1").textContent = `${label} Dashboard`;
    const board = document.getElementById("board");
    const toolbar = document.createElement("section");
    toolbar.className = "rf-due-toolbar";
    toolbar.innerHTML = `<button type="button" data-rf-due-mode="submit" class="active">SUBMIT DUE <b id="rfSubmitDueCountTop">0</b></button><button type="button" data-rf-due-mode="assign">ASSIGN DUE <b id="rfAssignDueCountTop">0</b></button>`;
    board?.insertAdjacentElement("beforebegin", toolbar);
    const section = document.createElement("section");
    section.className = "rf-queue-section";
    section.innerHTML = `<div class="rf-queue-title"><div><h2>ASSIGN DUE</h2><p>Assign due work list.</p></div><span>Assign Due <b id="rfAssignDueCount">0</b> · Submit Due running cards/header से</span></div><div id="rfDepartmentQueue"></div>`;
    if (requested === "CUTTING") section.classList.add("hidden");
    board?.insertAdjacentElement("afterend", section);
    toolbar.querySelectorAll("[data-rf-due-mode]").forEach(button => button.onclick = () => setMode(button.dataset.rfDueMode));
  }

  const style = document.createElement("style");
  style.textContent = `.rf-running-hidden{display:none!important}.rf-due-toolbar{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:12px 16px}.rf-due-toolbar button{min-height:48px;border:1px solid #303641;background:#202635;color:#fff;border-radius:10px;font-weight:950}.rf-due-toolbar button.active{background:#d43d5e;border-color:#ff6b8a}.rf-due-toolbar b{margin-left:6px;color:#2bf6a2}.rf-card-actions{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:8px;margin-top:auto}.rf-card-actions button{width:100%;min-height:46px}.rf-card-actions button:first-child{background:#174936;border-color:#318b65}.rf-card-actions button:last-child{background:#493915;border-color:#8a6b2b}.rf-queue-section{margin-top:18px;border-top:2px solid #303641;padding:14px 16px 0}.rf-queue-title{display:flex;gap:10px;align-items:center;justify-content:space-between}.rf-queue-title h2{margin:0;color:#ffc857}.rf-queue-title p{margin:4px 0 0;color:#9ec5ff;font-weight:750}.rf-queue-title span{color:#98a2b3}.rf-queue-title b{color:#2bf6a2}.rf-queue-card{background:#12151c;border:1px solid #303641;border-radius:14px;padding:12px;margin-top:10px}.rf-queue-card>div:first-child{display:flex;justify-content:space-between;gap:10px}.rf-queue-card>div:first-child span{color:#98a2b3}.rf-worker-rule{margin:8px 0 0;color:#9ec5ff;font-weight:750}.rf-due-column-head{display:grid;grid-template-columns:1fr 1fr 1fr;gap:7px;margin-top:10px;color:#ffc857;font-size:11px;font-weight:900;text-transform:uppercase}.rf-due-column-head span{background:#080a0f;border:1px solid #303641;border-radius:8px;padding:7px;text-align:center}.rf-route-chart{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:7px;margin-top:7px}.rf-route-chart button{width:100%;min-height:68px}.rf-route-chart b{display:block}.rf-route-chart small{display:block;margin-top:4px;font-size:9px}.rf-route-chart em{display:block;margin-top:3px;color:#cbd5e1;font-size:9px;font-style:normal}.rf-direct{border-color:#318b65;background:#174936}.rf-warning{border-color:#8a6b2b;background:#493915}@media(max-width:700px){.rf-queue-title,.rf-queue-card>div:first-child{align-items:flex-start;flex-direction:column}.rf-route-chart{grid-template-columns:1fr 1fr}}@media(max-width:520px){.rf-due-toolbar,.rf-route-chart{grid-template-columns:1fr}.rf-due-column-head{grid-template-columns:1fr}}`;
  document.head.append(style);
  applyShell();

  let timer;
  const sync = () => {
    lockDepartment();
    enhanceRunningCards();
    clearTimeout(timer);
    timer = setTimeout(async () => {
      try {
        await filterRunningCards();
        await renderQueue();
        setMode(filterMode);
      } catch (error) {
        const host = document.getElementById("rfDepartmentQueue");
        if (host) host.innerHTML = `<div class="msg">ASSIGN DUE load failed: ${esc(error?.message || error)}</div>`;
      }
    }, 80);
  };
  new MutationObserver(mutations => {
    if (mutations.every(mutation => mutation.target.closest?.("#rfDepartmentQueue"))) return;
    sync();
  }).observe(document.body, { childList: true, subtree: true });
  sync();
  setTimeout(sync, 1000);
  setMode("submit");
  console.info("REAL FACTORY V875 · ASSIGN DUE MODAL CONTEXT SOURCE");
})();
