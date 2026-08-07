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
  const upper = value => String(value || "").trim().toUpperCase();
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const canonical = code => route.find(key => (aliases[key] || [key]).includes(upper(code))) || upper(code);
  const matchesCurrent = code => accepted.includes(upper(code)) || canonical(code) === requested;
  const client = () => window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;

  async function statusFor(lotId) {
    const old = cache.get(lotId);
    if (old && Date.now() - old.at < 2500) return old.data;
    // Reuse the base board's already-resolved metadata. Do not make a second
    // hard dependency on the optional v743 status RPC: some deployments do
    // not expose it, while the canonical Lot board itself remains available.
    const snap = window.RealFactoryUPM?.snapshot?.();
    const resolved = snap?.boardMeta?.find(row => row.canonical_lot_id === lotId)?.meta;
    const data = resolved && Object.keys(resolved).length
      ? resolved
      : { department_statuses: [], identity: {}, status_unavailable: true };
    cache.set(lotId, { data, at: Date.now() });
    return data;
  }

  async function lastSubmittedDepartment(lotId) {
    const old = lastSubmitCache.get(lotId);
    if (old && Date.now() - old.at < 2500) return old.code;
    const sb = client();
    if (!sb) throw new Error("Production client unavailable.");
    const { data, error } = await sb.from("rr_upm_dynamic_submit_history_v741")
      .select("department_code,submitted_at")
      .eq("canonical_lot_id", lotId)
      .order("submitted_at", { ascending: false })
      .limit(1);
    if (error) {
      console.warn("Last submitted department unavailable", lotId, error);
      lastSubmitCache.set(lotId, { code: "", at: Date.now() });
      return "";
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
    const traveller = document.getElementById("traveller");
    if (traveller) {
      traveller.classList.remove("rf-smart-assign", "rf-smart-submit");
      if (targetId === "submitBtn") traveller.classList.add("rf-smart-submit");
    }
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
        if (meta.status_unavailable) return card.classList.remove("rf-running-hidden");
        if (!activeInCurrent(meta.department_statuses || [])) return card.remove();
        card.classList.remove("rf-running-hidden");
      } catch (error) {
        console.warn("Running status unavailable; keeping Lot card", card.dataset.lot, error);
        card.classList.remove("rf-running-hidden");
      }
    }));
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
      if (!route.includes(d.canonical) || d.canonical === "CUTTING") return false;
      // A department may be both the last submit point and the current screen
      // after a reopen/return. In that case it must remain assignable here.
      if (d.canonical === lastSubmitted && d.canonical !== requested) return false;
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
      const traveller = document.getElementById("traveller");
      traveller?.classList.remove("rf-smart-submit");
      traveller?.classList.add("rf-smart-assign");
      await window.RealFactoryUPM.openLotAtDepartment(lotId, target.department_code);
      document.getElementById("selectAllBtn")?.focus();
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
      // Activity in other departments must not suppress the whole Lot from
      // this routing view. The claim RPC validates selected colours on action.
      const lastSubmitted = await lastSubmittedDepartment(lot.canonical_lot_id);
      const targets = eligibleTargets(snap.departments, meta.identity || {}, lastSubmitted);
      if (!targets.length) continue;
      cards.push(`<article class="rf-queue-card"><div><b>${esc(lot.lot_no)}</b><span>CB ${esc(meta.identity?.cb_no || lot.cb_no || "—")} · ART ${esc(meta.identity?.art_no || lot.art_no || "—")}</span></div><p class="rf-worker-rule">एक या multiple Colours select · हर Colour की सभी Sizes एक Worker</p><div class="rf-route-chart">${targets.map(t => `<button type="button" data-lot="${esc(lot.canonical_lot_id)}" data-dept="${esc(t.department_code)}" class="${route.indexOf(t.canonical) >= route.indexOf(requested) ? "rf-direct" : "rf-warning"}">${esc(t.department_name || t.canonical)}<small>${route.indexOf(t.canonical) >= route.indexOf(requested) ? "ASSIGN SELECTED COLOURS" : "⚠ WARNING ASSIGN"}</small></button>`).join("")}</div></article>`);
    }
    host.innerHTML = cards.join("") || `<div class="msg">No OPEN RANDOM QUEUE lots available for ${esc(label)}.</div>`;
    host.querySelectorAll("[data-lot][data-dept]").forEach(button => button.onclick = () => {
      const department = snap.departments.find(d => upper(d.department_code) === upper(button.dataset.dept));
      if (department) chooseTarget(button.dataset.lot, { ...department, canonical: canonical(department.department_code) });
    });
  }

  function applyShell() {
    document.title = `REAL FACTORY — ${label} Dashboard`;
    const shellBrand = document.querySelector(".page > .top small.art-no");
    const shellTitle = document.querySelector(".page > .top h1");
    if (shellBrand) shellBrand.textContent = "REAL FACTORY · UPM";
    if (shellTitle) shellTitle.textContent = `${label} Dashboard`;
    const board = document.getElementById("board");
    const section = document.createElement("section");
    section.className = "rf-queue-section";
    section.innerHTML = `<div class="rf-queue-title"><h2>OPEN RANDOM QUEUE</h2><span>Cutting अलग flow · केवल Last Submitted Department hidden · Current Department visible</span></div><div id="rfDepartmentQueue"></div>`;
    if (requested === "CUTTING") section.classList.add("hidden");
    board?.insertAdjacentElement("afterend", section);
  }

  const style = document.createElement("style");
  style.textContent = `.rf-running-hidden{display:none!important}.rf-card-actions{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:8px;margin-top:auto}.rf-card-actions button{width:100%;min-height:46px}.rf-card-actions button:first-child{background:#174936;border-color:#318b65}.rf-card-actions button:last-child{background:#493915;border-color:#8a6b2b}.rf-queue-section{margin-top:18px;border-top:2px solid #303641;padding-top:14px}.rf-queue-title{display:flex;gap:10px;align-items:center;justify-content:space-between}.rf-queue-title h2{margin:0;color:#ffc857}.rf-queue-title span{color:#98a2b3}.rf-queue-card{background:#12151c;border:1px solid #303641;border-radius:14px;padding:12px;margin-top:10px}.rf-queue-card>div:first-child{display:flex;justify-content:space-between;gap:10px}.rf-queue-card>div:first-child span{color:#98a2b3}.rf-worker-rule{margin:8px 0 0;color:#9ec5ff;font-weight:750}.rf-route-chart{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:7px;margin-top:10px}.rf-route-chart button{width:100%;min-height:58px}.rf-route-chart small{display:block;margin-top:4px;font-size:9px}.rf-direct{border-color:#318b65;background:#174936}.rf-warning{border-color:#8a6b2b;background:#493915}
  #traveller.rf-smart-assign,#traveller.rf-smart-submit{align-items:center;padding:10px}
  #traveller.rf-smart-assign .sheet,#traveller.rf-smart-submit .sheet{width:min(430px,96vw);height:auto;max-height:92dvh;border-radius:20px;padding:14px;overscroll-behavior:contain}
  #traveller.rf-smart-assign .sticky,#traveller.rf-smart-submit .sticky{position:sticky;top:-14px;padding:8px 0 10px}
  #traveller.rf-smart-assign .sticky #identity,#traveller.rf-smart-submit .sticky #identity{display:none!important}
  #traveller.rf-smart-assign .sticky .top,#traveller.rf-smart-submit .sticky .top{min-height:46px}
  #traveller.rf-smart-assign .sticky [data-close],#traveller.rf-smart-submit .sticky [data-close]{min-width:76px;min-height:44px}
  #traveller.rf-smart-assign .sticky h2{font-size:0}#traveller.rf-smart-assign .sticky h2:after{content:'SMART ASSIGN';font-size:20px}
  #traveller.rf-smart-submit .sticky h2{font-size:0}#traveller.rf-smart-submit .sticky h2:after{content:'SMART SUBMIT';font-size:20px}
  #traveller.rf-smart-assign #entryThumbs,#traveller.rf-smart-assign #summary,#traveller.rf-smart-assign #freezeSummary,#traveller.rf-smart-assign .legend,#traveller.rf-smart-assign #routeNote,#traveller.rf-smart-assign .actions,#traveller.rf-smart-assign .debug,#traveller.rf-smart-assign #stdWrap,#traveller.rf-smart-assign #marginWrap,#traveller.rf-smart-assign .formbar .field:first-child{display:none!important}
  #traveller.rf-smart-assign .formbar{display:block;margin:2px 0 10px}
  #traveller.rf-smart-assign .formbar .field:nth-child(2){display:block!important}
  #traveller.rf-smart-assign .formbar input{width:100%;min-height:50px;font-size:17px}
  #traveller.rf-smart-assign .colour-card.assigned,#traveller.rf-smart-assign .colour-card.waiting,#traveller.rf-smart-assign .colour-card.done{display:none!important}
  #traveller.rf-smart-assign .colour-card .size-wrap,#traveller.rf-smart-assign .colour-card .colour-meta,#traveller.rf-smart-assign .worker-block label:nth-child(2){display:none!important}
  #traveller.rf-smart-assign .bulk-assign{position:static;display:flex!important;flex-direction:column;align-items:stretch;gap:9px;margin:0;padding:11px}
  #traveller.rf-smart-assign .bulk-assign>*{width:100%;min-height:52px}
  #traveller.rf-smart-assign .bulk-assign label{display:flex;flex-direction:column;min-height:auto;font-size:12px}
  #traveller.rf-smart-assign .bulk-assign select{min-height:52px;font-size:16px}
  #traveller.rf-smart-assign #assignBtn{min-height:58px;font-size:15px}
  #traveller.rf-smart-submit .formbar,#traveller.rf-smart-submit #entryThumbs,#traveller.rf-smart-submit #summary,#traveller.rf-smart-submit #freezeSummary,#traveller.rf-smart-submit .legend,#traveller.rf-smart-submit .bulk-assign,#traveller.rf-smart-submit #routeNote,#traveller.rf-smart-submit .debug{display:none!important}
  #traveller.rf-smart-submit .colour-card:not(.assigned){display:none!important}
  #traveller.rf-smart-submit .colour-card .worker-block,#traveller.rf-smart-submit .colour-card .size-wrap{display:none!important}
  #traveller.rf-smart-submit .actions{position:sticky;bottom:-14px;padding:10px 0 0}
  #traveller.rf-smart-submit .actions button{display:none!important}#traveller.rf-smart-submit .actions #submitBtn{display:block!important;width:100%;min-height:58px;font-size:15px}
  #traveller.rf-smart-assign .colour-list,#traveller.rf-smart-submit .colour-list{max-height:38dvh;overflow:auto}
  #traveller.rf-smart-assign .colour-card,#traveller.rf-smart-submit .colour-card{border-radius:12px}
  #traveller.rf-smart-assign .colour-head,#traveller.rf-smart-submit .colour-head{padding:10px}
  @media(max-width:700px){.rf-queue-title,.rf-queue-card>div:first-child{align-items:flex-start;flex-direction:column}.rf-route-chart{grid-template-columns:1fr 1fr}#traveller.rf-smart-assign,#traveller.rf-smart-submit{align-items:flex-end;padding:0}#traveller.rf-smart-assign .sheet,#traveller.rf-smart-submit .sheet{width:100%;max-height:94dvh;border-radius:20px 20px 0 0;padding:12px 12px calc(12px + env(safe-area-inset-bottom))}}
  @media(max-width:420px){.rf-route-chart{grid-template-columns:1fr}#traveller.rf-smart-assign .sticky h2:after,#traveller.rf-smart-submit .sticky h2:after{font-size:18px}}`;
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
  console.info("REAL FACTORY V797.9 · V796 BASELINE + RANDOM QUEUE CONTRACT RESTORED");
})();
