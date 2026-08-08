(() => {
"use strict";

const VERSION = "V765_DEPARTMENT_INDEPENDENT_ALTER_UI";
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
let pendingV760Submit = null;
let activeCostingPanel = null;
let v760SubmitBypassOnce = null;
let v76043DepartmentCache = null;
let v764CompletedCache = new Map();

function canonicalDepartmentV762(value) {
  const raw = upper(value);
  const key = raw.replace(/[^A-Z0-9]+/g, "");

  return {
    OV: "OVERLOCK",
    OVERLOCK: "OVERLOCK",
    OVERLOCKING: "OVERLOCK",

    FLD: "FOLDING",
    FOLD: "FOLDING",
    FOLDING: "FOLDING",
    FLATLOCK: "FOLDING",

    PRINT: "PRINTING",
    PRINTER: "PRINTING",
    PRINTING: "PRINTING",

    KR: "STITCHING",
    KARIGAR: "STITCHING",
    STITCH: "STITCHING",
    STITCHING: "STITCHING",

    THCUT: "THREAD_CUT",
    THREADCUT: "THREAD_CUT",
    THREADCUTTING: "THREAD_CUT",

    CHECK: "QC",
    CHECKING: "QC",
    QUALITYCHECK: "QC",
    QC: "QC",

    KAJ: "KAAJ",
    KAAJ: "KAAJ",
    BTN: "BUTTON",
    BUTTON: "BUTTON",

    PRESSFINISHING: "PRESS",
    FINISHING: "PRESS",
    PRESS: "PRESS",

    PACK: "PACKING",
    PACKING: "PACKING",

    OPENNEXT: "OPEN_NEXT",
    OPENFORNEXTPROCESS: "OPEN_NEXT"
  }[key] || raw;
}

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

async function fetchCompletedDepartmentMapV764() {
  const canonical =
    currentMatrix?.canonical_lot_id
    || activeCanonical
    || locateActiveCanonical();

  const empty = {
    completedByColour: new Map(),
    fullyCompletedDepartments: new Set()
  };

  if (!canonical) return empty;
  if (v764CompletedCache.has(canonical)) {
    return v764CompletedCache.get(canonical);
  }

  const client = getClient();
  if (!client) return empty;

  const { data, error } = await client.rpc(
    "rr_upm_completed_departments_v764",
    { p_canonical_lot_id: canonical }
  );

  if (error) throw error;

  const completedByColour = new Map();

  for (const row of data?.completed_pairs || []) {
    const colour = upper(row.colour_code);
    const department =
      canonicalDepartmentV762(row.department_code);

    if (!completedByColour.has(colour)) {
      completedByColour.set(colour, new Set());
    }

    completedByColour.get(colour).add(department);
  }

  const result = {
    completedByColour,
    fullyCompletedDepartments: new Set(
      (data?.fully_completed_departments || [])
        .map(canonicalDepartmentV762)
    )
  };

  v764CompletedCache.set(canonical, result);
  return result;
}

async function assignableDepartmentsForColourV764(colourCode) {
  const [departments, history] = await Promise.all([
    fetchAssignableDepartmentsV76043(),
    fetchCompletedDepartmentMapV764()
  ]);

  const completed =
    history.completedByColour.get(upper(colourCode))
    || new Set();

  return departments.filter(department =>
    !completed.has(
      canonicalDepartmentV762(department.department_code)
    )
  );
}

async function assignableDepartmentsForBulkV764() {
  const [departments, history] = await Promise.all([
    fetchAssignableDepartmentsV76043(),
    fetchCompletedDepartmentMapV764()
  ]);

  return departments.filter(department =>
    !history.fullyCompletedDepartments.has(
      canonicalDepartmentV762(department.department_code)
    )
  );
}

function isAssignableDepartmentV76043(row) {
  const code = canonicalDepartmentV762(row?.department_code);
  const type = upper(row?.department_type || "PRODUCTION");

  return Boolean(
    code
    && ![
      "ADMIN",
      "ACCOUNTS",
      "CUTTING",
      "FABRICATION",
      "SALES",
      "DISPATCH",
      "DISTRIBUTOR",
      "OPEN_NEXT"
    ].includes(code)
    && ["PRODUCTION","FABRICATION"].includes(type)
    && row?.is_active !== false
    && row?.production_enabled !== false
    && row?.colour_assignment_enabled !== false
    && row?.worker_assignment_enabled !== false
  );
}
async function fetchAssignableDepartmentsV76043() {
  if (Array.isArray(v76043DepartmentCache)) {
    return v76043DepartmentCache;
  }

  const client = getClient();
  if (!client) return [];

  const { data, error } = await client
    .from("rr_upm_department_catalog_v762")
    .select(
      "department_code,department_name,department_type,is_active," +
      "production_enabled,colour_assignment_enabled," +
      "worker_assignment_enabled,sequence_no"
    )
    .order("sequence_no", { ascending: true });

  if (error) throw error;

  const seen = new Set();

  v76043DepartmentCache = (data || [])
    .map(row => ({
      ...row,
      department_code: canonicalDepartmentV762(row.department_code)
    }))
    .filter(isAssignableDepartmentV76043)
    .filter(row => {
      if (seen.has(row.department_code)) return false;
      seen.add(row.department_code);
      return true;
    });

  return v76043DepartmentCache;
}

function departmentDropdownItemsV76043(departments) {
  return (departments || []).map(department => ({
    value: upper(department.department_code),
    label: department.department_name || department.department_code,
    searchText: [
      department.department_name,
      department.department_code
    ].filter(Boolean).join(" ")
  }));
}

async function fetchWorkers(departmentCode) {
  const department = canonicalDepartmentV762(departmentCode);
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

async function fetchCostingPanelV760(canonical) {
  const client = getClient();
  if (!client) throw new Error("Connected Supabase client nahi mila.");

  const { data, error } = await client.rpc("rr_upm_costing_panel_v760", {
    p_canonical_lot_id: canonical
  });

  if (error) throw error;
  return data;
}

function costingDepartmentOrderV760(code) {
  return {
    CUTTING: 10,
    STICKER: 20,
    PRINTING: 30,
    STITCHING: 40,
    OVERLOCK: 50,
    FOLDING: 60,
    KAJ_BUTTON: 70,
    TANKI_TACK: 80,
    QC: 90,
    THREAD_CUT: 100,
    PRESS: 110,
    PACKING: 120,
    OTHER: 130
  }[String(code || "").toUpperCase()] ?? 999;
}

function isRealCostingDepartmentV760(code) {
  const key = String(code || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, "");

  return ![
    "",
    "OPENNEXT",
    "OPENFORNEXTPROCESS",
    "NEXTPROCESS",
    "OPEN",
    "UNASSIGNED",
    "ROUTEGATE"
  ].includes(key);
}

function costingRateRowsV760(data) {
  const rates = [...(data?.rates || [])]
    .filter(rate => isRealCostingDepartmentV760(rate.department_code))
    .sort((a, b) =>
      costingDepartmentOrderV760(a.department_code)
      - costingDepartmentOrderV760(b.department_code)
      || String(a.department_name || "").localeCompare(
        String(b.department_name || "")
      )
    );

  return rates.map(rate => `
    <div class="v760-rate-row"
      data-department="${esc(rate.department_code)}"
      data-original="${esc(rate.actual_rate ?? "")}">
      <div>
        <b>${esc(rate.department_name)}</b>
        <small>${esc(rate.department_code)}</small>
      </div>
      <label>Actual Rate
        <input type="number"
          min="0"
          step="0.01"
          class="v760-actual-rate"
          value="${rate.actual_rate ?? ""}"
          ${rate.editable ? "" : "disabled"}>
      </label>
      <label>Standard
        <input value="${esc(rate.standard_rate ?? 0)}" disabled>
      </label>
      <span class="v760-rate-source ${String(rate.rate_source || "").toLowerCase()}">
        ${esc(rate.rate_source)}
      </span>
    </div>
  `).join("");
}
function closeCostingPanelV760() {
  document.getElementById("v760CostingOverlay")?.remove();
  activeCostingPanel = null;
}

async function openCostingPanelV760(canonical, focusDepartment = "") {
  if (!canonical) throw new Error("Canonical Lot ID nahi mila.");

  closeCostingPanelV760();

  const data = await fetchCostingPanelV760(canonical);
  const scope = data?.scope || {};
  const costing = data?.costing || {};
  const loss = data?.company_loss || {};

  const overlay = document.createElement("div");
  overlay.id = "v760CostingOverlay";
  overlay.className = "v760-costing-overlay";
  overlay.innerHTML = `
    <div class="v760-costing-modal">
      <div class="v760-costing-head">
        <div>
          <b>COSTING · ${esc(data?.lot?.lot_no || "")}</b>
          <small>${esc(data?.lot?.art_no || "")} · ${esc(data?.lot?.item_name || "")}</small>
        </div>
        <button type="button" class="v760-close">CLOSE</button>
      </div>

      ${scope.can_view_material ? `
        <section class="v760-section">
          <h3>Material Cost · Owner Only</h3>
          <div class="v760-material-grid">
            <label>Regular Fabric / PCS
              <input type="number" min="0" step="0.01"
                id="v760RegularFabric"
                value="${esc(costing.regular_fabric_cost_per_piece ?? 0)}">
            </label>
            <label>Matching / PCS
              <input type="number" min="0" step="0.01"
                id="v760Matching"
                value="${esc(costing.matching_cost_per_piece ?? 0)}">
            </label>
            <label>Other Material / PCS
              <input type="number" min="0" step="0.01"
                id="v760OtherMaterial"
                value="${esc(costing.other_material_cost_per_piece ?? 0)}">
            </label>
            <label>Material Status
              <select id="v760MaterialStatus">
                ${["MISSING","PARTIAL","ACTUAL","NOT_APPLICABLE"].map(value =>
                  `<option value="${value}"
                    ${value === costing.material_cost_status ? "selected" : ""}>
                    ${value}
                  </option>`
                ).join("")}
              </select>
            </label>
            ${scope.can_edit_owner_margin ? `
              <label>Owner Margin · Flat / PCS
                <input type="number" min="0" step="0.01"
                  id="v760OwnerMargin"
                  value="${esc(costing.owner_margin_flat ?? 0)}">
              </label>` : ""}
            <button type="button" id="v760SaveMaterial">
              SAVE MATERIAL / MARGIN
            </button>
          </div>
        </section>` : ""}

      <section class="v760-section v760-top-summary">
        <h3>Live Cost Summary</h3>
        <div class="v760-summary-grid">
          <span>Material <b>₹${esc(costing.material_total ?? 0)}</b></span>
          <span>Making <b>₹${esc(
            Number(costing.process_actual_total || 0)
            + Number(costing.process_standard_fallback_total || 0)
          )}</b></span>
          <span>Owner Margin <b>₹${esc(costing.owner_margin_flat ?? 0)}</b></span>
          <span>Company Cost <b>₹${esc(costing.base_cost_per_piece ?? 0)}</b></span>
          <span>Sale Price <b>₹${esc(
            costing.store_price_locked
              ? costing.locked_sale_price
              : costing.final_sale_price
          )}</b></span>
        </div>
      </section>

      <section class="v760-section">
        <h3>Department Actual Rates</h3>
        <div class="v760-rate-list">
          ${costingRateRowsV760(data)}
        </div>
        <div class="v760-save-all-wrap">
          <button type="button" id="v760SaveAllRates">
            SAVE COSTING
          </button>
          <small id="v760RateSaveStatus"></small>
        </div>
      </section>

      <section class="v760-section">
        <h3>Cost Summary</h3>
        <div class="v760-summary-grid">
          <span>Material <b>₹${esc(costing.material_total ?? 0)}</b></span>
          <span>Actual Process <b>₹${esc(costing.process_actual_total ?? 0)}</b></span>
          <span>Standard Fallback <b>₹${esc(costing.process_standard_fallback_total ?? 0)}</b></span>
          <span>Base Cost / PCS <b>₹${esc(costing.base_cost_per_piece ?? 0)}</b></span>
          <span>Owner Margin <b>₹${esc(costing.owner_margin_flat ?? 0)}</b></span>
          <span>Sale Price <b>₹${esc(
            costing.store_price_locked
              ? costing.locked_sale_price
              : costing.final_sale_price
          )}</b></span>
        </div>
      </section>

      <section class="v760-section v760-loss-section">
        <h3>Company Loss · Damage Effect</h3>
        <div class="v760-summary-grid">
          <span>Gross Damage Loss <b>₹${esc(loss.gross_damage_loss ?? 0)}</b></span>
          <span>Worker Claim Booked <b>₹${esc(loss.worker_claim_booked ?? 0)}</b></span>
          <span>No-Claim Factory Loss <b>₹${esc(loss.no_claim_factory_loss ?? 0)}</b></span>
          <span>Recovery / Relaxation <b>₹${esc(loss.recovery_or_relaxation ?? 0)}</b></span>
          <span>Net Company Loss <b>₹${esc(loss.net_company_loss ?? 0)}</b></span>
        </div>
        <small>Har Damage costing level par Company Loss hai. Recovery alag count hogi.</small>
      </section>

      ${scope.is_owner || scope.role === "admin" ? `
        <section class="v760-section">
          <button type="button" id="v760LockStorePrice"
            ${costing.store_price_locked ? "disabled" : ""}>
            ${costing.store_price_locked
              ? "STORE PRICE LOCKED"
              : "LOCK STORE / WEB SALE PRICE"}
          </button>
        </section>` : ""}
    </div>
  `;

  document.body.appendChild(overlay);
  activeCostingPanel = { canonical, data };

  overlay.querySelector(".v760-close").onclick = closeCostingPanelV760;
  overlay.addEventListener("click", event => {
    if (event.target === overlay) closeCostingPanelV760();
  });

  overlay.querySelectorAll(".v760-actual-rate").forEach(input => {
    input.addEventListener("input", () => {
      const row = input.closest(".v760-rate-row");
      const source = row.querySelector(".v760-rate-source");
      const value = Number(input.value || 0);
      const original = Number(row.dataset.original || 0);

      if (value > 0) {
        source.textContent = value === original ? "ACTUAL" : "UNSAVED ACTUAL";
        source.className = "v760-rate-source actual";
      } else {
        const standard = Number(
          row.querySelector('label:nth-of-type(2) input')?.value || 0
        );
        source.textContent = standard > 0 ? "STANDARD FALLBACK" : "MISSING";
        source.className =
          `v760-rate-source ${standard > 0 ? "standard_fallback" : "missing"}`;
      }
    });
  });

  overlay.querySelector("#v760SaveAllRates")?.addEventListener("click", async event => {
    const button = event.currentTarget;
    const status = overlay.querySelector("#v760RateSaveStatus");
    const changed = [...overlay.querySelectorAll(".v760-rate-row")]
      .map(row => ({
        row,
        department: row.dataset.department,
        original: Number(row.dataset.original || 0),
        rate: Number(row.querySelector(".v760-actual-rate")?.value || 0),
        disabled: row.querySelector(".v760-actual-rate")?.disabled
      }))
      .filter(item =>
        !item.disabled
        && item.rate > 0
        && item.rate !== item.original
      );

    if (!changed.length) {
      status.textContent = "Koi changed Actual Rate nahi hai.";
      return;
    }

    button.disabled = true;
    status.textContent = `${changed.length} Rate save ho rahi hain...`;

    try {
      const client = getClient();

      for (const item of changed) {
        const requestId =
          pendingV760Submit?.departmentCode === item.department
            ? pendingV760Submit.requestId
            : null;

        const { error } = await client.rpc("rr_upm_set_department_rate_v760", {
          p_canonical_lot_id: canonical,
          p_department_code: item.department,
          p_actual_rate: item.rate,
          p_request_id: requestId
        });

        if (error) throw error;
      }

      status.textContent = "UPDATED";
      const pending = pendingV760Submit;

      closeCostingPanelV760();

      if (pending && changed.some(
        item => item.department === pending.departmentCode
      )) {
        pendingV760Submit = null;
        await resumePendingSubmitV760(pending);
      } else {
        await openCostingPanelV760(canonical);
      }
    } catch (error) {
      status.textContent = "SAVE FAILED";
      alert(error.message || String(error));
    } finally {
      button.disabled = false;
    }
  });

  overlay.querySelector("#v760SaveMaterial")?.addEventListener("click", async event => {
    const button = event.currentTarget;
    button.disabled = true;
    try {
      const client = getClient();
      const { error } = await client.rpc("rr_upm_update_lot_costing_v760", {
        p_canonical_lot_id: canonical,
        p_regular_fabric: Number(overlay.querySelector("#v760RegularFabric")?.value || 0),
        p_matching: Number(overlay.querySelector("#v760Matching")?.value || 0),
        p_other_material: Number(overlay.querySelector("#v760OtherMaterial")?.value || 0),
        p_material_status: overlay.querySelector("#v760MaterialStatus")?.value || "MISSING",
        p_owner_margin: Number(overlay.querySelector("#v760OwnerMargin")?.value || 0)
      });
      if (error) throw error;
      closeCostingPanelV760();
      await openCostingPanelV760(canonical);
    } catch (error) {
      alert(error.message || String(error));
    } finally {
      button.disabled = false;
    }
  });

  overlay.querySelector("#v760LockStorePrice")?.addEventListener("click", async event => {
    const button = event.currentTarget;
    if (!confirm("Store / Web Sale Price lock karna hai? Future universal margin is Lot ko effect nahi karega.")) {
      return;
    }

    button.disabled = true;
    try {
      const client = getClient();
      const { error } = await client.rpc("rr_upm_lock_store_price_v760", {
        p_canonical_lot_id: canonical
      });
      if (error) throw error;
      closeCostingPanelV760();
      await openCostingPanelV760(canonical);
    } catch (error) {
      alert(error.message || String(error));
    } finally {
      button.disabled = false;
    }
  });

  if (focusDepartment) {
    const target = overlay.querySelector(
      `.v760-rate-row[data-department="${CSS.escape(focusDepartment)}"]`
    );
    target?.scrollIntoView({ behavior: "smooth", block: "center" });
    target?.classList.add("v760-focus-rate");
    target?.querySelector(".v760-actual-rate")?.focus();
  }
}

function closeDirectSubmitConfirmationV7604(result = null) {
  const modal = document.getElementById("v7604DirectSubmitModal");
  const resolve = modal?._resolve;
  modal?.remove();
  if (resolve) resolve(result);
}

function activeSubmitDepartmentsV763() {
  const departments = new Map();

  for (const row of currentMatrix?.colours || []) {
    const status = upper(row.ownership_status);
    const code = canonicalDepartmentV762(row.department_code);

    if (
      !row.assignment_id
      || !code
      || status === "OPEN"
      || !["ASSIGNED","RUNNING","IN_PROGRESS"].includes(status)
    ) {
      continue;
    }

    if (!departments.has(code)) {
      departments.set(code, {
        value: code,
        label: row.department_name || code,
        searchText: `${row.department_name || ""} ${code}`,
        count: 0
      });
    }

    departments.get(code).count += 1;
  }

  return [...departments.values()]
    .map(item => ({
      ...item,
      label: `${item.label} · ${item.count} Colour`
    }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

function bulkSubmitRowsV763(departmentCode) {
  const department = canonicalDepartmentV762(departmentCode);

  return (currentMatrix?.colours || []).filter(row => {
    const status = upper(row.ownership_status);

    return Boolean(
      row.assignment_id
      && canonicalDepartmentV762(row.department_code) === department
      && ["ASSIGNED","RUNNING","IN_PROGRESS"].includes(status)
    );
  });
}

function bulkSubmitSummaryV763(rows) {
  return rows.map(row => {
    const sizeSummary =
      colourSizeInfo(row.colour_code)?.summary
      || row.size_text
      || "";

    return `
      <div class="v763-bulk-submit-colour">
        <b>${esc(row.colour_code)}</b>
        <span>${esc(sizeSummary)}</span>
        <small>${esc(row.worker_name || "Mapped Worker")}</small>
      </div>
    `;
  }).join("");
}

function closeBulkSubmitConfirmationV763(result = null) {
  const modal = document.getElementById("v763BulkSubmitModal");
  const resolve = modal?._resolve;
  modal?.remove();
  if (resolve) resolve(result);
}

function askBulkSubmitConfirmationV763(departmentCode, departmentName, rows) {
  return new Promise(resolve => {
    const modal = document.createElement("div");
    modal.id = "v763BulkSubmitModal";
    modal.className = "v7604-submit-overlay";
    modal._resolve = resolve;

    modal.innerHTML = `
      <section class="v7604-submit-modal v763-bulk-submit-modal">
        <h2>CONFIRM BULK SUBMIT</h2>

        <div class="v7604-submit-copy">
          <b>${esc(departmentName || departmentCode)} ke ${
            rows.length
          } running Colour Submit honge.</b>
          <span>Har Colour apni complete mapped Sizes/Qty ke saath Submit hoga.</span>
        </div>

        <div class="v763-bulk-submit-list">
          ${bulkSubmitSummaryV763(rows)}
        </div>

        <div class="v7604-random-route-note">
          Submit ke baad sabhi selected Colours <b>RANDOM OPEN QUEUE</b> me
          jayenge. Koi next Department preselect nahi hoga.
        </div>

        <div class="v7604-submit-actions">
          <button type="button" id="v763BulkSubmitCancel">CANCEL</button>
          <button type="button" id="v763BulkSubmitYes">
            YES · SUBMIT ${rows.length} COLOURS
          </button>
        </div>
      </section>
    `;

    document.body.appendChild(modal);

    modal.querySelector("#v763BulkSubmitCancel").onclick = () =>
      closeBulkSubmitConfirmationV763(null);

    modal.querySelector("#v763BulkSubmitYes").onclick = () =>
      closeBulkSubmitConfirmationV763({ confirmed: true });

    modal.addEventListener("click", event => {
      if (event.target === modal) {
        closeBulkSubmitConfirmationV763(null);
      }
    });
  });
}

async function directBulkSubmitV763({
  departmentCode,
  departmentName,
  rows,
  skipConfirmation = false
}) {
  const canonical =
    currentMatrix?.canonical_lot_id
    || activeCanonical
    || locateActiveCanonical();

  if (!canonical) {
    throw new Error("Canonical Lot ID nahi mila.");
  }

  const canonicalDepartment =
    canonicalDepartmentV762(departmentCode);

  const liveRows = bulkSubmitRowsV763(canonicalDepartment);
  const requestedCodes = new Set((rows || []).map(row => upper(row.colour_code)).filter(Boolean));
  const rowsToSubmit = requestedCodes.size
    ? liveRows.filter(row => requestedCodes.has(upper(row.colour_code)))
    : liveRows;

  if (!rowsToSubmit.length) {
    throw new Error(
      `${departmentName || canonicalDepartment} me koi running Colour nahi hai.`
    );
  }

  const answer = skipConfirmation
    ? { confirmed: true }
    : await askBulkSubmitConfirmationV763(
        canonicalDepartment,
        departmentName,
        rowsToSubmit
      );

  if (!answer?.confirmed) return false;

  const client = getClient();
  if (!client) {
    throw new Error("Connected Supabase client nahi mila.");
  }

  const button = $("v763BulkSubmit");
  if (button) {
    button.disabled = true;
    button.textContent = "SUBMITTING ALL...";
  }

  try {
    const { data, error } = await client.rpc(
      "rr_upm_submit_colours_v741",
      {
        p_canonical_lot_id: canonical,
        p_department_code: canonicalDepartment,
        p_rows: rowsToSubmit.map(row => ({
          colour_id: row.colour_id || null,
          colour_code: upper(row.colour_code)
        })),
        p_remarks:
          `V763 Bulk Submit · ${canonicalDepartment} · ` +
          `${rowsToSubmit.length} Colours to Random Open Queue`
      }
    );

    if (error) throw error;

    alert(
      `${rowsToSubmit.length} Colour(s) successfully submitted from ` +
      `${departmentName || canonicalDepartment}.\n` +
      `Sabhi Colours ab RANDOM OPEN QUEUE me hain.`
    );

    checkinSignature = "";
    workerCache.clear();
    lotSizeCache.clear();
    v764CompletedCache.clear();
    v76043DepartmentCache = null;

    await new Promise(resolve => setTimeout(resolve, 350));
    await syncAll();

    return data || true;
  } finally {
    if (button) {
      button.disabled = false;
      button.textContent = "SUBMIT SELECTED";
    }
  }
}

async function bulkSubmitRateGateV763({
  departmentCode,
  departmentName,
  rows
}) {
  const canonical =
    currentMatrix?.canonical_lot_id
    || activeCanonical
    || locateActiveCanonical();

  if (!canonical) {
    throw new Error("Canonical Lot ID nahi mila.");
  }

  const firstRow = rows[0];
  if (!firstRow) {
    throw new Error("Bulk Submit ke liye running Colour nahi mila.");
  }

  const client = getClient();
  if (!client) {
    throw new Error("Connected Supabase client nahi mila.");
  }

  const { data, error } = await client.rpc(
    "rr_upm_first_submit_rate_gate_v760",
    {
      p_canonical_lot_id: canonical,
      p_department_code: canonicalDepartmentV762(departmentCode),
      p_colour_code: firstRow.colour_code
    }
  );

  if (error) throw error;
  if (data?.allowed) return true;

  pendingV760Submit = {
    mode: "BULK",
    canonical,
    departmentCode: data.department_code,
    departmentName:
      departmentName || data.department_name || data.department_code,
    requestId: data.request_id,
    rows
  };

  alert(
    `Bulk Submit hold hai.\n\n` +
    `Lot: ${data.lot_no}\n` +
    `Department: ${data.department_name}\n` +
    `Colours: ${rows.map(row => row.colour_code).join(", ")}\n\n` +
    `Actual Rate fill karne ke baad confirmed Bulk Submit automatically ` +
    `continue hoga.`
  );

  await openCostingPanelV760(canonical, data.department_code);
  return false;
}

function v799SelectedCodes() {
  return new Set([...document.querySelectorAll('.v799-bulk-pick:checked')]
    .map(input => upper(input.dataset.v799Colour)).filter(Boolean));
}
function v799SetBulkSelection(mode, departmentCode = '') {
  const department = canonicalDepartmentV762(departmentCode);
  document.querySelectorAll('.v799-bulk-pick').forEach(input => {
    const row = (currentMatrix?.colours || []).find(r => upper(r.colour_code) === upper(input.dataset.v799Colour));
    if (!row) return;
    const status = upper(row.ownership_status);
    const rowDepartment = canonicalDepartmentV762(row.department_code);
    input.checked = mode === 'CLEAR' ? false
      : mode === 'ASSIGN' ? status === 'OPEN'
      : mode === 'SUBMIT' ? Boolean(row.assignment_id) && rowDepartment === department && ['ASSIGNED','RUNNING','IN_PROGRESS'].includes(status)
      : input.checked;
  });
}
function v799SelectedSubmitRows(departmentCode) {
  const selected = v799SelectedCodes();
  return bulkSubmitRowsV763(departmentCode).filter(row => selected.has(upper(row.colour_code)));
}

async function runBulkSubmitV763() {
  try {
    const department =
      window.v763BulkSubmitDepartmentSearch?.getValue?.() || "";
    const departmentLabel =
      window.v763BulkSubmitDepartmentSearch?.getLabel?.() || department;

    if (!department) {
      throw new Error("Bulk Submit ke liye active Department select karein.");
    }

    const rows = v799SelectedSubmitRows(department);

    if (!rows.length) {
      throw new Error(
        `${departmentLabel} me Submit ke liye kam se kam 1 running Colour select karein.`
      );
    }

    const answer = await askBulkSubmitConfirmationV763(
      department,
      departmentLabel,
      rows
    );

    if (!answer?.confirmed) return;

    const rateAllowed = await bulkSubmitRateGateV763({
      departmentCode: department,
      departmentName: departmentLabel,
      rows
    });

    if (!rateAllowed) return;

    await directBulkSubmitV763({
      departmentCode: department,
      departmentName: departmentLabel,
      rows,
      skipConfirmation: true
    });
  } catch (error) {
    console.error("V763 Bulk Submit failed", error);
    alert([
      error?.message,
      error?.details,
      error?.hint,
      error?.code
    ].filter(Boolean).join(" — ") || String(error));
  }
}

async function askDirectSubmitConfirmationV7604(rowData) {
  return new Promise(resolve => {
    const modal = document.createElement("div");
    modal.id = "v7604DirectSubmitModal";
    modal.className = "v7604-submit-overlay";
    modal._resolve = resolve;

    modal.innerHTML = `
      <section class="v7604-submit-modal">
        <h2>CONFIRM COLOUR SUBMIT</h2>

        <div class="v7604-submit-copy">
          <b>Kya aap ${esc(rowData.colour_code)} Submit kar rahe hain?</b>
          <span>Current Department: ${esc(
            rowData.department_name || rowData.department_code
          )}</span>
          <span>Worker: ${esc(
            rowData.worker_name || rowData.worker_code || "Mapped Worker"
          )}</span>
          <span>Colour: ${esc(rowData.colour_code)}</span>
          <span>Sizes: ${esc(
            colourSizeInfo(rowData.colour_code).summary
            || rowData.size_text
            || ""
          )}</span>
        </div>

        <div class="v7604-random-route-note">
          Submit ke baad Colour <b>RANDOM OPEN QUEUE</b> me jayega.
          Koi Department abhi owner nahi banega. Jis eligible Department me
          pehle mapped Worker assign hoga, wahi next owner hoga.
        </div>

        <div class="v7604-submit-actions">
          <button type="button" id="v7604SubmitCancel">CANCEL</button>
          <button type="button" id="v7604SubmitYes">
            YES · SUBMIT ${esc(rowData.colour_code)}
          </button>
        </div>
      </section>
    `;

    document.body.appendChild(modal);

    modal.querySelector("#v7604SubmitCancel").onclick = () =>
      closeDirectSubmitConfirmationV7604(null);

    modal.querySelector("#v7604SubmitYes").onclick = () =>
      closeDirectSubmitConfirmationV7604({ confirmed: true });

    modal.addEventListener("click", event => {
      if (event.target === modal) {
        closeDirectSubmitConfirmationV7604(null);
      }
    });
  });
}
async function directSubmitColourV7604(rowData, options = {}) {
  const canonical =
    currentMatrix?.canonical_lot_id
    || activeCanonical
    || locateActiveCanonical();

  if (!canonical) {
    throw new Error("Canonical Lot ID nahi mila.");
  }

  const client = getClient();
  if (!client) {
    throw new Error("Connected Supabase client nahi mila.");
  }

  const answer = options.skipConfirmation
    ? { confirmed: true }
    : await askDirectSubmitConfirmationV7604(rowData);

  if (!answer?.confirmed) return false;

  const submitButton = document.querySelector(
    `.v756-action[data-v756-action="SUBMIT"][data-v756-colour="${CSS.escape(
      rowData.colour_code
    )}"]`
  );

  if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = "SUBMITTING...";
  }

  try {
    const { data, error } = await client.rpc("rr_upm_submit_colours_v741", {
      p_canonical_lot_id: canonical,
      p_department_code: rowData.department_code,
      p_rows: [{
        colour_id: rowData.colour_id || null,
        colour_code: rowData.colour_code
      }],
      p_remarks: "V760.4.2 Direct Colour Submit to Random Open Queue"
    });

    if (error) throw error;

    alert(
      `${upper(rowData.colour_code)} successfully submitted.\n` +
      `Colour ab RANDOM OPEN QUEUE me hai.`
    );

    checkinSignature = "";
    workerCache.clear();
    lotSizeCache.clear();
    v764CompletedCache.clear();
    v76043DepartmentCache = null;

    // Do not force any Department view or ownership.
    // Fresh matrix decides the Random Open Queue state from backend.
    await syncAll();
    return data || true;
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = "SUBMIT";
    }
  }
}
async function repairIdentityDisplayV7604() {
  const canonical = currentMatrix?.canonical_lot_id
    || activeCanonical
    || locateActiveCanonical();
  const lotNo = [...document.querySelectorAll("#identity .box")]
    .find(box => upper(box.querySelector("small")?.textContent) === "LOT NO")
    ?.querySelector("b")?.textContent?.trim();

  if (!canonical || !lotNo) return;

  const client = getClient();
  if (!client) return;

  try {
    const { data, error } = await client.rpc(
      "rr_upm_resolve_identity_v740",
      {
        p_canonical_lot_id: canonical,
        p_force: false,
        p_reason: null
      }
    );

    if (error || !data) return;

    const art = data.art_no || "";
    const printNo = data.print_no || "";
    const frameNo = data.frame_no || "";

    if (art && $("identityArt")) $("identityArt").textContent = art;

    if ($("identityPrint")) {
      $("identityPrint").textContent =
        printNo || "NOT APPLICABLE";
    }

    if ($("identityFrame")) {
      $("identityFrame").textContent =
        frameNo || "NOT APPLICABLE";
    }
  } catch (error) {
    console.warn("V797.7 identity resolver unavailable", error);
  }
}

async function resumePendingSubmitV760(pending) {
  if (!pending) return;

  if (pending.mode === "BULK") {
    checkinSignature = "";
    await new Promise(resolve => setTimeout(resolve, 250));
    await syncAll();

    await directBulkSubmitV763({
      departmentCode: pending.departmentCode,
      departmentName: pending.departmentName,
      rows: pending.rows || [],
      skipConfirmation: true
    });
    return;
  }

  closeInlineAction(pending.rowElement);
  checkinSignature = "";

  await new Promise(resolve => setTimeout(resolve, 250));
  await syncAll();

  const latestRow = (currentMatrix?.colours || []).find(item =>
    upper(item.colour_code) === upper(pending.rowData.colour_code)
    && canonicalDepartmentV762(item.department_code)
      === canonicalDepartmentV762(pending.rowData.department_code)
  ) || pending.rowData;

  await directSubmitColourV7604(latestRow);
}
function ensureRateContactModalV7976() {
  let modal = document.getElementById("rfRateContactModalV7976");
  if (modal) return modal;

  const style = document.createElement("style");
  style.textContent = `
    #rfRateContactModalV7976{position:fixed;inset:0;z-index:10050;background:rgba(5,8,13,.86);display:grid;place-items:center;padding:14px}
    #rfRateContactModalV7976.rf7976-hidden{display:none}
    .rf7976-card{width:min(560px,100%);max-height:92vh;overflow:auto;background:#141922;border:1px solid #394455;border-radius:18px;padding:18px;box-shadow:0 22px 70px #000}
    .rf7976-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}.rf7976-head h2{margin:0;color:#ffc857;font-size:21px}.rf7976-head button{min-width:44px}
    .rf7976-summary{margin:12px 0;padding:12px;border-radius:12px;background:#211d12;border:1px solid #745d25;color:#ffe6a3;line-height:1.45}
    .rf7976-contact{border:1px solid #344054;border-radius:13px;padding:12px;margin-top:10px}.rf7976-contact b{display:block;margin-bottom:5px}.rf7976-contact small{display:block;color:#98a2b3;margin-bottom:10px}
    .rf7976-actions{display:grid;grid-template-columns:1fr 1fr;gap:9px}.rf7976-actions button{min-height:50px;font-weight:800}.rf7976-wa{background:#126c43!important;border-color:#25d366!important}.rf7976-sms{background:#174d7a!important;border-color:#3d91d6!important}
    .rf7976-note{font-size:12px;color:#98a2b3;margin:12px 0 0;line-height:1.4}
    @media(max-width:430px){.rf7976-actions{grid-template-columns:1fr}.rf7976-card{padding:14px}}
  `;
  document.head.append(style);

  modal = document.createElement("div");
  modal.id = "rfRateContactModalV7976";
  modal.className = "rf7976-hidden";
  modal.innerHTML = `<section class="rf7976-card" role="dialog" aria-modal="true" aria-labelledby="rf7976Title">
    <div class="rf7976-head"><div><small>REAL FACTORY · MANUAL ALERT</small><h2 id="rf7976Title">Actual Rate Required</h2></div><button type="button" data-rf7976-close>×</button></div>
    <div id="rf7976Summary" class="rf7976-summary"></div>
    <div id="rf7976Contacts"></div>
    <p class="rf7976-note">WhatsApp/SMS app खुलेगी; message भेजने के लिए Send दबाना जरूरी है. App खुलने को OPENED_MANUAL माना जाएगा, DELIVERED नहीं.</p>
  </section>`;
  document.body.append(modal);
  modal.querySelector("[data-rf7976-close]").onclick = () => modal.classList.add("rf7976-hidden");
  return modal;
}

async function markManualContactOpenedV7976(queueId, channel) {
  const client = getClient();
  if (!client || !queueId) return;
  const { error } = await client.rpc("rr_mark_manual_contact_opened_v797_6", {
    p_queue_id: queueId,
    p_channel: channel
  });
  if (error) console.warn("V797.6 manual contact status", error);
}

async function showManualRateContactV7976(rateRequest) {
  const modal = ensureRateContactModalV7976();
  const summary = modal.querySelector("#rf7976Summary");
  const host = modal.querySelector("#rf7976Contacts");
  summary.innerHTML = `<b>First Submit HOLD</b><br>Lot ${esc(rateRequest.lot_no || "—")} · Colour ${esc(rateRequest.colour_code || "—")} · ${esc(rateRequest.department_name || rateRequest.department_code || "Department")}<br>Actual Rate fill/approve होने तक Submit आगे नहीं जाएगा.`;
  host.innerHTML = `<div class="msg">Contact actions loading…</div>`;
  modal.classList.remove("rf7976-hidden");

  try {
    const client = getClient();
    if (!client) throw new Error("Connected Supabase client nahi mila.");
    const { data, error } = await client.rpc("rr_manual_rate_contact_payload_v797_6", { p_request_id: rateRequest.request_id });
    if (error) throw error;
    const contacts = Array.isArray(data?.contacts) ? data.contacts : [];
    if (!contacts.length) {
      host.innerHTML = `<div class="msg error">Recipient mobile ready नहीं है. In-app alert record सुरक्षित है.</div>`;
      return;
    }
    host.innerHTML = contacts.map((contact, index) => {
      const people = (Array.isArray(contact.recipients) ? contact.recipients : []).map(person => person.name).filter(Boolean).join(" + ") || "Management";
      const last4 = String(contact.mobile || "").slice(-4);
      return `<div class="rf7976-contact" data-rf7976-contact="${index}"><b>${esc(people)}</b><small>Shared/unique mobile · ending ${esc(last4)}</small><div class="rf7976-actions"><button type="button" class="rf7976-wa" data-rf7976-channel="WHATSAPP">OPEN WHATSAPP</button><button type="button" class="rf7976-sms" data-rf7976-channel="SMS">OPEN SMS</button></div></div>`;
    }).join("");

    host.querySelectorAll("[data-rf7976-channel]").forEach(button => {
      button.onclick = () => {
        const contact = contacts[Number(button.closest("[data-rf7976-contact]").dataset.rf7976Contact)];
        const channel = button.dataset.rf7976Channel;
        const url = channel === "WHATSAPP" ? contact.whatsapp_url : contact.sms_url;
        if (!url) return alert(`${channel} link ready nahi hai.`);
        const opened = window.open(url, "_blank", "noopener");
        if (!opened && channel === "SMS") window.location.href = url;
        void markManualContactOpenedV7976(contact.queue_id, channel);
        button.textContent = channel === "WHATSAPP" ? "WHATSAPP OPENED" : "SMS OPENED";
      };
    });
  } catch (error) {
    host.innerHTML = `<div class="msg error">${esc(error?.message || error || "Contact payload unavailable")}</div>`;
  }
}

async function firstSubmitRateGateV760(rowData, rowElement) {
  const client = getClient();
  if (!client) throw new Error("Connected Supabase client nahi mila.");

  const canonical =
    currentMatrix?.canonical_lot_id
    || activeCanonical
    || locateActiveCanonical();

  if (!canonical) throw new Error("Canonical Lot ID nahi mila.");

  const canonicalDepartment =
    String(rowData.department_code || "").toUpperCase();

  if (
    v760SubmitBypassOnce
    && v760SubmitBypassOnce.canonical === canonical
    && upper(v760SubmitBypassOnce.colourCode) === upper(rowData.colour_code)
    && (
      upper(v760SubmitBypassOnce.departmentCode) === canonicalDepartment
      || upper(v760SubmitBypassOnce.departmentCode) === "PRINTING"
        && canonicalDepartment === "PRINT"
      || upper(v760SubmitBypassOnce.departmentCode) === "STITCHING"
        && ["KR","KARIGAR","STITCHING"].includes(canonicalDepartment)
    )
  ) {
    v760SubmitBypassOnce = null;
    return true;
  }

  const { data, error } = await client.rpc(
    "rr_upm_first_submit_rate_gate_v760",
    {
      p_canonical_lot_id: canonical,
      p_department_code: rowData.department_code,
      p_colour_code: rowData.colour_code
    }
  );

  if (error) throw error;
  if (data?.allowed) return true;

  pendingV760Submit = {
    canonical,
    departmentCode: data.department_code,
    requestId: data.request_id,
    rowData,
    rowElement
  };

  await openCostingPanelV760(canonical, data.department_code);
  await showManualRateContactV7976(data);
  return false;
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

  let costingButton = card.querySelector(".v760-costing-button");
  if (!costingButton) {
    costingButton = document.createElement("button");
    costingButton.type = "button";
    costingButton.className = "v760-costing-button";
    costingButton.textContent = "COSTING";
    costingButton.dataset.canonical = data?.canonical_lot_id || canonical;

    if (checkInButton) {
      checkInButton.insertAdjacentElement("beforebegin", costingButton);
    } else {
      card.appendChild(costingButton);
    }
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
          <label class="v799-bulk-pick-wrap" title="Bulk action ke liye Colour select karein">
            <input type="checkbox" class="v799-bulk-pick" data-v799-colour="${esc(row.colour_code)}">
            <b>${esc(row.colour_code)}</b>
          </label>
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
      <div class="v799-bulk-select-actions">
        <button type="button" id="v799AssignSelectAll">SELECT ALL ELIGIBLE</button>
        <button type="button" id="v799AssignClear">CLEAR</button>
      </div>
      <button type="button" id="v756BulkAssign">ASSIGN SELECTED</button>
      <small id="v756BulkNote">
        1, 2, random multiple ya all OPEN Colours select karke selected Department/Worker ko assign karein.
      </small>
    </div>

    <div class="v756-bulk v763-bulk-submit">
      <strong>BULK SUBMIT</strong>
      <div id="v763BulkSubmitDepartmentHost"></div>
      <div class="v799-bulk-select-actions">
        <button type="button" id="v799SubmitSelectAll">SELECT ALL RUNNING</button>
        <button type="button" id="v799SubmitClear">CLEAR</button>
      </div>
      <button type="button" id="v763BulkSubmit">SUBMIT SELECTED</button>
      <small id="v763BulkSubmitNote">
        1, 2, random multiple ya all running Colours select karein. Har Colour apne already assigned Worker mapping se auto Submit hoga.
      </small>
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

  assignableDepartmentsForBulkV764()
    .then(departments => {
      window.v757BulkDepartmentSearch = createSearchableDropdown({
        container: $("v756BulkDepartmentHost"),
        items: departmentDropdownItemsV76043(departments),
        placeholder: "Search unfinished department",
        emptyText:
          "Lot ke sabhi eligible Departments complete ho chuke hain",
        onSelect: item => renderBulkWorkers(item.value)
      });
      renderBulkWorkers("");
    })
    .catch(error => {
      console.error("V764 unfinished department list failed", error);
    });
  $("v756BulkAssign")?.addEventListener("click", runBulkAssign);
  $("v799AssignSelectAll")?.addEventListener("click", () => v799SetBulkSelection("ASSIGN"));
  $("v799AssignClear")?.addEventListener("click", () => v799SetBulkSelection("CLEAR"));

  window.v763BulkSubmitDepartmentSearch = createSearchableDropdown({
    container: $("v763BulkSubmitDepartmentHost"),
    items: activeSubmitDepartmentsV763(),
    placeholder: "Search active department",
    emptyText: "Koi Department me running Colour nahi hai"
  });

  $("v763BulkSubmit")?.addEventListener("click", runBulkSubmitV763);
  $("v799SubmitSelectAll")?.addEventListener("click", () => {
    const department = window.v763BulkSubmitDepartmentSearch?.getValue?.() || "";
    if (!department) return alert("Pehle active Department select karein.");
    v799SetBulkSelection("SUBMIT", department);
  });
  $("v799SubmitClear")?.addEventListener("click", () => v799SetBulkSelection("CLEAR"));

  repairIdentityDisplayV7604();

  $("v760CheckinCosting")?.addEventListener("click", () => {
    openCostingPanelV760(
      currentMatrix?.canonical_lot_id
      || activeCanonical
      || locateActiveCanonical()
    ).catch(error => alert(error.message || String(error)));
  });
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
  // Inline action is rendered inside a separate <tr> immediately after
  // the Colour row, not inside rowElement itself.
  const nextRow = rowElement?.nextElementSibling;

  if (nextRow?.classList.contains("v756-inline-row")) {
    nextRow.remove();
  }

  // Safety cleanup for any orphaned panel linked to this Colour row.
  rowElement?.querySelector(".v756-inline-action")?.closest("tr")?.remove();

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

function damageAvailabilityFromEngineRow(tableRow) {
  const cells = tableRow ? [...tableRow.querySelectorAll("td")] : [];
  return {
    PENDING: Number(cells[2]?.textContent?.trim() || 0),
    ALTER: Number(cells[4]?.textContent?.trim() || 0),
    REMAKE: Number(cells[9]?.textContent?.trim() || 0)
  };
}

function damageInputsFromCard(card) {
  const rows = [...(card?.querySelectorAll("[data-row-index]") || [])];

  return rows.map(tableRow => {
    const size = tableRow.querySelector("td:first-child")?.textContent?.trim() || "";
    const available = damageAvailabilityFromEngineRow(tableRow);
    const total = available.PENDING + available.ALTER + available.REMAKE;

    if (total <= 0) return "";

    return `
      <div class="v756-size-input v759-damage-size"
           data-engine-row="${esc(tableRow.dataset.rowIndex)}">
        <b>${esc(size)}</b>
        <select class="v756-inline-source v759-damage-source">
          ${available.PENDING > 0
            ? `<option value="PENDING">Good Qty · Max ${esc(available.PENDING)}</option>`
            : ""}
          ${available.ALTER > 0
            ? `<option value="ALTER">Alter Pending · Max ${esc(available.ALTER)}</option>`
            : ""}
          ${available.REMAKE > 0
            ? `<option value="REMAKE">Remake Pending · Max ${esc(available.REMAKE)}</option>`
            : ""}
        </select>
        <input type="number"
          min="0"
          value="0"
          class="v756-inline-qty v759-damage-qty">
        <small class="v759-damage-max"></small>
      </div>`;
  }).filter(Boolean).join("");
}

function installNoClaimReasonSearch(panel) {
  const reasons = [
    { value: "FABRIC_DEFECT", label: "Fabric / Cloth Defect" },
    { value: "CUTTING_DEFECT_NO_OWNER", label: "Cutting Defect · No Identified Responsibility" },
    { value: "MACHINE_TECHNICAL", label: "Machine / Technical Issue" },
    { value: "NATURAL_PROCESS_LOSS", label: "Natural Process Loss" },
    { value: "UNKNOWN_CAUSE", label: "Unknown Cause" },
    { value: "OWNER_APPROVED_NO_RESPONSIBILITY", label: "Owner Approved · No Responsibility" },
    { value: "OTHER_NO_CLAIM", label: "Other No-Claim Damage" }
  ];

  return createSearchableDropdown({
    container: panel.querySelector(".v759-no-claim-reason-host"),
    items: reasons,
    placeholder: "Search no-claim reason",
    emptyText: "No matching reason"
  });
}

function bindDamageResponsibilityMode(panel) {
  const hidden = panel.querySelector(".v759-responsibility-mode");
  const wrap = panel.querySelector(".v759-no-claim-wrap");
  const buttons = [...panel.querySelectorAll(".v759-mode")];

  const reasonSearch = installNoClaimReasonSearch(panel);

  const setMode = mode => {
    hidden.value = mode;
    buttons.forEach(button => {
      button.classList.toggle("active", button.dataset.mode === mode);
    });
    wrap.hidden = mode !== "NO_CLAIM";
  };

  buttons.forEach(button => {
    button.addEventListener("click", () => setMode(button.dataset.mode));
  });

  setMode("WORKER_CLAIM");
  return reasonSearch;
}

function bindDamageMaxControls(panel, card) {
  panel.querySelectorAll(".v759-damage-size").forEach(item => {
    const engineRow = card.querySelector(
      `[data-row-index="${CSS.escape(item.dataset.engineRow)}"]`
    );
    const available = damageAvailabilityFromEngineRow(engineRow);
    const select = item.querySelector(".v759-damage-source");
    const input = item.querySelector(".v759-damage-qty");
    const label = item.querySelector(".v759-damage-max");

    const sync = () => {
      const maximum = Number(available[select.value] || 0);
      input.max = String(maximum);
      if (Number(input.value || 0) > maximum) input.value = String(maximum);
      label.textContent = `Available ${maximum} PCS`;
    };

    select.addEventListener("change", sync);
    sync();
  });
}

async function saveDamageDirectV759(rowData, panel, card, reasonSearch) {
  const rows = [];

  panel.querySelectorAll(".v759-damage-size").forEach(item => {
    const qty = Number(item.querySelector(".v759-damage-qty")?.value || 0);
    if (qty <= 0) return;

    const source = item.querySelector(".v759-damage-source")?.value || "PENDING";
    const maximum = Number(item.querySelector(".v759-damage-qty")?.max || 0);

    if (qty > maximum) {
      throw new Error(
        `${rowData.colour_code}: Damage ${qty} exceeds ${source} balance ${maximum}.`
      );
    }

    const engineRow = card.querySelector(
      `[data-row-index="${CSS.escape(item.dataset.engineRow)}"]`
    );
    const size = engineRow?.querySelector("td:first-child")?.textContent?.trim() || "";

    const responsibilityMode =
      panel.querySelector(".v759-responsibility-mode")?.value || "WORKER_CLAIM";
    const reasonCode = reasonSearch?.getValue?.() || "";

    if (responsibilityMode === "NO_CLAIM" && !reasonCode) {
      throw new Error("No-Claim Damage reason select करें.");
    }

    rows.push({
      colour_id: rowData.colour_id || null,
      colour_code: rowData.colour_code,
      colour_name: rowData.colour_name || rowData.colour_code,
      size_code: size,
      source_bucket: source,
      qty,
      responsibility_mode: responsibilityMode,
      damage_reason_code: reasonCode || null
    });
  });

  if (!rows.length) {
    throw new Error("कम से कम एक Size में Damage Qty भरें.");
  }

  const client = getClient();
  if (!client) throw new Error("Connected Supabase client नहीं मिला.");

  const identity = currentLotIdentity();
  if (!identity.canonical_lot_id) throw new Error("Canonical Lot ID नहीं मिला.");

  const { data, error } = await client.rpc("rr_upm_save_damage_v731", {
    p_canonical_lot_id: identity.canonical_lot_id,
    p_department_code: rowData.department_code,
    p_rows: rows,
    p_rate: 0,
    p_remarks: "V759 independent Colour Damage Register"
  });

  if (error) throw error;
  return data;
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

function currentLotIdentity() {
  const boxes = [...document.querySelectorAll("#identity .box")];
  const read = label => boxes.find(box =>
    upper(box.querySelector("small")?.textContent) === upper(label)
  )?.querySelector("b")?.textContent?.trim() || "";

  return {
    lot_no: read("LOT NO"),
    canonical_lot_id:
      currentMatrix?.canonical_lot_id ||
      activeCanonical ||
      locateActiveCanonical()
  };
}

function colourAssignedQty(colourCode) {
  const backendRows = currentSizeMap?.get(upper(colourCode)) || [];
  const backendTotal = backendRows.reduce(
    (sum, row) => sum + Number(row.qty || 0),
    0
  );
  if (backendTotal > 0) return backendTotal;

  const card = findColourCard(colourCode);
  if (!card) return 0;

  return [...card.querySelectorAll("[data-row-index]")].reduce((sum, row) => {
    const qty = Number(row.querySelectorAll("td")[1]?.textContent?.trim() || 0);
    return sum + qty;
  }, 0);
}

function askDirectSingleColourConfirmation({
  colourCode,
  departmentName,
  workerLabel,
  sizeSummary
}) {
  return new Promise(resolve => {
    const modal = $("actionConfirmModal");
    const yes = $("actionConfirmYes");
    const cancel = $("actionConfirmCancel");

    if (!modal || !yes || !cancel) {
      resolve(window.confirm(
        `Assign ${colourCode}\nDepartment: ${departmentName}\n` +
        `Worker: ${workerLabel}\nSizes: ${sizeSummary || "All Sizes"}`
      ));
      return;
    }

    $("actionConfirmTitle").textContent = "CONFIRM COLOUR ASSIGNMENT";
    $("actionConfirmCopy").innerHTML = `
      <b>क्या आप पूरा Colour ${esc(colourCode)} assign करना चाहते हैं?</b><br>
      Department: ${esc(departmentName)}<br>
      Worker: ${esc(workerLabel)}<br>
      Colour: ${esc(colourCode)}
      ${sizeSummary ? `<br>Sizes: ${esc(sizeSummary)}` : ""}
    `;
    $("actionConfirmColours").innerHTML =
      `<span class="badge">${esc(colourCode)}</span>`;
    $("actionConfirmNextWrap")?.classList.add("hidden");
    yes.textContent = `YES · ASSIGN ${upper(colourCode)}`;

    const cleanup = result => {
      modal.classList.add("hidden");
      yes.removeEventListener("click", onYes, true);
      cancel.removeEventListener("click", onCancel, true);
      resolve(result);
    };

    const onYes = event => {
      event.preventDefault();
      event.stopImmediatePropagation();
      cleanup(true);
    };

    const onCancel = event => {
      event.preventDefault();
      event.stopImmediatePropagation();
      cleanup(false);
    };

    yes.addEventListener("click", onYes, true);
    cancel.addEventListener("click", onCancel, true);
    modal.classList.remove("hidden");
  });
}

async function directAssignSingleColour({
  rowData,
  workerId,
  workerLabel
}) {
  const client = getClient();
  if (!client) throw new Error("Connected Supabase client नहीं मिला.");

  const identity = currentLotIdentity();
  if (!identity.canonical_lot_id) {
    throw new Error("Canonical Lot ID नहीं मिला.");
  }
  if (!identity.lot_no) {
    throw new Error("Lot No नहीं मिला.");
  }

  const completedState =
    await fetchCompletedDepartmentMapV764();

  if (
    completedState.completedByColour
      .get(upper(rowData.colour_code))
      ?.has(
        canonicalDepartmentV762(rowData.department_code)
      )
  ) {
    throw new Error(
      `${upper(rowData.colour_code)} ne ` +
      `${canonicalDepartmentV762(rowData.department_code)} ` +
      `Department already complete kar liya hai.`
    );
  }

  const assignedQty = colourAssignedQty(rowData.colour_code);
  if (assignedQty <= 0) {
    throw new Error(`${rowData.colour_code} की assigned Qty resolve नहीं हुई.`);
  }

  const payload = {
    p_canonical_lot_id: identity.canonical_lot_id,
    p_lot_no: identity.lot_no,
    p_department_code: canonicalDepartmentV762(rowData.department_code),
    p_rows: [{
      colour_id: rowData.colour_id,
      colour_code: upper(rowData.colour_code),
      worker_id: workerId,
      assigned_qty: assignedQty,
      actual_rate: Number($("actualRate")?.value || 0)
    }],
    p_remarks:
      `V757 direct single Colour assignment · ` +
      `${upper(rowData.colour_code)} · ${upper(rowData.department_code)} · ` +
      `${workerLabel}`
  };

  const { data, error } = await client.rpc(
    "rr_upm_claim_colours_v741",
    payload
  );

  if (error) throw error;
  return data;
}

async function openAssignPanel(rowData, rowElement, card) {
  const departments =
    await assignableDepartmentsForColourV764(
      rowData.colour_code
    );

  const panel = appendInlinePanel(rowElement, `
    <div class="v756-inline-head">
      <b>${esc(rowData.colour_code)} · Assign Worker</b>
      <button type="button" class="v756-inline-cancel">CANCEL</button>
    </div>

    <div class="v756-inline-grid assign v76043-assign-grid">
      <label>Department
        <div class="v76043-inline-department-host"></div>
      </label>

      <label>Mapped Worker
        <div class="v757-inline-worker-host"></div>
      </label>

      <button type="button"
        class="v756-inline-save primary"
        disabled>
        CONFIRM ASSIGN
      </button>

      <span class="v7571-assign-note">
        Pehle Department select karein. Sirf us Department ke active mapped
        workers dikhaye jayenge.
      </span>
    </div>
  `);

  const departmentSearch = createSearchableDropdown({
    container: panel.querySelector(".v76043-inline-department-host"),
    items: departmentDropdownItemsV76043(departments),
    placeholder: "Search department",
    emptyText: "Is Colour ke liye koi unfinished Department available nahi"
  });

  const workerHost = panel.querySelector(".v757-inline-worker-host");
  const saveButton = panel.querySelector(".v756-inline-save");
  const note = panel.querySelector(".v7571-assign-note");
  let workerSearch = null;
  let selectedDepartmentName = "";

  const resetWorker = message => {
    workerSearch = createSearchableDropdown({
      container: workerHost,
      items: [],
      placeholder: "Select Department first",
      emptyText: message || "Select Department first"
    });
    saveButton.disabled = true;
  };

  resetWorker();

  const loadDepartmentWorkers = async departmentCode => {
    saveButton.disabled = true;
    note.textContent = "Mapped workers loading...";

    const department = departments.find(item =>
      upper(item.department_code) === upper(departmentCode)
    );
    selectedDepartmentName =
      department?.department_name || departmentCode;

    const workers = await fetchWorkers(departmentCode);
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

    workerSearch = createSearchableDropdown({
      container: workerHost,
      items: workerItems,
      placeholder: "Search mapped worker by name or code",
      emptyText: `No active mapped worker in ${selectedDepartmentName}`,
      onSelect: () => {
        saveButton.disabled = !workerSearch?.getValue?.();
      }
    });

    note.textContent = workers.length
      ? `${selectedDepartmentName}: ${workers.length} active mapped worker(s).`
      : `${selectedDepartmentName} me koi active mapped worker nahi mila.`;
  };

  /*
    createSearchableDropdown does not expose an on-change hook after creation
    in every older version. Listen to its hidden value and clickable items.
  */
  panel.querySelector(".v76043-inline-department-host")
    .addEventListener("click", () => {
      setTimeout(() => {
        const value = departmentSearch?.getValue?.() || "";
        if (value) {
          loadDepartmentWorkers(value).catch(error => {
            console.error(error);
            resetWorker(error.message || String(error));
            note.textContent = error.message || String(error);
          });
        }
      }, 0);
    });

  panel.querySelector(".v76043-inline-department-host")
    .addEventListener("input", () => {
      setTimeout(() => {
        const value = departmentSearch?.getValue?.() || "";
        if (value) {
          loadDepartmentWorkers(value).catch(error => {
            console.error(error);
            resetWorker(error.message || String(error));
          });
        }
      }, 0);
    });

  panel.querySelector(".v756-inline-cancel").onclick = () =>
    closeInlineAction(rowElement);

  saveButton.onclick = async () => {
    try {
      const departmentCode = departmentSearch?.getValue?.() || "";
      const workerId = workerSearch?.getValue?.() || "";
      const workerLabel = workerSearch?.getLabel?.() || workerId;

      if (!departmentCode) {
        throw new Error("Department select karein.");
      }
      if (!workerId) {
        throw new Error(
          "Selected Department ka mapped Worker search karke select karein."
        );
      }

      const confirmed = await askDirectSingleColourConfirmation({
        colourCode: rowData.colour_code,
        departmentName: selectedDepartmentName || departmentCode,
        workerLabel,
        sizeSummary: colourSizeInfo(rowData.colour_code)?.summary || ""
      });

      if (!confirmed) return;

      saveButton.disabled = true;
      saveButton.textContent =
        `ASSIGNING ${upper(rowData.colour_code)}...`;

      await directAssignSingleColour({
        rowData: {
          ...rowData,
          department_code: canonicalDepartmentV762(departmentCode),
          department_name:
            selectedDepartmentName || departmentCode
        },
        workerId,
        workerLabel
      });

      closeInlineAction(rowElement);
      workerCache.clear();
      lotSizeCache.clear();
    v764CompletedCache.clear();
      checkinSignature = "";

      await new Promise(resolve => setTimeout(resolve, 450));
      await syncAll();

      alert(
        `${upper(rowData.colour_code)} successfully assigned to ` +
        `${workerLabel} in ${selectedDepartmentName || departmentCode}.`
      );
    } catch (error) {
      console.error("V760.4.3 direct single assignment failed", error);
      alert([
        error?.message,
        error?.details,
        error?.hint,
        error?.code
      ].filter(Boolean).join(" — ") || String(error));
    } finally {
      saveButton.disabled = false;
      saveButton.textContent = "CONFIRM ASSIGN";
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

function hiddenGoodQtyRowsV765(card) {
  return [...(card?.querySelectorAll("[data-row-index]") || [])]
    .map(tableRow => {
      const cells = tableRow.querySelectorAll("td");
      return {
        tableRow,
        size_code: upper(cells[0]?.textContent?.trim() || ""),
        good_qty: Number(cells[2]?.textContent?.trim() || 0)
      };
    })
    .filter(row => row.size_code && row.good_qty > 0);
}

async function fetchIndependentAlterRowsV765(rowData, card) {
  const canonical =
    currentMatrix?.canonical_lot_id
    || activeCanonical
    || locateActiveCanonical();

  if (!canonical) {
    throw new Error("Canonical Lot ID nahi mila.");
  }

  const client = getClient();
  if (!client) {
    throw new Error("Connected Supabase client nahi mila.");
  }

  const department =
    canonicalDepartmentV762(rowData.department_code);

  const { data, error } = await client.rpc(
    "rr_upm_universal_form_v741",
    {
      p_canonical_lot_id: canonical,
      p_department_code: department
    }
  );

  if (error) throw error;

  const colour = upper(rowData.colour_code);

  const rows = (data?.rows || [])
    .filter(row =>
      upper(row.colour_code) === colour
      && Number(row.good_qty || 0) > 0
    )
    .map(row => ({
      colour_id: row.colour_id || rowData.colour_id || null,
      colour_code: colour,
      colour_name:
        row.colour_name
        || rowData.colour_name
        || colour,
      size_code: upper(row.size_code),
      good_qty: Number(row.good_qty || 0)
    }));

  if (rows.length) return rows;

  /*
    Compatibility fallback only reads the visible verified Good Qty cell.
    It never uses Main/Cutting Qty as Alter availability.
  */
  return hiddenGoodQtyRowsV765(card).map(row => ({
    colour_id: rowData.colour_id || null,
    colour_code: colour,
    colour_name: rowData.colour_name || colour,
    size_code: row.size_code,
    good_qty: row.good_qty
  }));
}

function independentAlterInputsV765(rows) {
  return rows.map(row => `
    <div class="v756-size-input v765-alter-size"
      data-v765-size="${esc(row.size_code)}">
      <b>${esc(row.size_code)}</b>
      <input type="number"
        min="0"
        max="${esc(row.good_qty)}"
        value="0"
        class="v756-inline-qty v765-alter-qty">
      <small>Current Good Qty · Max ${esc(row.good_qty)}</small>
    </div>
  `).join("");
}

function applyIndependentAlterToLegacyEngineV765(panel, card) {
  const engineRows =
    [...(card?.querySelectorAll("[data-row-index]") || [])];

  card.querySelectorAll(".alterEntry")
    .forEach(input => input.value = "0");

  let entered = 0;

  panel.querySelectorAll(".v765-alter-size")
    .forEach(item => {
      const size = upper(item.dataset.v765Size);
      const qty = Number(
        item.querySelector(".v765-alter-qty")?.value || 0
      );
      const max = Number(
        item.querySelector(".v765-alter-qty")?.max || 0
      );

      if (qty < 0 || qty > max) {
        throw new Error(
          `${size}: Alter Qty ${qty} current Good Qty ${max} se zyada hai.`
        );
      }

      if (qty <= 0) return;

      const engineRow = engineRows.find(row =>
        upper(
          row.querySelector("td:first-child")
            ?.textContent?.trim() || ""
        ) === size
      );

      const target = engineRow?.querySelector(".alterEntry");

      if (!target) {
        throw new Error(
          `${size}: Alter action engine row nahi mila.`
        );
      }

      /*
        Hidden legacy input may be disabled/max=0 because it was designed
        around old pending_qty. Programmatic value is intentional; the
        backend remains the final Good Qty and active-assignment authority.
      */
      target.value = String(qty);
      entered += qty;
    });

  if (entered <= 0) {
    throw new Error(
      "Kam se kam ek Size me New Alter Qty bharein."
    );
  }

  const workPick = card.querySelector(".work-pick");
  if (workPick && !workPick.disabled) {
    workPick.checked = true;
  }

  return entered;
}

async function openIndependentAlterPanelV765(
  rowData,
  rowElement,
  card
) {
  const rows = await fetchIndependentAlterRowsV765(
    rowData,
    card
  );

  if (!rows.length) {
    throw new Error(
      "Is assigned Department me New Alter raise karne ke liye " +
      "current Good Qty available nahi hai."
    );
  }

  const panel = appendInlinePanel(rowElement, `
    <div class="v756-inline-head">
      <b>${esc(rowData.colour_code)} · NEW ALTER FILL</b>
      <button type="button"
        class="v756-inline-cancel">CANCEL</button>
    </div>

    <div class="v765-alter-rule">
      Ye current <b>${esc(
        rowData.department_name || rowData.department_code
      )}</b> ka naya defect hai.
      Purani open/closed Alter journey se merge nahi hoga.
      Har Save par separate journey start hogi.
    </div>

    <div class="v756-size-grid">
      ${independentAlterInputsV765(rows)}
    </div>

    <div class="v756-inline-foot">
      <button type="button"
        class="v756-inline-save primary">
        CONTINUE · EVIDENCE & PHYSICAL PIECE
      </button>
    </div>
  `);

  panel.querySelector(".v756-inline-cancel").onclick = () =>
    closeInlineAction(rowElement);

  panel.querySelector(".v756-inline-save").onclick = () => {
    try {
      applyIndependentAlterToLegacyEngineV765(
        panel,
        card
      );

      /*
        Existing Alter modal remains authoritative for:
        - 1–3 live camera images
        - Physical piece confirmation
        - mapped Line Man enrolment
        - WhatsApp/outbox
        - rr_upm_alter_stage_v740 journey insert
      */
      clickExistingButton("alterBtn");
      closeInlineAction(rowElement);
    } catch (error) {
      alert([
        error?.message,
        error?.details,
        error?.hint,
        error?.code
      ].filter(Boolean).join(" — ") || String(error));
    }
  };
}

async function openQuantityPanel(rowData, rowElement, card, action) {
  const config = actionConfig(action);
  if (!config) return;

  if (action === "ALTER") {
    await openIndependentAlterPanelV765(
      rowData,
      rowElement,
      card
    );
    return;
  }

  const isDamage = action === "DAMAGE";
  const inputs = isDamage
    ? damageInputsFromCard(card)
    : sizeInputsFromCard(card, config.inputClass, config.sourceSelect);

  if (!inputs) {
    throw new Error(`${config.title} के लिए कोई pending Qty उपलब्ध नहीं है.`);
  }

  const panel = appendInlinePanel(rowElement, `
    <div class="v756-inline-head">
      <b>${esc(rowData.colour_code)} · ${esc(config.title)}</b>
      <button type="button" class="v756-inline-cancel">CANCEL</button>
    </div>
    ${isDamage ? `
      <div class="v759-damage-rule">
        Damage Rate Upto This Stage backend से calculate और freeze होगी.
      </div>
      <div class="v759-responsibility-box">
        <label>Damage Responsibility</label>
        <div class="v759-mode-buttons">
          <button type="button"
            class="v759-mode active"
            data-mode="WORKER_CLAIM">WORKER CLAIM</button>
          <button type="button"
            class="v759-mode"
            data-mode="NO_CLAIM">NO CLAIM</button>
        </div>
        <input type="hidden"
          class="v759-responsibility-mode"
          value="WORKER_CLAIM">
        <div class="v759-no-claim-wrap" hidden>
          <label>No-Claim Reason</label>
          <div class="v759-no-claim-reason-host"></div>
        </div>
      </div>` : ""}
    <div class="v756-size-grid">${inputs}</div>
    <div class="v756-inline-foot">
      <button type="button" class="v756-inline-save primary">
        SAVE ${esc(config.title)}
      </button>
    </div>
  `);

  panel.querySelector(".v756-inline-cancel").onclick = () =>
    closeInlineAction(rowElement);

  let noClaimReasonSearch = null;

  if (isDamage) {
    bindDamageMaxControls(panel, card);
    noClaimReasonSearch = bindDamageResponsibilityMode(panel);
  }

  panel.querySelector(".v756-inline-save").onclick = async () => {
    const button = panel.querySelector(".v756-inline-save");

    try {
      button.disabled = true;
      button.textContent = isDamage ? "SAVING DAMAGE..." : "SAVING...";

      if (isDamage) {
        const result = await saveDamageDirectV759(
          rowData,
          panel,
          card,
          noClaimReasonSearch
        );

        closeInlineAction(rowElement);
        workerCache.clear();
        lotSizeCache.clear();
    v764CompletedCache.clear();
        checkinSignature = "";

        await new Promise(resolve => setTimeout(resolve, 350));
        await syncAll();

        alert(
          `Damage saved. Rows: ${result?.damage_rows_saved ?? 0}\n` +
          `Damage Rate Upto This Stage frozen. Worker Claim या No-Claim mode applied.`
        );
        return;
      }

      applyInlineQuantities(
        panel,
        card,
        config.inputClass,
        config.sourceSelect
      );

      clickExistingButton(config.buttonId);
      closeInlineAction(rowElement);
    } catch (error) {
      console.error("V759 Damage save failed", error);
      alert([
        error?.message,
        error?.details,
        error?.hint,
        error?.code
      ].filter(Boolean).join(" — ") || String(error));
    } finally {
      button.disabled = false;
      button.textContent = `SAVE ${config.title}`;
    }
  };
}

async function runBulkAssign() {
  try {
    const department =
      window.v757BulkDepartmentSearch?.getValue?.() || "";
    const departmentLabel =
      window.v757BulkDepartmentSearch?.getLabel?.() || department;
    const workerId = bulkWorkerSearch?.getValue?.() || "";
    const workerLabel =
      bulkWorkerSearch?.getLabel?.() || workerId;

    if (!department) throw new Error("Department select karein.");
    if (!workerId) {
      throw new Error(
        "Selected Department ka mapped Worker select karein."
      );
    }

    const completedState =
      await fetchCompletedDepartmentMapV764();

    if (
      completedState.fullyCompletedDepartments.has(
        canonicalDepartmentV762(department)
      )
    ) {
      throw new Error(
        `${departmentLabel} me Lot ke sabhi Colours already complete hain.`
      );
    }

    const selectedCodes = v799SelectedCodes();
    if (!selectedCodes.size) throw new Error("Assign ke liye kam se kam 1 OPEN Colour select karein.");

    const eligible = (currentMatrix?.colours || []).filter(row => {
      if (!selectedCodes.has(upper(row.colour_code))) return false;
      if (upper(row.ownership_status) !== "OPEN") return false;

      const completedForColour =
        completedState.completedByColour
          .get(upper(row.colour_code))
          || new Set();

      return !completedForColour.has(
        canonicalDepartmentV762(department)
      );
    });

    if (!eligible.length) {
      throw new Error("Selected Colours me koi eligible OPEN Colour available nahi hai.");
    }

    const names = eligible.map(row => row.colour_code).join(", ");

    if (!confirm(
      `Assign SELECTED OPEN Colours: ${names}\n` +
      `Department: ${departmentLabel}\n` +
      `Worker: ${workerLabel}\n\nConfirm?`
    )) return;

    const identity = currentLotIdentity();
    const rows = eligible.map(row => {
      const qty = colourAssignedQty(row.colour_code);
      if (qty <= 0) {
        throw new Error(
          `${row.colour_code} ki assigned Qty resolve nahi hui.`
        );
      }

      return {
        colour_id: row.colour_id || null,
        colour_code: upper(row.colour_code),
        worker_id: workerId,
        assigned_qty: qty,
        actual_rate: Number($("actualRate")?.value || 0)
      };
    });

    const client = getClient();
    if (!client) throw new Error("Connected Supabase client nahi mila.");

    const { data, error } = await client.rpc(
      "rr_upm_claim_colours_v741",
      {
        p_canonical_lot_id: identity.canonical_lot_id,
        p_lot_no: identity.lot_no,
        p_department_code: canonicalDepartmentV762(department),
        p_rows: rows,
        p_remarks:
          `V760.4.3 Bulk Random Queue assignment · ` +
          `${upper(department)} · ${workerLabel}`
      }
    );

    if (error) throw error;

    workerCache.clear();
    lotSizeCache.clear();
    v764CompletedCache.clear();
    v76043DepartmentCache = null;
    checkinSignature = "";
    await new Promise(resolve => setTimeout(resolve, 450));
    await syncAll();

    alert(
      `${eligible.length} OPEN Colour(s) successfully assigned to ` +
      `${workerLabel} in ${departmentLabel}.`
    );

    return data;
  } catch (error) {
    alert([
      error?.message,
      error?.details,
      error?.hint,
      error?.code
    ].filter(Boolean).join(" — ") || String(error));
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

    /*
      SUBMIT is matrix-driven and must never depend on the legacy hidden
      Colour card. This fixes Lots where currentMatrix exists but the old
      state.context rows/card engine is empty or stale.
    */
    if (action === "SUBMIT") {
      const allowed = await firstSubmitRateGateV760(rowData, rowElement);
      if (!allowed) return;

      await directSubmitColourV7604(rowData);
      closeInlineAction(rowElement);
      return;
    }

    await ensureDepartmentContext(rowData.department_code);

    const card = selectColourCard(colourCode);
    if (!card) {
      throw new Error(
        `Colour ${colourCode} ka quantity-action engine nahi mila. ` +
        `Submit direct engine se available hai.`
      );
    }

    if (action === "ASSIGN") {
      await openAssignPanel(rowData, rowElement, card);
      return;
    }

    if (["ALTER", "DAMAGE", "REMAKE_ISSUE", "RECEIVE_MASTER",
      "DELIVER_KARIGAR", "RECEIVE_KARIGAR"].includes(action)) {
      await openQuantityPanel(
        rowData,
        rowElement,
        card,
        action
      );
      return;
    }
  } catch (error) {
    alert([
      error?.message,
      error?.details,
      error?.hint,
      error?.code
    ].filter(Boolean).join(" — ") || String(error));

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

    const costingButton = event.target.closest(".v760-costing-button");
    if (costingButton) {
      event.preventDefault();
      event.stopPropagation();
      openCostingPanelV760(
        costingButton.dataset.canonical
        || lotCard?.dataset.lot
        || lotCard?.dataset.canonicalLotId
      ).catch(error => alert(error.message || String(error)));
      return;
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
    .v759-damage-rule{
      margin:8px 0;
      padding:9px 11px;
      border:1px solid #705f1c;
      border-radius:7px;
      background:#211d0b;
      color:#f3d86d;
      font-size:12px
    }
    .v759-damage-size{
      grid-template-columns:70px minmax(220px,1fr) 110px 130px!important
    }
    .v759-responsibility-box{
      display:grid;
      gap:8px;
      margin:10px 0;
      padding:10px;
      border:1px solid #38506d;
      border-radius:8px;
      background:#111a27
    }
    .v759-mode-buttons{display:flex;gap:8px;flex-wrap:wrap}
    .v759-mode{
      background:#263449;
      border-color:#536984
    }
    .v759-mode.active{
      background:#1d6b45;
      border-color:#47c787
    }
    .v759-no-claim-wrap{display:grid;gap:6px}
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

    #v756ColourActionPanel ~ #colours > .empty,
    #v756ColourActionPanel + #colours > .empty,
    #colours:has(.v756-detail-hidden) > .empty{
      display:none!important
    }

    .v7604-submit-overlay{
      position:fixed;
      inset:0;
      z-index:14000;
      display:flex;
      align-items:center;
      justify-content:center;
      padding:16px;
      background:#000c
    }
    .v7604-submit-modal{
      width:min(560px,100%);
      padding:16px;
      border:1px solid #425877;
      border-radius:14px;
      background:#111722;
      color:#fff
    }
    .v7604-submit-modal h2{margin:0 0 12px}
    .v7604-submit-copy{
      display:grid;
      gap:8px;
      padding:12px;
      border:1px solid #303e53;
      border-radius:10px;
      background:#19212e
    }
    .v7604-next-label{
      display:grid;
      gap:7px;
      margin-top:12px;
      font-weight:800
    }
    .v7604-next-label select{width:100%}
    .v765-alter-rule{
      margin:10px 0;
      padding:11px;
      border-left:4px solid #d6a81f;
      border-radius:8px;
      background:#332a08;
      color:#fff0ad;
      line-height:1.45
    }
    .v765-alter-size{
      border-color:#8b711e!important;
      background:#261f08!important
    }
    .v765-alter-size small{
      color:#e7d27a
    }

    .v763-bulk-submit{
      border-color:#8a6b2b!important;
      background:#241e12!important;
      grid-template-columns:auto minmax(240px,1fr) auto!important;
    }
    .v763-bulk-submit strong{
      color:#ffd36a;
    }
    #v763BulkSubmit{
      background:#7b5310;
      border-color:#d39b32;
      color:#fff3c4;
    }
    .v763-bulk-submit-modal{
      width:min(700px,100%);
    }
    .v763-bulk-submit-list{
      display:grid;
      gap:7px;
      max-height:42vh;
      overflow:auto;
      margin-top:12px;
    }
    .v763-bulk-submit-colour{
      display:grid;
      grid-template-columns:70px minmax(170px,1fr) minmax(130px,auto);
      gap:8px;
      align-items:center;
      padding:9px;
      border:1px solid #3b4658;
      border-radius:8px;
      background:#151d29;
    }
    .v763-bulk-submit-colour span{
      color:#d7dfeb;
    }
    .v763-bulk-submit-colour small{
      color:#9fb0c5;
      text-align:right;
    }
    @media(max-width:760px){
      .v763-bulk-submit{
        grid-template-columns:1fr!important;
      }
      .v763-bulk-submit-colour{
        grid-template-columns:55px 1fr;
      }
      .v763-bulk-submit-colour small{
        grid-column:1/-1;
        text-align:left;
      }
    }

    .v76043-assign-grid{
      grid-template-columns:minmax(210px,1fr) minmax(260px,1.4fr) auto;
    }
    .v76043-assign-grid .v7571-assign-note{
      grid-column:1/-1;
      color:#9fb0c5;
      font-size:12px
    }
    @media(max-width:760px){
      .v76043-assign-grid{
        grid-template-columns:1fr;
      }
    }

    .v7604-random-route-note{
      margin-top:12px;
      padding:11px;
      border-left:4px solid #37b878;
      border-radius:8px;
      background:#123628;
      line-height:1.45
    }
    .v7604-submit-actions{
      display:grid;
      grid-template-columns:1fr 1fr;
      gap:10px;
      margin-top:14px
    }
    #v7604SubmitYes{
      background:#cf3b59;
      border-color:#ec6680
    }

    .v760-costing-button,
    #v760CheckinCosting{
      margin:7px 0;
      padding:8px 12px;
      border:1px solid #d5a51c;
      border-radius:8px;
      background:#4b3905;
      color:#ffe07a;
      font-weight:950
    }
    .v760-title #v760CheckinCosting{margin-left:auto}
    .v760-costing-overlay{
      position:fixed;
      inset:0;
      z-index:12000;
      display:flex;
      align-items:center;
      justify-content:center;
      padding:16px;
      background:#000c
    }
    .v760-costing-modal{
      width:min(1100px,100%);
      max-height:94vh;
      overflow:auto;
      padding:14px;
      border:1px solid #465a75;
      border-radius:12px;
      background:#0b111b;
      color:#fff
    }
    .v760-costing-head{
      display:flex;
      justify-content:space-between;
      gap:12px;
      align-items:center;
      position:sticky;
      top:0;
      z-index:2;
      padding:10px;
      background:#0b111bf2;
      border-bottom:1px solid #334760
    }
    .v760-costing-head div{display:grid;gap:3px}
    .v760-costing-head small{color:#9fb0c5}
    .v760-section{
      margin-top:12px;
      padding:12px;
      border:1px solid #2c3d53;
      border-radius:10px;
      background:#101927
    }
    .v760-section h3{margin:0 0 10px;font-size:14px}
    .v760-material-grid,
    .v760-summary-grid{
      display:grid;
      grid-template-columns:repeat(auto-fit,minmax(180px,1fr));
      gap:8px
    }
    .v760-material-grid label{display:grid;gap:4px}
    .v760-rate-list{display:grid;gap:8px}
    .v760-rate-row{
      display:grid;
      grid-template-columns:minmax(170px,1fr) 150px 140px 145px auto;
      gap:8px;
      align-items:end;
      padding:9px;
      border:1px solid #344961;
      border-radius:8px;
      background:#131f2e
    }
    .v760-rate-row>div{display:grid;gap:3px}
    .v760-rate-row small{color:#94a8bd}
    .v760-rate-row label{display:grid;gap:4px}
    .v760-rate-source{
      padding:8px;
      border-radius:6px;
      text-align:center;
      font-weight:900;
      background:#3d4654
    }
    .v760-rate-source.actual{background:#165f3d}
    .v760-rate-source.standard_fallback{background:#66520c}
    .v760-rate-source.missing{background:#772d38}
    .v760-focus-rate{
      outline:3px solid #d6a928;
      box-shadow:0 0 18px #d6a92866
    }
    .v760-summary-grid span{
      display:flex;
      justify-content:space-between;
      gap:8px;
      padding:8px;
      border:1px solid #31435b;
      border-radius:7px;
      background:#111b29
    }
    .v760-loss-section{
      border-color:#753b43;
      background:#221217
    }
    .v760-top-summary{
      position:sticky;
      top:66px;
      z-index:1;
      background:#101927f2
    }
    .v760-save-all-wrap{
      position:sticky;
      bottom:0;
      display:flex;
      align-items:center;
      justify-content:flex-end;
      gap:12px;
      margin-top:12px;
      padding:10px;
      border-top:1px solid #455b75;
      background:#101927f2
    }
    #v760SaveAllRates{
      min-width:180px;
      background:#1d6b45;
      border-color:#47c787
    }
    #v760RateSaveStatus{
      min-width:180px;
      color:#9fdabf;
      font-weight:900
    }
    @media(max-width:800px){
      .v760-rate-row{
        grid-template-columns:1fr 1fr;
      }
      .v760-rate-row>div{grid-column:1/-1}
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
    badge.textContent = "V765 ACTIVE";
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
    v764CompletedCache.clear();
    v76043DepartmentCache = null;
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

window.REDZED_UPM_V765 = {
  version: VERSION,
  sync: syncAll
};

console.info("REDZED UPM", VERSION);

const v799BulkStyle = document.createElement("style");
v799BulkStyle.textContent = `
  .v799-bulk-pick-wrap{display:flex;align-items:center;gap:9px;cursor:pointer}
  .v799-bulk-pick{width:20px;height:20px;accent-color:#56efb2;flex:0 0 auto}
  .v799-bulk-select-actions{display:grid;grid-template-columns:1fr auto;gap:8px;margin-top:8px}
  .v799-bulk-select-actions button{min-height:40px}
`;
document.head.appendChild(v799BulkStyle);
console.log("REAL FACTORY V799.2 SELECTIVE BULK ASSIGN/SUBMIT ready");
})();
