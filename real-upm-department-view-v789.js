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
  const upper = value => String(value || "").trim().toUpperCase();
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const canonical = code => route.find(key => (aliases[key] || [key]).includes(upper(code))) || upper(code);
  const matchesCurrent = code => accepted.includes(upper(code)) || canonical(code) === requested;
  const client = () => window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;

  async function statusFor(lotId) {
    const old = cache.get(lotId);
    if (old && Date.now() - old.at < 2500) return old.data;
    const sb = client();
    if (!sb) throw new Error("Production client unavailable.");
    const { data, error } = await sb.rpc("rr_upm_board_lot_status_v743", { p_canonical_lot_id: lotId });
    if (error) throw error;
    cache.set(lotId, { data: data || {}, at: Date.now() });
    return data || {};
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
        target.scrollIntoView({ behavior: "smooth", block: "center" });
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
      actions.innerHTML = '<button type="button" data-rf-action="alter">ALTER</button><button type="button" data-rf-action="submit">READY TO SUBMIT</button>';
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
  }

  function specialChoice(identity) {
    const text = upper([identity?.work_type, identity?.print_work_type, identity?.decoration_type, identity?.selected_department_code, identity?.print_department_code].filter(Boolean).join(" "));
    if (text.includes("STICKER")) return "STICKER";
    if (/\bID\b|IDENTITY/.test(text)) return "ID";
    if (text.includes("PRINT")) return "PRINTING";
    return "";
  }

  function eligibleTargets(departments, statuses, identity) {
    const submitted = new Set(statuses.filter(s => (s.submitted_codes?.length || 0) > 0).map(s => canonical(s.department_code)));
    const special = specialChoice(identity);
    return departments.map(d => ({ ...d, canonical: canonical(d.department_code) })).filter(d => {
      if (!route.includes(d.canonical) || d.canonical === "CUTTING" || d.canonical === requested || submitted.has(d.canonical)) return false;
      if (["PRINTING", "STICKER", "ID"].includes(d.canonical) && special && d.canonical !== special) return false;
      return d.is_active !== false && upper(d.department_type || "PRODUCTION") === "PRODUCTION";
    }).sort((a, b) => route.indexOf(a.canonical) - route.indexOf(b.canonical));
  }

  async function chooseTarget(lotId, target) {
    const currentRank = route.indexOf(requested);
    const targetRank = route.indexOf(target.canonical);
    if (targetRank <= currentRank) {
      const ok = confirm(`WARNING: ${target.department_name || target.department_code} production order में ${label} से ऊपर है. क्या आप फिर भी इस Lot को वहाँ Assign करने के लिए खोलना चाहते हैं?`);
      if (!ok) return;
    }
    try {
      await window.RealFactoryUPM.openLotAtDepartment(lotId, target.department_code);
      document.getElementById("selectAllBtn")?.scrollIntoView({ behavior: "smooth", block: "center" });
    } catch (error) { alert(error?.message || error); }
  }

  async function renderQueue() {
    const api = window.RealFactoryUPM;
    const host = document.getElementById("rfDepartmentQueue");
    if (!api || !host) return;
    const snap = api.snapshot();
    const cards = [];
    for (const lot of snap.lots) {
      const meta = await statusFor(lot.canonical_lot_id);
      const statuses = meta.department_statuses || [];
      const active = new Set(statuses.flatMap(s => [...(s.assigned_codes || []), ...(s.running_codes || [])]));
      const total = Math.max(0, ...statuses.map(s => Number(s.total_colours || 0)), Array.isArray(lot.colours) ? lot.colours.length : 0);
      if (total > 0 && active.size >= total) continue;
      const targets = eligibleTargets(snap.departments, statuses, meta.identity || {});
      if (!targets.length) continue;
      cards.push(`<article class="rf-queue-card"><div><b>${esc(lot.lot_no)}</b><span>CB ${esc(meta.identity?.cb_no || lot.cb_no || "—")} · ART ${esc(meta.identity?.art_no || lot.art_no || "—")}</span></div><p class="rf-worker-rule">एक या multiple Colours select · हर Colour की सभी Sizes एक Worker</p><div class="rf-route-chart">${targets.map(t => `<button type="button" data-lot="${esc(lot.canonical_lot_id)}" data-dept="${esc(t.department_code)}" class="${route.indexOf(t.canonical) > route.indexOf(requested) ? "rf-direct" : "rf-warning"}">${esc(t.department_name || t.canonical)}<small>${route.indexOf(t.canonical) > route.indexOf(requested) ? "ASSIGN SELECTED COLOURS" : "⚠ WARNING ASSIGN"}</small></button>`).join("")}</div></article>`);
    }
    host.innerHTML = cards.join("") || `<div class="msg">No OPEN RANDOM QUEUE lots available for ${esc(label)}.</div>`;
    host.querySelectorAll("[data-lot][data-dept]").forEach(button => button.onclick = () => {
      const department = snap.departments.find(d => upper(d.department_code) === upper(button.dataset.dept));
      if (department) chooseTarget(button.dataset.lot, { ...department, canonical: canonical(department.department_code) });
    });
  }

  function applyShell() {
    document.title = `REAL FACTORY — ${label} Dashboard`;
    document.querySelector(".top small.art-no").textContent = "REAL FACTORY · UPM";
    document.querySelector(".top h1").textContent = `${label} Dashboard`;
    const board = document.getElementById("board");
    const section = document.createElement("section");
    section.className = "rf-queue-section";
    section.innerHTML = `<div class="rf-queue-title"><h2>OPEN RANDOM QUEUE</h2><span>Cutting अलग flow · Submitted/current hidden · नीचे Direct · ऊपर Warning</span></div><div id="rfDepartmentQueue"></div>`;
    if (requested === "CUTTING") section.classList.add("hidden");
    board?.insertAdjacentElement("afterend", section);
  }

  const style = document.createElement("style");
  style.textContent = `.rf-running-hidden{display:none!important}.rf-card-actions{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:8px;margin-top:auto}.rf-card-actions button{width:100%;min-height:46px}.rf-card-actions button:first-child{background:#174936;border-color:#318b65}.rf-card-actions button:last-child{background:#493915;border-color:#8a6b2b}.rf-queue-section{margin-top:18px;border-top:2px solid #303641;padding-top:14px}.rf-queue-title{display:flex;gap:10px;align-items:center;justify-content:space-between}.rf-queue-title h2{margin:0;color:#ffc857}.rf-queue-title span{color:#98a2b3}.rf-queue-card{background:#12151c;border:1px solid #303641;border-radius:14px;padding:12px;margin-top:10px}.rf-queue-card>div:first-child{display:flex;justify-content:space-between;gap:10px}.rf-queue-card>div:first-child span{color:#98a2b3}.rf-worker-rule{margin:8px 0 0;color:#9ec5ff;font-weight:750}.rf-route-chart{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:7px;margin-top:10px}.rf-route-chart button{width:100%;min-height:58px}.rf-route-chart small{display:block;margin-top:4px;font-size:9px}.rf-direct{border-color:#318b65;background:#174936}.rf-warning{border-color:#8a6b2b;background:#493915}@media(max-width:700px){.rf-queue-title,.rf-queue-card>div:first-child{align-items:flex-start;flex-direction:column}.rf-route-chart{grid-template-columns:1fr 1fr}}@media(max-width:420px){.rf-route-chart{grid-template-columns:1fr}}`;
  document.head.append(style);
  applyShell();

  let timer;
  const sync = () => {
    lockDepartment();
    enhanceRunningCards();
    clearTimeout(timer);
    timer = setTimeout(async () => { await filterRunningCards(); await renderQueue(); }, 80);
  };
  new MutationObserver(mutations => {
    if (mutations.every(mutation => mutation.target.closest?.("#rfDepartmentQueue"))) return;
    sync();
  }).observe(document.body, { childList: true, subtree: true });
  sync();
})();
