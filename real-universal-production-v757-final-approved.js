(() => {
"use strict";

const VERSION = "V757_5_SINGLE_CONFIRMATION_CONTEXT_FIX";
const $ = id => document.getElementById(id);
const upper = value => String(value || "").trim().toUpperCase();
const esc = value => String(value ?? "").replace(/[&<>"']/g, char => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[char]));

function matrixSignature(data) {
  return JSON.stringify((data?.colours || []).map(row => ({
    c: row.colour_code,
    d: row.department_code,
    s: row.ownership_status,
    w: row.worker_id,
    a: row.alter_journey
  })));
}

let activeCanonical = "";
let currentMatrix = null;
let syncing = false;
let observerTimer = null;
const workerCache = new Map();
const lotSizeCache = new Map();
const boardSignatures = new WeakMap();
let checkinSignature = "";
let observer = null;

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

async function fetchLotSizeRows(lotNo) {
  const key = upper(lotNo);
  if (!key) return [];
  if (lotSizeCache.has(key)) return lotSizeCache.get(key);

  const client = getClient();
  if (!client) return [];

  const calls = [
    { name: "rr_upm_cut_size_rows_v726", args: { p_lot_no: key } },
    { name: "rr_upm_cut_size_rows_v726", args: { lot_no: key } }
  ];

  for (const call of calls) {
    try {
      const { data, error } = await client.rpc(call.name, call.args);
      if (!error && Array.isArray(data)) {
        lotSizeCache.set(key, data);
        return data;
      }
    } catch (_) {}
  }

  lotSizeCache.set(key, []);
  return [];
}

function buildSizeMap(rows) {
  const map = new Map();

  for (const row of rows || []) {
    const code = upper(row.colour_code);
    const size = upper(row.size_code);
    if (!code || !size) continue;

    if (!map.has(code)) map.set(code, []);

    map.get(code).push({
      size,
      qty: Number(
        row.cutting_qty ??
        row.main_qty ??
        row.inbound_qty ??
        row.assigned_qty ??
        row.qty ??
        0
      ),
      alter: Number(
        row.alter_open_qty ??
        row.alter_qty ??
        row.alter_pending_qty ??
        0
      )
    });
  }

  for (const items of map.values()) {
    items.sort((a, b) => {
      const order = { S:1, M:2, L:3, XL:4, XXL:5, "2XL":5, "3XL":6, "4XL":7, "5XL":8 };
      return (order[a.size] || 99) - (order[b.size] || 99);
    });
  }

  return map;
}

function sizeInfoFromMap(sizeMap, colourCode) {
  const rows = sizeMap?.get(upper(colourCode)) || [];
  const summary = rows.map(item => `${item.size} ${item.qty}`).join(" · ");
  const alterRows = rows.filter(item => item.alter > 0);
  return {
    summary,
    alterQty: alterRows.reduce((sum, item) => sum + item.alter, 0),
    alterSizes: alterRows.map(item => `${item.size} ${item.alter} PCS`).join(" · ")
  };
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

let currentSizeMap = new Map();

function colourSizeInfo(colourCode) {
  const backendInfo = sizeInfoFromMap(currentSizeMap, colourCode);
  if (backendInfo.summary) return backendInfo;

  const card = findColourCard(colourCode);
  if (!card) return { summary: "", alterQty: 0, alterSizes: "" };

  const sizes = [];
  const alterSizes = [];
  let alterQty = 0;

  card.querySelectorAll("[data-row-index]").forEach(tableRow => {
    const cells = tableRow.querySelectorAll("td");
    const size = cells[0]?.textContent?.trim() || "";
    const mainQty = Number(cells[1]?.textContent?.trim() || 0);
    const alterPendingText = cells[4]?.textContent?.trim() || "0";
    const rowAlterQty = Number(alterPendingText || 0);

    if (size) {
      sizes.push(`${size} ${mainQty}`);
      if (rowAlterQty > 0) {
        alterSizes.push(`${size} ${rowAlterQty} PCS`);
        alterQty += rowAlterQty;
      }
    }
  });

  return {
    summary: sizes.join(" · "),
    alterQty,
    alterSizes: alterSizes.join(" · ")
  };
}

function compactAlterStatus(row) {
  const sizeInfo = colourSizeInfo(row.colour_code);
  const journey = row?.alter_journey;
  const journeyQty = Number(journey?.qty || 0);
  const totalAlter = Math.max(sizeInfo.alterQty, journeyQty);

  if (totalAlter <= 0) return "ALTER NONE";

  const responsible = [
    journey?.responsible_name,
    journey?.responsible_role_short
  ].filter(Boolean).join(" · ");

  const qtyText = sizeInfo.alterSizes
    ? `ALTER · ${sizeInfo.alterSizes}`
    : `ALTER ${totalAlter} PCS`;

  return [qtyText, responsible].filter(Boolean).join(" · ");
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

function isFirstWindowLotCard(card) {
  if (!card) return false;
  if (card.closest("#traveller")) return false;
  if (card.classList.contains("colour-card")) return false;

  return [...card.querySelectorAll("button")].some(button =>
    upper(button.textContent).includes("CHECK IN")
  );
}

function extractLotNoFromFirstWindowCard(card) {
  const explicit = getLotNoFromCard(card);
  if (explicit) return explicit;

  const lines = String(card.innerText || "")
    .split(/\n+/)
    .map(line => line.trim())
    .filter(Boolean);

  return lines.find(line =>
    /^[A-Z0-9][A-Z0-9_-]{2,20}$/i.test(line) &&
    !["OPEN QUEUE","CHECK IN","TOTAL CUT"].includes(upper(line))
  ) || "";
}

async function renderFirstWindowCard(card) {
  if (!isFirstWindowLotCard(card)) return;

  const canonical = card.dataset.lot || card.dataset.canonicalLotId || "";
  const lotNo = extractLotNoFromFirstWindowCard(card);
  if (!canonical && !lotNo) return;

  const data = await fetchMatrix(canonical, lotNo);
  const sizeRows = await fetchLotSizeRows(data?.lot_no || lotNo);
  const localSizeMap = buildSizeMap(sizeRows);
  const previousSizeMap = currentSizeMap;
  currentSizeMap = localSizeMap;
  const signature = matrixSignature(data) + JSON.stringify([...localSizeMap.entries()]);

  if (
    boardSignatures.get(card) === signature &&
    card.querySelector(".v756-short-summary")
  ) return;

  boardSignatures.set(card, signature);

  card.querySelectorAll(
    ".lot-live-list,.lot-live-status,.v753-route-bar,.v754-board-status," +
    ".v755-board-matrix,.v7552-short-matrix,.v756-short-summary"
  ).forEach(node => node.remove());

  const summary = document.createElement("div");
  summary.className = "v756-short-summary";

  summary.innerHTML = (data?.colours || []).map(row => {
    const sizeInfo = colourSizeInfo(row.colour_code);
    const ownerText = [
      row.department_name,
      row.worker_name || "Worker pending"
    ].filter(Boolean).join(" · ");

    return `
      <div class="v756-short-row ${statusClass(row)}">
        <div class="v757-code-size">
          <b>${esc(row.colour_code)}</b>
          ${sizeInfo.summary ? `<small class="v756-size-summary">${esc(sizeInfo.summary)}</small>` : ""}
        </div>
        <span class="v756-owner-summary">${esc(ownerText)}</span>
        <em>${esc(userStatus(row))}</em>
        <small class="v756-alter-summary">${esc(compactAlterStatus(row))}</small>
      </div>`;
  }).join("");

  const checkInButton = [...card.querySelectorAll("button")].find(button =>
    upper(button.textContent).includes("CHECK IN")
  );

  if (checkInButton) {
    checkInButton.insertAdjacentElement("beforebegin", summary);
  } else {
    card.appendChild(summary);
  }

  currentSizeMap = previousSizeMap;
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

function createSearchableDropdown({
  container,
  items,
  placeholder = "Search...",
  emptyText = "No matching option",
  valueKey = "value",
  labelKey = "label",
  onSelect = null
}) {
  if (!container) return null;

  const normalizedItems = (items || []).map(item => ({
    ...item,
    value: String(item[valueKey] ?? item.value ?? ""),
    label: String(item[labelKey] ?? item.label ?? "")
  }));

  container.innerHTML = `
    <div class="v757-search-select">
      <input type="search"
        class="v757-search-input"
        placeholder="${esc(placeholder)}"
        autocomplete="off"
        spellcheck="false">
      <input type="hidden" class="v757-search-value">
      <button type="button" class="v757-search-toggle" aria-label="Open list">▼</button>
      <div class="v757-search-list" hidden></div>
    </div>
  `;

  const root = container.querySelector(".v757-search-select");
  const search = root.querySelector(".v757-search-input");
  const hidden = root.querySelector(".v757-search-value");
  const toggle = root.querySelector(".v757-search-toggle");
  const list = root.querySelector(".v757-search-list");

  const render = query => {
    const q = upper(query);
    const filtered = normalizedItems.filter(item =>
      !q || upper(item.label).includes(q) || upper(item.searchText || "").includes(q)
    );

    list.innerHTML = filtered.length
      ? filtered.map(item => `
          <button type="button"
            class="v757-search-option"
            data-value="${esc(item.value)}">
            ${esc(item.label)}
          </button>
        `).join("")
      : `<div class="v757-search-empty">${esc(emptyText)}</div>`;

    list.hidden = false;
  };

  const choose = item => {
    hidden.value = item.value;
    search.value = item.label;
    list.hidden = true;
    root.classList.add("has-value");
    onSelect?.(item);
  };

  search.addEventListener("focus", () => render(search.value));
  search.addEventListener("input", () => {
    hidden.value = "";
    root.classList.remove("has-value");
    render(search.value);
  });

  toggle.addEventListener("click", () => {
    if (list.hidden) render(search.value);
    else list.hidden = true;
    search.focus();
  });

  list.addEventListener("click", event => {
    const option = event.target.closest(".v757-search-option");
    if (!option) return;

    const item = normalizedItems.find(entry => entry.value === option.dataset.value);
    if (item) choose(item);
  });

  document.addEventListener("click", event => {
    if (!root.contains(event.target)) list.hidden = true;
  });

  return {
    root,
    input: search,
    hidden,
    getValue: () => hidden.value,
    getLabel: () => search.value,
    setValue: value => {
      const item = normalizedItems.find(entry => entry.value === String(value || ""));
      if (item) choose(item);
    },
    clear: () => {
      hidden.value = "";
      search.value = "";
      root.classList.remove("has-value");
      list.hidden = true;
    }
  };
}

let bulkWorkerSearch = null;

async function renderBulkWorkers(departmentCode) {
  const host = $("v756BulkWorkerHost");
  if (!host) return;

  const workers = await fetchWorkers(departmentCode);

  const items = workers.map(worker => ({
    value: worker.worker_id,
    label: [
      worker.worker_name || "Unnamed",
      worker.worker_code
    ].filter(Boolean).join(" · "),
    searchText: [
      worker.worker_name,
      worker.worker_code,
      worker.department_code,
      worker.role_code
    ].filter(Boolean).join(" ")
  }));

  bulkWorkerSearch = createSearchableDropdown({
    container: host,
    items,
    placeholder: "Search mapped worker by name/code",
    emptyText: "No mapped worker found"
  });
}

function detailedRows(data) {
  return (data?.colours || []).map(row => {
    const sizeInfo = colourSizeInfo(row.colour_code);

    return `
      <tr class="v756-colour-row ${statusClass(row)}"
        data-v756-colour="${esc(row.colour_code)}"
        data-v756-department="${esc(row.department_code)}"
        data-v756-status="${esc(row.ownership_status)}">
        <td class="v756-colour">
          <b>${esc(row.colour_code)}</b>
          ${sizeInfo.summary ? `<small class="v756-row-sizes">${esc(sizeInfo.summary)}</small>` : ""}
        </td>
        <td>${esc(row.department_name)}</td>
        <td><span class="v756-active-label">${esc(userStatus(row))}</span></td>
        <td>${esc(row.worker_name || "Worker pending")}</td>
        <td class="v756-alter">${esc(compactAlterStatus(row))}</td>
        <td class="v756-actions">${rowActionButtons(row)}</td>
      </tr>`;
  }).join("");
}

function removeLegacyCheckinUi() {
  const traveller = $("traveller");
  if (!traveller) return;

  traveller.querySelectorAll(
    ".v7552-detail-panel,.v755-checkin-matrix,.v7552-short-matrix," +
    ".v755-board-matrix,.v756-short-summary"
  ).forEach(node => node.remove());

  // Old global-department messages are no longer valid in Colour-wise mode.
  $("debugBtn")?.setAttribute("hidden", "hidden");
  document.querySelector("details.debug")?.setAttribute("hidden", "hidden");
  $("formMsg")?.setAttribute("hidden", "hidden");

  // V755.2 may recreate these through its observer; CSS also hard-hides them.
}

async function renderCheckinTable() {
  const traveller = $("traveller");
  if (!traveller || traveller.classList.contains("hidden")) return;

  removeLegacyCheckinUi();

  const canonical = locateActiveCanonical();
  if (!canonical) return;

  currentMatrix = await fetchMatrix(canonical, "");
  activeCanonical = canonical;
  currentSizeMap = buildSizeMap(
    await fetchLotSizeRows(currentMatrix?.lot_no || "")
  );

  const nextSignature = matrixSignature(currentMatrix);
  let panel = $("v756ColourActionPanel");

  if (panel && checkinSignature === nextSignature) {
    return;
  }

  checkinSignature = nextSignature;
  if (!panel) {
    panel = document.createElement("section");
    panel.id = "v756ColourActionPanel";
    panel.className = "v756-panel";
    $("colours")?.insertAdjacentElement("beforebegin", panel);
  }

  panel.innerHTML = `
    <div class="v756-title">COLOUR-WISE PRODUCTION ACTIONS</div>

    <div class="v756-bulk">
      <strong>BULK ASSIGN</strong>
      <div id="v756BulkDepartmentHost"></div>
      <div id="v756BulkWorkerHost"></div>
      <button type="button" id="v756BulkAssign">ASSIGN ALL ELIGIBLE</button>
      <small id="v756BulkNote">Only OPEN Colours locked to the selected department will be assigned.</small>
    </div>

    <div class="v756-table-wrap">
      <table>
        <thead>
          <tr>
            <th>Colour / Size (PCS)</th>
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

  const departmentItems = [];
  const seenDepartments = new Set();

  for (const row of currentMatrix?.colours || []) {
    if (upper(row.ownership_status) !== "OPEN") continue;
    if (!row.department_code || seenDepartments.has(row.department_code)) continue;

    seenDepartments.add(row.department_code);
    departmentItems.push({
      value: row.department_code,
      label: row.department_name,
      searchText: `${row.department_name} ${row.department_code}`
    });
  }

  window.v757BulkDepartmentSearch = createSearchableDropdown({
    container: $("v756BulkDepartmentHost"),
    items: departmentItems,
    placeholder: "Search department",
    emptyText: "No OPEN department group",
    onSelect: item => renderBulkWorkers(item.value)
  });

  renderBulkWorkers("");
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

function selectColourCard(colourCode) {
  clearProgrammaticSelection();

  const card = findColourCard(colourCode);
  if (!card) return null;

  const pick = card.querySelector(".work-pick,.assign-pick");
  if (pick && !pick.disabled) {
    pick.checked = true;
    pick.dispatchEvent(new Event("change", { bubbles: true }));
  }

  // Legacy cards are engine-only and must never become visible.
  document.querySelectorAll(".colour-card").forEach(item => {
    item.classList.add("v756-detail-hidden");
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

function tableRowForButton(button) {
  return button.closest(".v756-colour-row");
}

function removeInlinePanels(exceptRow = null) {
  document.querySelectorAll(".v756-inline-action").forEach(panel => {
    if (!exceptRow || panel.closest(".v756-colour-row") !== exceptRow) {
      panel.remove();
    }
  });
}

function closeInlineAction(rowElement) {
  rowElement?.querySelector(".v756-inline-action")?.remove();
  document.querySelectorAll(".v756-colour-row").forEach(row => {
    row.classList.remove("v756-action-focus", "v756-action-dim");
  });
}

function workerOptionsFromCard(card) {
  const select = card?.querySelector(".colour-worker");
  if (!select) return '<option value="">No worker mapped</option>';

  return [...select.options]
    .filter(option => option.value)
    .map(option => `<option value="${esc(option.value)}">${esc(option.textContent.trim())}</option>`)
    .join("");
}

function sizeInputsFromCard(card, inputClass, sourceSelect = false) {
  const rows = [...(card?.querySelectorAll("[data-row-index]") || [])];

  return rows.map(tableRow => {
    const size = tableRow.querySelector("td:first-child")?.textContent?.trim() || "";
    const sourceInput = tableRow.querySelector(`.${inputClass}`);
    const max = Number(sourceInput?.max || 0);

    if (!sourceInput || sourceInput.disabled || max <= 0) return "";

    return `
      <div class="v756-size-input" data-engine-row="${esc(tableRow.dataset.rowIndex)}">
        <b>${esc(size)}</b>
        <input type="number" min="0" max="${esc(max)}" value="0"
          class="v756-inline-qty" data-target-class="${esc(inputClass)}">
        ${sourceSelect ? `
          <select class="v756-inline-source">
            <option value="PENDING">Good Qty</option>
            <option value="ALTER">Alter Pending</option>
            <option value="REMAKE">Remake Pending</option>
          </select>` : ""}
        <small>Max ${esc(max)}</small>
      </div>`;
  }).filter(Boolean).join("");
}

function applyInlineQuantities(panel, card, inputClass, sourceSelect = false) {
  card.querySelectorAll(`.${inputClass}`).forEach(input => input.value = "0");

  let entered = 0;

  panel.querySelectorAll(".v756-size-input").forEach(item => {
    const engineIndex = item.dataset.engineRow;
    const engineRow = card.querySelector(`[data-row-index="${CSS.escape(engineIndex)}"]`);
    const qty = Number(item.querySelector(".v756-inline-qty")?.value || 0);
    const target = engineRow?.querySelector(`.${inputClass}`);

    if (target) target.value = String(qty);

    if (sourceSelect) {
      const source = item.querySelector(".v756-inline-source")?.value || "PENDING";
      const targetSource = engineRow?.querySelector(".damageSource");
      if (targetSource) targetSource.value = source;
    }

    entered += qty;
  });

  if (entered <= 0) throw new Error("कम से कम एक Size में Qty भरें.");
}

function appendInlinePanel(rowElement, html) {
  removeInlinePanels(rowElement);
  rowElement.querySelector(".v756-inline-action")?.remove();

  const panel = document.createElement("td");
  panel.className = "v756-inline-action";
  panel.colSpan = 6;
  panel.innerHTML = html;

  const detailRow = document.createElement("tr");
  detailRow.className = "v756-inline-row";
  detailRow.appendChild(panel);

  rowElement.insertAdjacentElement("afterend", detailRow);
  return panel;
}

function decorateSingleColourAssignConfirmation({
  colourCode,
  departmentName,
  workerLabel,
  sizeSummary
}) {
  const apply = () => {
    const modal = $("actionConfirmModal");
    if (!modal || modal.classList.contains("hidden")) return false;

    $("actionConfirmTitle").textContent = "CONFIRM COLOUR ASSIGNMENT";

    $("actionConfirmCopy").innerHTML = `
      <b>क्या आप पूरा Colour ${esc(colourCode)} assign करना चाहते हैं?</b><br>
      Department: ${esc(departmentName)}<br>
      Worker: ${esc(workerLabel || "Selected worker")}<br>
      Colour: ${esc(colourCode)}
      ${sizeSummary ? `<br>Sizes: ${esc(sizeSummary)}` : ""}
    `;

    $("actionConfirmColours").innerHTML =
      `<span class="badge">${esc(colourCode)}</span>`;

    $("actionConfirmNextWrap")?.classList.add("hidden");
    $("actionConfirmYes").textContent = `YES · ASSIGN ${upper(colourCode)}`;
    modal.dataset.v757SingleColour = upper(colourCode);
    return true;
  };

  if (apply()) return;
  setTimeout(apply, 0);
  setTimeout(apply, 50);
  setTimeout(apply, 150);
}

function ensureWorkerOption(select, workerId, workerLabel) {
  if (!select || !workerId) return null;

  let option = [...select.options].find(item => item.value === workerId);

  if (!option) {
    option = document.createElement("option");
    option.value = workerId;
    option.textContent = workerLabel || workerId;
    option.dataset.v757Bridge = "1";
    select.appendChild(option);
  }

  return option;
}

async function openAssignPanel(rowData, rowElement, card) {
  let workers = await fetchWorkers(rowData.department_code);

  // Fallback to the original hidden card options if RPC list is unavailable.
  if (!workers.length) {
    const engineSelect = card?.querySelector(".colour-worker");
    workers = [...(engineSelect?.options || [])]
      .filter(option => option.value)
      .map(option => ({
        worker_id: option.value,
        worker_name: option.textContent.trim(),
        worker_code: ""
      }));
  }

  const workerItems = workers.map(worker => ({
    value: worker.worker_id,
    label: [
      worker.worker_name || "Unnamed",
      worker.worker_code
    ].filter(Boolean).join(" · "),
    searchText: [
      worker.worker_name,
      worker.worker_code,
      worker.role_code,
      worker.department_code
    ].filter(Boolean).join(" ")
  }));

  const panel = appendInlinePanel(rowElement, `
    <div class="v756-inline-head">
      <b>${esc(rowData.colour_code)} · Assign Worker</b>
      <button type="button" class="v756-inline-cancel">CANCEL</button>
    </div>
    <div class="v756-inline-grid assign">
      <label>Department
        <input value="${esc(rowData.department_name)}" disabled>
      </label>
      <label>Mapped Worker
        <div class="v757-inline-worker-host"></div>
      </label>
      <button type="button" class="v756-inline-save primary">CONFIRM ASSIGN</button>
      <span class="v7571-assign-note"></span>
    </div>
  `);

  const workerSearch = createSearchableDropdown({
    container: panel.querySelector(".v757-inline-worker-host"),
    items: workerItems,
    placeholder: "Search worker by name or code",
    emptyText: "No active mapped worker in this department"
  });

  panel.querySelector(".v756-inline-cancel").onclick = () => closeInlineAction(rowElement);

  panel.querySelector(".v756-inline-save").onclick = async () => {
    try {
      const workerId = workerSearch?.getValue?.();
      const workerLabel = workerSearch?.getLabel?.() || workerId;
      if (!workerId) throw new Error("Mapped worker search करके select करें.");

      // Hard reset: only this Colour may enter the assignment payload.
      clearProgrammaticSelection();

      const pick = card.querySelector(".work-pick,.assign-pick");
      if (!pick || pick.disabled) {
        throw new Error(`${rowData.colour_code} assignment के लिए selectable नहीं है.`);
      }

      pick.checked = true;
      pick.dispatchEvent(new Event("change", { bubbles: true }));

      const engineWorker = card.querySelector(".colour-worker");
      if (!engineWorker) throw new Error("Hidden Colour worker dropdown नहीं मिला.");

      const workerOption = ensureWorkerOption(
        engineWorker,
        workerId,
        workerLabel
      );

      if (!workerOption) {
        throw new Error("Selected mapped worker को Colour engine में bind नहीं किया जा सका.");
      }

      engineWorker.value = workerId;
      engineWorker.dispatchEvent(new Event("change", { bubbles: true }));

      const bulkWorker = $("bulkWorker");
      if (bulkWorker) {
        const bulkOption = ensureWorkerOption(
          bulkWorker,
          workerId,
          workerLabel
        );

        if (!bulkOption) {
          throw new Error("Selected mapped worker को original assignment engine में bind नहीं किया जा सका.");
        }

        bulkWorker.value = workerId;
        bulkWorker.dispatchEvent(new Event("change", { bubbles: true }));
      }

      if ($("applyBulkWorkerBtn")) {
        clickExistingButton("applyBulkWorkerBtn");
        await new Promise(resolve => setTimeout(resolve, 120));
      }

      clickExistingButton("assignBtn");

      // This is a single-row action. V729 can mislabel it as full Lot when
      // this Colour is the only currently available Colour.
      decorateSingleColourAssignConfirmation({
        colourCode: rowData.colour_code,
        departmentName: rowData.department_name,
        workerLabel,
        sizeSummary: colourSizeInfo(rowData.colour_code)?.summary || ""
      });

      const refreshAfterAssignment = async () => {
        workerCache.clear();
        lotSizeCache.clear();
        checkinSignature = "";
        await new Promise(resolve => setTimeout(resolve, 900));
        await syncAll();
      };

      setTimeout(refreshAfterAssignment, 500);
      closeInlineAction(rowElement);
    } catch (error) {
      alert(error.message || String(error));
    }
  };
}

function actionConfig(action) {
  return {
    ALTER: {
      title: "ALTER FILL",
      inputClass: "alterEntry",
      buttonId: "alterBtn",
      sourceSelect: false
    },
    DAMAGE: {
      title: "SAVE DAMAGE",
      inputClass: "damageEntry",
      buttonId: "damageBtn",
      sourceSelect: true
    },
    REMAKE_ISSUE: {
      title: "REMAKE ISSUE · CM",
      inputClass: "remakeIssueEntry",
      buttonId: "remakeIssueBtn",
      sourceSelect: false
    },
    RECEIVE_MASTER: {
      title: "RECEIVE MASTER · LM",
      inputClass: "receiveMasterEntry",
      buttonId: "remakeDeliveredBtn",
      sourceSelect: false
    },
    DELIVER_KARIGAR: {
      title: "DELIVER KARIGAR · LM",
      inputClass: "deliverKarigarEntry",
      buttonId: "remakeCompleteBtn",
      sourceSelect: false
    },
    RECEIVE_KARIGAR: {
      title: "RECEIVE KARIGAR · LM",
      inputClass: "receiveKarigarEntry",
      buttonId: "receiveKarigarBtn",
      sourceSelect: false
    }
  }[action] || null;
}

function openQuantityPanel(rowData, rowElement, card, action) {
  const config = actionConfig(action);
  if (!config) return;

  const inputs = sizeInputsFromCard(card, config.inputClass, config.sourceSelect);
  if (!inputs) throw new Error(`${config.title} के लिए कोई pending Qty उपलब्ध नहीं है.`);

  const panel = appendInlinePanel(rowElement, `
    <div class="v756-inline-head">
      <b>${esc(rowData.colour_code)} · ${esc(config.title)}</b>
      <button type="button" class="v756-inline-cancel">CANCEL</button>
    </div>
    <div class="v756-size-grid">${inputs}</div>
    <div class="v756-inline-foot">
      <button type="button" class="v756-inline-save primary">SAVE ${esc(config.title)}</button>
    </div>
  `);

  panel.querySelector(".v756-inline-cancel").onclick = () => closeInlineAction(rowElement);

  panel.querySelector(".v756-inline-save").onclick = () => {
    try {
      applyInlineQuantities(
        panel,
        card,
        config.inputClass,
        config.sourceSelect
      );

      clickExistingButton(config.buttonId);
      closeInlineAction(rowElement);
    } catch (error) {
      alert(error.message || String(error));
    }
  };
}

async function runBulkAssign() {
  try {
    const department = window.v757BulkDepartmentSearch?.getValue?.() || "";
    const workerId = bulkWorkerSearch?.getValue?.() || "";

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
      `Worker: ${bulkWorkerSearch?.getLabel?.() || workerId}\n\nConfirm?`
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

    clickExistingButton("assignBtn");
  } catch (error) {
    alert(error.message || String(error));
  }
}

async function handleRowAction(button) {
  const colourCode = upper(button.dataset.v756Colour);
  const action = upper(button.dataset.v756Action);
  const rowData = (currentMatrix?.colours || [])
    .find(item => upper(item.colour_code) === colourCode);

  if (!rowData) return;

  const rowElement = tableRowForButton(button);
  if (!rowElement) return;

  try {
    focusActionRow(colourCode);
    removeInlinePanels(rowElement);

    await ensureDepartmentContext(rowData.department_code);

    const card = selectColourCard(colourCode);
    if (!card) throw new Error(`Colour ${colourCode} का hidden action engine नहीं मिला.`);

    if (action === "ASSIGN") {
      await openAssignPanel(rowData, rowElement, card);
      return;
    }

    if (["ALTER", "DAMAGE", "REMAKE_ISSUE", "RECEIVE_MASTER",
      "DELIVER_KARIGAR", "RECEIVE_KARIGAR"].includes(action)) {
      openQuantityPanel(rowData, rowElement, card, action);
      return;
    }

    if (action === "SUBMIT") {
      clickExistingButton("submitBtn");
      return;
    }
  } catch (error) {
    alert(error.message || String(error));
    closeInlineAction(rowElement);
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

  installRefreshBridge();

  if (observer) observer.disconnect();

  try {
    await Promise.all(
      [...document.querySelectorAll(".lot-card")]
        .filter(isFirstWindowLotCard)
        .map(renderFirstWindowCard)
    );

    await renderCheckinTable();
  } catch (error) {
    console.error(VERSION, error);
  } finally {
    syncing = false;

    if (observer) {
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["class"]
      });
    }
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
      grid-template-columns:minmax(150px,1.2fr) minmax(150px,1fr) 65px;
      gap:5px 10px;
      padding:8px 9px;
      border:1px solid #465365;
      border-radius:7px;
      background:#171d26
    }
    .v756-short-row small{color:#c8d2df}
    .v757-code-size{display:grid;gap:3px;min-width:0}
    .v757-code-size b{font-size:13px}
    .v756-short-row .v756-alter-summary{grid-column:2/4}
    .v756-short-row .v756-size-summary{grid-column:auto}
    .v756-owner-summary{
      color:#ffffff;
      font-weight:900;
      overflow:hidden;
      text-overflow:ellipsis;
      white-space:nowrap
    }
    .v756-size-summary{
      color:#ffffff!important;
      font-weight:900;
      letter-spacing:.1px
    }
    .v756-alter-summary{
      color:#ffd66b!important;
      font-weight:950
    }
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
      grid-template-columns:auto minmax(200px,1fr) minmax(240px,1fr) auto;
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
    .v756-panel table{min-width:1180px!important}
    .v756-colour{min-width:210px}
    .v756-colour-row{transition:opacity .2s,filter .2s,outline .2s}
    .v756-colour-row.running{background:#103d2c}
    .v756-colour-row.assigned{background:#4b330d}
    .v756-colour-row.open{background:#112d49}
    .v756-colour-row.legacy{background:#471820}
    .v756-row-sizes{
      display:block;
      margin-top:4px;
      color:#dbe7f5;
      font-weight:850;
      font-size:11px
    }
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
    .v756-detail-hidden,
    #traveller .colour-card{
      display:none!important;
    }

    .v756-inline-row{background:#090d13!important}
    .v756-inline-action{
      padding:12px!important;
      border:2px solid #378fd2!important;
      background:#0e1a28!important;
      white-space:normal!important;
    }
    .v756-inline-head{
      display:flex;justify-content:space-between;align-items:center;
      gap:10px;margin-bottom:10px
    }
    .v756-inline-grid.assign{
      display:grid;
      grid-template-columns:minmax(180px,1fr) minmax(220px,1fr) auto;
      gap:8px;align-items:end
    }
    .v756-inline-grid label{display:grid;gap:4px;color:#b8c9dd}
    .v756-inline-grid input,.v756-inline-grid select{width:100%}
    .v756-size-grid{
      display:grid;
      grid-template-columns:repeat(auto-fit,minmax(180px,1fr));
      gap:8px
    }
    .v756-size-input{
      display:grid;
      grid-template-columns:45px minmax(70px,1fr);
      gap:6px;align-items:center;
      padding:8px;border:1px solid #40536d;
      border-radius:8px;background:#131d2a
    }
    .v756-size-input small{grid-column:1/-1;color:#9eb0c5}
    .v756-size-input select{grid-column:1/-1;width:100%}
    .v756-inline-foot{display:flex;justify-content:flex-end;margin-top:10px}
    .v756-inline-cancel{background:#3d2027;border-color:#81404c}

    .v757-search-select{
      position:relative;
      display:grid;
      grid-template-columns:minmax(0,1fr) 38px;
      min-width:180px
    }
    .v757-search-input{
      width:100%;
      min-height:38px;
      padding:8px 10px;
      border-radius:8px 0 0 8px!important;
      border-right:0!important
    }
    .v757-search-toggle{
      min-height:38px;
      border-radius:0 8px 8px 0!important;
      padding:0!important;
      background:#28364a;
      border-color:#536984
    }
    .v757-search-list{
      position:absolute;
      top:calc(100% + 4px);
      left:0;
      right:0;
      z-index:10020;
      max-height:240px;
      overflow:auto;
      padding:5px;
      background:#0c131e;
      border:1px solid #536984;
      border-radius:8px;
      box-shadow:0 10px 24px #000b
    }
    .v757-search-option{
      display:block;
      width:100%;
      margin:0 0 4px;
      padding:9px 10px;
      text-align:left;
      background:#172337;
      border:1px solid #324866;
      border-radius:6px;
      color:#fff
    }
    .v757-search-option:hover,
    .v757-search-option:focus{
      background:#20558a;
      border-color:#5aa8ee
    }
    .v757-search-empty{
      padding:10px;
      color:#9eabbc;
      text-align:center
    }

    #debugBtn,
    details.debug,
    #traveller #formMsg,
    #traveller #summary,
    #traveller #freezeSummary,
    #traveller .legend,
    #traveller .formbar{
      display:none!important;
    }

    #traveller .v7552-detail-panel,
    #traveller .v755-checkin-matrix,
    #traveller .v7552-short-matrix,
    #traveller .v755-board-matrix,
    #traveller .v756-short-summary{
      display:none!important;
    }

    @media(max-width:900px){
      .v756-bulk{grid-template-columns:1fr}
      .v756-actions{min-width:320px}
    }
  `;

  document.head.appendChild(style);
}


function showV756Badge() {
  let badge = document.getElementById("v756ActiveBadge");
  if (!badge) {
    badge = document.createElement("div");
    badge.id = "v756ActiveBadge";
    badge.textContent = "V757.5 ACTIVE";
    badge.style.cssText = `
      position:fixed;right:12px;bottom:12px;z-index:99999;
      background:#075f85;color:#fff;padding:9px 12px;
      border-radius:9px;font-weight:950;box-shadow:0 4px 18px #0008;
    `;
    document.body.appendChild(badge);
    setTimeout(() => badge.remove(), 4000);
  }
}

function installRefreshBridge() {
  const refreshButton = $("refresh");
  if (!refreshButton || refreshButton.dataset.v757RefreshBridge === "1") return;

  refreshButton.dataset.v757RefreshBridge = "1";

  refreshButton.addEventListener("click", () => {
    // Let the original V729 refresh/load execute first.
    workerCache.clear();
    lotSizeCache.clear();
    checkinSignature = "";
    activeCanonical = "";

    // New board cards are created asynchronously; invalidate and resync in stages.
    const resync = async () => {
      document.querySelectorAll(".v756-short-summary").forEach(node => node.remove());

      document.querySelectorAll(".lot-card").forEach(card => {
        boardSignatures.delete(card);
      });

      await syncAll();
    };

    setTimeout(resync, 250);
    setTimeout(resync, 800);
    setTimeout(resync, 1600);
  }, true);
}

function install() {
  document.getElementById("v755HardBootBadge")?.remove();
  showV756Badge();
  addStyles();
  bindGlobalClicks();
  installRefreshBridge();
  syncAll();

  observer = new MutationObserver(mutations => {
    const meaningful = mutations.some(mutation => {
      const target = mutation.target;
      if (!(target instanceof Element)) return true;

      return !target.closest(
        ".v756-short-summary,#v756ColourActionPanel,#v756ActiveBadge"
      );
    });

    if (!meaningful) return;

    clearTimeout(observerTimer);
    observerTimer = setTimeout(syncAll, 220);
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["class"]
  });
}

document.readyState === "loading"
  ? document.addEventListener("DOMContentLoaded", install)
  : install();

window.REDZED_UPM_V757_5 = {
  version: VERSION,
  sync: syncAll
};

console.info("REDZED UPM", VERSION);
})();