(() => {
"use strict";

const VERSION = "V756_INDEPENDENT_COLOUR_ACTIONS";
const $ = id => document.getElementById(id);
const upper = value => String(value || "").trim().toUpperCase();
const esc = value => String(value ?? "").replace(/[&<>"']/g, char => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[char]));

let activeCanonical = "";
let currentMatrix = null;
let syncing = false;
let observerTimer = null;
const workerCache = new Map();

function getClient() {
  const direct = [
    window.supabaseClient,
    window.supabaseDb,
    window.redzedSupabase,
    window.sb
  ].find(client => client && typeof client.rpc === "function");

  if (direct) return direct;

  for (const key of Object.getOwnPropertyNames(window)) {
    try {
      const value = window[key];
      if (
        value &&
        typeof value === "object" &&
        typeof value.rpc === "function" &&
        value.auth
      ) return value;
    } catch (_) {}
  }

  return null;
}

async function fetchMatrix(canonical, lotNo = "") {
  const client = getClient();
  if (!client) throw new Error("Connected Supabase client not found.");

  const { data, error } = await client.rpc("rr_upm_lot_colour_matrix_v755", {
    p_canonical_lot_id: canonical || null,
    p_lot_no: lotNo || null
  });

  if (error) throw error;
  return data;
}

async function fetchWorkers(departmentCode) {
  const department = upper(departmentCode);
  if (!department) return [];
  if (workerCache.has(department)) return workerCache.get(department);

  const client = getClient();
  if (!client) return [];

  const rpcNames = ["rr_upm_worker_list_v754", "rr_upm_worker_list_v8_3"];

  for (const rpcName of rpcNames) {
    try {
      const { data, error } = await client.rpc(rpcName, {
        p_department_code: department
      });

      if (!error && Array.isArray(data)) {
        workerCache.set(department, data);
        return data;
      }
    } catch (_) {}
  }

  workerCache.set(department, []);
  return [];
}

function statusClass(row) {
  const status = upper(row?.ownership_status);
  if (status === "RUNNING") return "running";
  if (status === "ASSIGNED") return "assigned";
  if (status === "OPEN") return "open";
  return "legacy";
}

function userStatus(row) {
  return ["OPEN", "ASSIGNED", "RUNNING"].includes(upper(row?.ownership_status))
    ? "ACTIVE"
    : "CHECK";
}

function alterText(row) {
  const journey = row?.alter_journey;
  if (!journey || Number(journey.qty || 0) <= 0) return "NONE";

  const responsible = [
    journey.responsible_name,
    journey.responsible_role_short
  ].filter(Boolean).join(" · ");

  return [
    journey.stage_label || journey.stage,
    `${journey.qty} PCS`,
    responsible
  ].filter(Boolean).join(" · ");
}

function rowActionButtons(row) {
  const status = upper(row.ownership_status);
  const stage = upper(row.alter_journey?.stage);
  const buttons = [];

  if (status === "OPEN") {
    buttons.push(`<button type="button" class="v756-action assign"
      data-v756-action="ASSIGN"
      data-v756-colour="${esc(row.colour_code)}">ASSIGN WORKER</button>`);
  }

  if (["ASSIGNED", "RUNNING"].includes(status)) {
    buttons.push(`<button type="button" class="v756-action alter"
      data-v756-action="ALTER"
      data-v756-colour="${esc(row.colour_code)}">ALTER FILL</button>`);

    buttons.push(`<button type="button" class="v756-action damage"
      data-v756-action="DAMAGE"
      data-v756-colour="${esc(row.colour_code)}">DAMAGE</button>`);

    buttons.push(`<button type="button" class="v756-action submit"
      data-v756-action="SUBMIT"
      data-v756-colour="${esc(row.colour_code)}">SUBMIT</button>`);
  }

  if (stage === "LM_ALTER_PENDING") {
    buttons.push(`<button type="button" class="v756-action journey"
      data-v756-action="REMAKE_ISSUE"
      data-v756-colour="${esc(row.colour_code)}">REMAKE ISSUE · CM</button>`);
  }

  if (stage === "CM_REMAKE_READY") {
    buttons.push(`<button type="button" class="v756-action journey"
      data-v756-action="RECEIVE_MASTER"
      data-v756-colour="${esc(row.colour_code)}">RECEIVE MASTER · LM</button>`);
  }

  if (stage === "LM_DELIVERY_PENDING") {
    buttons.push(`<button type="button" class="v756-action journey"
      data-v756-action="DELIVER_KARIGAR"
      data-v756-colour="${esc(row.colour_code)}">DELIVER KARIGAR · LM</button>`);
  }

  if (stage === "KARIGAR_REMAKE_PENDING") {
    buttons.push(`<button type="button" class="v756-action journey"
      data-v756-action="RECEIVE_KARIGAR"
      data-v756-colour="${esc(row.colour_code)}">RECEIVE KARIGAR · LM</button>`);
  }

  return buttons.join("");
}

function getLotNoFromCard(card) {
  return card.querySelector(".lot-no")?.textContent?.trim() || "";
}

async function renderFirstWindowCard(card) {
  const canonical = card.dataset.lot || card.dataset.canonicalLotId || "";
  const lotNo = getLotNoFromCard(card);
  if (!canonical && !lotNo) return;

  const data = await fetchMatrix(canonical, lotNo);

  card.querySelectorAll(
    ".lot-live-list,.lot-live-status,.v753-route-bar,.v754-board-status," +
    ".v755-board-matrix,.v7552-short-matrix,.v756-short-summary"
  ).forEach(node => node.remove());

  const summary = document.createElement("div");
  summary.className = "v756-short-summary";

  summary.innerHTML = (data?.colours || []).map(row => `
    <div class="v756-short-row ${statusClass(row)}">
      <b>${esc(row.colour_code)}</b>
      <span>${esc(row.department_name)}</span>
      <em>${esc(userStatus(row))}</em>
      <small>Alter ${esc(alterText(row))}</small>
    </div>
  `).join("");

  const thumbs = card.querySelector(".thumbs");
  if (thumbs) thumbs.insertAdjacentElement("beforebegin", summary);
  else card.querySelector(".card-top")?.insertAdjacentElement("afterend", summary);
}

function locateActiveCanonical() {
  if (activeCanonical) return activeCanonical;

  const lotNo = [...document.querySelectorAll("#identity .box")]
    .find(box => upper(box.querySelector("small")?.textContent) === "LOT NO")
    ?.querySelector("b")?.textContent?.trim();

  if (!lotNo) return "";

  const card = [...document.querySelectorAll(".lot-card")]
    .find(item => getLotNoFromCard(item) === lotNo);

  return card?.dataset?.lot || "";
}

function departmentOptions(rows) {
  const departments = new Map();

  for (const row of rows) {
    if (upper(row.ownership_status) !== "OPEN") continue;
    if (!row.department_code) continue;
    departments.set(row.department_code, row.department_name);
  }

  return [...departments.entries()].map(([code, name]) =>
    `<option value="${esc(code)}">${esc(name)}</option>`
  ).join("");
}

async function renderBulkWorkers(departmentCode) {
  const select = $("v756BulkWorker");
  if (!select) return;

  const workers = await fetchWorkers(departmentCode);

  select.innerHTML = `<option value="">Select worker</option>` +
    workers.map(worker => `
      <option value="${esc(worker.worker_id)}"
        data-name="${esc(worker.worker_name || "")}"
        data-code="${esc(worker.worker_code || "")}">
        ${esc(worker.worker_name || "Unnamed")}
        ${worker.worker_code ? ` · ${esc(worker.worker_code)}` : ""}
      </option>
    `).join("");

  select.disabled = workers.length === 0;
}

function detailedRows(data) {
  return (data?.colours || []).map(row => `
    <tr class="v756-colour-row ${statusClass(row)}"
      data-v756-colour="${esc(row.colour_code)}"
      data-v756-department="${esc(row.department_code)}"
      data-v756-status="${esc(row.ownership_status)}">
      <td class="v756-colour"><b>${esc(row.colour_code)}</b></td>
      <td>${esc(row.department_name)}</td>
      <td><span class="v756-active-label">${esc(userStatus(row))}</span></td>
      <td>${esc(row.worker_name || "Worker pending")}</td>
      <td class="v756-alter">${esc(alterText(row))}</td>
      <td class="v756-actions">${rowActionButtons(row)}</td>
    </tr>
  `).join("");
}

async function renderCheckinTable() {
  const traveller = $("traveller");
  if (!traveller || traveller.classList.contains("hidden")) return;

  const canonical = locateActiveCanonical();
  if (!canonical) return;

  currentMatrix = await fetchMatrix(canonical, "");
  activeCanonical = canonical;

  let panel = $("v756ColourActionPanel");
  if (!panel) {
    panel = document.createElement("section");
    panel.id = "v756ColourActionPanel";
    panel.className = "v756-panel";
    $("colours")?.insertAdjacentElement("beforebegin", panel);
  }

  panel.innerHTML = `
    <div class="v756-title">COLOUR × ACTIVE DEPARTMENT</div>

    <div class="v756-bulk">
      <strong>BULK ASSIGN</strong>
      <select id="v756BulkDepartment">
        <option value="">Select department group</option>
        ${departmentOptions(currentMatrix?.colours || [])}
      </select>
      <select id="v756BulkWorker" disabled>
        <option value="">Select worker</option>
      </select>
      <button type="button" id="v756BulkAssign">ASSIGN ALL ELIGIBLE</button>
      <small id="v756BulkNote">Only OPEN Colours locked to the selected department will be assigned.</small>
    </div>

    <div class="v756-table-wrap">
      <table>
        <thead>
          <tr>
            <th>Colour</th>
            <th>Active Department</th>
            <th>Status</th>
            <th>Worker</th>
            <th>Alter Journey</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>${detailedRows(currentMatrix)}</tbody>
      </table>
    </div>
  `;

  // Old controls remain in DOM as action engine, but are hidden from users.
  document.querySelector(".bulk-assign")?.classList.add("v756-engine-only");
  document.querySelector(".actions")?.classList.add("v756-engine-only");
  $("dept")?.closest(".field")?.classList.add("v756-engine-only");

  // Hide legacy visible checkboxes while retaining programmatic control.
  document.querySelectorAll(".work-pick,.assign-pick").forEach(input => {
    input.classList.add("v756-hidden-pick");
  });

  // Hide all detailed cards until a row action is selected.
  document.querySelectorAll(".colour-card").forEach(card => {
    card.classList.add("v756-detail-hidden");
  });

  const departmentSelect = $("v756BulkDepartment");
  departmentSelect?.addEventListener("change", () => {
    renderBulkWorkers(departmentSelect.value);
  });

  $("v756BulkAssign")?.addEventListener("click", runBulkAssign);
}

function colourCodeFromCard(card) {
  return upper(card?.querySelector(".colour-title")?.textContent)
    .match(/\bC\d+\b/)?.[0] || "";
}

function findColourCard(colourCode) {
  return [...document.querySelectorAll(".colour-card")]
    .find(card => colourCodeFromCard(card) === upper(colourCode));
}

function clearProgrammaticSelection() {
  document.querySelectorAll(".work-pick,.assign-pick").forEach(input => {
    input.checked = false;
  });
}

function selectColourCard(colourCode, showDetails = false) {
  clearProgrammaticSelection();

  const card = findColourCard(colourCode);
  if (!card) return null;

  const pick = card.querySelector(".work-pick,.assign-pick");
  if (pick && !pick.disabled) {
    pick.checked = true;
    pick.dispatchEvent(new Event("change", { bubbles: true }));
  }

  document.querySelectorAll(".colour-card").forEach(item => {
    item.classList.toggle("v756-detail-hidden", item !== card || !showDetails);
  });

  return card;
}

function focusActionRow(colourCode) {
  document.querySelectorAll(".v756-colour-row").forEach(row => {
    const active = upper(row.dataset.v756Colour) === upper(colourCode);
    row.classList.toggle("v756-action-focus", active);
    row.classList.toggle("v756-action-dim", !active);
  });

  clearTimeout(focusActionRow.timer);
  focusActionRow.timer = setTimeout(() => {
    document.querySelectorAll(".v756-colour-row").forEach(row => {
      row.classList.remove("v756-action-focus", "v756-action-dim");
    });
  }, 5000);
}

function clickExistingButton(id) {
  const button = $(id);
  if (!button) throw new Error(`Action button ${id} not found.`);
  button.click();
}

async function ensureDepartmentContext(departmentCode) {
  const department = upper(departmentCode);
  const select = $("dept");
  if (!select || !department) return;

  const option = [...select.options]
    .find(item => upper(item.value) === department);

  if (option && select.value !== option.value) {
    select.value = option.value;
    select.dispatchEvent(new Event("change", { bubbles: true }));
    await new Promise(resolve => setTimeout(resolve, 750));
  }
}

async function assignSingleColour(row) {
  await ensureDepartmentContext(row.department_code);
  const card = selectColourCard(row.colour_code, true);
  if (!card) throw new Error(`Colour ${row.colour_code} card not found.`);

  const workerSelect = card.querySelector(".colour-worker");
  if (!workerSelect) throw new Error("Worker dropdown not found.");

  workerSelect.focus();
  card.scrollIntoView({ behavior: "smooth", block: "center" });
}

async function runBulkAssign() {
  try {
    const department = $("v756BulkDepartment")?.value;
    const workerId = $("v756BulkWorker")?.value;

    if (!department) throw new Error("Select department group.");
    if (!workerId) throw new Error("Select worker.");

    const eligible = (currentMatrix?.colours || []).filter(row =>
      upper(row.ownership_status) === "OPEN" &&
      upper(row.department_code) === upper(department)
    );

    if (!eligible.length) {
      throw new Error("No eligible OPEN Colours in this department.");
    }

    const names = eligible.map(row => row.colour_code).join(", ");
    if (!confirm(
      `Assign ${names}\nDepartment: ${eligible[0].department_name}\n` +
      `Worker: ${$("v756BulkWorker").selectedOptions[0]?.textContent.trim()}\n\nConfirm?`
    )) return;

    await ensureDepartmentContext(department);
    clearProgrammaticSelection();

    for (const row of eligible) {
      const card = findColourCard(row.colour_code);
      if (!card) continue;

      const pick = card.querySelector(".work-pick,.assign-pick");
      if (pick && !pick.disabled) pick.checked = true;

      const workerSelect = card.querySelector(".colour-worker");
      if (workerSelect && [...workerSelect.options].some(o => o.value === workerId)) {
        workerSelect.value = workerId;
      }
    }

    const bulkWorker = $("bulkWorker");
    if (bulkWorker && [...bulkWorker.options].some(o => o.value === workerId)) {
      bulkWorker.value = workerId;
      bulkWorker.dispatchEvent(new Event("change", { bubbles: true }));
    }

    clickExistingButton("assignSelectedBtn");
  } catch (error) {
    alert(error.message || String(error));
  }
}

async function handleRowAction(button) {
  const colourCode = upper(button.dataset.v756Colour);
  const action = upper(button.dataset.v756Action);
  const row = (currentMatrix?.colours || [])
    .find(item => upper(item.colour_code) === colourCode);

  if (!row) return;

  try {
    focusActionRow(colourCode);
    await ensureDepartmentContext(row.department_code);

    const showDetails = ["ASSIGN", "ALTER", "DAMAGE", "REMAKE_ISSUE",
      "RECEIVE_MASTER", "DELIVER_KARIGAR", "RECEIVE_KARIGAR"].includes(action);

    const card = selectColourCard(colourCode, showDetails);
    if (!card) throw new Error(`Colour ${colourCode} card not found.`);

    if (showDetails) {
      card.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    if (action === "ASSIGN") {
      await assignSingleColour(row);
      return;
    }

    if (action === "ALTER") {
      card.querySelector(".alterEntry:not(:disabled)")?.focus();
      return;
    }

    if (action === "DAMAGE") {
      card.querySelector(".damageEntry:not(:disabled)")?.focus();
      return;
    }

    const buttonMap = {
      SUBMIT: "submitBtn",
      REMAKE_ISSUE: "remakeIssueBtn",
      RECEIVE_MASTER: "remakeDeliveredBtn",
      DELIVER_KARIGAR: "remakeCompleteBtn",
      RECEIVE_KARIGAR: "receiveKarigarBtn"
    };

    if (buttonMap[action]) {
      clickExistingButton(buttonMap[action]);
    }
  } catch (error) {
    alert(error.message || String(error));
  }
}

function bindGlobalClicks() {
  document.addEventListener("click", event => {
    const lotCard = event.target.closest(".lot-card");
    if (lotCard) {
      activeCanonical = lotCard.dataset.lot || activeCanonical;
      setTimeout(syncAll, 800);
    }

    const actionButton = event.target.closest(".v756-action");
    if (actionButton) {
      event.preventDefault();
      event.stopPropagation();
      handleRowAction(actionButton);
    }
  }, true);
}

async function syncAll() {
  if (syncing) return;
  syncing = true;

  try {
    await Promise.all(
      [...document.querySelectorAll(".lot-card")].map(renderFirstWindowCard)
    );

    await renderCheckinTable();
  } catch (error) {
    console.error(VERSION, error);
  } finally {
    syncing = false;
  }
}

function addStyles() {
  if ($("v756Style")) return;

  const style = document.createElement("style");
  style.id = "v756Style";
  style.textContent = `
    .lot-card{height:auto!important;min-height:285px!important}

    .v756-short-summary{display:grid;gap:4px;margin:8px 0}
    .v756-short-row{
      display:grid;
      grid-template-columns:35px minmax(120px,1fr) 65px;
      gap:5px 8px;
      padding:6px 8px;
      border:1px solid #465365;
      border-radius:7px;
      background:#171d26
    }
    .v756-short-row small{grid-column:1/-1;color:#c8d2df}
    .v756-short-row.running{background:#103d2c;border-color:#38d58a}
    .v756-short-row.assigned{background:#4b330d;border-color:#f0a82f}
    .v756-short-row.open{background:#112d49;border-color:#4f97e4}
    .v756-short-row.legacy{background:#471820;border-color:#df5869}
    .v756-short-row em{font-style:normal;font-size:10px;font-weight:950}

    .v756-panel{
      margin:10px 0;
      padding:10px;
      border:2px solid #506b91;
      border-radius:12px;
      background:#101723
    }
    .v756-title{font-weight:950;color:#d5e8ff;margin-bottom:9px}
    .v756-bulk{
      display:grid;
      grid-template-columns:auto minmax(170px,1fr) minmax(190px,1fr) auto;
      gap:8px;
      align-items:center;
      margin-bottom:10px;
      padding:9px;
      background:#172131;
      border:1px solid #40536e;
      border-radius:9px
    }
    .v756-bulk small{grid-column:1/-1;color:#aebed1}
    .v756-table-wrap{overflow:auto}
    .v756-panel table{min-width:1120px!important}
    .v756-colour-row{transition:opacity .2s,filter .2s,outline .2s}
    .v756-colour-row.running{background:#103d2c}
    .v756-colour-row.assigned{background:#4b330d}
    .v756-colour-row.open{background:#112d49}
    .v756-colour-row.legacy{background:#471820}
    .v756-active-label{
      display:inline-block;
      padding:4px 8px;
      border-radius:999px;
      background:#165786;
      color:#fff;
      font-weight:950
    }
    .v756-actions{min-width:430px}
    .v756-action{
      margin:2px;
      padding:7px 9px;
      font-size:11px;
      font-weight:900
    }
    .v756-action.assign{background:#1e5e91;border-color:#4b9be2}
    .v756-action.submit{background:#a91f35;border-color:#e14c63}
    .v756-action.alter{background:#84600c;border-color:#d7a52b}
    .v756-action.damage{background:#7b2430;border-color:#d65568}
    .v756-action.journey{background:#244d73;border-color:#4f8dc3}
    .v756-action-focus{
      outline:3px solid #4ab0ff!important;
      filter:none!important;
      opacity:1!important
    }
    .v756-action-dim{
      background:#050607!important;
      filter:grayscale(1);
      opacity:.16
    }

    .v756-engine-only{
      position:absolute!important;
      width:1px!important;
      height:1px!important;
      overflow:hidden!important;
      opacity:0!important;
      pointer-events:none!important
    }
    .v756-hidden-pick{
      position:absolute!important;
      width:1px!important;
      height:1px!important;
      opacity:0!important
    }
    .v756-detail-hidden{display:none!important}

    @media(max-width:900px){
      .v756-bulk{grid-template-columns:1fr}
      .v756-actions{min-width:320px}
    }
  `;

  document.head.appendChild(style);
}

function install() {
  addStyles();
  bindGlobalClicks();
  syncAll();

  const observer = new MutationObserver(() => {
    clearTimeout(observerTimer);
    observerTimer = setTimeout(syncAll, 140);
  });

  observer.observe(document.body, { childList: true, subtree: true });
}

document.readyState === "loading"
  ? document.addEventListener("DOMContentLoaded", install)
  : install();

window.REDZED_UPM_V756 = {
  version: VERSION,
  sync: syncAll
};

console.info("REDZED UPM", VERSION);
})();