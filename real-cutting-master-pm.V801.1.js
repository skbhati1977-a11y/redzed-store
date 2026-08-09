// ===== REAL FACTORY CUTTING MASTER PM CORE V801 START =====

(() => {
"use strict";

/*
  REAL FACTORY — Cutting Master PM Core V801.1 + Individual Multi Lot Cards
  Product Master child-aware Cutting Lots.

  Locked architecture:
  - Matching Cloth is optional.
  - Single release keeps the selected child code: D1, D2, D3...
  - Multi release splits that child: D1A, D1B... or D2A, D2B...
  - Child display never includes the CB prefix.
  - Released Lot No is the permanent downstream identity.
*/

const $ = id => document.getElementById(id);

const gallery = $("divisionGallery");
const message = $("cmMessage");
const lotSheet = $("lotSheet");
const splitSheet = $("splitSheet");
const costSheet = $("costSheet");

let galleryRows = [];
let purchaseRows = [];
let matchingPurchaseRows = [];
let colourRows = [];
let artRows = [];
let printRows = [];
let assignmentRows = [];
let printAssignmentRows = [];
let printFrameRows = [];
let stickerInstructionRows = [];
let stickerAssignmentRows = [];
let metalIdInstructionRows = [];
let metalIdAssignmentRows = [];
let cuttingWorkerRows = [];
let mediaRows = [];
let lotRows = [];
let singleLotRows = [];
let multiLotRows = [];
let breakupRows = [];
let matchingStockRows = [];
let matchingLotRows = [];
let currentRole = "";

let currentFilter = "all";
let activeCard = null;
let releaseLock = false;
let lastReleasedLotNo = "";
let lastReleasedDivisionId = "";
let costSettings = {
  settings_key: "default",
  default_base_cost: 0,
  big_adjustment: 5,
  full_sleeve_adjustment: 5,
  border_adjustment: 5,
  allow_custom_adjustment: true
};

function esc(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    char =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;"
      }[char])
  );
}

function safe(value) {
  try {
    if (
      typeof RR !== "undefined" &&
      RR &&
      typeof RR.safeText === "function"
    ) {
      return RR.safeText(value ?? "");
    }
  } catch (_) {}

  return esc(value);
}

function cuttingCanViewFinancials() {
  return ["owner","admin","account","accounts"].includes(String(currentRole||"").toLowerCase());
}
function cuttingCanConfigure() {
  return ["owner","admin"].includes(String(currentRole||"").toLowerCase());
}

async function loadCuttingRole(client) {
  if (currentRole) return currentRole;
  try {
    const result = await client.rpc("rr_current_role");
    if (!result.error && result.data) currentRole = String(result.data).toLowerCase();
  } catch (_) {}
  const settingsButton = $("openCostSettings");
  if (settingsButton && !cuttingCanConfigure()) settingsButton.style.display = "none";
  return currentRole;
}

function getClient() {
  try {
    if (
      typeof supabaseClient !== "undefined" &&
      supabaseClient &&
      typeof supabaseClient.from === "function"
    ) {
      return supabaseClient;
    }
  } catch (_) {}

  return [
    window.supabaseClient,
    window.supabaseDb,
    window.redzedSupabase,
    window.sb
  ].find(
    item =>
      item &&
      typeof item.from === "function"
  ) || null;
}

function say(text = "", type = "") {
  if (!message) return;

  message.textContent = text;
  message.className = `rr-message ${type}`.trim();
}

function ensureLotReleaseFeedback() {
  let node = $("cmLotReleaseFeedback");
  if (node) return node;

  const form = $("lotForm");
  const button =
    $("releaseLotBtn") ||
    form?.querySelector('button[type="submit"]');

  if (!form || !button) return null;

  node = document.createElement("div");
  node.id = "cmLotReleaseFeedback";
  node.className = "cm-release-feedback cm-hidden";
  node.setAttribute("role", "alert");
  node.setAttribute("aria-live", "assertive");

  const holder = button.closest(".cm-actions") || button.parentElement;
  holder?.insertAdjacentElement("beforebegin", node);
  return node;
}

function setLotReleaseFeedback(text = "", type = "") {
  const node = ensureLotReleaseFeedback();
  if (!node) return;

  node.textContent = text;
  node.className = `cm-release-feedback ${text ? "" : "cm-hidden"} ${type ? `is-${type}` : ""}`.trim();

  if (text && type === "error") {
    node.scrollIntoView({ behavior: "smooth", block: "center" });
  }
}

function isMissingRpcError(error) {
  const text = errorText(error);
  return (
    String(error?.code || "") === "PGRST202" ||
    /could not find the function|function .* does not exist|schema cache/i.test(text)
  );
}

function releaseErrorText(error) {
  const text = errorText(error);

  if (/dev code must be d1|variant[_ ]code|d1, d2, d3 or d4/i.test(text)) {
    return `${text} — Supabase में V719_1_MULTI_SUBDEV_RELEASE_PATCH.sql run करें.`;
  }

  if (isMissingRpcError(error)) {
    return `${text} — Required Cutting Release SQL/RPC Supabase में install नहीं है.`;
  }

  return text;
}

function money(value) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2
  }).format(Number(value || 0));
}

function canonicalDevelopmentCode(value, fallbackIndex = 0) {
  const raw = String(value || "")
    .trim()
    .toUpperCase()
    .replace(/\s+/g, "");

  const direct = raw.match(/D(\d+)([A-Z]*)$/);
  if (direct) {
    return `D${Number(direct[1])}${direct[2] || ""}`;
  }

  const legacy = raw.match(/S(\d+)([A-Z]*)$/);
  if (legacy) {
    return `D${Number(legacy[1])}${legacy[2] || ""}`;
  }

  const index = Number(fallbackIndex || 0);
  return index > 0 ? `D${index}` : "D1";
}

function childCodeForRow(row = {}) {
  return canonicalDevelopmentCode(
    row.division_code ||
    row.cb_child ||
    row.child_code ||
    row.child_no ||
    row.cb_code ||
    row.unit_code ||
    "",
    row.division_index || row.batch_index || 0
  );
}

function activeChildCode() {
  return activeCard
    ? childCodeForRow(activeCard.division)
    : "D1";
}

function subDevelopmentCode(baseCode, index) {
  const suffix = String.fromCharCode(65 + Math.max(0, Number(index || 0)));
  return `${canonicalDevelopmentCode(baseCode)}${suffix}`;
}

function normalizeMatchingStockRow(row = {}) {
  return {
    ...row,
    matching_item_id:
      row.matching_item_id ||
      row.stock_item_id ||
      row.item_id ||
      row.matching_purchase_entry_id ||
      row.purchase_entry_id ||
      row.id ||
      row.cb_id ||
      row.cb_purchase_id ||
      row.purchase_id ||
      "",
    cb_id:
      row.cb_id ||
      row.cb_purchase_id ||
      row.purchase_id ||
      "",
    fabric_name:
      row.fabric_name ||
      row.matching_fabric_name ||
      row.item_name ||
      "Matching Cloth",
    available_qty: Number(
      row.available_qty ??
      row.current_qty ??
      row.balance_qty ??
      row.quantity ??
      0
    ),
    avg_cost: Number(
      row.avg_cost ??
      row.current_avg_rate ??
      row.average_rate ??
      row.weighted_avg_cost ??
      row.rate ??
      0
    )
  };
}

function matchingRowsForActiveCard() {
  const activeCbId = String(activeCard?.group?.cb_id || "");

  return matchingStockRows
    .map(normalizeMatchingStockRow)
    .filter(row => {
      const rowCbId = String(row.cb_id || "");
      return (
        !activeCbId ||
        !rowCbId ||
        rowCbId === activeCbId ||
        isMatchingOnlyCb(rowCbId)
      );
    });
}

function matchingStockFor(id) {
  return matchingStockRows
    .map(normalizeMatchingStockRow)
    .find(row =>
      String(row.matching_item_id || "") === String(id || "")
    ) || null;
}

function matchingItemId(row = {}) {
  return normalizeMatchingStockRow(row).matching_item_id;
}

function matchingStockOptions(selectedId = "") {
  const selected = String(selectedId || "");
  const rows = matchingRowsForActiveCard().sort((a, b) =>
    String(a.fabric_name || "").localeCompare(String(b.fabric_name || ""))
  );

  const stockOptions = rows.map(row => {
    const id = matchingItemId(row);
    const available = Number(row.available_qty || 0);
    const avg = Number(row.avg_cost || 0);

    return `
      <option
        value="${safe(id)}"
        ${String(id) === selected ? "selected" : ""}
        ${available <= 0 && String(id) !== selected ? "disabled" : ""}
      >
        ${safe(row.fabric_name || "Matching Cloth")} · ${available.toFixed(3)} kg${cuttingCanViewFinancials() ? ` · ${money(avg)}/kg` : ""}
      </option>
    `;
  });

  return [
    `<option value="">No Matching Cloth</option>`,
    ...stockOptions,
    ...(!rows.length
      ? [`<option value="" disabled>Stock नहीं मिला — Product Master में Matching Purchase जोड़ें</option>`]
      : [])
  ].join("");
}

function matchingSnapshot(id) {
  const row = matchingStockFor(id);
  return {
    itemId: row ? matchingItemId(row) : "",
    fabricName: row?.fabric_name || "",
    availableQty: Number(row?.available_qty || 0),
    avgCost: Number(row?.avg_cost || 0)
  };
}

function matchingPostingForLot(lotNo) {
  return matchingLotRows.find(row =>
    String(row.lot_no || "").trim().toUpperCase() === String(lotNo || "").trim().toUpperCase() &&
    String(row.status || "").toUpperCase() === "POSTED"
  ) || null;
}

function effectiveLotTotalCost(lot = {}) {
  const base = Number(lot.total_cutting_cost || 0);
  const posted = matchingPostingForLot(lot.lot_no);
  if (!posted) return base;
  const alreadyStored = Number(lot.matching_total_cost || 0);
  return base + Math.max(0, Number(posted.total_cost || 0) - alreadyStored);
}

function setSingleMatchingState(selectedId = null) {
  const select = $("cmSingleMatchingItem");
  const qtyInput = $("cmSingleMatchingQty");
  const avgInput = $("cmSingleMatchingAvgCost");
  const info = $("cmSingleMatchingStockInfo");
  if (!select) return;

  const id = selectedId === null ? select.value : selectedId;
  const snapshot = matchingSnapshot(id);
  select.value = snapshot.itemId || "";

  if (snapshot.itemId) {
    if (qtyInput) { qtyInput.disabled = false; if (Number(qtyInput.value || 0) === 0) qtyInput.value = ""; }
    if (avgInput) avgInput.value = String(snapshot.avgCost || 0);
    if (info) {
      info.textContent = cuttingCanViewFinancials()
        ? `Available ${snapshot.availableQty.toFixed(3)} kg · Current Avg ${money(snapshot.avgCost)}/kg`
        : `Available ${snapshot.availableQty.toFixed(3)} kg`;
    }
  } else {
    if (qtyInput) {
      qtyInput.value = "";
      qtyInput.disabled = true;
    }
    if (avgInput) avgInput.value = "";
    if (info) {
      info.textContent = matchingRowsForActiveCard().length
        ? "No Matching Cloth selected · Qty 0 · Avg Cost 0 · Release allowed."
        : "Matching stock नहीं मिला. Product Master → CB Details → Add Purchase → + Add Matching Purchase से stock डालें.";
    }
  }
}

function refreshMatchingStockControls() {
  const single = $("cmSingleMatchingItem");
  if (single) {
    const selected = single.value;
    single.innerHTML = matchingStockOptions(selected);
    single.value = matchingStockFor(selected) ? selected : "";
    setSingleMatchingState(single.value);
  }
}

function normalizeMatchingRow(row = {}, label = "Lot") {
  const snapshot = matchingSnapshot(row.matching_item_id);

  if (!snapshot.itemId) {
    return {
      ...row,
      matching_item_id: null,
      matching_consumption: 0,
      matching_avg_cost: 0
    };
  }

  const matchingQty = Number(row.matching_consumption || 0);

  if (matchingQty <= 0) {
    throw new Error(`${label}: Enter Matching Qty.`);
  }

  if (matchingQty > snapshot.availableQty + 0.0005) {
    throw new Error(
      `${label}: Matching stock ${snapshot.availableQty.toFixed(3)} kg है, Qty ${matchingQty.toFixed(3)} kg है.`
    );
  }

  return {
    ...row,
    matching_item_id: snapshot.itemId,
    matching_consumption: matchingQty,
    matching_avg_cost: snapshot.avgCost
  };
}

function today() {
  const date = new Date();

  return `${date.getFullYear()}-${String(
    date.getMonth() + 1
  ).padStart(2, "0")}-${String(
    date.getDate()
  ).padStart(2, "0")}`;
}

function errorText(error) {
  return [
    error?.message,
    error?.details,
    error?.hint,
    error?.code ? `Code: ${error.code}` : ""
  ]
    .filter(Boolean)
    .join(" — ") || "Unknown error";
}

function withTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      reject(new Error(`${label} timed out.`));
    }, ms);

    Promise
      .resolve(promise)
      .then(
        value => {
          window.clearTimeout(timer);
          resolve(value);
        },
        error => {
          window.clearTimeout(timer);
          reject(error);
        }
      );
  });
}

function setInputValue(id, value) {
  const input = $(id);

  if (input) {
    input.value = value ?? "";
  }
}

function readText(id) {
  return String($(id)?.value ?? "").trim();
}

function numberValue(id) {
  return Number($(id)?.value || 0);
}

function selectValue(id) {
  return String($(id)?.value ?? "");
}

function closeSheet(sheet) {
  if (!sheet) return;

  sheet.classList.add("cm-hidden");
  sheet.setAttribute("aria-hidden", "true");

  if (
    lotSheet?.classList.contains("cm-hidden") &&
    splitSheet?.classList.contains("cm-hidden") &&
    costSheet?.classList.contains("cm-hidden")
  ) {
    document.body.classList.remove("cm-no-scroll");
  }
}

function openSheet(sheet) {
  if (!sheet) return;

  sheet.classList.remove("cm-hidden");
  sheet.setAttribute("aria-hidden", "false");
  document.body.classList.add("cm-no-scroll");
}

function showFatal(error) {
  console.error(error);

  if (gallery) {
    gallery.setAttribute("aria-busy", "false");

    gallery.innerHTML = `
      <article class="cm-empty">
        <h3>Cutting Master could not load</h3>
        <p>${safe(errorText(error))}</p>
      </article>
    `;
  }

  say(errorText(error), "error");
}

async function selectRows(client, table, options = {}) {
  let query = client
    .from(table)
    .select(options.select || "*");

  if (options.eq) {
    Object.entries(options.eq).forEach(([key, value]) => {
      query = query.eq(key, value);
    });
  }

  if (options.order) {
    query = query.order(options.order, {
      ascending: options.ascending ?? false
    });
  }

  let result = await query;

  if (result.error && options.order) {
    let retry = client
      .from(table)
      .select(options.select || "*");

    if (options.eq) {
      Object.entries(options.eq).forEach(([key, value]) => {
        retry = retry.eq(key, value);
      });
    }

    result = await retry;
  }

  return result;
}

async function optionalRows(client, table, options = {}) {
  const result = await selectRows(client, table, options);

  if (result.error) {
    console.warn(`${table} unavailable:`, result.error);
    return [];
  }

  return result.data || [];
}

function requiredData(result, label) {
  if (result.error) {
    throw new Error(`${label}: ${errorText(result.error)}`);
  }

  return result.data || [];
}

function normalizeGalleryRow(row) {
  const cbId =
    row.cb_id ||
    row.purchase_id ||
    row.parent_cb_id ||
    row.fabric_purchase_id ||
    "";

  const divisionId =
    row.division_id ||
    row.unit_id ||
    row.id ||
    row.cb_unit_id ||
    "";

  const divisionIndex = Number(
    row.division_index ||
    row.batch_index ||
    0
  );

  return {
    ...row,
    cb_id: cbId,
    division_id: divisionId,
    division_index: divisionIndex,

    division_code: canonicalDevelopmentCode(
      row.division_code ||
      row.cb_child ||
      row.child_code ||
      row.child_no ||
      row.cb_code ||
      row.unit_code ||
      "",
      divisionIndex
    ),

    division_status:
      row.division_status ||
      row.status ||
      "planning",

    allocated_qty: Number(
      row.allocated_qty ??
      row.divided_weight ??
      row.base_qty ??
      row.weight ??
      0
    ),

    allocated_amount: Number(
      row.allocated_amount ??
      row.divided_amount ??
      row.base_amount ??
      0
    ),

    base_qty: Number(
      row.base_qty ??
      row.allocated_qty ??
      row.divided_weight ??
      0
    ),

    base_amount: Number(
      row.base_amount ??
      row.allocated_amount ??
      row.divided_amount ??
      0
    ),

    cb_no:
      row.cb_no ||
      row.purchase_no ||
      row.purchase_code ||
      "CB",

    created_at:
      row.created_at ||
      row.updated_at ||
      ""
  };
}

async function loadGallerySource(client) {
  const productionView = await client
    .from("rr_product_gallery_production_v719")
    .select("*");

  if (!productionView.error) {
    return (productionView.data || []).map(normalizeGalleryRow);
  }

  const viewResult = await client
    .from("rr_product_gallery_view")
    .select("*");

  if (!viewResult.error) {
    return (viewResult.data || []).map(normalizeGalleryRow);
  }

  console.warn(
    "Product gallery views unavailable; using fallback.",
    productionView.error,
    viewResult.error
  );

  const [divisionResult, purchaseResult] = await Promise.all([
    client
      .from("rr_cb_units")
      .select("*"),

    client
      .from("rr_fabric_purchases")
      .select("*")
  ]);

  if (divisionResult.error) throw divisionResult.error;
  if (purchaseResult.error) throw purchaseResult.error;

  const purchaseMap = new Map(
    (purchaseResult.data || []).map(row => [
      String(row.id),
      row
    ])
  );

  const statusMap = {
    available: "planning",
    art_assigned: "ready_for_cutting",
    material_pending: "material_pending",
    cutting: "ready_for_cutting",
    completed: "ready_for_cutting",
    cancelled: "hold"
  };

  return (divisionResult.data || []).map(division => {
    const purchase =
      purchaseMap.get(String(division.purchase_id)) ||
      {};

    return normalizeGalleryRow({
      cb_id: division.purchase_id,
      division_id: division.id,
      division_index: division.division_index,
      division_code: division.cb_code,

      division_status:
        statusMap[division.status] ||
        "planning",

      allocated_qty: division.divided_weight,
      allocated_amount: division.divided_amount,
      base_qty: division.divided_weight,
      base_amount: division.divided_amount,

      cb_no:
        purchase.cb_no ||
        division.cb_base_no,

      created_at:
        division.created_at ||
        purchase.created_at
    });
  });
}

async function loadPrintSource(client) {
  const view = await client
    .from("rr_print_library_view")
    .select("*");

  if (!view.error) {
    return view.data || [];
  }

  console.warn(
    "rr_print_library_view unavailable; using rr_print_master.",
    view.error
  );

  const table = await client
    .from("rr_print_master")
    .select("*");

  if (table.error) {
    throw table.error;
  }

  return table.data || [];
}

function groupGalleryRows() {
  const groups = new Map();

  const statusPriority = {
    hold: 50,
    ready_for_cutting: 40,
    material_pending: 30,
    planning: 20,
    purchase: 10
  };

  galleryRows.forEach(row => {
    const key = String(row.cb_id || "");

    if (!key) return;

    if (!groups.has(key)) {
      groups.set(key, {
        cb_id: row.cb_id,
        cb_no: row.cb_no,
        status: row.division_status,
        created_at: row.created_at,
        divisionMap: new Map()
      });
    }

    const group = groups.get(key);

    const divisionKey = String(
      row.division_id ||
      row.division_code
    );

    if (!group.divisionMap.has(divisionKey)) {
      group.divisionMap.set(divisionKey, row);
    }

    if (
      (statusPriority[row.division_status] || 0) >
      (statusPriority[group.status] || 0)
    ) {
      group.status = row.division_status;
    }
  });

  return [...groups.values()]
    .map(group => {
      const divisions = [
        ...group.divisionMap.values()
      ].sort(
        (a, b) =>
          Number(a.division_index || 0) -
          Number(b.division_index || 0)
      );

      return {
        ...group,
        divisions,

        quantity: divisions.reduce(
          (sum, row) =>
            sum + Number(row.allocated_qty || 0),
          0
        ),

        amount: divisions.reduce(
          (sum, row) =>
            sum + Number(row.allocated_amount || 0),
          0
        )
      };
    })
    .sort((a, b) => {
      const dateCompare = String(
        b.created_at || ""
      ).localeCompare(
        String(a.created_at || "")
      );

      if (dateCompare) return dateCompare;

      return String(b.cb_no || "").localeCompare(
        String(a.cb_no || ""),
        undefined,
        { numeric: true }
      );
    });
}

function purchasesFor(cbId) {
  return purchaseRows.filter(
    row => String(row.cb_id) === String(cbId)
  );
}

function meaningfulProductionPurchase(row = {}) {
  const quantity = Number(
    row.quantity ??
    row.total_quantity ??
    row.purchase_qty ??
    0
  );

  const amount = Number(
    row.amount ??
    row.total_amount ??
    row.purchase_amount ??
    0
  );

  // Ignore zero-value placeholder material rows created by older CB RPCs.
  // A Matching-only stock card must not become a Cutting card because of them.
  return quantity > 0.0005 || amount > 0.01;
}

function productionPurchaseExists(cbId) {
  return purchaseRows.some(row =>
    String(row.cb_id) === String(cbId) &&
    meaningfulProductionPurchase(row)
  );
}

function matchingPurchaseExists(cbId) {
  return matchingPurchaseRows.some(row => String(row.cb_id) === String(cbId));
}

function isMatchingOnlyCb(cbId) {
  return Boolean(cbId) &&
    matchingPurchaseExists(cbId) &&
    !productionPurchaseExists(cbId);
}

function rowExplicitlyMatchingOnly(row = {}) {
  const type = String(
    row.card_type ||
    row.record_type ||
    row.cb_type ||
    ""
  ).trim().toLowerCase();

  return (
    type === "matching_stock" ||
    type === "matching-cloth" ||
    type === "matching_cloth" ||
    row.is_cutting_enabled === false ||
    row.cutting_enabled === false
  );
}

function productionGalleryRows(rows = []) {
  return rows.filter(row =>
    !rowExplicitlyMatchingOnly(row) &&
    !isMatchingOnlyCb(row.cb_id)
  );
}

function coloursFor(cbId) {
  return colourRows
    .filter(row => String(row.cb_id) === String(cbId))
    .sort(
      (a, b) =>
        Number(a.colour_order || 0) -
        Number(b.colour_order || 0)
    );
}

function artById(id) {
  return (
    artRows.find(row => String(row.id) === String(id)) ||
    null
  );
}

function printById(id) {
  return (
    printRows.find(row => String(row.id) === String(id)) ||
    null
  );
}

function assignmentForDivision(divisionId) {
  return (
    assignmentRows
      .filter(
        row =>
          String(row.division_id) === String(divisionId) ||
          String(row.cb_id) === String(divisionId)
      )
      .sort((a, b) =>
        String(
          b.updated_at ||
          b.created_at ||
          ""
        ).localeCompare(
          String(
            a.updated_at ||
            a.created_at ||
            ""
          )
        )
      )[0] || null
  );
}

function assignedPrintsForDivision(divisionId) {
  const assignment = assignmentForDivision(divisionId);

  if (!assignment) return [];

  return printAssignmentRows
    .filter(
      row =>
        String(row.assignment_id) ===
        String(assignment.id)
    )
    .sort(
      (a, b) =>
        Number(a.sequence_no || 0) -
        Number(b.sequence_no || 0)
    )
    .map(row => printById(row.print_id))
    .filter(Boolean);
}

function activeFramesForPrints(prints = []) {
  const ids = new Set((prints || []).map(row => String(row?.id || '')).filter(Boolean));
  return printFrameRows
    .filter(row => ids.has(String(row.print_id || '')) && String(row.frame_status || '').trim().toLowerCase() === 'active')
    .sort((a,b) => String(a.frame_no || '').localeCompare(String(b.frame_no || ''), undefined, { numeric: true }));
}


function stickerInstructionById(id) {
  return stickerInstructionRows.find(row => String(row.id) === String(id)) || null;
}

function metalIdInstructionById(id) {
  return metalIdInstructionRows.find(row => String(row.id) === String(id)) || null;
}

function assignedStickerInstructionsForDivision(divisionId) {
  const assignment = assignmentForDivision(divisionId);
  if (!assignment) return [];
  return stickerAssignmentRows
    .filter(row => String(row.assignment_id) === String(assignment.id))
    .sort((a,b) => Number(a.sequence_no || 0) - Number(b.sequence_no || 0))
    .map(row => stickerInstructionById(row.sticker_instruction_id))
    .filter(Boolean);
}

function assignedMetalIdInstructionsForDivision(divisionId) {
  const assignment = assignmentForDivision(divisionId);
  if (!assignment) return [];
  return metalIdAssignmentRows
    .filter(row => String(row.assignment_id) === String(assignment.id))
    .sort((a,b) => Number(a.sequence_no || 0) - Number(b.sequence_no || 0))
    .map(row => metalIdInstructionById(row.metal_id_instruction_id))
    .filter(Boolean);
}

function normalizedStickerType(value) {
  const type = String(value || '').trim().toLowerCase();
  return ['hd','dtf','vinyl'].includes(type) ? type : '';
}

function stickerTypeText(value) {
  const type = normalizedStickerType(value);
  return type ? type.toUpperCase() : '';
}

function mediaForEntity(entityId, kind) {
  const list = mediaRows.filter(
    row => String(row.entity_id) === String(entityId)
  );

  return list.sort((a, b) => {
    const aKind =
      kind === "print"
        ? String(a.entity_type || "").toLowerCase() === "printing"
        : String(a.entity_type || "").toLowerCase() !== "printing";

    const bKind =
      kind === "print"
        ? String(b.entity_type || "").toLowerCase() === "printing"
        : String(b.entity_type || "").toLowerCase() !== "printing";

    if (aKind !== bKind) return aKind ? -1 : 1;

    if (Boolean(a.is_cover) !== Boolean(b.is_cover)) {
      return a.is_cover ? -1 : 1;
    }

    return Number(a.sort_order || 0) -
      Number(b.sort_order || 0);
  });
}

function artImageUrl(art) {
  if (!art) return "";

  return (
    art.hero_image_url ||
    art.image_url ||
    art.artwork_url ||
    art.reference_image_url ||
    mediaForEntity(art.id, "art")[0]?.file_url ||
    ""
  );
}

function printImageUrl(print) {
  if (!print) return "";

  return (
    print.artwork_url ||
    print.garment_preview_url ||
    print.image_url ||
    mediaForEntity(print.id, "print")[0]?.file_url ||
    ""
  );
}

function artNo(art) {
  return (
    art?.art_no ||
    art?.art_code ||
    art?.code ||
    ""
  );
}

function styleNameFromArt(art) {
  return (
    art?.product_name ||
    art?.item_name ||
    art?.style_name ||
    art?.category ||
    artNo(art) ||
    ""
  );
}

function printNo(print) {
  return (
    print?.print_no ||
    print?.print_code ||
    print?.code ||
    ""
  );
}

function printText(prints) {
  const text = prints
    .map(printNo)
    .filter(Boolean)
    .join(", ");

  return text || "N/A";
}

function carouselItemsForAssignment(art, prints = []) {
  if (!art && !prints.length) return [];

  const items = [];

  if (art) {
    items.push({
      url: artImageUrl(art),
      label: `ART ${artNo(art) || ""}`,
      kind: "art"
    });
  }

  prints.forEach(print => {
    items.push({
      url: printImageUrl(print),
      label: `PRINT ${printNo(print) || ""}`,
      kind: "print"
    });
  });

  return items;
}

function imageStripHtml(items, colours = []) {
  let finalItems = items.filter(item => item.url);

  if (!finalItems.length) {
    const colourImage =
      colours.find(row => row.image_url)?.image_url;

    if (colourImage) {
      finalItems = [
        {
          url: colourImage,
          label: "CB COLOUR",
          kind: "colour"
        }
      ];
    }
  }

  if (!finalItems.length) {
    return `
      <div class="cm-pm-photo-empty">
        <span>ART PHOTO</span>
        <small>Photo not added in Master</small>
      </div>
    `;
  }

  return `
    <div class="cm-pm-images">
      ${finalItems
        .slice(0, 4)
        .map(
          item => `
            <figure>
              <img
                src="${safe(item.url)}"
                alt="${safe(item.label)}"
                loading="lazy"
              >
              <figcaption>${safe(item.label)}</figcaption>
            </figure>
          `
        )
        .join("")}
    </div>
  `;
}

function divisionCards() {
  return groupGalleryRows()
    .filter(group => !isMatchingOnlyCb(group.cb_id))
    .flatMap(group =>
      group.divisions
        .filter(division => !rowExplicitlyMatchingOnly(division))
        .map(division => ({
          group,
          division,
          assignment: assignmentForDivision(
            division.division_id
          )
        }))
    )
    .sort((a, b) => {
      const dateCompare = String(
        b.division.created_at ||
        b.group.created_at ||
        ""
      ).localeCompare(
        String(
          a.division.created_at ||
          a.group.created_at ||
          ""
        )
      );

      if (dateCompare) return dateCompare;

      return String(
        b.division.division_code || ""
      ).localeCompare(
        String(
          a.division.division_code || ""
        ),
        undefined,
        { numeric: true }
      );
    });
}

function lotsForDivision(divisionId) {
  return lotRows.filter(
    row =>
      String(row.cb_unit_id) === String(divisionId) ||
      String(row.division_id) === String(divisionId) ||
      String(row.cb_division_id) === String(divisionId)
  );
}

function lotForDivision(divisionId) {
  return lotsForDivision(divisionId)[0] || null;
}

function cardDecision(card) {
  const assignment = card.assignment || null;
  const art = assignment ? artById(assignment.art_id) : null;
  const prints = assignedPrintsForDivision(card.division.division_id);
  const frames = activeFramesForPrints(prints);
  const stickerInstructions = assignedStickerInstructionsForDivision(card.division.division_id);
  const metalIdInstructions = assignedMetalIdInstructionsForDivision(card.division.division_id);

  const noPrintRequired = Boolean(
    assignment && (
      assignment.no_print_required === true ||
      assignment.print_required === false ||
      assignment.print_not_applicable === true ||
      String(assignment.print_status || '').trim().toLowerCase() === 'not_required'
    )
  );

  const stickerNotApplicable = Boolean(assignment?.sticker_not_applicable === true);
  const metalIdNotApplicable = Boolean(assignment?.metal_id_not_applicable === true);
  const selectedSticker = stickerInstructions.find(row => normalizedStickerType(row.work_type)) || null;
  const selectedMetalId = metalIdInstructions[0] || null;

  const artReady = Boolean(assignment && art);
  const printReady = Boolean(artReady && (prints.length > 0 || noPrintRequired));
  const stickerDecided = Boolean(stickerNotApplicable || selectedSticker);
  const metalIdDecided = Boolean(metalIdNotApplicable || selectedMetalId);
  const releaseReady = Boolean(printReady && stickerDecided && metalIdDecided);

  return {
    assignment,
    art,
    prints,
    frames,
    stickerInstructions,
    metalIdInstructions,
    noPrintRequired,
    stickerNotApplicable,
    metalIdNotApplicable,
    selectedSticker,
    selectedMetalId,
    artReady,
    printReady,
    stickerDecided,
    metalIdDecided,
    releaseReady,
    // ready means final release-ready in V801.
    ready: releaseReady,
    artNo: artNo(art),
    printNo: noPrintRequired ? 'N/A' : printText(prints),
    frameNo: noPrintRequired ? 'N/A' : frames.map(row => row.frame_no).filter(Boolean).join(', '),
    stickerType: stickerNotApplicable ? 'N/A' : stickerTypeText(selectedSticker?.work_type),
    metalIdDecision: metalIdNotApplicable ? 'N/A' : (selectedMetalId ? 'REQUIRED' : ''),
    styleName: styleNameFromArt(art)
  };
}

function cardState(card) {
  const lots = lotsForDivision(
    card.division.division_id
  );

  if (lots.some(lot => lot?.status === "completed")) {
    return "completed";
  }

  if (lots.length) return "released";

  const decision = cardDecision(card);

  if (!decision.artReady) return "art_due";
  if (!decision.printReady || !decision.stickerDecided || !decision.metalIdDecided) return "decision_due";

  return "ready";
}

function cardSearchText(card) {
  const decision = cardDecision(card);
  const purchases = purchasesFor(card.group.cb_id);
  const colours = coloursFor(card.group.cb_id);

  return [
    card.group.cb_no,
    childCodeForRow(card.division),
    decision.artNo,
    decision.styleName,
    decision.printNo,
    decision.frameNo,
    decision.stickerType,
    decision.metalIdDecision,

    ...purchases.map(
      row =>
        `${row.vendor_name || ""} ${row.vendor_bill_no || ""} ${row.fabric_name || ""}`
    ),

    ...colours.map(row => row.colour_name || "")
  ]
    .join(" ")
    .toLowerCase();
}

function filterMatches(card) {
  const state = cardState(card);

  if (currentFilter === "all") return true;
  if (currentFilter === "ready") return state === "ready";
  if (currentFilter === "released") return state === "released";
  if (currentFilter === "completed") return state === "completed";
  if (currentFilter === "art_due") return state === "art_due";
  if (currentFilter === "decision_due") return state === "decision_due";
  if (currentFilter === "planning") return state === "art_due" || state === "decision_due";
  if (currentFilter === "child") return true;
  if (currentFilter === "child_batches") return true;

  return true;
}

function injectStyles() {
  if ($("cmPmStyle")) return;

  const style = document.createElement("style");
  style.id = "cmPmStyle";

  style.textContent = `
    .chip-decision_due{background:#3b2c13;color:#ffe4a3}
    .cm-process-decision-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
    .cm-process-state{margin-top:8px;padding:10px 12px;border:1px solid #3c3c46;border-radius:12px;background:#101015;color:#cfcfd8;font-size:12px;font-weight:800}
    .cm-process-state.is-ok{border-color:#277849;background:#11291b;color:#a7edbd}
    .cm-process-state.is-error{border-color:#a43d4a;background:#38171d;color:#ffc4cc}
    .cm-pm-images{display:flex;gap:8px;overflow-x:auto;margin:10px 0}
    .cm-pm-images figure{margin:0;min-width:88px;max-width:110px;border-radius:14px;overflow:hidden;background:#121218;border:1px solid #30303a}
    .cm-pm-images img{width:100%;height:96px;object-fit:cover;display:block}
    .cm-pm-images figcaption{font-size:10px;font-weight:900;padding:5px 6px;color:#fff;background:rgba(0,0,0,.55)}
    .cm-pm-photo-empty{height:100px;border:1px dashed #444;border-radius:14px;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#aaa;margin:10px 0}
    .cm-pm-photo-empty span{font-weight:900}
    .cm-pm-decision{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:10px 0}
    .cm-pm-decision span{background:#15151b;border:1px solid #2e2e38;border-radius:12px;padding:8px}
    .cm-pm-decision small{display:block;color:#999;font-size:10px;font-weight:800;margin-bottom:3px}
    .cm-pm-decision strong{font-size:13px;color:#fff}
    .cm-pm-debug{font-size:11px;color:#aaa;margin-top:10px;line-height:1.45}
    .cm-matrix-card{border:1px solid #30303a;background:#111116;border-radius:14px;padding:10px;margin:10px 0}
    .cm-matrix-head{display:flex;gap:8px;align-items:center;margin-bottom:8px}
    .cm-matrix-head img{width:34px;height:34px;object-fit:cover;border-radius:8px}
    .cm-size-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
    .cm-size-grid label{display:block}
    .cm-size-grid span{font-size:11px;color:#aaa;font-weight:800}
    .cm-size-grid input{width:100%}
    .cm-colour-cut-card{border:1px solid #35353f;background:#0d0d12;border-radius:14px;padding:11px;margin:10px 0}
    .cm-colour-cut-head{display:grid;grid-template-columns:minmax(0,1fr) minmax(145px,190px);gap:10px;align-items:end}
    .cm-colour-name{display:flex;align-items:center;gap:8px;min-width:0}.cm-colour-name img{width:38px;height:38px;object-fit:cover;border-radius:9px}.cm-colour-name strong{overflow:hidden;text-overflow:ellipsis}
    .cm-colour-total-label span{display:block;color:#f3c96a;font-size:11px;font-weight:900;margin-bottom:5px}.cm-colour-total-label input{width:100%}
    .cm-colour-balance{display:flex;justify-content:space-between;gap:8px;margin-top:9px;padding:8px 9px;border:1px solid #35353f;border-radius:10px;background:#14141a;font-size:11px;font-weight:850;color:#c8c8d0}
    .cm-colour-balance.is-ok{border-color:#277849;background:#11291b;color:#9be8b5}.cm-colour-balance.is-bad{border-color:#a43d4a;background:#38171d;color:#ffc4cc}
    .cm-dev-auto-total{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin-top:10px}.cm-dev-auto-total span{padding:9px;border:1px solid #363640;border-radius:10px;background:#101015}.cm-dev-auto-total small,.cm-dev-auto-total strong{display:block}.cm-dev-auto-total small{color:#999;font-size:10px}.cm-dev-auto-total strong{margin-top:4px}
    .cm-cutting-grand-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:9px;margin-top:14px;padding:13px;border:1px solid #5d4a2b;border-radius:15px;background:linear-gradient(145deg,#221d13,#111116)}
    .cm-cutting-grand-summary>div,.cm-cutting-grand-summary>label{min-width:0;padding:10px;border:1px solid #3b3a35;border-radius:11px;background:#0d0d11}.cm-cutting-grand-summary small,.cm-cutting-grand-summary label>span{display:block;color:#bcb6a6;font-size:10px;font-weight:850;margin-bottom:5px}.cm-cutting-grand-summary strong{display:block;font-size:16px}.cm-cutting-grand-summary input{width:100%}.cm-grand-main{border-color:#8e6b28!important;background:#2b2415!important}.cm-grand-main strong{font-size:23px;color:#ffe39a}.cm-piece-balance.is-ok{color:#8fe4ad}.cm-piece-balance.is-bad{color:#ff9ba7}
    .cm-newly-released{border:2px solid #f4c542!important;box-shadow:0 0 0 3px rgba(244,197,66,.18),0 16px 42px rgba(244,197,66,.18)!important;animation:cmLotPulse 1.2s ease-in-out 2}
    .cm-lot-number-highlight{background:#f4c542;color:#18140a!important;border-radius:9px;padding:4px 9px;font-size:1.08em;letter-spacing:.04em;box-shadow:0 0 0 2px rgba(244,197,66,.24)}
    .cm-lot-identity{margin:12px 0;padding:14px;border-radius:15px;text-align:center;border:2px solid #f4c542;background:linear-gradient(180deg,rgba(244,197,66,.18),rgba(244,197,66,.06))}
    .cm-lot-identity small{display:block;font-size:10px;font-weight:950;letter-spacing:.16em;color:#f4c542;margin-bottom:5px}
    .cm-lot-identity strong{display:block;font-size:22px;line-height:1.15;color:#fff;word-break:break-word}
    .cm-lot-identity span{display:block;margin-top:5px;font-size:11px;font-weight:850;color:#cfcfcf}
    .cm-lot-title-new{color:#f4c542}
    .cm-lot-release-summary{margin:12px 0;padding:14px;border-radius:15px;border:2px solid #f4c542;background:linear-gradient(180deg,rgba(244,197,66,.16),rgba(244,197,66,.05))}
    .cm-lot-release-summary small{display:block;font-size:10px;font-weight:950;letter-spacing:.12em;color:#f4c542;margin-bottom:5px}
    .cm-lot-release-summary strong{display:block;font-size:20px;color:#fff}
    .cm-lot-release-summary span{display:block;margin-top:5px;font-size:11px;font-weight:800;color:#cfcfcf}
    .cm-individual-lot-grid{display:grid;gap:12px;margin:12px 0}
    .cm-independent-lot-card{border:2px solid rgba(244,197,66,.7)!important;border-radius:15px!important}
    .cm-independent-lot-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}
    .cm-independent-lot-head small{display:block;font-size:10px;font-weight:950;letter-spacing:.1em;color:#f4c542}
    .cm-dev-code-badge{display:inline-flex;align-items:center;justify-content:center;min-width:50px;padding:7px 10px;border-radius:999px;background:#f4c542;color:#18140a;font-weight:950}
    .cm-independent-note{margin-top:10px;padding-top:10px;border-top:1px dashed #444;font-size:11px;color:#bdbdbd;line-height:1.45}
    @media(min-width:900px){.cm-individual-lot-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
    .cm-release-feedback{margin:12px 0;padding:12px 14px;border-radius:12px;border:1px solid #4a4a55;background:#17171d;color:#fff;font-weight:800;line-height:1.45;white-space:pre-wrap}
    .cm-release-feedback.is-info{border-color:#3b82f6;background:rgba(59,130,246,.13);color:#dbeafe}
    .cm-release-feedback.is-success{border-color:#22c55e;background:rgba(34,197,94,.13);color:#dcfce7}
    .cm-release-feedback.is-error{border-color:#ef4444;background:rgba(239,68,68,.14);color:#fee2e2}
    @keyframes cmLotPulse{0%,100%{transform:scale(1)}50%{transform:scale(1.012)}}
    @media(max-width:620px){
      .cm-pm-decision,.cm-process-decision-grid{grid-template-columns:1fr}
      .cm-size-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
      .cm-colour-cut-head,.cm-cutting-grand-summary{grid-template-columns:1fr}
    }
  `;

  document.head.appendChild(style);
}

function renderStats(cards) {
  const stats = $("cmStats");

  if (!stats) return;

  const ready = cards.filter(
    card => cardState(card) === "ready"
  ).length;

  const released = cards.filter(
    card => cardState(card) === "released"
  ).length;

  const completed = cards.filter(
    card => cardState(card) === "completed"
  ).length;

  const artDue = cards.filter(card => cardState(card) === "art_due").length;
  const decisionDue = cards.filter(card => cardState(card) === "decision_due").length;

  stats.innerHTML = `
    <article>
      <small>PM Cards</small>
      <strong>${cards.length}</strong>
    </article>

    <article>
      <small>Ready</small>
      <strong>${ready}</strong>
    </article>

    <article>
      <small>Released</small>
      <strong>${released}</strong>
    </article>

    <article>
      <small>Decision Due</small>
      <strong>${artDue + decisionDue}</strong>
    </article>

    <article>
      <small>Completed</small>
      <strong>${completed}</strong>
    </article>
  `;
}

let comboDevRows = [];
let currentLotMode = "single";
let matrixQtyMemory = new Map();
let matrixColourTotalMemory = new Map();

const SIZE_COMBO_OPTIONS = [
  "M",
  "L",
  "XL",
  "2XL",
  "M.L.XL",
  "L.XL.XXL",
  "M.L.XL.XXL",
  "2XL.3XL.4XL",
  "3XL.4XL.5XL"
];

const DEFAULT_SIZE_COMBO = "L.XL.XXL";

const SMALL_SIZE_COMBOS = new Set([
  "M",
  "L",
  "XL",
  "M.L.XL"
]);

const BIG_SIZE_COMBOS = new Set([
  "2XL",
  "2XL.3XL.4XL",
  "3XL.4XL.5XL"
]);

function lotStatusLabel(lot) {
  const status = String(lot?.status || "released")
    .trim()
    .toLowerCase();

  if (status === "completed") {
    return "Completed";
  }

  return "Released · UPM Ready";
}

function renderGallery() {
  if (!gallery) return;

  const query = String($("cmSearch")?.value || "")
    .trim()
    .toLowerCase();

  const allCards = divisionCards();

  const cards = allCards.filter(card => {
    return (
      filterMatches(card) &&
      cardSearchText(card).includes(query)
    );
  });

  gallery.setAttribute("aria-busy", "false");
  renderStats(allCards);

  if (!cards.length) {
    gallery.innerHTML = `
      <article class="cm-empty">
        <h3>No Product Master cutting card found</h3>
        <p>
          PM cards: ${allCards.length}<br>
          Gallery rows: ${galleryRows.length}<br>
          Assignments: ${assignmentRows.length}<br>
          Lots: ${lotRows.length}
        </p>
      </article>
    `;
    return;
  }

  gallery.innerHTML = cards
    .map(card => {
      const decision = cardDecision(card);
      const state = cardState(card);
      const lots = lotsForDivision(card.division.division_id);
      const lot = lots[0] || null;
      const colours = coloursFor(card.group.cb_id);
      const purchases = purchasesFor(card.group.cb_id);
      const items = carouselItemsForAssignment(
        decision.art,
        decision.prints
      );
      const isNewLot = Boolean(
        lots.length &&
        lastReleasedDivisionId &&
        String(card.division.division_id) ===
          String(lastReleasedDivisionId)
      );

      const lotNos = lots
        .map(row => row.lot_no)
        .filter(Boolean);

      const totalPcs = lots.reduce(
        (sum, row) => sum + Number(row.planned_pcs || row.cutting_pcs || 0),
        0
      );

      const totalCost = lots.reduce(
        (sum, row) => sum + effectiveLotTotalCost(row),
        0
      );

      const finalPerPiece = totalPcs > 0
        ? totalCost / totalPcs
        : Number(lot?.final_cost_per_piece || 0);

      const childCode = childCodeForRow(card.division);

      return `
        <article
          class="cm-card ${isNewLot ? "cm-newly-released" : ""}"
          data-division-id="${safe(card.division.division_id)}"
          ${lotNos.length ? `data-lot-no="${safe(lotNos.join(","))}"` : ""}
        >
          <span class="cm-chip chip-${safe(state)}">
            ${safe(state)}
          </span>

          <h3>${safe(card.group.cb_no || "CB")}</h3>
          <p>${safe(childCode)}</p>

          ${imageStripHtml(items, colours)}

          <div class="cm-pm-decision">
            <span>
              <small>D No.</small>
              <strong>${safe(childCode)}</strong>
            </span>
            <span>
              <small>Art No</small>
              <strong>${safe(decision.artNo || "ART DUE")}</strong>
            </span>
            <span>
              <small>Print No</small>
              <strong>${safe(
                decision.noPrintRequired
                  ? "N/A — No Print Required"
                  : decision.printNo || "PRINT DUE"
              )}</strong>
            </span>
            <span>
              <small>Frame No</small>
              <strong>${safe(decision.noPrintRequired ? "N/A" : (decision.frameNo || "FRAME REQUIRED"))}</strong>
            </span>
            <span>
              <small>Sticker</small>
              <strong>${safe(decision.stickerType || "DECISION DUE")}</strong>
            </span>
            <span>
              <small>Metal ID</small>
              <strong>${safe(decision.metalIdDecision || "DECISION DUE")}</strong>
            </span>
            <span>
              <small>Style</small>
              <strong>${safe(decision.styleName || "—")}</strong>
            </span>
            <span>
              <small>Colours</small>
              <strong>${colours.length || 0}</strong>
            </span>
          </div>

          <div class="cm-metrics">
            <span>
              <small>Weight</small>
              <strong>${Number(card.division.allocated_qty || 0).toFixed(3)} kg</strong>
            </span>
            <span>
              <small>Purchase</small>
              <strong>${purchases.length}</strong>
            </span>
            <span class="${isNewLot ? "cm-lot-metric-new" : ""}">
              <small>Lot</small>
              <strong class="cm-lot-number ${isNewLot ? "cm-lot-number-highlight" : ""}">
                ${lotNos.length ? `${lots.length} Individual Lot${lots.length > 1 ? "s" : ""}` : "Due"}
              </strong>
            </span>
          </div>

          ${
            lots.length
              ? `
                <div class="cm-lot-release-summary ${isNewLot ? "is-new" : ""}">
                  <small>${lots.length > 1 ? "MULTI RELEASED · INDIVIDUAL PRODUCTION LOTS" : "RELEASED LOT NO · PRIMARY IDENTITY"}</small>
                  <strong>${lots.length} Lot${lots.length > 1 ? "s" : ""} · ${totalPcs} pcs</strong>
                  <span>हर Lot No अलग जगह और अलग समय पर independently process हो सकता है.</span>
                </div>

                <div class="cm-individual-lot-grid">
                  ${lots.map((individualLot, lotIndex) => {
                    const individualLotNo = String(individualLot.lot_no || "")
                      .trim()
                      .toUpperCase();

                    const individualPcs = Number(
                      individualLot.planned_pcs ||
                      individualLot.cutting_pcs ||
                      0
                    );

                    const individualTotalCost = effectiveLotTotalCost(individualLot);

                    const individualFinalPerPiece = individualPcs > 0
                      ? individualTotalCost / individualPcs
                      : Number(individualLot.final_cost_per_piece || 0);

                    const individualDevCode = canonicalDevelopmentCode(
                      individualLot.variant_code ||
                      individualLot.dev_code ||
                      individualLot.development_code ||
                      individualLot.child_code ||
                      (lots.length > 1
                        ? subDevelopmentCode(childCode, lotIndex)
                        : childCode)
                    );

                    const individualMatching = matchingPostingForLot(
                      individualLot.lot_no
                    );

                    return `
                      <article
                        class="cm-lot-box cm-independent-lot-card ${isNewLot ? "is-new" : ""}"
                        data-production-lot-id="${safe(individualLot.id || individualLot.production_lot_id || "")}"
                        data-lot-no="${safe(individualLotNo)}"
                        data-dev-code="${safe(individualDevCode)}"
                      >
                        <div class="cm-independent-lot-head">
                          <div>
                            <small>INDIVIDUAL RELEASED LOT</small>
                            <h4 class="${isNewLot ? "cm-lot-title-new" : ""}">
                              <span class="cm-lot-number ${isNewLot ? "cm-lot-number-highlight" : ""}">
                                ${safe(individualLotNo)}
                              </span>
                            </h4>
                          </div>
                          <span class="cm-dev-code-badge">${safe(individualDevCode)}</span>
                        </div>

                        <p>${safe(individualLot.style_name || decision.styleName || "")}</p>
                        <p>
                          <strong>${individualPcs} pcs</strong> ·
                          ${safe(lotStatusLabel(individualLot))}
                        </p>

                        ${individualMatching
                          ? `<p><strong>Matching:</strong> ${safe(individualMatching.fabric_name || "Matching Cloth")} · ${Number(individualMatching.qty || 0).toFixed(3)} kg</p>`
                          : ""
                        }

                        <div class="cm-lot-cost">
                          <span>
                            Actual Cutting Rate:
                            <strong>${money(Number(individualLot.base_cost || individualLot.process_cost_per_piece || 0))} / pc</strong>
                          </span>

                          ${cuttingCanViewFinancials() ? `
                            <span>
                              Final / Pc:
                              <strong>${money(individualFinalPerPiece)}</strong>
                            </span>
                            <span>
                              Total:
                              <strong>${money(individualTotalCost)}</strong>
                            </span>
                          ` : ""}
                        </div>

                        <div class="cm-independent-note">
                          Printing, Sticker, Metal ID, KR, OV, Folding, Kaj/Btn, Teak/Tanki, Thread Cut, QC, Press, Packing और Despatch तक यह Lot अपने fixed UPM order में अलग चलेगा।
                        </div>
                      </article>
                    `;
                  }).join("")}
                </div>
              `
              : `
                <div class="cm-lot-box">
                  <h4>Permanent Lot No Due</h4>
                  <p>
                    पहले Single या Multi Lot चुनें, फिर Manual Lot No भरें.
                  </p>
                </div>
              `
          }

          <div class="cm-actions cm-actions-two">
            <button
              class="cm-primary"
              type="button"
              data-single="${safe(card.division.division_id)}"
              data-lot-mode="single"
              ${!decision.printReady || lots.length ? "disabled" : ""}
            >
              Single Lot
            </button>

            <button
              class="cm-secondary"
              type="button"
              data-multi="${safe(card.division.division_id)}"
              data-lot-mode="multi"
              ${!decision.printReady || lots.length ? "disabled" : ""}
            >
              Multi Lot
            </button>
          </div>
        </article>
      `;
    })
    .join("");

  say(
    `${allCards.length} Product Master cutting cards loaded.`,
    "success"
  );
}

function sizesFromText(text) {
  const raw = Array.isArray(text)
    ? text.join(",")
    : String(text || "");

  return [
    ...new Set(
      raw
        .split(/[,.+]+/)
        .map(item => item.trim().toUpperCase())
        .filter(Boolean)
    )
  ];
}

function sizesForCard(card) {
  const decision = cardDecision(card);

  const sources = [
    card.assignment?.size_set,
    card.assignment?.sizes,
    decision.art?.size_set,
    decision.art?.sizes,
    decision.art?.size_combo,
    decision.art?.size_range
  ];

  for (const source of sources) {
    const sizes = sizesFromText(source);

    if (sizes.length) return sizes;
  }

  return sizesFromText(DEFAULT_SIZE_COMBO);
}

function nextLotNumber() {
  const year = String(
    new Date().getFullYear()
  ).slice(-2);

  const nums = lotRows
    .map(row => {
      const match = String(row.lot_no || "").match(/(\d+)$/);

      return match
        ? Number(match[1])
        : 0;
    })
    .filter(Number.isFinite);

  const next = Math.max(0, ...nums) + 1;

  return `LOT-${year}-${String(next).padStart(4, "0")}`;
}

function openLotByDivision(divisionId, requestedMode = "single") {
  if (releaseLock) return;
  releaseLock = true;

  try {
    const card = divisionCards().find(
      item =>
        String(item.division.division_id) ===
        String(divisionId)
    );

    if (!card) {
      throw new Error("Product Master card not found.");
    }

    if (
      isMatchingOnlyCb(card.group.cb_id) ||
      rowExplicitlyMatchingOnly(card.division)
    ) {
      throw new Error(
        "Matching Cloth is Stock Only. It can only be mapped as a cost factor inside a Regular Cloth Cutting Lot."
      );
    }

    const decision = cardDecision(card);

    if (!decision.artReady) {
      throw new Error("Product Master में Art decide करें.");
    }
    if (!decision.printReady) {
      throw new Error("Print Bharna Zaroori — Print select करें या N.A. final करें.");
    }

    if (lotsForDivision(divisionId).length) {
      throw new Error("इस D card का Lot पहले ही release हो चुका है.");
    }

    activeCard = card;
    currentLotMode = requestedMode === "multi" ? "multi" : "single";
    matrixQtyMemory = new Map();
    matrixColourTotalMemory = new Map();

    if (typeof setActiveUnit === "function") {
      setActiveUnit(card.division);
    }

    const sizes = sizesForCard(card);
    const unitWeight = Number(card.division.allocated_qty || 0);

    setInputValue("lotUnitId", card.division.division_id);
    setInputValue("lotNo", "");
    setInputValue("lotDate", today());
    setInputValue("styleName", decision.styleName);
    setInputValue("artNo", decision.artNo);
    setInputValue("printNo", decision.noPrintRequired ? "N/A" : decision.printNo);
    setInputValue("frameNo", decision.noPrintRequired ? "N/A" : decision.frameNo);
    setInputValue("stickerDecision", decision.stickerNotApplicable ? "na" : normalizedStickerType(decision.selectedSticker?.work_type));
    setInputValue("metalIdDecision", decision.metalIdNotApplicable ? "na" : (decision.selectedMetalId ? "required" : ""));
    setInputValue("sizeSet", sizes.join(","));
    updateProcessDecisionPreview();
    setInputValue("lotNotes", "");
    setInputValue("operatorName", "");
    refreshCuttingWorkerControl();
    setInputValue("fabricUsed", unitWeight ? unitWeight.toFixed(3) : "");
    setInputValue("wastageWeight", "");
    setInputValue("remnantWeight", "");
    setInputValue("baseCost", Number(costSettings.default_base_cost || 0) > 0 ? String(costSettings.default_base_cost) : "");

    if ($("lotContext")) {
      $("lotContext").textContent =
        `${card.group.cb_no} · ${childCodeForRow(card.division)}`;
    }

    ["artNo", "printNo"].forEach(id => {
      const input = $(id);
      if (input) input.readOnly = true;
    });

    openSheet(lotSheet);

    ensureComboUi();
    refreshMatchingStockControls();
    setLotReleaseFeedback();
    hideLegacyOwnerCosting();
    setComboDefaults();
    setLotMode(currentLotMode);
    buildComboDevRows({
      keepManual: false,
      autoDistribute: true,
      resetMatrix: true
    });
    renderCuttingMatrix();
    updateWeightSettlement();
    updateCostPreview();

    window.setTimeout(() => {
      const target = currentLotMode === "multi"
        ? $("cmDevRows")?.querySelector(".cm-dev-lot-no")
        : $("cmManualLotNo");
      target?.focus();
    }, 50);
  } catch (error) {
    console.error("Opening Cutting Lot sheet failed:", error);
    activeCard = null;
    say(errorText(error), "error");
  } finally {
    releaseLock = false;
  }
}

function hideBundleUi() {
  const legacySizeSet = $("sizeSet");
  if (legacySizeSet) {
    const label = legacySizeSet.closest("label");
    if (label) label.style.display = "none";
  }

  const parentTotal = $("cmParentCuttingPcs");
  if (parentTotal) {
    const label = parentTotal.closest("label");
    if (label) label.style.display = "none";
  }

  const equalDevButton = $("cmEqualDevPcs");
  if (equalDevButton) equalDevButton.style.display = "none";

  const totalPieces = $("totalPieces");
  if (totalPieces) {
    const totalLine = totalPieces.closest(".cm-total-line");
    if (totalLine) totalLine.style.display = "";
  }

  const bundle = $("bundleQty");
  if (bundle) {
    bundle.value = "";
    const label = bundle.closest("label");
    if (label) label.style.display = "none";
  }

  const totalBundles = $("totalBundles");
  if (totalBundles) {
    totalBundles.textContent = "";
    const holder = totalBundles.closest("span") || totalBundles.parentElement;
    if (holder) holder.style.display = "none";
  }

  document
    .querySelectorAll("[data-bundle], .bundle, .bundle-count, .bundle-qty")
    .forEach(el => { el.style.display = "none"; });
}

function ensureComboUi() {
  const existingPanel = $("cmComboPanel");
  if (existingPanel) {
    hideBundleUi();
    refreshMatchingStockControls();
    return;
  }

  const form = $("lotForm");
  if (!form) return;

  const firstCard = form.querySelector(".cm-form-card");
  const lotNoInput = $("lotNo");
  const lotNoLabel = lotNoInput?.closest("label");
  if (lotNoLabel) lotNoLabel.style.display = "none";

  const panel = document.createElement("section");
  panel.id = "cmComboPanel";
  panel.className = "cm-form-card cm-decision-panel";
  panel.innerHTML = `
    <div class="cm-matrix-head">
      <h3>Cutting Lot</h3>
      <strong id="cmSelectedMode">Single Lot</strong>
    </div>

    <section id="cmSinglePanel">
      <div class="cm-primary-input-row">
        <label>
          <span>Manual Lot No *</span>
          <input id="cmManualLotNo" type="text" autocomplete="off" placeholder="2N2526">
        </label>
      </div>

      <div class="cm-grid-3">
        <label><span>Size Combo</span><select id="cmSingleSizeCombo"></select></label>
        <label><span>Sleeve</span><select id="cmSingleSleeve"><option value="Half">Half Sleeve</option><option value="Full">Full Sleeve</option></select></label>
        <label><span>Border</span><select id="cmSingleBorder"><option value="Without Border">Without Border</option><option value="With Border">With Border</option></select></label>
      </div>

      <div class="cm-grid-3">
        <label><span>Matching Cloth Stock (Optional)</span><select id="cmSingleMatchingItem">${matchingStockOptions()}</select></label>
        <label><span>Matching Cloth Qty (kg)</span><input id="cmSingleMatchingQty" type="number" min="0" step="0.001" disabled></label>
        ${cuttingCanViewFinancials() ? `<label><span>Matching Cloth Avg Cost</span><input id="cmSingleMatchingAvgCost" type="number" min="0" step="0.0001" readonly></label>` : ""}
      </div>
      <p id="cmSingleMatchingStockInfo" class="cm-rule-note">No Matching Cloth selected · Qty 0 · Avg Cost 0 · Release allowed.</p>
    </section>

    <section id="cmMultiPanel" class="cm-hidden">
      <div class="cm-primary-input-row">
        <label>
          <span>Sub-Dev Count</span>
          <select id="cmDevCount"><option value="2">2 Sub-Dev</option><option value="3">3 Sub-Dev</option><option value="4">4 Sub-Dev</option></select>
        </label>
      </div>
      <div class="cm-actions cm-actions-one">
        <button id="cmBuildDevRows" type="button" class="cm-secondary">Build Sub-Dev Cards</button>
      </div>
      <div id="cmDevRows"></div>
    </section>
  `;

  if (firstCard) firstCard.insertAdjacentElement("beforebegin", panel);
  else form.prepend(panel);

  fillSizeComboOptions("cmSingleSizeCombo");
  refreshMatchingStockControls();

  $("cmManualLotNo")?.addEventListener("input", event => {
    setInputValue("lotNo", String(event.target.value || "").trim().toUpperCase());
  });

  ["cmSingleSizeCombo", "cmSingleSleeve", "cmSingleBorder"].forEach(id => {
    $(id)?.addEventListener("change", () => {
      if (id === "cmSingleSizeCombo") clearMatrixMemoryForDev(activeChildCode());
      buildComboDevRows({ keepManual: true, autoDistribute: false, resetMatrix: false });
      renderCuttingMatrix();
      updateCostPreview();
    });
  });

  $("cmSingleMatchingItem")?.addEventListener("change", event => {
    setSingleMatchingState(event.target.value);
    buildComboDevRows({ keepManual: true, autoDistribute: false, resetMatrix: false });
    updateCostPreview();
  });

  $("cmSingleMatchingQty")?.addEventListener("input", () => {
    buildComboDevRows({ keepManual: true, autoDistribute: false, resetMatrix: false });
    updateCostPreview();
  });

  $("cmDevCount")?.addEventListener("change", () => {
    matrixQtyMemory = new Map();
    matrixColourTotalMemory = new Map();
    buildComboDevRows({ keepManual: true, autoDistribute: false, resetMatrix: true });
    renderCuttingMatrix();
    updateCostPreview();
  });

  $("cmBuildDevRows")?.addEventListener("click", () => {
    matrixQtyMemory = new Map();
    matrixColourTotalMemory = new Map();
    buildComboDevRows({ keepManual: true, autoDistribute: false, resetMatrix: true });
    renderCuttingMatrix();
    updateCostPreview();
  });

  hideBundleUi();
}

function hideLegacyOwnerCosting() {
  const card = document.querySelector("#lotForm .cm-cost-card");
  if (card) card.style.display = "none";
}

function setLotMode(mode) {
  currentLotMode = mode === "multi" ? "multi" : "single";

  if ($("cmSelectedMode")) {
    $("cmSelectedMode").textContent =
      currentLotMode === "multi"
        ? `Multi Lot · ${activeChildCode()}A…`
        : `Single Lot · ${activeChildCode()}`;
  }

  $("cmSinglePanel")?.classList.toggle(
    "cm-hidden",
    currentLotMode !== "single"
  );

  $("cmMultiPanel")?.classList.toggle(
    "cm-hidden",
    currentLotMode !== "multi"
  );

  matrixQtyMemory = new Map();
  matrixColourTotalMemory = new Map();

  buildComboDevRows({
    keepManual: false,
    autoDistribute: true,
    resetMatrix: true
  });

  renderCuttingMatrix();
  updatePieceTotals();
  updateCostPreview();
  hideBundleUi();
}

function fillSizeComboOptions(id) {
  const select = $(id);

  if (!select) return;

  select.innerHTML = SIZE_COMBO_OPTIONS
    .map(option => `
      <option value="${safe(option)}">
        ${safe(option)}
      </option>
    `)
    .join("");
}

function fillSizeComboSelect(select, value) {
  if (!select) return;

  select.innerHTML = SIZE_COMBO_OPTIONS
    .map(option => `
      <option
        value="${safe(option)}"
        ${option === value ? "selected" : ""}
      >
        ${safe(option)}
      </option>
    `)
    .join("");
}

function setComboDefaults() {
  const singleSize = $("cmSingleSizeCombo");
  if (singleSize) singleSize.value = DEFAULT_SIZE_COMBO;
  if ($("cmSingleSleeve")) $("cmSingleSleeve").value = "Half";
  if ($("cmSingleBorder")) $("cmSingleBorder").value = "Without Border";

  setInputValue("cmManualLotNo", "");
  setInputValue("lotNo", "");
  setInputValue("cmSingleMatchingItem", "");
  setInputValue("cmSingleMatchingQty", "");
  setInputValue("cmSingleMatchingAvgCost", "");
  refreshMatchingStockControls();

  if ($("cmDevCount")) $("cmDevCount").value = "2";

  comboDevRows = [];
  matrixQtyMemory = new Map();
  matrixColourTotalMemory = new Map();
  hideBundleUi();
}

function readArtAverageCost() {
  const decision = activeCard ? cardDecision(activeCard) : {};
  const art = decision.art || {};
  const assignment = activeCard?.assignment || {};

  return Number(
    art.avg_cost ??
    art.average_cost ??
    art.calculated_avg_cost ??
    art.cost_avg ??
    art.base_cost ??
    art.final_cost ??
    art.cost ??
    art.rate ??
    assignment.avg_cost ??
    assignment.average_cost ??
    assignment.base_cost ??
    assignment.cost ??
    0
  );
}

function devCount() {
  return Math.min(
    4,
    Math.max(
      2,
      Math.floor(Number(selectValue("cmDevCount") || 2))
    )
  );
}

function defaultDevSizeCombo(index) {
  const defaults = [
    "L.XL.XXL",
    "2XL.3XL.4XL",
    "M.L.XL",
    "M.L.XL.XXL"
  ];

  return defaults[index] || DEFAULT_SIZE_COMBO;
}

function singleRowFromInputs(old = {}) {
  const sizeCombo = selectValue("cmSingleSizeCombo") || DEFAULT_SIZE_COMBO;
  const snapshot = matchingSnapshot(selectValue("cmSingleMatchingItem"));

  return {
    ...old,
    lot_mode: "single",
    dev_no: activeChildCode(),
    lot_no: readText("cmManualLotNo"),
    size_combo: sizeCombo,
    sizes: sizesFromText(sizeCombo),
    sleeve: selectValue("cmSingleSleeve") || "Half",
    border: selectValue("cmSingleBorder") || "Without Border",
    cutting_pcs: plannedTotalForDev(activeChildCode()),
    matching_item_id: snapshot.itemId || null,
    matching_consumption: snapshot.itemId ? numberValue("cmSingleMatchingQty") : 0,
    matching_avg_cost: snapshot.itemId ? snapshot.avgCost : 0,
    custom_adjustment: 0
  };
}

function buildComboDevRows(options = {}) {
  const existing = new Map(
    comboDevRows.map(row => [
      row.dev_no,
      row
    ])
  );

  if (currentLotMode === "single") {
    const devNo = activeChildCode();
    comboDevRows = [
      singleRowFromInputs(
        options.keepManual
          ? existing.get(devNo) || comboDevRows[0] || {}
          : {}
      )
    ];

    hideBundleUi();
    return;
  }

  const count = devCount();
  const rows = [];
  const parentChild = activeChildCode();

  for (let index = 0; index < count; index += 1) {
    const devNo = subDevelopmentCode(parentChild, index);

    const old = options.keepManual
      ? existing.get(devNo) || {}
      : {};

    const sizeCombo =
      old.size_combo ||
      defaultDevSizeCombo(index);

    const stock = matchingSnapshot(old.matching_item_id);

    rows.push({
      ...old,
      lot_mode: "multi",
      parent_child_code: parentChild,
      dev_no: devNo,
      lot_no: old.lot_no || "",
      size_combo: sizeCombo,
      sizes: sizesFromText(sizeCombo),
      sleeve: old.sleeve || "Half",
      border: old.border || "Without Border",
      cutting_pcs: Number(old.cutting_pcs || 0),
      matching_item_id: stock.itemId || null,
      matching_consumption: stock.itemId
        ? Number(old.matching_consumption || 0)
        : 0,
      matching_avg_cost: stock.itemId
        ? stock.avgCost
        : 0,
      custom_adjustment: 0
    });
  }

  comboDevRows = rows;

  if (options.autoDistribute) distributeDevPcs();

  renderDevRows();
  hideBundleUi();
}

function renderDevRows() {
  const holder = $("cmDevRows");
  if (!holder) return;

  if (currentLotMode !== "multi") {
    holder.innerHTML = "";
    hideBundleUi();
    return;
  }

  if (!comboDevRows.length) {
    holder.innerHTML = `<div class="cm-empty"><p>No Sub-Dev cards. Select Sub-Dev Count.</p></div>`;
    hideBundleUi();
    return;
  }

  holder.innerHTML = comboDevRows.map((row, index) => {
    const hasMatching = Boolean(row.matching_item_id);
    const stock = matchingSnapshot(row.matching_item_id);
    const autoPcs = plannedTotalForDev(row.dev_no);
    row.cutting_pcs = autoPcs;

    return `
      <article class="cm-matrix-card" data-dev-card="${index}">
        <div class="cm-matrix-head"><strong>${safe(row.dev_no)}</strong><span>${safe(row.size_combo)} · ${safe(row.sleeve)} · ${safe(row.border)}</span></div>

        <div class="cm-primary-input-row">
          <label><span>${safe(row.dev_no)} Manual Lot No *</span><input class="cm-dev-lot-no" type="text" autocomplete="off" value="${safe(row.lot_no || "")}" placeholder="${safe(row.dev_no)} Lot No" data-dev-index="${index}"></label>
        </div>

        <div class="cm-grid-3">
          <label><span>Size Combo</span><select class="cm-dev-size" data-dev-index="${index}"></select></label>
          <label><span>Sleeve</span><select class="cm-dev-sleeve" data-dev-index="${index}"><option value="Half">Half Sleeve</option><option value="Full">Full Sleeve</option></select></label>
          <label><span>Border</span><select class="cm-dev-border" data-dev-index="${index}"><option value="Without Border">Without Border</option><option value="With Border">With Border</option></select></label>
        </div>

        <div class="cm-grid-3">
          <label><span>Matching Cloth Stock (Optional)</span><select class="cm-dev-match-item" data-dev-index="${index}">${matchingStockOptions(row.matching_item_id)}</select></label>
          <label><span>Matching Cloth Qty (kg)</span><input class="cm-dev-match-cons" type="number" min="0" step="0.001" value="${hasMatching && Number(row.matching_consumption || 0) ? Number(row.matching_consumption) : ""}" data-dev-index="${index}" ${hasMatching ? "" : "disabled"}></label>
          ${cuttingCanViewFinancials() ? `<label><span>Matching Cloth Avg Cost</span><input class="cm-dev-match-cost" type="number" min="0" step="0.0001" readonly value="${hasMatching && Number(stock.avgCost || 0) ? Number(stock.avgCost) : ""}" data-dev-index="${index}"></label>` : ""}
        </div>

        <p class="cm-rule-note">${hasMatching ? (cuttingCanViewFinancials() ? `Available ${stock.availableQty.toFixed(3)} kg · Current Avg ${money(stock.avgCost)}/kg` : `Available ${stock.availableQty.toFixed(3)} kg`) : (matchingRowsForActiveCard().length ? "No Matching Cloth · Qty 0 · Release allowed." : "Stock नहीं मिला · Product Master में + MC New से stock डालें.")}</p>

        ${cuttingCanViewFinancials() ? `<div class="cm-grid-2">
          <label><span>Sub-Dev Cost Preview</span><input class="cm-dev-cost-preview" type="text" readonly value="${safe(devCostText(row))}"></label>
        </div>` : ""}

        <div class="cm-dev-auto-total">
          <span><small>${safe(row.dev_no)} Auto Cutting Pcs</small><strong data-dev-planned-total="${safe(row.dev_no)}">${autoPcs}</strong></span>
          <span><small>Size Matrix Pcs</small><strong data-dev-actual-total="${safe(row.dev_no)}">${actualTotalForDev(row.dev_no)}</strong></span>
        </div>
      </article>`;
  }).join("");

  holder.querySelectorAll(".cm-dev-size").forEach(select => {
    const index = Number(select.dataset.devIndex);
    fillSizeComboSelect(select, comboDevRows[index]?.size_combo || DEFAULT_SIZE_COMBO);
    select.addEventListener("change", () => updateDevRowFromInput(select, { resetMatrix: true }));
  });
  holder.querySelectorAll(".cm-dev-sleeve").forEach(select => {
    const index = Number(select.dataset.devIndex);
    select.value = comboDevRows[index]?.sleeve || "Half";
    select.addEventListener("change", () => updateDevRowFromInput(select));
  });
  holder.querySelectorAll(".cm-dev-border").forEach(select => {
    const index = Number(select.dataset.devIndex);
    select.value = comboDevRows[index]?.border || "Without Border";
    select.addEventListener("change", () => updateDevRowFromInput(select));
  });
  holder.querySelectorAll(".cm-dev-match-item").forEach(select => {
    const index = Number(select.dataset.devIndex);
    select.value = comboDevRows[index]?.matching_item_id || "";
    select.addEventListener("change", () => updateDevRowFromInput(select, { rerenderDev: true }));
  });
  holder.querySelectorAll("[data-dev-index]").forEach(input => {
    if (input.classList.contains("cm-dev-size") || input.classList.contains("cm-dev-sleeve") || input.classList.contains("cm-dev-border") || input.classList.contains("cm-dev-match-item")) return;
    input.addEventListener("input", () => updateDevRowFromInput(input));
  });

  updatePieceTotals();
  hideBundleUi();
}

function updateDevRowFromInput(input, options = {}) {
  const index = Number(input.dataset.devIndex);
  const row = comboDevRows[index];
  if (!row) return;

  if (input.classList.contains("cm-dev-lot-no")) {
    row.lot_no = String(input.value || "").trim().toUpperCase();
    input.value = row.lot_no;
  }
  if (input.classList.contains("cm-dev-size")) {
    row.size_combo = input.value || DEFAULT_SIZE_COMBO;
    row.sizes = sizesFromText(row.size_combo);
  }
  if (input.classList.contains("cm-dev-sleeve")) row.sleeve = input.value || "Half";
  if (input.classList.contains("cm-dev-border")) row.border = input.value || "Without Border";
  if (input.classList.contains("cm-dev-match-item")) {
    const snapshot = matchingSnapshot(input.value);
    row.matching_item_id = snapshot.itemId || null;
    row.matching_avg_cost = snapshot.itemId ? snapshot.avgCost : 0;
    if (!snapshot.itemId) row.matching_consumption = 0;
  }
  if (input.classList.contains("cm-dev-match-cons")) row.matching_consumption = row.matching_item_id ? Number(input.value || 0) : 0;
  if (input.classList.contains("cm-dev-match-cost")) row.matching_avg_cost = row.matching_item_id ? Number(input.value || 0) : 0;
  if (input.classList.contains("cm-dev-custom")) row.custom_adjustment = Number(input.value || 0);

  if (options.rerenderDev) {
    renderDevRows();
  } else if (options.resetMatrix) {
    clearMatrixMemoryForDev(row.dev_no);
    renderDevRows();
    renderCuttingMatrix();
  } else {
    const card = input.closest("[data-dev-card]");
    const preview = card?.querySelector(".cm-dev-cost-preview");
    if (preview) preview.value = devCostText(row);
  }

  updatePieceTotals();
  updateCostPreview();
  hideBundleUi();
}

function distributeDevPcs() {
  if (currentLotMode !== "multi") return;

  const total = Math.max(
    0,
    Math.floor(numberValue("cmParentCuttingPcs"))
  );

  if (!comboDevRows.length || total <= 0) return;

  const base = Math.floor(total / comboDevRows.length);
  const remainder = total - base * comboDevRows.length;

  comboDevRows.forEach((row, index) => {
    row.cutting_pcs =
      base +
      (index === comboDevRows.length - 1 ? remainder : 0);
  });
}

function clearMatrixMemoryForDev(devNo) {
  [...matrixQtyMemory.keys()].forEach(key => {
    if (key.startsWith(`${devNo}|`)) matrixQtyMemory.delete(key);
  });
}

function sizeFactorForCombo(row) {
  if (row.lot_mode !== "multi") return 0;

  const combo = String(row.size_combo || "").toUpperCase();

  if (SMALL_SIZE_COMBOS.has(combo)) return -5;
  if (BIG_SIZE_COMBOS.has(combo)) return 5;
  return 0;
}

function sleeveFactorFor(row) {
  return row.sleeve === "Full"
    ? Number(costSettings.full_sleeve_adjustment || 0)
    : 0;
}

function borderFactorFor(row) {
  return row.border === "With Border"
    ? Number(costSettings.border_adjustment || 0)
    : 0;
}

function regularMaterialTotalForActiveCard() {
  return Number(
    activeCard?.division?.allocated_amount ??
    activeCard?.division?.base_amount ??
    0
  );
}

function totalPiecesForCosting() {
  if (!comboDevRows.length) return 0;

  return comboDevRows.reduce((sum, row, index) => {
    return sum + Math.max(0, Number(devMatrixQuantity(row, index) || 0));
  }, 0);
}

function regularMaterialCostSnapshot(totalPieces = null) {
  const total = regularMaterialTotalForActiveCard();
  const pcs = totalPieces === null
    ? totalPiecesForCosting()
    : Number(totalPieces || 0);

  return {
    total,
    pcs,
    perPiece: pcs > 0 ? total / pcs : 0
  };
}

function matchingCostFor(row) {
  if (!row.matching_item_id) return 0;

  return Number(row.matching_consumption || 0) *
    Number(row.matching_avg_cost || 0);
}

function devMatrixQuantity(row, index) {
  const inputs = matrixInputs().filter(input => {
    return (
      String(input.dataset.devIndex) === String(index) ||
      String(input.dataset.devNo) === String(row.dev_no)
    );
  });

  const qty = inputs.reduce((sum, input) => {
    return sum + Math.max(
      0,
      Math.floor(Number(input.value || 0))
    );
  }, 0);

  return qty || Number(row.cutting_pcs || 0);
}

function devCost(row, pcsOverride = null) {
  const base = Number(
    numberValue("baseCost") ||
    costSettings.default_base_cost ||
    0
  );

  const pcs = pcsOverride === null
    ? Number(row.cutting_pcs || 0)
    : Number(pcsOverride || 0);

  // Actual Cutting Rate is the final approved process rate for this Lot.
  // Size/sleeve/border remain production attributes; they do not silently
  // change the operator-entered actual rate.
  const processPerPiece = base;

  const regularMaterial = regularMaterialCostSnapshot();
  const regularMaterialPerPiece = regularMaterial.perPiece;
  const regularMaterialTotal = regularMaterialPerPiece * pcs;
  const matchingTotal = matchingCostFor(row);
  const matchingPerPiece = pcs > 0 ? matchingTotal / pcs : 0;
  const finalPerPiece =
    regularMaterialPerPiece +
    processPerPiece +
    matchingPerPiece;

  return {
    base,
    processPerPiece,
    perPiece: processPerPiece,
    regularMaterialPerPiece,
    regularMaterialTotal,
    matchingTotal,
    matchingPerPiece,
    finalPerPiece,
    total:
      regularMaterialTotal +
      processPerPiece * pcs +
      matchingTotal
  };
}

function devCostText(row) {
  const cost = devCost(row);
  return `${money(cost.finalPerPiece)} / pc · ${money(cost.total)}`;
}

function matrixInputs() {
  return [...($("cuttingMatrix")?.querySelectorAll(".cm-size-qty") || [])];
}

function matrixColourTotalInputs() {
  return [...($("cuttingMatrix")?.querySelectorAll(".cm-colour-total") || [])];
}

function cuttingEntries() {
  return matrixInputs().map(input => ({
    colour_id: input.dataset.colourId || input.dataset.colorId || null,
    colour_name: input.dataset.colourName || input.dataset.colorName || "",
    size_name: input.dataset.size || input.dataset.sizeName || "",
    quantity: Math.max(0, Math.floor(Number(input.value || 0))),
    dev_no: input.dataset.devNo || activeChildCode()
  })).filter(row => row.quantity > 0);
}

function parseSizes() {
  if (comboDevRows.length) return [...new Set(comboDevRows.flatMap(row => row.sizes))];
  return sizesFromText(DEFAULT_SIZE_COMBO);
}

function matrixColours() {
  if (!activeCard) return [];
  const list = coloursFor(activeCard.group.cb_id);
  if (list.length) return list;
  return [{ id: "", colour_name: "Default Colour", image_url: "", colour_order: 1 }];
}

function matrixKey(dev, colour, size) {
  return [dev.dev_no, colour.id || colour.colour_name || "", size].join("|");
}

function colourTotalKey(dev, colour) {
  return [dev.dev_no, colour.id || colour.colour_name || ""].join("|");
}

function plannedColourQty(dev, colour) {
  const key = colourTotalKey(dev, colour);
  return Math.max(0, Math.floor(Number(matrixColourTotalMemory.get(key) || 0)));
}

function splitColourQty(total, sizeCount, sizeIndex) {
  const count = Math.max(1, Number(sizeCount || 1));
  const qty = Math.max(0, Math.floor(Number(total || 0)));
  const base = Math.floor(qty / count);
  const remainder = qty - base * count;
  return base + (sizeIndex < remainder ? 1 : 0);
}

function autoQtyForCell(dev, colour, sizeIndex) {
  return splitColourQty(plannedColourQty(dev, colour), dev.sizes.length, sizeIndex);
}

function distributeColourQty(dev, colour, total) {
  const planned = Math.max(0, Math.floor(Number(total || 0)));
  matrixColourTotalMemory.set(colourTotalKey(dev, colour), planned);
  dev.sizes.forEach((size, sizeIndex) => {
    matrixQtyMemory.set(matrixKey(dev, colour, size), splitColourQty(planned, dev.sizes.length, sizeIndex));
  });
}

function plannedTotalForDev(devNo) {
  let total = 0;
  matrixColourTotalMemory.forEach((qty, key) => {
    if (String(key).startsWith(`${devNo}|`)) total += Math.max(0, Math.floor(Number(qty || 0)));
  });
  return total;
}

function actualTotalForDev(devNo) {
  return matrixInputs().filter(input => String(input.dataset.devNo) === String(devNo)).reduce((sum, input) => sum + Math.max(0, Math.floor(Number(input.value || 0))), 0);
}

function colourPlanRows() {
  return matrixColourTotalInputs().map(input => {
    const key = input.dataset.colourTotalKey || "";
    const planned = Math.max(0, Math.floor(Number(input.value || 0)));
    const actual = matrixInputs().filter(sizeInput => sizeInput.dataset.colourTotalKey === key).reduce((sum, sizeInput) => sum + Math.max(0, Math.floor(Number(sizeInput.value || 0))), 0);
    return {
      key,
      dev_no: input.dataset.devNo || activeChildCode(),
      colour_id: input.dataset.colourId || null,
      colour_name: input.dataset.colourName || "Colour",
      planned,
      actual
    };
  });
}

function renderMatrixBalanceState() {
  const plans = colourPlanRows();
  plans.forEach(plan => {
    const node = $("cuttingMatrix")?.querySelector(`[data-colour-balance-key="${CSS.escape(plan.key)}"]`);
    if (!node) return;
    const difference = plan.actual - plan.planned;
    node.classList.toggle("is-ok", difference === 0 && plan.planned > 0);
    node.classList.toggle("is-bad", difference !== 0);
    node.innerHTML = `<span>Size Total: ${plan.actual}</span><span>${difference === 0 ? "Balance: 0" : `Balance: ${difference > 0 ? "+" : ""}${difference}`}</span>`;
  });

  comboDevRows.forEach(row => {
    row.cutting_pcs = plannedTotalForDev(row.dev_no);
    document.querySelectorAll(`[data-dev-planned-total="${CSS.escape(row.dev_no)}"]`).forEach(node => { node.textContent = String(row.cutting_pcs); });
    document.querySelectorAll(`[data-dev-actual-total="${CSS.escape(row.dev_no)}"]`).forEach(node => { node.textContent = String(actualTotalForDev(row.dev_no)); });
  });
}

function renderCuttingMatrix() {
  const holder = $("cuttingMatrix");
  if (!holder || !activeCard) return;

  const colours = matrixColours();
  if (!comboDevRows.length) buildComboDevRows({ keepManual: true, autoDistribute: false });

  holder.innerHTML = comboDevRows.map((dev, devIndex) => `
    <article class="cm-matrix-card">
      <div class="cm-matrix-head"><strong>${safe(dev.dev_no)}</strong><span>${safe(dev.size_combo)} · ${safe(dev.sleeve)} · ${safe(dev.border)}</span></div>
      ${colours.map(colour => {
        const colourName = colour.colour_name || colour.color_name || "Colour";
        const totalKey = colourTotalKey(dev, colour);
        const planned = plannedColourQty(dev, colour);
        return `
          <div class="cm-colour-cut-card">
            <div class="cm-colour-cut-head">
              <div class="cm-colour-name">${colour.image_url ? `<img src="${safe(colour.image_url)}" alt="${safe(colourName)}">` : `<strong>●</strong>`}<strong>${safe(colourName)}</strong></div>
              <label class="cm-colour-total-label"><span>Colour Cutting Qty *</span><input class="cm-colour-total" type="number" min="0" step="1" placeholder="Pcs" value="${planned || ""}" data-dev-index="${devIndex}" data-dev-no="${safe(dev.dev_no)}" data-colour-id="${safe(colour.id || "")}" data-colour-name="${safe(colourName)}" data-colour-total-key="${safe(totalKey)}"></label>
            </div>
            <div class="cm-size-grid">
              ${dev.sizes.map((size, sizeIndex) => {
                const key = matrixKey(dev, colour, size);
                const qty = matrixQtyMemory.has(key) ? matrixQtyMemory.get(key) : autoQtyForCell(dev, colour, sizeIndex);
                return `<label><span>${safe(size)}</span><input class="cm-size-qty" type="number" min="0" step="1" placeholder="Pcs" value="${qty || ""}" data-dev-index="${devIndex}" data-dev-no="${safe(dev.dev_no)}" data-size-combo="${safe(dev.size_combo)}" data-sleeve="${safe(dev.sleeve)}" data-border="${safe(dev.border)}" data-colour-id="${safe(colour.id || "")}" data-colour-name="${safe(colourName)}" data-size="${safe(size)}" data-matrix-key="${safe(key)}" data-colour-total-key="${safe(totalKey)}"></label>`;
              }).join("")}
            </div>
            <div class="cm-colour-balance" data-colour-balance-key="${safe(totalKey)}"><span>Size Total: 0</span><span>Balance: 0</span></div>
          </div>`;
      }).join("")}
      <div class="cm-dev-auto-total"><span><small>${safe(dev.dev_no)} Auto Cutting Pcs</small><strong data-dev-planned-total="${safe(dev.dev_no)}">${plannedTotalForDev(dev.dev_no)}</strong></span><span><small>Size Matrix Pcs</small><strong data-dev-actual-total="${safe(dev.dev_no)}">${actualTotalForDev(dev.dev_no)}</strong></span></div>
    </article>`).join("");

  matrixColourTotalInputs().forEach(input => {
    input.addEventListener("input", () => {
      const dev = comboDevRows[Number(input.dataset.devIndex)];
      const colour = colours.find(row => String(row.id || "") === String(input.dataset.colourId || "")) || { id: input.dataset.colourId || "", colour_name: input.dataset.colourName || "Colour" };
      const total = Math.max(0, Math.floor(Number(input.value || 0)));
      distributeColourQty(dev, colour, total);
      matrixInputs().filter(sizeInput => sizeInput.dataset.colourTotalKey === input.dataset.colourTotalKey).forEach(sizeInput => {
        sizeInput.value = matrixQtyMemory.get(sizeInput.dataset.matrixKey) || "";
      });
      updatePieceTotals();
    });
  });

  matrixInputs().forEach(input => {
    input.addEventListener("input", () => {
      matrixQtyMemory.set(input.dataset.matrixKey, Math.max(0, Math.floor(Number(input.value || 0))));
      updatePieceTotals();
    });
  });

  updatePieceTotals();
  hideBundleUi();
}

function updatePieceTotals() {
  const plans = colourPlanRows();
  const plannedPieces = plans.reduce((sum, row) => sum + row.planned, 0);
  const actualPieces = plans.reduce((sum, row) => sum + row.actual, 0);
  const balance = actualPieces - plannedPieces;

  comboDevRows.forEach(row => { row.cutting_pcs = plannedTotalForDev(row.dev_no); });

  if ($("totalPieces")) $("totalPieces").textContent = String(plannedPieces);
  if ($("cmMatrixPieces")) $("cmMatrixPieces").textContent = String(actualPieces);
  if ($("cmPieceBalance")) {
    $("cmPieceBalance").textContent = balance === 0 ? "0" : `${balance > 0 ? "+" : ""}${balance}`;
    $("cmPieceBalance").classList.toggle("is-ok", balance === 0 && plannedPieces > 0);
    $("cmPieceBalance").classList.toggle("is-bad", balance !== 0);
  }
  if ($("cmTotalColours")) $("cmTotalColours").textContent = String(plans.filter(row => row.planned > 0).length);

  renderMatrixBalanceState();
  hideBundleUi();
  updateCostPreview();
}

function updateWeightSettlement() {
  const unitWeight = Number(
    activeCard?.division?.allocated_qty || 0
  );

  const fabricUsed = numberValue("fabricUsed");
  const wastage = numberValue("wastageWeight");
  const remnant = numberValue("remnantWeight");

  const settled = fabricUsed + wastage + remnant;
  const difference = unitWeight - settled;

  if ($("lotUnitWeight")) {
    $("lotUnitWeight").textContent =
      `${unitWeight.toFixed(3)} kg`;
  }

  if ($("settledWeight")) {
    $("settledWeight").textContent =
      `${settled.toFixed(3)} kg`;
  }

  if ($("weightDifference")) {
    $("weightDifference").textContent =
      `${difference.toFixed(3)} kg`;
  }
}

function selectedAdjustments() {
  return [];
}

function costResult() {
  if (comboDevRows.length) {
    let total = 0;
    let pcs = 0;

    comboDevRows.forEach((row, index) => {
      const rowPcs = devMatrixQuantity(row, index);
      const rowCost = devCost(row, rowPcs);

      pcs += rowPcs;
      total += rowCost.total;
    });

    const final = pcs > 0 ? total / pcs : 0;

    return {
      base: Number(
        numberValue("baseCost") ||
        costSettings.default_base_cost ||
        0
      ),
      adjustments: [],
      adjustmentTotal: 0,
      final,
      pcs,
      total
    };
  }

  return {
    base: 0,
    adjustments: [],
    adjustmentTotal: 0,
    final: 0,
    pcs: 0,
    total: 0
  };
}

function setMoneyText(id, value) {
  const el = $(id);
  if (el) el.textContent = money(value);
}

function updateCostPreview() {
  const result = costResult();
  const actualRate = Number(numberValue("baseCost") || costSettings.default_base_cost || 0);
  const actualCuttingAmount = actualRate * Number(result.pcs || 0);

  setMoneyText("sizeCostPreview", 0);
  setMoneyText("sleeveCostPreview", 0);
  setMoneyText("borderCostPreview", 0);
  setMoneyText("finalCostPreview", result.final);
  setMoneyText("totalCostPreview", result.total);
  setMoneyText("cmActualCuttingAmount", actualCuttingAmount);

  setMoneyText("costBasePreview", result.base);
  setMoneyText("costAdjustmentPreview", result.adjustmentTotal);
  setMoneyText("costPerPiecePreview", result.final);
  setMoneyText("costTotalPreview", result.total);

  hideBundleUi();
}

function normalizedSleeve(value) {
  return String(value || "Half").toLowerCase().startsWith("full")
    ? "full"
    : "half";
      }

  function normalizedBorder(value) {
  return String(value || "Without Border").toLowerCase().startsWith("with ") ||
    String(value || "").toLowerCase() === "with"
    ? "with"
    : "without";
}

function sizeTypeForCombo(combo) {
  return BIG_SIZE_COMBOS.has(String(combo || "").toUpperCase())
    ? "big"
    : "small";
}

function normalizeCuttingWorker(row = {}) {
  return {
    ...row,
    worker_id: row.worker_id || row.id || row.profile_id || "",
    worker_code: String(row.worker_code || row.code || row.employee_code || "").trim(),
    worker_name: String(row.worker_name || row.full_name || row.display_name || row.name || "").trim(),
    department_code: String(row.department_code || row.department || row.dept_code || "").trim().toUpperCase(),
    is_active: row.is_active !== false && String(row.access_status || "ACTIVE").toUpperCase() !== "INACTIVE"
  };
}

function activeCuttingWorkers() {
  return (cuttingWorkerRows || [])
    .map(normalizeCuttingWorker)
    .filter(row => row.is_active && row.department_code === "CUTTING" && row.worker_name)
    .sort((a, b) => a.worker_name.localeCompare(b.worker_name));
}

function cuttingWorkerOptionValue(worker = {}) {
  const name = String(worker.worker_name || "").trim();
  const code = String(worker.worker_code || "").trim();
  return code ? `${name} · ${code}` : name;
}

function selectedCuttingWorker() {
  const raw = String($("operatorName")?.value || "").trim();
  if (!raw) return null;
  return activeCuttingWorkers().find(worker =>
    cuttingWorkerOptionValue(worker).toLowerCase() === raw.toLowerCase()
  ) || null;
}

function selectedCuttingWorkerName() {
  return selectedCuttingWorker()?.worker_name || "";
}

function refreshCuttingWorkerControl() {
  const input = $("operatorName");
  const list = $("cuttingMasterOptions");
  if (!input || !list) return;

  const workers = activeCuttingWorkers();
  list.innerHTML = workers.map(worker =>
    `<option value="${safe(cuttingWorkerOptionValue(worker))}">${safe(worker.worker_code || "CUTTING")}</option>`
  ).join("");

  input.placeholder = workers.length
    ? "Search active Cutting worker"
    : "No active CUTTING worker mapped";
}

function requireCuttingWorker() {
  const worker = selectedCuttingWorker();
  if (!worker) {
    throw new Error("Cutting Master: active CUTTING worker select karna zaroori hai.");
  }
  return worker;
}

function notesForRelease(valid, extra = []) {
  const cbNo = activeCard?.group?.cb_no || "";
  const childNo = activeCard ? activeChildCode() : "";

  return [
    readText("lotNotes"),
    selectedCuttingWorkerName() ? `Operator: ${selectedCuttingWorkerName()}` : "",
    cbNo ? `CB: ${cbNo}` : "",
    childNo ? `D No.: ${childNo}` : "",
    `Lot Mode: ${valid.lotMode}`,
    `Sticker Decision: ${valid.decision?.stickerType || ""}`,
    `Metal ID Decision: ${valid.decision?.metalIdDecision || ""}`,
    ...extra
  ].filter(Boolean).join("\n");
}

function updateProcessDecisionPreview() {
  const sticker = String($("stickerDecision")?.value || "").toLowerCase();
  const metal = String($("metalIdDecision")?.value || "").toLowerCase();
  const box = $("releaseDecisionState");
  if (!box) return;
  const stickerOk = ["hd","dtf","vinyl","na"].includes(sticker);
  const metalOk = ["required","na"].includes(metal);
  box.textContent = stickerOk && metalOk
    ? `Sticker ${sticker === "na" ? "N.A." : sticker.toUpperCase()} · Metal ID ${metal === "na" ? "N.A." : "Required"} · Decision Ready`
    : !stickerOk
      ? "Sticker Bharna Zaroori"
      : "Metal ID Bharna Zaroori";
  box.className = `cm-process-state ${stickerOk && metalOk ? "is-ok" : "is-error"}`;
}

async function ensureStickerInstruction(client, artId, type) {
  const normalized = normalizedStickerType(type);
  let row = stickerInstructionRows.find(item =>
    String(item.art_id) === String(artId) &&
    normalizedStickerType(item.work_type) === normalized &&
    item.is_active !== false
  );
  if (row) return row;
  const result = await client.from("rr_art_sticker_instructions").insert({
    art_id: artId,
    sequence_no: 1,
    work_type: normalized,
    work_name: normalized.toUpperCase(),
    hidden_rate: 0,
    is_active: true
  }).select("*").single();
  if (result.error) throw result.error;
  row = result.data;
  stickerInstructionRows.push(row);
  return row;
}

async function ensureMetalIdInstruction(client, artId) {
  let row = metalIdInstructionRows.find(item =>
    String(item.art_id) === String(artId) && item.is_active !== false
  );
  if (row) return row;
  const result = await client.from("rr_art_metal_id_instructions_v801").insert({
    art_id: artId,
    sequence_no: 1,
    work_name: "Metal ID",
    hidden_rate: 0,
    is_active: true
  }).select("*").single();
  if (result.error) throw result.error;
  row = result.data;
  metalIdInstructionRows.push(row);
  return row;
}

async function saveReleaseProcessDecisions(client) {
  if (!activeCard) throw new Error("No Product Master card selected.");
  const assignment = assignmentForDivision(activeCard.division.division_id);
  const art = assignment ? artById(assignment.art_id) : null;
  if (!assignment || !art) throw new Error("Art Bharna Zaroori");

  const sticker = String($("stickerDecision")?.value || "").trim().toLowerCase();
  const metal = String($("metalIdDecision")?.value || "").trim().toLowerCase();
  if (!["hd","dtf","vinyl","na"].includes(sticker)) throw new Error("Sticker Bharna Zaroori");
  if (!["required","na"].includes(metal)) throw new Error("Metal ID Bharna Zaroori");

  const updateResult = await client
    .from("rr_cb_art_assignments")
    .update({
      sticker_not_applicable: sticker === "na",
      metal_id_not_applicable: metal === "na",
      updated_at: new Date().toISOString()
    })
    .eq("id", assignment.id)
    .select("*")
    .single();
  if (updateResult.error) throw updateResult.error;
  Object.assign(assignment, updateResult.data || {});

  const stickerDelete = await client.from("rr_cb_sticker_assignments").delete().eq("assignment_id", assignment.id);
  if (stickerDelete.error) throw stickerDelete.error;
  stickerAssignmentRows = stickerAssignmentRows.filter(row => String(row.assignment_id) !== String(assignment.id));
  if (sticker !== "na") {
    const instruction = await ensureStickerInstruction(client, art.id, sticker);
    const add = await client.from("rr_cb_sticker_assignments").insert({
      assignment_id: assignment.id,
      sticker_instruction_id: instruction.id,
      sequence_no: 1
    }).select("*").single();
    if (add.error) throw add.error;
    stickerAssignmentRows.push(add.data);
  }

  const metalDelete = await client.from("rr_cb_metal_id_assignments_v801").delete().eq("assignment_id", assignment.id);
  if (metalDelete.error) throw metalDelete.error;
  metalIdAssignmentRows = metalIdAssignmentRows.filter(row => String(row.assignment_id) !== String(assignment.id));
  if (metal === "required") {
    const instruction = await ensureMetalIdInstruction(client, art.id);
    const add = await client.from("rr_cb_metal_id_assignments_v801").insert({
      assignment_id: assignment.id,
      metal_id_instruction_id: instruction.id,
      sequence_no: 1
    }).select("*").single();
    if (add.error) throw add.error;
    metalIdAssignmentRows.push(add.data);
  }

  activeCard.assignment = assignment;
  updateProcessDecisionPreview();
}

async function assertReleaseDecisionV801(client) {
  const cbUnitId = activeCard?.division?.division_id;
  if (!cbUnitId) throw new Error("CB Bharna Zaroori");
  const result = await client.rpc("rr_cutting_release_decision_check_v801", { p_cb_unit_id: cbUnitId });
  if (result.error) throw result.error;
  const row = result.data || {};
  if (row.release_ready !== true) throw new Error(row.short_status || "Release Decision Bharna Zaroori");
  return row;
}

function validateLot() {
  if (!activeCard) throw new Error("No Product Master card selected.");

  requireCuttingWorker();

  const decision = cardDecision(activeCard);
  if (!decision.artReady) throw new Error("Art Bharna Zaroori");
  if (!decision.printReady) throw new Error("Print Bharna Zaroori");
  if (!decision.stickerDecided) throw new Error("Sticker Bharna Zaroori");
  if (!decision.metalIdDecided) throw new Error("Metal ID Bharna Zaroori");

  const styleName = readText("styleName");
  if (!styleName) throw new Error("Style name required.");

  const actualCuttingRate = numberValue("baseCost");
  if (actualCuttingRate <= 0) throw new Error("Actual Cutting Rate / Pc required.");

  const lotMode = currentLotMode || "single";
  const plans = colourPlanRows();
  if (!plans.length || plans.every(row => row.planned <= 0)) throw new Error("कम से कम एक Colour Cutting Qty required है.");

  plans.forEach(row => {
    if (row.planned !== row.actual) {
      throw new Error(`${row.dev_no} · ${row.colour_name}: Colour Cutting Qty ${row.planned} है, लेकिन Size total ${row.actual} है.`);
    }
  });

  const allEntries = cuttingEntries();

  if (lotMode === "single") {
    const lotNo = String(readText("cmManualLotNo") || readText("lotNo")).trim().toUpperCase();
    if (!lotNo) throw new Error("Manual Lot No required.");

    const rawRow = comboDevRows[0] || singleRowFromInputs();
    const row = normalizeMatchingRow({ ...rawRow, dev_no: activeChildCode() }, activeChildCode());
    const entries = allEntries.map(entry => ({ ...entry, dev_no: row.dev_no, lot_no: lotNo }));
    const totalPieces = plans.filter(plan => String(plan.dev_no) === String(row.dev_no)).reduce((sum, plan) => sum + plan.planned, 0);
    if (totalPieces <= 0) throw new Error("Grand Total Cutting Pcs required.");

    return {
      decision, styleName, lotMode, totalPieces,
      lots: [{
        dev_no: row.dev_no,
        parent_child_code: activeChildCode(),
        lot_no: lotNo,
        size_combo: row.size_combo,
        sizes: row.sizes,
        sleeve: row.sleeve,
        border: row.border,
        cutting_pcs: totalPieces,
        matching_item_id: row.matching_item_id,
        matching_consumption: Number(row.matching_consumption || 0),
        matching_avg_cost: Number(row.matching_avg_cost || 0),
        custom_adjustment: 0,
        entries
      }]
    };
  }

  if (comboDevRows.length < 2 || comboDevRows.length > 4) throw new Error("Multi Lot में 2 से 4 Sub-Dev required हैं.");
  const lotNos = comboDevRows.map(row => String(row.lot_no || "").trim().toUpperCase());
  if (lotNos.some(value => !value)) throw new Error("हर Sub-Dev का Manual Lot No required है.");
  if (new Set(lotNos.map(value => value.toLowerCase())).size !== lotNos.length) throw new Error("Multi Lot में duplicate Lot No allowed नहीं है.");

  const lots = comboDevRows.map(rawRow => {
    const row = normalizeMatchingRow(rawRow, rawRow.dev_no);
    const entries = allEntries.filter(entry => String(entry.dev_no) === String(row.dev_no)).map(entry => ({ ...entry, lot_no: String(row.lot_no || "").trim().toUpperCase() }));
    const total = plans.filter(plan => String(plan.dev_no) === String(row.dev_no)).reduce((sum, plan) => sum + plan.planned, 0);
    if (total <= 0) throw new Error(`${row.dev_no} Colour Cutting Qty required.`);
    return { ...row, parent_child_code: activeChildCode(), lot_no: String(row.lot_no || "").trim().toUpperCase(), cutting_pcs: total, entries };
  });

  const matchingUse = new Map();
  lots.forEach(row => {
    if (!row.matching_item_id) return;
    const key = String(row.matching_item_id);
    matchingUse.set(key, Number(matchingUse.get(key) || 0) + Number(row.matching_consumption || 0));
  });
  matchingUse.forEach((requiredQty, itemId) => {
    const stock = matchingSnapshot(itemId);
    if (requiredQty > stock.availableQty + 0.0005) throw new Error(`${stock.fabricName || "Matching Cloth"}: available ${stock.availableQty.toFixed(3)} kg, required ${requiredQty.toFixed(3)} kg.`);
  });

  const totalPieces = lots.reduce((sum, row) => sum + row.cutting_pcs, 0);
  return { decision, styleName, lotMode, totalPieces, lots };
}

function singleRpcPayload(valid) {
  const lot = valid.lots[0];
  const cost = devCost(lot, lot.cutting_pcs);

  return {
    p_lot_no: lot.lot_no,
    p_cb_unit_id: activeCard.division.division_id,
    p_release_date: readText("lotDate") || today(),
    p_style_name: valid.styleName,
    p_art_no: valid.decision.artNo || null,
    p_print_no: valid.decision.noPrintRequired
      ? "N/A"
      : valid.decision.printNo || null,
    p_operator_name: selectedCuttingWorkerName() || null,
    p_size_set: lot.sizes,
    p_bundle_qty: 1,
    p_fabric_used: numberValue("fabricUsed"),
    p_wastage_weight: numberValue("wastageWeight"),
    p_remnant_weight: numberValue("remnantWeight"),
    p_base_cost: numberValue("baseCost") || costSettings.default_base_cost || 0,
    p_size_type: sizeTypeForCombo(lot.size_combo),
    p_sleeve_type: normalizedSleeve(lot.sleeve),
    p_border_type: normalizedBorder(lot.border),
    p_custom_adjustment: 0,
    p_notes: notesForRelease(valid, [
      `D No.: ${lot.dev_no}`,
      lot.matching_item_id
        ? `Matching Qty: ${lot.matching_consumption}`
        : "Matching Cloth: No",
      lot.matching_item_id
        ? `Matching Avg Cost: ${lot.matching_avg_cost}`
        : "Matching Avg Cost: 0",
      `Raw Material Total: ${cost.regularMaterialTotal}`,
      `Raw Material / Pc: ${cost.regularMaterialPerPiece}`,
      `Actual Cutting Rate / Pc: ${cost.base}`,
      `Actual Cutting Amount: ${cost.base * lot.cutting_pcs}`,
      `Process / Pc: ${cost.processPerPiece}`,
      `Final Product / Pc: ${cost.finalPerPiece}`
    ]) || null,
    p_breakup: lot.entries.map(row => ({
      cb_colour_id: row.colour_id,
      colour_name: row.colour_name,
      size_code: row.size_name,
      qty: row.quantity
    })),
    p_matching_item_id: lot.matching_item_id || null,
    p_matching_qty: lot.matching_item_id
      ? Number(lot.matching_consumption || 0)
      : 0
  };
}

function multiRpcPayload(valid) {
  return {
    p_cb_unit_id: activeCard.division.division_id,
    p_release_date: readText("lotDate") || today(),
    p_style_name: valid.styleName,
    p_art_no: valid.decision.artNo || null,
    p_print_no: valid.decision.noPrintRequired
      ? "N/A"
      : valid.decision.printNo || null,
    p_operator_name: selectedCuttingWorkerName() || null,
    p_fabric_used: numberValue("fabricUsed"),
    p_wastage_weight: numberValue("wastageWeight"),
    p_remnant_weight: numberValue("remnantWeight"),
    p_base_cost: numberValue("baseCost") || costSettings.default_base_cost || 0,
    p_notes: notesForRelease(valid, [
      `Parent D No.: ${activeChildCode()}`,
      `Actual Cutting Rate / Pc: ${numberValue("baseCost") || costSettings.default_base_cost || 0}`
    ]) || null,
    p_lots: valid.lots.map((row, index) => {
      const cost = devCost(row, row.cutting_pcs);

      return {
        variant_code: row.dev_no,
        variant_name: row.dev_no,
        sort_order: index + 1,
        lot_no: row.lot_no,
        size_combo: row.size_combo,
        sleeve_type: normalizedSleeve(row.sleeve),
        border_type: normalizedBorder(row.border),
        selected_sizes: row.sizes,
        cutting_pcs: row.cutting_pcs,
        matching_item_id: row.matching_item_id || null,
        matching_qty: row.matching_item_id
          ? Number(row.matching_consumption || 0)
          : 0,
        matching_avg_cost: row.matching_item_id
          ? Number(row.matching_avg_cost || 0)
          : 0,
        base_cost: cost.base,
        size_adjustment: 0,
        sleeve_adjustment: 0,
        border_adjustment: 0,
        custom_adjustment: 0,
        raw_material_total: cost.regularMaterialTotal,
        raw_material_cost_per_piece: cost.regularMaterialPerPiece,
        matching_total_cost: cost.matchingTotal,
        process_cost_per_piece: cost.processPerPiece,
        final_product_cost_per_piece: cost.finalPerPiece,
        final_product_cost: cost.total,
        final_cost_per_piece: cost.finalPerPiece,
        total_cutting_cost: cost.total,
        breakup: row.entries.map(entry => ({
          cb_colour_id: entry.colour_id,
          colour_name: entry.colour_name,
          size_code: entry.size_name,
          qty: entry.quantity
        }))
      };
    })
  };
}

async function reserveMatchingForLots(valid, client) {
  const reserved = [];
  for (const lot of valid.lots) {
    if (!lot.matching_item_id) continue;
    const result = await client.rpc("rr_reserve_lot_matching_v2", {
      p_fabric_id: lot.matching_item_id,
      p_lot_no: lot.lot_no,
      p_qty: Number(lot.matching_consumption || 0),
      p_source_kind: "CUTTING_MASTER",
      p_remarks: `${valid.lotMode || "single"} Lot reservation`
    });
    if (result.error) {
      if (isMissingRpcError(result.error)) {
        throw new Error("Matching Fabric V720.36 SQL patch required before Lot release.");
      }
      throw result.error;
    }
    const row = result.data || {};
    lot.matching_avg_cost = Number(row.avg_rate_snapshot || lot.matching_avg_cost || 0);
    reserved.push({ lotNo: lot.lot_no, data: row });
  }
  return reserved;
}

async function cancelMatchingReservations(client, reserved, reason) {
  await Promise.all((reserved || []).map(item =>
    client.rpc("rr_cancel_lot_matching_v2", {
      p_lot_no: item.lotNo,
      p_reason: reason || "Lot release failed"
    }).catch(() => null)
  ));
}

async function confirmMatchingReservations(client, reserved) {
  const warnings = [];
  for (const item of reserved || []) {
    const result = await client.rpc("rr_confirm_lot_matching_v2", {
      p_lot_no: item.lotNo,
      p_source_id: null
    });
    if (result.error) warnings.push(`${item.lotNo}: ${errorText(result.error)}`);
  }
  return warnings;
}

async function postCuttingActuals(valid, client) {
  const warnings = [];
  const actualRate = Number(numberValue("baseCost") || costSettings.default_base_cost || 0);

  for (const lot of valid.lots || []) {
    for (const entry of lot.entries || []) {
      const qty = Math.max(0, Math.floor(Number(entry.quantity || 0)));
      if (!qty) continue;

      const result = await client.rpc("rr_upsert_lot_process_actual_v1", {
        p_lot_no: lot.lot_no,
        p_process_code: "CUTTING",
        p_art_no: valid.decision?.artNo || null,
        p_print_no: valid.decision?.noPrintRequired ? "N/A" : (valid.decision?.printNo || null),
        p_colour_id: entry.colour_id || null,
        p_colour_name: entry.colour_name || null,
        p_size_code: entry.size_name || null,
        p_in_pcs: qty,
        p_out_pcs: qty,
        p_short_pcs: 0,
        p_reject_pcs: 0,
        p_actual_rate: actualRate,
        p_process_status: "COMPLETED",
        p_remarks: "Cutting Lot release"
      });

      if (result.error) {
        if (isMissingRpcError(result.error)) {
          return ["Production Actual Rate foundation SQL अभी install नहीं है."];
        }
        warnings.push(`${lot.lot_no} · ${entry.colour_name || "Colour"} · ${entry.size_name || "Size"}: ${errorText(result.error)}`);
      }
    }
  }

  return warnings;
}

async function createLot(event = {}) {
  event?.preventDefault?.();

  const client = getClient();
  if (!client) {
    say("Supabase client unavailable.", "error");
    return;
  }

  if (createLot.busy) return;
  createLot.busy = true;

  const button =
    event.submitter ||
    $("lotForm")?.querySelector('button[type="submit"]') ||
    $("lotForm")?.querySelector("button");

  const originalText = button?.textContent || "Release Lot No";
  let matchingReservations = [];
  let releaseCommitted = false;

  try {
    if (button) {
      button.disabled = true;
      button.textContent =
        currentLotMode === "multi"
          ? "Releasing Multi Lots..."
          : "Releasing Lot...";
    }

    await saveReleaseProcessDecisions(client);
    const valid = validateLot();
    await assertReleaseDecisionV801(client);
    matchingReservations = await reserveMatchingForLots(valid, client);
    const progressText = valid.lotMode === "multi"
      ? "Multi Lots save हो रहे हैं..."
      : "Cutting Lot save हो रहा है...";

    say(progressText, "info");
    setLotReleaseFeedback(progressText, "info");

    let result;

    if (valid.lotMode === "multi") {
      const payload = multiRpcPayload(valid);
      if (matchingReservations.length) {
        payload.p_lots.forEach(row => {
          const matchingCost = Number(row.matching_total_cost || 0);
          const pcs = Number(row.cutting_pcs || 0);
          row.matching_item_id = null;
          row.matching_qty = 0;
          row.matching_avg_cost = 0;
          row.matching_total_cost = 0;
          row.final_product_cost = Math.max(0, Number(row.final_product_cost || 0) - matchingCost);
          row.total_cutting_cost = Math.max(0, Number(row.total_cutting_cost || 0) - matchingCost);
          if (pcs > 0) {
            const matchingPerPiece = matchingCost / pcs;
            row.final_product_cost_per_piece = Math.max(0, Number(row.final_product_cost_per_piece || 0) - matchingPerPiece);
            row.final_cost_per_piece = Math.max(0, Number(row.final_cost_per_piece || 0) - matchingPerPiece);
          }
        });
      }
      result = await client.rpc("rr_release_multi_lots_v4", payload);

      const hasMatching = valid.lots.some(row => Boolean(row.matching_item_id));

      if (result.error && isMissingRpcError(result.error) && !hasMatching) {
        console.warn(
          "rr_release_multi_lots_v4 unavailable; using V3 only because no Matching Cloth is selected.",
          result.error
        );
        result = await client.rpc("rr_release_multi_lots_v3", payload);
      }
    } else {
      const payload = singleRpcPayload(valid);
      if (matchingReservations.length) {
        payload.p_matching_item_id = null;
        payload.p_matching_qty = 0;
      }
      result = await client.rpc(
        "rr_release_single_lot_v4",
        payload
      );
    }

    if (result.error) throw result.error;
    releaseCommitted = true;

    // V800 release triggers are authoritative. Frontend only verifies the
    // canonical registry result; it never runs a legacy manual sync RPC.
    const releasedNos = valid.lots.map(row => String(row.lot_no || "").trim().toUpperCase()).filter(Boolean);
    const { data: mapped, error: mapError } = await client
      .from("rr_upm_lot_registry")
      .select("lot_no,canonical_lot_id")
      .in("lot_no", releasedNos);
    if (mapError) throw mapError;
    const mappedNos = new Set((mapped || []).map(row => String(row.lot_no || "").trim().toUpperCase()));
    const missingRegistry = releasedNos.filter(lotNo => !mappedNos.has(lotNo));
    if (missingRegistry.length) {
      throw new Error(`Cutting release saved, but V800 canonical registry mapping missing: ${missingRegistry.join(", ")}.`);
    }

    const matchingWarnings = await confirmMatchingReservations(client, matchingReservations);
    const actualRateWarnings = await postCuttingActuals(valid, client);
    lastReleasedLotNo = releasedNos[0] || "";
    lastReleasedDivisionId = activeCard.division.division_id;

    closeSheet(lotSheet);
    activeCard = null;

    await loadAllData();

    window.setTimeout(() => {
      gallery
        ?.querySelector(".cm-newly-released")
        ?.scrollIntoView({ behavior: "smooth", block: "center" });
    }, 80);

    const releaseWarnings = [...matchingWarnings, ...actualRateWarnings];
    const nextStage = !valid.decision?.noPrintRequired
      ? "NEXT: PRINTING"
      : !valid.decision?.stickerNotApplicable
        ? "NEXT: STICKER"
        : !valid.decision?.metalIdNotApplicable
          ? "NEXT: METAL ID"
          : "NEXT: KR";
    const successText = releaseWarnings.length
      ? `LOT ${releasedNos.join(" · ")} RELEASED · ${nextStage} · Follow-up warning: ${releaseWarnings.join(" | ")}`
      : `LOT ${releasedNos.join(" · ")} RELEASED · Cutting completed · ${nextStage}.`;
    say(successText, releaseWarnings.length ? "info" : "success");
    setLotReleaseFeedback(successText, releaseWarnings.length ? "info" : "success");
  } catch (error) {
    if (!releaseCommitted && matchingReservations.length) {
      await cancelMatchingReservations(client, matchingReservations, "Lot release failed");
    }
    console.error("Lot release failed:", error);
    const messageText = releaseErrorText(error);
    say(messageText, "error");
    setLotReleaseFeedback(messageText, "error");

    if (lotSheet && !lotSheet.classList.contains("cm-hidden")) {
      const releaseButton = $("releaseLotBtn");
      releaseButton?.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  } finally {
    createLot.busy = false;

    if (button) {
      button.disabled = false;
      button.textContent = originalText;
    }
  }
}

function openCostSettingsSheet() {
  setInputValue(
    "settingBaseCost",
    costSettings.default_base_cost || 0
  );
  setInputValue(
    "settingBigAdjustment",
    costSettings.big_adjustment || 0
  );
  setInputValue(
    "settingFullAdjustment",
    costSettings.full_sleeve_adjustment || 0
  );
  setInputValue(
    "settingBorderAdjustment",
    costSettings.border_adjustment || 0
  );

  if ($("settingAllowCustom")) {
    $("settingAllowCustom").checked =
      costSettings.allow_custom_adjustment !== false;
  }

  openSheet(costSheet);
}

async function saveCostSettings(event) {
  event?.preventDefault?.();

  const client = getClient();
  if (!client) {
    say("Supabase client unavailable.", "error");
    return;
  }

  const button = $("saveCostSettings");
  const originalText = button?.textContent || "Save Cost Settings";

  try {
    if (button) {
      button.disabled = true;
      button.textContent = "Saving...";
    }

    const payload = {
      settings_key: "default",
      default_base_cost: numberValue("settingBaseCost"),
      big_adjustment: numberValue("settingBigAdjustment"),
      full_sleeve_adjustment: numberValue("settingFullAdjustment"),
      border_adjustment: numberValue("settingBorderAdjustment"),
      allow_custom_adjustment:
        $("settingAllowCustom")?.checked !== false,
      updated_at: new Date().toISOString()
    };

    const result = await client
      .from("rr_cutting_cost_settings_v3")
      .upsert(payload, { onConflict: "settings_key" })
      .select("*")
      .single();

    if (result.error) throw result.error;

    costSettings = {
      ...costSettings,
      ...(result.data || payload)
    };

    setInputValue("baseCost", Number(costSettings.default_base_cost || 0) > 0 ? costSettings.default_base_cost : "");
    updateCostPreview();
    closeSheet(costSheet);
    say("Cutting cost settings saved.", "success");
  } catch (error) {
    console.error("Saving cost settings failed:", error);
    say(errorText(error), "error");
  } finally {
    if (button) {
      button.disabled = false;
      button.textContent = originalText;
    }
  }
}

async function loadCostSettings(client) {
  const result = await client
    .from("rr_cutting_cost_settings_v3")
    .select("*")
    .eq("settings_key", "default")
    .maybeSingle();

  if (!result.error && result.data) {
    costSettings = {
      ...costSettings,
      ...result.data
    };
  }

  setInputValue(
    "baseCost",
    Number(costSettings.default_base_cost || 0) > 0 ? costSettings.default_base_cost : ""
  );

  if ($("customAdjustment")) {
    $("customAdjustment").disabled =
      costSettings.allow_custom_adjustment === false;
  }
}

async function loadMatchingStockSource(client) {
  // V720.36: stable fabric-name pool IDs are the primary Matching identity.
  const v2Result = await client.rpc("rr_get_matching_cloth_stock_v2");
  if (!v2Result.error) {
    // V2 is authoritative even when it returns zero rows.
    // Falling back on an empty V2 result would revive old purchase/card IDs
    // and can cause "Matching Cloth stock item not found" during release.
    return (v2Result.data || [])
      .map(normalizeMatchingStockRow)
      .filter(row => row.matching_item_id);
  } else {
    console.warn("Matching Fabric V2 stock RPC unavailable; trying legacy source.",v2Result.error);
  }

  const rpcResult = await client.rpc("rr_get_matching_cloth_stock_v1");

  if (!rpcResult.error) {
    const rows = (rpcResult.data || [])
      .map(normalizeMatchingStockRow)
      .filter(row => row.matching_item_id);

    if (rows.length) return rows;
  } else {
    console.warn(
      "Legacy matching stock RPC unavailable; trying V719 stock-card view.",
      rpcResult.error
    );
  }

  const viewResult = await client
    .from("rr_matching_stock_cards_v719")
    .select("*")
    .order("updated_at", { ascending: false });

  if (!viewResult.error) {
    const rows = (viewResult.data || [])
      .map(normalizeMatchingStockRow)
      .filter(row => row.matching_item_id);

    if (rows.length) return rows;
  } else {
    console.warn(
      "rr_matching_stock_cards_v719 unavailable; trying raw balance view.",
      viewResult.error
    );
  }

  const tableResult = await client
    .from("rr_matching_stock_balance")
    .select("*")
    .order("updated_at", { ascending: false });

  if (!tableResult.error) {
    return (tableResult.data || [])
      .map(normalizeMatchingStockRow)
      .filter(row => row.matching_item_id);
  }

  console.warn(
    "Matching stock source unavailable. Matching remains optional.",
    tableResult.error
  );

  return [];
}

async function loadMatchingLotSource(client) {
  const rpcResult = await client.rpc("rr_get_mc1_lot_matchings_v2");
  if (!rpcResult.error) return rpcResult.data || [];

  if (!isMissingRpcError(rpcResult.error)) {
    console.warn("Matching lot ledger RPC unavailable; trying legacy read view.", rpcResult.error);
  }

  return optionalRows(client, "rr_mc1_lot_matching_details_v2", {
    order: "created_at",
    ascending: false
  });
}

async function loadMultiLotSource(client) {
  const result = await client.rpc("rr_list_multi_lots_v3");

  if (result.error) {
    console.warn("Multi lots unavailable:", result.error);
    return [];
  }

  return (result.data || []).map(row => ({
    ...row,
    lot_mode: "multi",
    lot_source: "rr_production_lots"
  }));
}

async function loadAllData() {
  const client = getClient();

  if (!client) {
    throw new Error(
      "Supabase client unavailable. Check config.js."
    );
  }

  await loadCuttingRole(client);

  if (gallery) {
    gallery.setAttribute("aria-busy", "true");

    gallery.innerHTML = `
      <article class="cm-empty">
        <div class="cm-spinner"></div>

        <h3>Loading Cutting Master PM Core</h3>

        <p>
          Connecting Product Master cards...
        </p>
      </article>
    `;
  }

  say(
    "Product Master cutting cards load हो रहे हैं...",
    "info"
  );

  try {
    const recovery = await client.rpc("rr_recover_lot_matching_v2");
    if (recovery.error && !isMissingRpcError(recovery.error)) console.warn("Matching recovery warning",recovery.error);
  } catch (_) {}

  const [
    loadedGalleryRows,
    purchaseResult,
    matchingPurchaseResult,
    colourResult,
    artResult,
    loadedPrintRows,
    assignmentResult,
    printAssignmentResult,
    printFrameResult,
    stickerInstructionResult,
    stickerAssignmentResult,
    metalIdInstructionResult,
    metalIdAssignmentResult,
    cuttingWorkerResult,
    loadedMediaRows,
    lotResult,
    loadedMultiLotRows,
    breakupResult,
    matchingStockResult,
    matchingLotResult
  ] = await Promise.all([
    withTimeout(
      loadGallerySource(client),
      15000,
      "Product gallery"
    ),

    selectRows(client, "rr_cb_purchase_entries", {
      order: "created_at",
      ascending: false
    }),

    optionalRows(client, "rr_matching_purchase_entries", {
      order: "created_at",
      ascending: false
    }),

    selectRows(client, "rr_cb_colours", {
      order: "colour_order",
      ascending: true
    }),

    selectRows(client, "rr_art_master", {
      eq: { is_active: true },
      order: "updated_at",
      ascending: false
    }),

    loadPrintSource(client),

    selectRows(client, "rr_cb_art_assignments", {
      order: "updated_at",
      ascending: false
    }),

    selectRows(client, "rr_cb_print_assignments", {
      order: "sequence_no",
      ascending: true
    }),

    optionalRows(client, "rr_print_frames", { order: "updated_at", ascending: false }),
    optionalRows(client, "rr_art_sticker_instructions", { order: "sequence_no", ascending: true }),
    optionalRows(client, "rr_cb_sticker_assignments", { order: "sequence_no", ascending: true }),
    optionalRows(client, "rr_art_metal_id_instructions_v801", { order: "sequence_no", ascending: true }),
    optionalRows(client, "rr_cb_metal_id_assignments_v801", { order: "sequence_no", ascending: true }),
    optionalRows(client, "rr_user_profiles", { order: "created_at", ascending: false }),

    optionalRows(client, "rr_media"),

    selectRows(client, "rr_cutting_lots_v3", {
      order: "created_at",
      ascending: false
    }),

    loadMultiLotSource(client),

    selectRows(client, "rr_cutting_breakup_v3", {
      order: "created_at",
      ascending: false
    }),

    loadMatchingStockSource(client),

loadMatchingLotSource(client)
  ]);

  purchaseRows = requiredData(purchaseResult, "Purchase rows");
  matchingPurchaseRows = matchingPurchaseResult || [];
  galleryRows = productionGalleryRows(loadedGalleryRows || []);
  colourRows = requiredData(colourResult, "Colour rows");
  artRows = requiredData(artResult, "Art Master");
  printRows = loadedPrintRows || [];
  assignmentRows = requiredData(assignmentResult, "Art assignments");
  printAssignmentRows = requiredData(
    printAssignmentResult,
    "Print assignments"
  );
  printFrameRows = printFrameResult || [];
  stickerInstructionRows = stickerInstructionResult || [];
  stickerAssignmentRows = stickerAssignmentResult || [];
  metalIdInstructionRows = metalIdInstructionResult || [];
  metalIdAssignmentRows = metalIdAssignmentResult || [];
  cuttingWorkerRows = cuttingWorkerResult || [];
  mediaRows = loadedMediaRows || [];
  singleLotRows = requiredData(lotResult, "Cutting lots")
    .map(row => ({
      ...row,
      lot_mode: "single",
      lot_source: "rr_cutting_lots_v3"
    }));
  multiLotRows = loadedMultiLotRows || [];
  lotRows = [...singleLotRows, ...multiLotRows]
    .sort((a, b) =>
      String(b.created_at || "").localeCompare(String(a.created_at || ""))
    );
  breakupRows = requiredData(breakupResult, "Cutting breakup");
  matchingStockRows = (matchingStockResult || []).map(normalizeMatchingStockRow);
  matchingLotRows = matchingLotResult || [];

  await loadCostSettings(client);
  refreshMatchingStockControls();
  refreshCuttingWorkerControl();
  renderGallery();

  console.info("REAL FACTORY Cutting Master PM Core V801.1 loaded", {
    galleryRows: galleryRows.length,
    purchaseRows: purchaseRows.length,
    matchingPurchaseRows: matchingPurchaseRows.length,
    colourRows: colourRows.length,
    artRows: artRows.length,
    printRows: printRows.length,
    assignmentRows: assignmentRows.length,
    printAssignmentRows: printAssignmentRows.length,
    printFrameRows: printFrameRows.length,
    stickerAssignmentRows: stickerAssignmentRows.length,
    metalIdAssignmentRows: metalIdAssignmentRows.length,
    cuttingWorkerRows: activeCuttingWorkers().length,
    mediaRows: mediaRows.length,
    singleLotRows: singleLotRows.length,
    multiLotRows: multiLotRows.length,
    lotRows: lotRows.length,
    breakupRows: breakupRows.length,
    matchingStockRows: matchingStockRows.length,
    matchingLotRows: matchingLotRows.length
  });
}

async function refreshCuttingMaster() {
  try {
    await loadAllData();
  } catch (error) {
    showFatal(error);
  }
}

function bindEvents() {
  if (bindEvents.bound) return;
  bindEvents.bound = true;

  $("lotForm")?.addEventListener("submit", createLot);
  $("stickerDecision")?.addEventListener("change", updateProcessDecisionPreview);
  $("metalIdDecision")?.addEventListener("change", updateProcessDecisionPreview);

  gallery?.addEventListener("click", event => {
    const button = event.target?.closest?.(
      "[data-single], [data-multi], [data-release-lot]"
    );

    if (!button || !gallery.contains(button)) return;

    event.preventDefault();
    event.stopPropagation();

    const divisionId = String(
      button.dataset.single ||
      button.dataset.multi ||
      button.dataset.releaseLot ||
      button.dataset.divisionId ||
      ""
    ).trim();

    if (!divisionId) {
      say("D ID missing.", "error");
      return;
    }

    openLotByDivision(
      divisionId,
      button.dataset.lotMode ||
      (button.dataset.multi ? "multi" : "single")
    );
  });

  $("cmSearch")?.addEventListener("input", renderGallery);
  $("sizeSet")?.addEventListener("change", renderCuttingMatrix);
  $("sizeSet")?.addEventListener("blur", renderCuttingMatrix);

  [
    "fabricUsed",
    "wastageWeight",
    "remnantWeight"
  ].forEach(id => {
    $(id)?.addEventListener("input", updateWeightSettlement);
  });

  [
    "baseCost",
    "customAdjustment"
  ].forEach(id => {
    $(id)?.addEventListener("input", updateCostPreview);
  });

  [
    "sizeType",
    "sleeveType",
    "borderType"
  ].forEach(id => {
    $(id)?.addEventListener("change", updateCostPreview);
  });

  $("refreshCutting")?.addEventListener("click", refreshCuttingMaster);
  $("openCostSettings")?.addEventListener("click", openCostSettingsSheet);
  $("costSettingsForm")?.addEventListener("submit", saveCostSettings);

  $("cmFilters")
    ?.querySelectorAll("[data-filter]")
    .forEach(button => {
      button.addEventListener("click", () => {
        currentFilter = button.dataset.filter || "all";

        $("cmFilters")
          ?.querySelectorAll("[data-filter]")
          .forEach(item => {
            item.classList.toggle("is-active", item === button);
          });

        renderGallery();
      });
    });

  document
    .querySelectorAll("[data-close-lot]")
    .forEach(button => {
      button.addEventListener("click", () => {
        closeSheet(lotSheet);
        activeCard = null;
      });
    });

  document
    .querySelectorAll("[data-close-split]")
    .forEach(button => {
      button.addEventListener("click", () => {
        closeSheet(splitSheet);
      });
    });

  document
    .querySelectorAll("[data-close-cost]")
    .forEach(button => {
      button.addEventListener("click", () => {
        closeSheet(costSheet);
      });
    });

  $("splitForm")?.addEventListener("submit", event => {
    event.preventDefault();
    say(
      "Multi Lot इसी Cutting Lot sheet में उपलब्ध है.",
      "info"
    );
  });
}

async function start() {
  try {
    injectStyles();
    bindEvents();
    await loadAllData();
  } catch (error) {
    showFatal(error);
  }
}

window.RRCuttingMasterPM = {
  version: "pm-core-v720.36.2-mc-ledger-rate-foundation",

  state() {
    return {
      galleryRows,
      purchaseRows,
      colourRows,
      artRows,
      printRows,
      assignmentRows,
      printAssignmentRows,
      mediaRows,
      lotRows,
      singleLotRows,
      multiLotRows,
      matchingPurchaseRows,
      breakupRows,
      currentFilter,
      activeCard,
      currentLotMode,
      comboDevRows,
      lastReleasedLotNo,
      lastReleasedDivisionId
    };
  },

  refresh: refreshCuttingMaster,
  openLotByDivision,
  createLot,
  renderGallery
};

if (document.readyState === "loading") {
  document.addEventListener(
    "DOMContentLoaded",
    start,
    { once: true }
  );
} else {
  start();
}

})();

// ===== REAL FACTORY CUTTING MASTER PM CORE V801 END =====
      
            
