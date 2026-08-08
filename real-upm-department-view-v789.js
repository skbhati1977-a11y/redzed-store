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
    PACKING: ["PACKING", "PACK"]
  };
  // Despatch is a separate stock/challan module. It must never be mounted in
  // the production assignment or submit queue.
  const route = ["CUTTING", "PRINTING", "STICKER", "ID", "KR", "OVERLOCK", "FOLDING", "KAAJ_BUTTON", "TEAK_TANKI", "THREAD_CUT", "QC", "PRESS", "PACKING"];
  const accepted = aliases[requested] || [requested];
  const cache = new Map();
  const lastSubmitCache = new Map();
  const runningCache = new Map();
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
  async function activeInThisDepartment(lotId) {
    const old = runningCache.get(lotId); if (old && Date.now()-old.at < 2500) return old.active;
    const {data,error}=await client().from("rr_upm_work_assignments_v8").select("id").eq("canonical_lot_id",lotId).in("department_code",accepted).in("status",["ASSIGNED","RUNNING","ACTIVE"]);
    if(error) throw error; const active=(data||[]).length>0; runningCache.set(lotId,{active,at:Date.now()}); return active;
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
        const active=meta.status_unavailable ? await activeInThisDepartment(card.dataset.lot) : activeInCurrent(meta.department_statuses || []);
        if (!active) return card.remove();
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


  const rfDiagRuntime = {
    loadedAt: new Date().toISOString(),
    lastError: "",
    lastRejection: "",
    lastQueueError: ""
  };
  window.addEventListener("error", event => {
    rfDiagRuntime.lastError = [event.message, event.filename, event.lineno && `line ${event.lineno}`].filter(Boolean).join(" · " );
  });
  window.addEventListener("unhandledrejection", event => {
    rfDiagRuntime.lastRejection = String(event.reason?.message || event.reason || "Unhandled promise rejection");
  });

  function diagRow(name, ok, value) {
    return `<div class="rf-screen-check ${ok ? "ok" : "bad"}"><b>${ok ? "PASS" : "FAIL"}</b><span>${esc(name)}</span><strong>${esc(value)}</strong></div>`;
  }

  async function runScreenDiagnostic() {
    const panel = document.getElementById("rfScreenErrorPanel");
    if (!panel) return;
    panel.classList.remove("hidden");
    panel.innerHTML = '<div class="rf-screen-error-head"><b>UPM SCREEN ERROR CHECK</b><span class="badge warn">CHECKING…</span></div><div class="msg">Reading screen, UPM snapshot and backend source availability…</div>';

    const checks = [];
    const api = window.RealFactoryUPM;
    const sb = client();
    const selectedDept = document.getElementById("homeDept")?.value || "";
    const frontMsg = (document.getElementById("message")?.textContent || "").trim();
    let snap = null;
    let snapError = "";
    try { snap = api?.snapshot?.() || null; } catch (e) { snapError = e?.message || String(e); }

    checks.push(["Diagnostic JS", true, "V798.8 SCREEN + POPUP"]);
    checks.push(["Requested Department", !!requested, requested || "MISSING"]);
    checks.push(["Home Department", matchesCurrent(selectedDept), selectedDept || "EMPTY"]);
    checks.push(["Supabase client", !!sb, sb ? "CONNECTED OBJECT FOUND" : "CLIENT MISSING"]);
    checks.push(["RealFactoryUPM API", !!api, api ? "LOADED" : "NOT LOADED"]);
    checks.push(["UPM snapshot", !!snap, snap ? "READABLE" : (snapError || "UNAVAILABLE")]);
    checks.push(["Snapshot Lots", (snap?.lots?.length || 0) > 0, String(snap?.lots?.length || 0)]);
    checks.push(["Snapshot Departments", (snap?.departments?.length || 0) > 0, String(snap?.departments?.length || 0)]);
    checks.push(["Main board cards", document.querySelectorAll(".lot-card[data-lot]").length > 0, String(document.querySelectorAll(".lot-card[data-lot]").length)]);
    checks.push(["Open Random Queue cards", document.querySelectorAll("#rfDepartmentQueue .rf-queue-card").length > 0, String(document.querySelectorAll("#rfDepartmentQueue .rf-queue-card").length)]);
    checks.push(["Queue assign buttons", document.querySelectorAll("#rfDepartmentQueue [data-lot][data-dept]").length > 0, String(document.querySelectorAll("#rfDepartmentQueue [data-lot][data-dept]").length)]);
    checks.push(["Last JS runtime error", !rfDiagRuntime.lastError, rfDiagRuntime.lastError || "NONE"]);
    checks.push(["Last promise rejection", !rfDiagRuntime.lastRejection, rfDiagRuntime.lastRejection || "NONE"]);
    checks.push(["Queue render error", !rfDiagRuntime.lastQueueError, rfDiagRuntime.lastQueueError || "NONE"]);

    const serverLines = [];
    if (sb) {
      try {
        const { data, error } = await sb.from("rr_upm_work_assignments_v8").select("canonical_lot_id,department_code,status").in("department_code", accepted).in("status", ["ASSIGNED","RUNNING","ACTIVE"]).limit(50);
        if (error) throw error;
        serverLines.push(`Active assignment rows for ${requested}: ${(data || []).length}`);
      } catch (e) { serverLines.push(`Assignments query ERROR: ${e?.message || e}`); }
      try {
        const { data, error } = await sb.from("rr_upm_dynamic_submit_history_v741").select("canonical_lot_id,department_code,submitted_at").order("submitted_at", { ascending:false }).limit(25);
        if (error) throw error;
        serverLines.push(`Recent submit-history rows readable: ${(data || []).length}`);
      } catch (e) { serverLines.push(`Submit-history query ERROR: ${e?.message || e}`); }
    }

    const failCount = checks.filter(([,ok]) => !ok).length;
    panel.innerHTML = `<div class="rf-screen-error-head"><b>UPM SCREEN ERROR CHECK</b><span class="badge ${failCount ? "bad" : "ok"}">${failCount ? failCount + " FAIL" : "ALL PASS"}</span></div>${checks.map(([n,o,v]) => diagRow(n,o,v)).join("")}<div class="rf-form-last"><small>Frontend message</small><div>${esc(frontMsg || "No frontend message")}</div></div><div class="rf-server-debug"><b>BACKEND READ CHECK</b><pre>${esc(serverLines.join("\n") || "Backend check unavailable.")}</pre></div><div class="rf-server-debug"><b>SCREEN URL</b><pre>${esc(location.href)}</pre></div>`;
  }

  function installScreenErrorCheck() {
    if (document.getElementById("rfScreenErrorCheckBtn")) return;
    const section = document.querySelector(".rf-queue-section");
    if (!section) return;
    const wrap = document.createElement("div");
    wrap.className = "rf-screen-error-wrap";
    wrap.innerHTML = '<button id="rfScreenErrorCheckBtn" class="warning" type="button">ERROR CHECK · SCREEN</button><section id="rfScreenErrorPanel" class="rf-screen-error-panel hidden"></section>';
    section.insertAdjacentElement("afterbegin", wrap);
    document.getElementById("rfScreenErrorCheckBtn").onclick = runScreenDiagnostic;
  }

  let smartAssignDiagnosticContext = null;

  function installSmartAssignErrorCheck() {
    const traveller = document.getElementById("traveller");
    const bulk = traveller?.querySelector(".bulk-assign");
    if (!traveller || !bulk || !traveller.classList.contains("rf-smart-assign")) return;

    let button = document.getElementById("rfSmartErrorCheckBtn");
    if (!button) {
      button = document.createElement("button");
      button.id = "rfSmartErrorCheckBtn";
      button.type = "button";
      button.className = "warning rf-error-check-btn";
      button.textContent = "ERROR CHECK · DIAGNOSE";
      const assign = document.getElementById("assignBtn");
      if (assign?.parentElement === bulk) bulk.insertBefore(button, assign);
      else bulk.appendChild(button);
    }

    let panel = document.getElementById("rfSmartErrorPanel");
    if (!panel) {
      panel = document.createElement("section");
      panel.id = "rfSmartErrorPanel";
      panel.className = "rf-error-panel hidden";
      const colours = document.getElementById("colours");
      colours?.insertAdjacentElement("afterend", panel);
    }

    button.onclick = async () => {
      panel.classList.remove("hidden");
      panel.innerHTML = '<div class="rf-error-head"><b>SMART ASSIGN ERROR CHECK</b><span class="badge warn">CHECKING…</span></div><div class="rf-error-lines">Running client + server diagnostics…</div>';

      const lotId = smartAssignDiagnosticContext?.lotId || "UNKNOWN";
      const dept = smartAssignDiagnosticContext?.departmentCode || document.getElementById("dept")?.value || "UNKNOWN";
      const cards = [...document.querySelectorAll("#colours .colour-card")];
      const assignableCards = cards.filter(card => card.querySelector(".assign-pick:not(:disabled)"));
      const sizeRows = document.querySelectorAll("#colours [data-row-index]").length;
      const workerSelect = document.getElementById("bulkWorker");
      const workerCount = workerSelect ? [...workerSelect.options].filter(o => o.value).length : 0;
      const formMsg = (document.getElementById("formMsg")?.textContent || "").trim();
      const noMapping = /No Colour\s*[×xX]\s*Size mapping found/i.test(document.getElementById("colours")?.textContent || "");

      const checks = [
        ["Lot context", lotId !== "UNKNOWN", lotId],
        ["Department", dept !== "UNKNOWN", dept],
        ["Colour cards", cards.length > 0, String(cards.length)],
        ["Assignable colours", assignableCards.length > 0, String(assignableCards.length)],
        ["Colour × Size rows", sizeRows > 0, String(sizeRows)],
        ["Workers in dropdown", workerCount > 0, String(workerCount)],
        ["Mapping message", !noMapping, noMapping ? "NO COLOUR × SIZE MAPPING" : "Mapping visible"],
      ];

      const lineHtml = checks.map(([name, ok, value]) => `<div class="rf-check ${ok ? "ok" : "bad"}"><b>${ok ? "PASS" : "FAIL"}</b><span>${esc(name)}</span><strong>${esc(value)}</strong></div>`).join("");
      panel.innerHTML = `<div class="rf-error-head"><b>SMART ASSIGN ERROR CHECK</b><span class="badge">${esc(label)}</span></div>${lineHtml}<div class="rf-form-last"><small>Current message</small><div>${esc(formMsg || "No frontend message")}</div></div><div class="rf-server-debug"><b>SERVER FLOW DEBUG</b><pre id="rfServerDebugText">Running rr_upm_debug_v740…</pre></div>`;

      try {
        const hiddenDebug = document.getElementById("debugBtn");
        if (hiddenDebug) {
          hiddenDebug.click();
          await new Promise(resolve => setTimeout(resolve, 900));
          const text = document.getElementById("debugOutput")?.textContent?.trim();
          document.getElementById("rfServerDebugText").textContent = text || "Server debug returned no visible output yet. Click ERROR CHECK once more after 1 second.";
        } else {
          document.getElementById("rfServerDebugText").textContent = "FAIL: Flow Debug button/function not found in this build.";
        }
      } catch (error) {
        document.getElementById("rfServerDebugText").textContent = `ERROR: ${error?.message || error}`;
      }
    };

    // Auto-surface the checker when the exact mapping failure is visible.
    if (/No Colour\s*[×xX]\s*Size mapping found/i.test(document.getElementById("colours")?.textContent || "")) {
      button.classList.add("rf-error-pulse");
      button.textContent = "ERROR CHECK · MAPPING FAILED";
    } else {
      button.classList.remove("rf-error-pulse");
      button.textContent = "ERROR CHECK · DIAGNOSE";
    }
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
      smartAssignDiagnosticContext = { lotId, departmentCode: target.department_code, departmentName: target.department_name || target.department_code };
      await window.RealFactoryUPM.openLotAtDepartment(lotId, target.department_code);
      installSmartAssignErrorCheck();
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
      if (lastSubmitted === requested) continue;
      const targets = eligibleTargets(snap.departments, meta.identity || {}, lastSubmitted)
        .filter(t => t.canonical === requested);
      if (!targets.length) continue;
      cards.push(`<article class="rf-queue-card"><div><b>${esc(lot.lot_no)}</b><span>CB ${esc(meta.identity?.cb_no || lot.cb_no || "—")} · ART ${esc(meta.identity?.art_no || lot.art_no || "—")}</span></div><p class="rf-worker-rule">READY TO ASSIGN · एक या multiple Colours select · हर Colour की सभी Sizes एक Worker</p><div class="rf-route-chart">${targets.map(t => `<button type="button" data-lot="${esc(lot.canonical_lot_id)}" data-dept="${esc(t.department_code)}" class="${route.indexOf(t.canonical) >= route.indexOf(requested) ? "rf-direct" : "rf-warning"}">${esc(t.department_name || t.canonical)}<small>READY TO ASSIGN</small></button>`).join("")}</div></article>`);
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
    section.innerHTML = `<div class="rf-queue-title"><h2>OPEN RANDOM QUEUE</h2><span>Only ${esc(label)} unassigned/newly submitted work · other department running work stays separate</span></div><div id="rfDepartmentQueue"></div>`;
    if (requested === "CUTTING") section.classList.add("hidden");
    board?.insertAdjacentElement("afterend", section);
  }

  const style = document.createElement("style");
  style.textContent = `.rf-running-hidden{display:none!important}.rf-card-actions{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:8px;margin-top:auto}.rf-card-actions button{width:100%;min-height:46px}.rf-card-actions button:first-child{background:#174936;border-color:#318b65}.rf-card-actions button:last-child{background:#493915;border-color:#8a6b2b}.rf-queue-section{margin-top:18px;border-top:2px solid #303641;padding-top:14px}.rf-queue-title{display:flex;gap:10px;align-items:center;justify-content:space-between}.rf-queue-title h2{margin:0;color:#ffc857}.rf-queue-title span{color:#98a2b3}.rf-queue-card{background:#12151c;border:1px solid #303641;border-radius:14px;padding:12px;margin-top:10px}.rf-queue-card>div:first-child{display:flex;justify-content:space-between;gap:10px}.rf-queue-card>div:first-child span{color:#98a2b3}.rf-worker-rule{margin:8px 0 0;color:#9ec5ff;font-weight:750}.rf-route-chart{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:7px;margin-top:10px}.rf-route-chart button{width:100%;min-height:58px}.rf-route-chart small{display:block;margin-top:4px;font-size:9px}.rf-direct{border-color:#318b65;background:#174936}.rf-warning{border-color:#8a6b2b;background:#493915}.rf-despatch{border-color:#3b82f6;background:#17365f}
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
  /* Ready-to-Assign keeps the same colour × size table as Submit. Qty is
     locked from Cutting; only colour selection and worker routing are editable. */
  #traveller.rf-smart-assign .worker-block label:nth-child(2){display:none!important}
  #traveller.rf-smart-assign .bulk-assign{position:static;display:flex!important;flex-direction:column;align-items:stretch;gap:9px;margin:0;padding:11px}
  #traveller.rf-smart-assign .bulk-assign>*{width:100%;min-height:52px}
  #traveller.rf-smart-assign .bulk-assign label{display:flex;flex-direction:column;min-height:auto;font-size:12px}
  #traveller.rf-smart-assign .bulk-assign select{min-height:52px;font-size:16px}
  #traveller.rf-smart-assign #assignBtn{min-height:58px;font-size:15px}
  #traveller.rf-smart-assign .rf-error-check-btn{min-height:52px;border-color:#b7791f;background:#4b3412;color:#ffe3a3;font-weight:900}
  #traveller.rf-smart-assign .rf-error-pulse{animation:rfErrorPulse 1s steps(1) infinite}
  #traveller.rf-smart-assign .rf-error-panel{margin:9px 0;border:1px solid #8a6b2b;border-radius:12px;padding:10px;background:#120f09;max-height:38dvh;overflow:auto}
  #traveller.rf-smart-assign .rf-error-head{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:8px}
  #traveller.rf-smart-assign .rf-check{display:grid;grid-template-columns:48px 1fr auto;gap:8px;align-items:center;padding:7px 0;border-top:1px solid #ffffff18;font-size:12px}
  #traveller.rf-smart-assign .rf-check.ok b{color:#56efb2}#traveller.rf-smart-assign .rf-check.bad b{color:#ff7b8a}
  #traveller.rf-smart-assign .rf-check strong{font-size:11px;max-width:180px;overflow-wrap:anywhere;text-align:right}
  #traveller.rf-smart-assign .rf-form-last{margin-top:8px;padding:8px;background:#171b23;border-radius:8px}.rf-form-last small{color:#98a2b3}
  #traveller.rf-smart-assign .rf-server-debug{margin-top:8px;padding-top:8px;border-top:1px solid #ffffff22}
  #traveller.rf-smart-assign .rf-server-debug pre{white-space:pre-wrap;overflow-wrap:anywhere;max-height:220px;overflow:auto;font-size:11px;color:#cbd5e1}
  @keyframes rfErrorPulse{0%,100%{box-shadow:0 0 0 0 #ff7b8a00}50%{box-shadow:0 0 0 3px #ff7b8a66}}
  #traveller.rf-smart-submit .formbar,#traveller.rf-smart-submit #entryThumbs,#traveller.rf-smart-submit #summary,#traveller.rf-smart-submit #freezeSummary,#traveller.rf-smart-submit .legend,#traveller.rf-smart-submit .bulk-assign,#traveller.rf-smart-submit #routeNote,#traveller.rf-smart-submit .debug{display:none!important}
  #traveller.rf-smart-submit .colour-card:not(.assigned){display:none!important}
  #traveller.rf-smart-submit .colour-card .worker-block,#traveller.rf-smart-submit .colour-card .size-wrap{display:none!important}
  #traveller.rf-smart-submit .actions{position:sticky;bottom:-14px;padding:10px 0 0}
  #traveller.rf-smart-submit .actions button{display:none!important}#traveller.rf-smart-submit .actions #submitBtn{display:block!important;width:100%;min-height:58px;font-size:15px}
  #traveller.rf-smart-assign .colour-list,#traveller.rf-smart-submit .colour-list{max-height:38dvh;overflow:auto}
  #traveller.rf-smart-assign .colour-card,#traveller.rf-smart-submit .colour-card{border-radius:12px}
  #traveller.rf-smart-assign .colour-head,#traveller.rf-smart-submit .colour-head{padding:10px}

  .rf-screen-error-wrap{margin:0 0 12px;position:relative}.rf-screen-error-wrap>button{min-height:44px;border-color:#b7791f;background:#4b3412;color:#ffe3a3}.rf-screen-error-panel{margin-top:8px;border:1px solid #8a6b2b;border-radius:12px;padding:10px;background:#120f09;max-height:55vh;overflow:auto}.rf-screen-error-head{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:8px}.rf-screen-check{display:grid;grid-template-columns:48px minmax(120px,1fr) minmax(110px,1.5fr);gap:8px;align-items:center;padding:7px 0;border-top:1px solid #ffffff18;font-size:12px}.rf-screen-check.ok b{color:#56efb2}.rf-screen-check.bad b{color:#ff7b8a}.rf-screen-check strong{font-size:11px;overflow-wrap:anywhere;text-align:right}.rf-screen-error-panel pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:11px;color:#cbd5e1}.rf-screen-error-panel .badge.bad{color:#ff7b8a;border-color:#8c3c49}.rf-screen-error-panel .badge.ok{color:#56efb2;border-color:#34745b}
  @media(max-width:700px){.rf-queue-title,.rf-queue-card>div:first-child{align-items:flex-start;flex-direction:column}.rf-route-chart{grid-template-columns:1fr 1fr}#traveller.rf-smart-assign,#traveller.rf-smart-submit{align-items:flex-end;padding:0}#traveller.rf-smart-assign .sheet,#traveller.rf-smart-submit .sheet{width:100%;max-height:94dvh;border-radius:20px 20px 0 0;padding:12px 12px calc(12px + env(safe-area-inset-bottom))}}
  @media(max-width:420px){.rf-route-chart{grid-template-columns:1fr}#traveller.rf-smart-assign .sticky h2:after,#traveller.rf-smart-submit .sticky h2:after{font-size:18px}}`;
  document.head.append(style);
  applyShell();
  installScreenErrorCheck();

  let timer;
  const sync = () => {
    lockDepartment();
    enhanceRunningCards();
    installSmartAssignErrorCheck();
    clearTimeout(timer);
    timer = setTimeout(async () => { try { await filterRunningCards(); await renderQueue(); rfDiagRuntime.lastQueueError = ""; } catch (error) { rfDiagRuntime.lastQueueError = error?.message || String(error); console.error("UPM queue render failed", error); const host=document.getElementById("rfDepartmentQueue"); if(host) host.innerHTML=`<div class="msg error">Queue load failed: ${esc(rfDiagRuntime.lastQueueError)} · Run ERROR CHECK.</div>`; } }, 80);
  };
  new MutationObserver(mutations => {
    if (mutations.every(mutation => mutation.target.closest?.("#rfDepartmentQueue"))) return;
    sync();
  }).observe(document.body, { childList: true, subtree: true });
  sync();
  console.info("REAL FACTORY V798.8 · SCREEN + SMART ASSIGN ERROR CHECK · RELEASED LOT QUEUE · DESPATCH SEPARATE");
})();
