(() => {
"use strict";

const VERSION = "V755_FINAL_MERGED";
const $ = id => document.getElementById(id);
const upper = v => String(v || "").trim().toUpperCase();
const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[c]));

const cache = new Map();
let busy = false;

function client() {
  const direct = [
    window.supabaseClient,window.supabaseDb,
    window.redzedSupabase,window.sb
  ].find(x => x && typeof x.rpc === "function");
  if (direct) return direct;

  for (const key of Object.getOwnPropertyNames(window)) {
    try {
      const value = window[key];
      if (value && typeof value === "object" &&
          typeof value.rpc === "function" && value.auth) return value;
    } catch (_) {}
  }
  return null;
}

async function matrix(canonical, lotNo = "") {
  const key = canonical || upper(lotNo);
  if (!key) return null;
  if (cache.has(key)) return cache.get(key);

  const sb = client();
  if (!sb) return null;

  const { data, error } = await sb.rpc("rr_upm_lot_colour_matrix_v755", {
    p_canonical_lot_id: canonical || null,
    p_lot_no: lotNo || null
  });
  if (error) {
    console.error(VERSION,error);
    return null;
  }
  cache.set(key,data);
  return data;
}

function statusClass(status) {
  const s = upper(status);
  if (s === "RUNNING") return "running";
  if (s === "ASSIGNED") return "assigned";
  if (s === "OPEN") return "open";
  return "legacy";
}

function boardRows(data) {
  return (data?.colours || []).map(row => `
    <div class="v755-board-colour ${statusClass(row.ownership_status)}"
         data-v755-open="${esc(data.canonical_lot_id)}"
         data-v755-colour="${esc(row.colour_code)}"
         data-v755-department="${esc(row.department_code)}">
      <b>${esc(row.colour_code)}</b>
      <span>${esc(row.department_name)}</span>
      <em>${esc(row.ownership_status)}</em>
    </div>
  `).join("");
}

async function renderBoardCard(card) {
  const canonical = card.dataset.lot || card.dataset.canonicalLotId || "";
  const lotNo = card.querySelector(".lot-no")?.textContent?.trim() || "";
  const data = await matrix(canonical,lotNo);
  if (!data) return;

  // Hard replace every old department summary with one row per Colour.
  card.querySelectorAll(".lot-live-list,.v753-route-bar,.v754-board-status")
    .forEach(node => node.remove());

  let box = card.querySelector(".v755-board-matrix");
  if (!box) {
    box = document.createElement("div");
    box.className = "v755-board-matrix";
    card.querySelector(".thumbs")?.insertAdjacentElement("beforebegin",box);
  }
  box.innerHTML = boardRows(data);
}

function contextCanonical() {
  const raw = $("debugOutput")?.textContent?.trim();
  if (raw?.startsWith("{")) {
    try {
      return JSON.parse(raw)?.context?.lot?.canonical_lot_id || "";
    } catch (_) {}
  }
  return document.querySelector(".lot-card[data-lot]")?.dataset.lot || "";
}

async function openColour(canonical, colour, department) {
  const dept = $("dept");
  if (dept && department) {
    const option = [...dept.options].find(o =>
      upper(o.value) === upper(department)
    );
    if (option && upper(dept.value) !== upper(department)) {
      dept.value = option.value;
      dept.dispatchEvent(new Event("change",{bubbles:true}));
      await new Promise(resolve => setTimeout(resolve,700));
    }
  }

  setTimeout(() => {
    const card = [...document.querySelectorAll(".colour-card")].find(c => {
      const text = upper(c.querySelector(".colour-title")?.textContent);
      return new RegExp(`\\b${colour}\\b`).test(text);
    });
    const pick = card?.querySelector(".work-pick,.assign-pick");
    if (pick && !pick.disabled) pick.checked = true;
    card?.scrollIntoView({behavior:"smooth",block:"center"});
  },250);
}

function checkinRows(data) {
  return (data?.colours || []).map(row => `
    <tr class="${statusClass(row.ownership_status)}"
        data-v755-open="${esc(data.canonical_lot_id)}"
        data-v755-colour="${esc(row.colour_code)}"
        data-v755-department="${esc(row.department_code)}">
      <td><b>${esc(row.colour_code)}</b></td>
      <td>${esc(row.department_name)}</td>
      <td><span class="v755-status">${esc(row.ownership_status)}</span></td>
      <td>${esc(row.worker_name || (upper(row.ownership_status)==="OPEN" ? "Worker pending" : "—"))}</td>
      <td><button type="button" class="v755-open-btn">OPEN</button></td>
    </tr>
  `).join("");
}

async function renderCheckin() {
  if (!$("traveller") || $("traveller").classList.contains("hidden")) return;

  const canonical = contextCanonical();
  if (!canonical) return;

  cache.delete(canonical);
  const data = await matrix(canonical,"");
  if (!data) return;

  let panel = $("v755CheckinMatrix");
  if (!panel) {
    panel = document.createElement("section");
    panel.id = "v755CheckinMatrix";
    panel.className = "v755-checkin-matrix";

    const anchor =
      document.querySelector(".bulk-assign") ||
      document.querySelector(".colour-list");

    anchor?.insertAdjacentElement("beforebegin",panel);
  }

  panel.innerHTML = `
    <div class="v755-title">COLOUR × ACTIVE DEPARTMENT · HARD LOCK</div>
    <div class="v755-table-wrap">
      <table>
        <thead><tr>
          <th>Colour</th><th>Active Department</th>
          <th>Status</th><th>Worker</th><th>Open</th>
        </tr></thead>
        <tbody>${checkinRows(data)}</tbody>
      </table>
    </div>
  `;

  // Old route bars and manual department UI are not the source of truth.
  document.querySelectorAll(".v753-route-bar").forEach(node => node.remove());
  const deptField = $("dept")?.closest(".field");
  if (deptField) deptField.classList.add("v755-hide-dept");

  // Detailed cards remain action engine, but matrix always shows every Colour.
  document.querySelectorAll(".colour-card").forEach(card => {
    card.classList.add("v755-detail-card");
  });
}

function bindClicks() {
  document.addEventListener("click",event => {
    const row = event.target.closest("[data-v755-open]");
    if (!row) return;

    event.preventDefault();
    event.stopPropagation();

    openColour(
      row.dataset.v755Open,
      upper(row.dataset.v755Colour),
      upper(row.dataset.v755Department)
    );
  },true);
}

async function sync() {
  if (busy) return;
  busy = true;
  try {
    await Promise.all(
      [...document.querySelectorAll(".lot-card")].map(renderBoardCard)
    );
    await renderCheckin();
  } finally {
    busy = false;
  }
}

function style() {
  if ($("v755Style")) return;
  const s = document.createElement("style");
  s.id = "v755Style";
  s.textContent = `
    .v755-board-matrix{display:grid;gap:5px;margin:8px 0}
    .v755-board-colour{
      display:grid;grid-template-columns:42px 1fr auto;
      gap:8px;align-items:center;padding:7px 9px;
      border:1px solid #475160;border-radius:8px;
      background:#171d26;cursor:pointer
    }
    .v755-board-colour b{font-size:14px;color:#fff}
    .v755-board-colour span{font-weight:850}
    .v755-board-colour em{font-style:normal;font-size:11px;font-weight:900}
    .v755-board-colour.running{border-color:#38d58a;background:#10432e}
    .v755-board-colour.assigned{border-color:#ffb33e;background:#52350b}
    .v755-board-colour.open{border-color:#5194df;background:#122d4a}
    .v755-board-colour.legacy{border-color:#e05263;background:#4b1720}

    .v755-checkin-matrix{
      margin:10px 0;border:2px solid #506b91;
      border-radius:12px;background:#101723;padding:10px
    }
    .v755-title{font-weight:950;color:#cfe4ff;margin-bottom:8px}
    .v755-table-wrap{overflow:auto}
    .v755-checkin-matrix table{min-width:720px}
    .v755-checkin-matrix tr.running{background:#103d2c}
    .v755-checkin-matrix tr.assigned{background:#49320d}
    .v755-checkin-matrix tr.open{background:#122940}
    .v755-checkin-matrix tr.legacy{background:#481820}
    .v755-status{font-weight:950}
    .v755-open-btn{padding:7px 12px;background:#204d80;border-color:#4c91dc}
    .v755-hide-dept{
      position:absolute!important;width:1px!important;height:1px!important;
      overflow:hidden!important;opacity:0!important;pointer-events:none!important
    }
  `;
  document.head.appendChild(s);
}

function install() {
  style();
  bindClicks();
  sync();

  const observer = new MutationObserver(() => {
    clearTimeout(install.timer);
    install.timer = setTimeout(sync,100);
  });
  observer.observe(document.body,{childList:true,subtree:true});
}

document.readyState==="loading"
  ? document.addEventListener("DOMContentLoaded",install)
  : install();

window.REDZED_UPM_V755={version:VERSION,sync,clearCache:()=>cache.clear()};
console.info("REDZED UPM",VERSION);
})();

(() => {
"use strict";

const VERSION = "V755_FINAL_MERGED_ALTER";
const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[c]));

function alterHtml(row, compact = false) {
  const a = row?.alter_journey;
  if (!a || Number(a.qty || 0) <= 0) {
    return `<span class="v7551-alter-none">NONE</span>`;
  }

  const responsible = [
    a.responsible_name,
    a.responsible_role_short
  ].filter(Boolean).join(" · ");

  if (compact) {
    return `<div class="v7551-alter-active">
      <b>${esc(a.stage_label || a.stage)}</b>
      <span>${esc(a.qty)} PCS</span>
      <small>${esc(responsible || "Mapped responsibility")}</small>
    </div>`;
  }

  return `<div class="v7551-alter-active">
    <b>${esc(a.stage_label || a.stage)}</b>
    <span>${esc(a.qty)} PCS</span>
    <small>${esc(responsible || "Mapped responsibility")}</small>
    ${a.size_details ? `<em>${esc(a.size_details)}</em>` : ""}
  </div>`;
}

function patchBoardMatrix() {
  document.querySelectorAll(".v755-board-matrix").forEach(matrix => {
    const card = matrix.closest(".lot-card");
    const canonical = card?.dataset?.lot || card?.dataset?.canonicalLotId || "";
    if (!canonical || !window.REDZED_UPM_V755) return;

    // Reuse V755 cache refresh by reading rendered rows after its normal sync.
    const rows = matrix.querySelectorAll(".v755-board-colour");
    rows.forEach(row => {
      if (row.querySelector(".v7551-alter-cell")) return;
      const cell = document.createElement("div");
      cell.className = "v7551-alter-cell";
      cell.innerHTML = `<span class="v7551-alter-none">Loading...</span>`;
      row.appendChild(cell);
    });
  });
}

function patchCheckinHeaders() {
  document.querySelectorAll(".v755-checkin-matrix table").forEach(table => {
    const header = table.querySelector("thead tr");
    if (header && !header.querySelector(".v7551-head")) {
      const th = document.createElement("th");
      th.className = "v7551-head";
      th.textContent = "Alter Journey";
      header.insertBefore(th, header.lastElementChild);
    }

    table.querySelectorAll("tbody tr").forEach(row => {
      if (row.querySelector(".v7551-alter-cell")) return;
      const td = document.createElement("td");
      td.className = "v7551-alter-cell";
      td.innerHTML = `<span class="v7551-alter-none">Loading...</span>`;
      row.insertBefore(td, row.lastElementChild);
    });
  });
}

function getClient() {
  const direct = [
    window.supabaseClient,window.supabaseDb,
    window.redzedSupabase,window.sb
  ].find(x => x && typeof x.rpc === "function");
  if (direct) return direct;

  for (const key of Object.getOwnPropertyNames(window)) {
    try {
      const value = window[key];
      if (value && typeof value === "object" &&
          typeof value.rpc === "function" && value.auth) return value;
    } catch (_) {}
  }
  return null;
}

async function loadMatrix(canonical, lotNo = "") {
  const sb = getClient();
  if (!sb) return null;
  const { data, error } = await sb.rpc("rr_upm_lot_colour_matrix_v755", {
    p_canonical_lot_id: canonical || null,
    p_lot_no: lotNo || null
  });
  if (error) {
    console.warn(VERSION,error);
    return null;
  }
  return data;
}

async function fillBoardAlter() {
  for (const card of document.querySelectorAll(".lot-card")) {
    const canonical = card.dataset.lot || card.dataset.canonicalLotId || "";
    const lotNo = card.querySelector(".lot-no")?.textContent?.trim() || "";
    const data = await loadMatrix(canonical,lotNo);
    if (!data) continue;

    const byCode = new Map((data.colours || []).map(r => [r.colour_code,r]));

    card.querySelectorAll(".v755-board-colour").forEach(row => {
      const code = row.dataset.v755Colour;
      const cell = row.querySelector(".v7551-alter-cell");
      if (cell) cell.innerHTML = alterHtml(byCode.get(code),true);
    });
  }
}

async function fillCheckinAlter() {
  const panel = document.querySelector(".v755-checkin-matrix");
  if (!panel) return;

  const firstRow = panel.querySelector("tbody tr[data-v755-open]");
  const canonical = firstRow?.dataset?.v755Open;
  if (!canonical) return;

  const data = await loadMatrix(canonical,"");
  if (!data) return;

  const byCode = new Map((data.colours || []).map(r => [r.colour_code,r]));

  panel.querySelectorAll("tbody tr[data-v755-colour]").forEach(row => {
    const cell = row.querySelector(".v7551-alter-cell");
    if (cell) cell.innerHTML = alterHtml(byCode.get(row.dataset.v755Colour),false);
  });
}

async function sync() {
  patchBoardMatrix();
  patchCheckinHeaders();
  await fillBoardAlter();
  await fillCheckinAlter();
}

function style() {
  if (document.getElementById("v7551Style")) return;
  const s = document.createElement("style");
  s.id = "v7551Style";
  s.textContent = `
    .v755-board-colour{
      grid-template-columns:42px minmax(130px,1fr) auto minmax(145px,220px)!important;
    }
    .v7551-alter-cell{
      border-left:1px solid #475160;
      padding-left:8px;
      min-width:135px;
    }
    .v7551-alter-none{
      color:#98a2b3;
      font-size:11px;
      font-weight:850;
    }
    .v7551-alter-active{
      display:grid;
      gap:2px;
      border-radius:7px;
      padding:5px 7px;
      background:#4b3609;
      border:1px solid #d8a72c;
      animation:v7551Blink 1.2s ease-in-out infinite;
    }
    .v7551-alter-active b{color:#ffe28c;font-size:11px}
    .v7551-alter-active span{font-weight:950;color:#fff}
    .v7551-alter-active small{color:#f4cf78}
    .v7551-alter-active em{
      font-style:normal;font-size:10px;color:#dce5ef
    }
    @keyframes v7551Blink{
      0%,100%{box-shadow:0 0 0 rgba(255,190,55,0)}
      50%{box-shadow:0 0 10px rgba(255,190,55,.65)}
    }
    .v755-checkin-matrix table{min-width:940px!important}
  `;
  document.head.appendChild(s);
}

function install() {
  style();
  sync();

  const observer = new MutationObserver(() => {
    clearTimeout(install.timer);
    install.timer = setTimeout(sync,120);
  });
  observer.observe(document.body,{childList:true,subtree:true});
}

document.readyState==="loading"
  ? document.addEventListener("DOMContentLoaded",install)
  : install();

window.REDZED_UPM_V755_1={version:VERSION,sync};
console.info("REDZED UPM",VERSION);
})();
