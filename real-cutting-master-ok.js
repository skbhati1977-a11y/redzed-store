// ===== REDZED CUTTING MASTER V33 PART 1 START =====
(() => {
"use strict";

/* REDZED REAL — Cutting Master Clean Core V33 */

const $ = id => document.getElementById(id);
const gallery = $("divisionGallery");
const message = $("cmMessage");
const splitSheet = $("splitSheet");
const lotSheet = $("lotSheet");
const costSheet = $("costSheet");

let purchases = [];
let units = [];
let colours = [];
let lots = [];
let breakup = [];
let currentFilter = "all";
let activeUnit = null;

let costSettings = {
  settings_key: "default",
  default_base_cost: 0,
  big_adjustment: 5,
  full_sleeve_adjustment: 5,
  border_adjustment: 5,
  allow_custom_adjustment: true
};

let productRefs = {
  assignments: [],
  printAssignments: [],
  arts: [],
  prints: [],
  media: []
};

let productRefsError = "";

function esc(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function safe(value) {
  return typeof RR !== "undefined" &&
    typeof RR.safeText === "function"
    ? RR.safeText(value ?? "")
    : esc(value);
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
  ].find(item =>
    item && typeof item.from === "function"
  ) || null;
}

function say(text = "", type = "") {
  if (!message) return;
  message.textContent = text;
  message.className = `rr-message ${type}`.trim();
}

function money(value) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2
  }).format(Number(value || 0));
}

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function withTimeout(promise, ms, label) {
  return Promise.race([
    Promise.resolve(promise),
    new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(`${label} timed out.`));
      }, ms);
    })
  ]);
}

function errorText(error) {
  return [
    error?.message,
    error?.details,
    error?.hint,
    error?.code ? `Code: ${error.code}` : ""
  ].filter(Boolean).join(" — ") || "Unknown error";
}

function showFatalError(error) {
  const text = errorText(error);

  if (gallery) {
    gallery.setAttribute("aria-busy", "false");
    gallery.innerHTML = `
      <article class="cm-empty">
        <h3>Cutting Master could not start</h3>
        <p>${safe(text)}</p>
        <p>Check config.js, Supabase connection and required Cutting Master tables.</p>
      </article>
    `;
  }

  say(text, "error");

  const refresh = $("refreshCutting");
  if (refresh) {
    refresh.disabled = false;
    refresh.textContent = "Retry";
  }
}

async function loadPrints(client) {
  const view = await client.from("rr_print_library_view").select("*");
  if (!view.error) return view.data || [];

  const table = await client.from("rr_print_master").select("*");
  if (table.error) throw table.error;
  return table.data || [];
}

async function loadProductRefs(client) {
  productRefsError = "";

  try {
    const [assignments, printAssignments, arts, prints, media] = await Promise.all([
      client.from("rr_cb_art_assignments").select("*"),
      client.from("rr_cb_print_assignments").select("*").order("sequence_no"),
      client.from("rr_art_master").select("*"),
      loadPrints(client),
      client.from("rr_media").select("*")
    ]);

    for (const result of [assignments, printAssignments, arts, media]) {
      if (result.error) throw result.error;
    }

    productRefs = {
      assignments: assignments.data || [],
      printAssignments: printAssignments.data || [],
      arts: arts.data || [],
      prints: prints || [],
      media: media.data || []
    };
  } catch (error) {
    productRefs = { assignments: [], printAssignments: [], arts: [], prints: [], media: [] };
    productRefsError = errorText(error);
    console.warn("Product Master references unavailable:", error);
  }
}

function artNumber(art) {
  return art?.art_no || art?.art_code || art?.code || art?.name || "";
}

function printNumber(print) {
  return print?.print_no || print?.print_code || print?.code || print?.name || "";
}

function artStyle(art) {
  return art?.style_name || art?.style || art?.product_style || art?.category_name || art?.category || "";
}

const unitId = row => row?.id || row?.division_id || row?.unit_id;
const unitPurchaseId = row => row?.purchase_id || row?.cb_id || row?.parent_cb_id;
const unitCode = row => row?.cb_code || row?.division_code || row?.unit_code || `S${row?.division_index || ""}`;
const unitWeight = row => Number(row?.divided_weight ?? row?.allocated_qty ?? row?.base_qty ?? row?.weight ?? 0);
const purchaseNo = row => row?.cb_no || row?.cb_code || row?.purchase_no || row?.purchase_code || "CB";

function purchaseFor(id) {
  return purchases.find(row => String(row.id) === String(id)) || null;
}

function coloursFor(id) {
  return colours
    .filter(row => String(row.cb_id) === String(id))
    .sort((a, b) => Number(a.colour_order || 0) - Number(b.colour_order || 0));
}

function lotForUnit(id) {
  return lots.find(row => String(row.cb_unit_id) === String(id)) || null;
}

function childrenFor(id) {
  return units
    .filter(row => String(row.parent_unit_id) === String(id))
    .sort((a, b) => Number(a.batch_index || a.division_index || 0) - Number(b.batch_index || b.division_index || 0));
}

function isFinal(row) {
  return row.is_final !== false;
}

function cardState(row) {
  const lot = lotForUnit(unitId(row));
  if (lot?.status === "completed") return "completed";
  if (lot) return "released";
  if (row.parent_unit_id) return "child";
  return "ready";
}

function parseSizes() {
  return [
    ...new Set(
      ($("sizeSet")?.value || "")
        .split(",")
        .map(value => value.trim().toUpperCase())
        .filter(Boolean)
    )
  ];
}

function setInputValue(id, value) {
  const input = $(id);
  if (!input) return;
  input.value = value ?? "";
}

function setSelectValue(select, value) {
  if (!select) return;
  const text = String(value ?? "");
  const existing = [...select.options].find(option =>
    String(option.value) === text ||
    String(option.textContent).trim().toLowerCase() === text.trim().toLowerCase()
  );
  if (existing) {
    select.value = existing.value;
    return;
  }
  if (text) {
    const option = document.createElement("option");
    option.value = text;
    option.textContent = text;
    option.selected = true;
    select.appendChild(option);
  }
}

function assignmentForUnit(id) {
  const direct = productRefs.assignments
    .filter(row => String(row.cb_id) === String(id))
    .sort((a, b) => String(b.updated_at || b.created_at || "").localeCompare(String(a.updated_at || a.created_at || "")))[0];

  if (direct) return { assignment: direct, inherited: false };

  const visited = new Set();
  let current = units.find(row => String(unitId(row)) === String(id)) || null;

  while (current?.parent_unit_id && !visited.has(String(current.parent_unit_id))) {
    visited.add(String(current.parent_unit_id));
    const parentId = current.parent_unit_id;
    const inherited = productRefs.assignments
      .filter(row => String(row.cb_id) === String(parentId))
      .sort((a, b) => String(b.updated_at || b.created_at || "").localeCompare(String(a.updated_at || a.created_at || "")))[0];
    if (inherited) return { assignment: inherited, inherited: true };
    current = units.find(row => String(unitId(row)) === String(parentId)) || null;
  }

  return { assignment: null, inherited: false };
}

function productDecision(id) {
  const source = assignmentForUnit(id);
  const assignment = source.assignment;

  if (!assignment) {
    return { assignment: null, art: null, prints: [], images: [], inherited: false, noPrintRequired: false, ready: false };
  }

  const art = productRefs.arts.find(row => String(row.id) === String(assignment.art_id)) || null;

  const printIds = productRefs.printAssignments
    .filter(row => String(row.assignment_id) === String(assignment.id))
    .sort((a, b) => Number(a.sequence_no || 0) - Number(b.sequence_no || 0))
    .map(row => String(row.print_id));

  const prints = printIds
    .map(id => productRefs.prints.find(row => String(row.id) === id))
    .filter(Boolean);

  const noPrintRequired =
    assignment.no_print_required === true ||
    assignment.print_required === false ||
    String(assignment.print_status || "").toLowerCase() === "not_required";

  const entityIds = new Set([art?.id, ...prints.map(row => row.id)].filter(Boolean).map(String));

  const directImages = [art, ...prints].flatMap(row => [
    row?.image_url,
    row?.artwork_url,
    row?.garment_image_url,
    row?.garment_preview_url,
    row?.preview_url,
    row?.reference_image_url,
    row?.file_url
  ]).filter(Boolean);

  const mediaImages = productRefs.media
    .filter(row => entityIds.has(String(row.entity_id)))
    .sort((a, b) => Number(Boolean(b.is_cover)) - Number(Boolean(a.is_cover)) || Number(a.sort_order || 0) - Number(b.sort_order || 0))
    .map(row => row.file_url)
    .filter(Boolean);

  return {
    assignment,
    art,
    prints,
    images: [...new Set([...directImages, ...mediaImages])],
    inherited: source.inherited,
    noPrintRequired,
    ready: Boolean(assignment && art && (prints.length || noPrintRequired))
  };
}

function decisionHtml(data, compact = false) {
  if (productRefsError) {
    return `
      <div class="v4-head">
        <small>PRODUCT MASTER DECISION</small>
        <span class="v4-source">Connection Error</span>
      </div>
      <div class="v4-error">${safe(productRefsError)}</div>
    `;
  }

  if (!data.assignment || !data.art) {
    return `
      <div class="v4-head">
        <small>PRODUCT MASTER DECISION</small>
        <span class="v4-source">Missing</span>
      </div>
      <div class="v4-error">Product Master में Art decision बाकी है। पहले Art decide करें।</div>
    `;
  }

  const prints = data.prints.map(printNumber).filter(Boolean);
  const printText = data.noPrintRequired ? "N/A — No Print Required" : prints.join(", ") || "Print decision missing";

  return `
    <div class="v4-head">
      <small>PRODUCT MASTER DECISION</small>
      <span class="v4-source">${data.inherited ? "Inherited Parent" : "Direct Child"}</span>
    </div>
    <div class="v4-meta">
      <span><small>Art No</small><strong>${safe(artNumber(data.art) || "—")}</strong></span>
      <span><small>Print No</small><strong>${safe(printText)}</strong></span>
      <span><small>Style</small><strong>${safe(artStyle(data.art) || "—")}</strong></span>
      <span><small>Status</small><strong>${data.ready ? "Ready" : "Decision Pending"}</strong></span>
    </div>
// ===== REDZED CUTTING MASTER V33 PART 1 END =====
// ===== REDZED CUTTING MASTER V33 PART 2 START =====
    ${data.images.length ? `
      <div class="v4-images">
        ${data.images.slice(0, compact ? 3 : 6).map(url => `
          <img src="${safe(url)}" alt="Art Print Reference" loading="lazy">
        `).join("")}
      </div>
    ` : ""}
  `;
}

function ensureDecisionUi() {
  if (!$("cuttingDecisionStyle")) {
    const style = document.createElement("style");
    style.id = "cuttingDecisionStyle";
    style.textContent = `
      .v4-decision{margin:12px 0;padding:12px;border:1px solid #3a3a44;border-radius:14px;background:#0d0d11}
      .v4-head{display:flex;justify-content:space-between;gap:8px;margin-bottom:8px}
      .v4-head small{color:#ff7b86;font-weight:900}
      .v4-source{font-size:10px;color:#bbb;background:#24242b;padding:4px 7px;border-radius:999px}
      .v4-meta{display:grid;grid-template-columns:1fr 1fr;gap:7px}
      .v4-meta span{padding:8px;border-radius:9px;background:#18181e;font-size:12px}
      .v4-meta small{display:block;color:#999;margin-bottom:3px}
      .v4-images{display:flex;gap:7px;overflow-x:auto;margin-top:8px}
      .v4-images img{width:72px;height:72px;flex:0 0 72px;object-fit:cover;border-radius:10px}
      .v4-error{color:#ffb6bd;font-size:12px;line-height:1.45}
      @media(max-width:620px){.v4-meta{grid-template-columns:1fr}}
    `;
    document.head.appendChild(style);
  }

  ["artNo", "printNo"].forEach(id => {
    const input = $(id);
    if (input) input.readOnly = true;
  });

  const bundle = $("bundleQty");
  if (bundle) {
    bundle.value = "1";
    bundle.closest("label")?.style.setProperty("display", "none");
  }

  const firstCard = $("lotForm")?.querySelector(".cm-form-card");
  if (firstCard && !$("lotDecisionV4")) {
    const box = document.createElement("section");
    box.id = "lotDecisionV4";
    box.className = "v4-decision";
    firstCard.insertAdjacentElement("afterend", box);
  }
}

function renderStats() {
  if (!$("cmStats")) return;
  const finalRows = units.filter(isFinal);
  const childRows = finalRows.filter(row => row.parent_unit_id);
  const totalPieces = lots.reduce((sum, lot) => sum + Number(lot.planned_pcs || 0), 0);

  $("cmStats").innerHTML = `
    <article><small>Final CB Children</small><strong>${finalRows.length}</strong></article>
    <article><small>Child Batches</small><strong>${childRows.length}</strong></article>
    <article><small>Lots Released</small><strong>${lots.length}</strong></article>
    <article><small>Total Pieces</small><strong>${totalPieces}</strong></article>
  `;
}

function colourHtml(purchaseId) {
  const list = coloursFor(purchaseId);
  if (!list.length) {
    return `<span><i class="cm-colour-dot">C</i>No colours</span>`;
  }

  return list.map(colour => {
    const name = colour.colour_name || `Colour ${colour.colour_order || ""}`;
    const icon = colour.image_url
      ? `<img src="${safe(colour.image_url)}" alt="${safe(name)}" loading="lazy">`
      : `<i class="cm-colour-dot">C</i>`;
    return `<span>${icon}${safe(name)}</span>`;
  }).join("");
}

function renderGallery() {
  if (!gallery) return;

  const query = ($("cmSearch")?.value || "").trim().toLowerCase();

  const rows = units
    .filter(row => {
      if (!isFinal(row)) return false;
      const purchase = purchaseFor(unitPurchaseId(row));
      const lot = lotForUnit(unitId(row));
      const state = cardState(row);
      const decision = productDecision(unitId(row));
      const searchText = [
        purchaseNo(purchase),
        unitCode(row),
        lot?.lot_no,
        lot?.style_name,
        lot?.art_no,
        lot?.print_no,
        decision.art ? artNumber(decision.art) : "",
        decision.art ? artStyle(decision.art) : "",
        ...decision.prints.map(printNumber)
      ].filter(Boolean).join(" ").toLowerCase();
      return (currentFilter === "all" || state === currentFilter) && searchText.includes(query);
    })
    .sort((a, b) => String(unitCode(a)).localeCompare(String(unitCode(b)), undefined, { numeric: true }));

  gallery.setAttribute("aria-busy", "false");

  if (!rows.length) {
    gallery.innerHTML = `
      <article class="cm-empty">
        <h3>No cutting card found</h3>
        <p>Create CB Children in Product Master or change the filter.</p>
      </article>
    `;
    renderStats();
    return;
  }

  gallery.innerHTML = rows.map(row => {
    const purchase = purchaseFor(unitPurchaseId(row));
    const lot = lotForUnit(unitId(row));
    const state = cardState(row);
    const isChild = Boolean(row.parent_unit_id);
    const decision = productDecision(unitId(row));

    const lotBox = lot ? `
      <div class="cm-lot-box">
        <h4>LOT ${safe(lot.lot_no)}</h4>
        <p>${safe(lot.style_name || "")}${lot.art_no ? ` · ${safe(lot.art_no)}` : ""}${lot.print_no ? ` · ${safe(lot.print_no)}` : ""}</p>
        <p>${Number(lot.planned_pcs || 0)} pcs · ${safe(lot.status)}</p>
        <div class="cm-lot-cost">
          <span>Final / Pc: <strong>${money(lot.final_cost_per_piece || 0)}</strong></span>
          <span>Total Cost: <strong>${money(lot.total_cutting_cost || 0)}</strong></span>
        </div>
      </div>
    ` : `
      <div class="cm-lot-box">
        <h4>Lot No Due</h4>
        <p>${isChild ? "Child / Dev card ready for permanent Lot No." : "Single card can release Lot No directly."}</p>
      </div>
    `;

    return `
      <article class="cm-card">
        <span class="cm-chip chip-${safe(state)}">${safe(state)}</span>
        <h3>${safe(purchaseNo(purchase))}</h3>
        <p>${safe(unitCode(row))}${isChild ? " · Child / Dev" : ""}</p>
        <div class="cm-colours">${colourHtml(unitPurchaseId(row))}</div>
        <div class="cm-metrics">
          <span><small>Weight</small><strong>${unitWeight(row).toFixed(3)} kg</strong></span>
          <span><small>Children</small><strong>${childrenFor(unitId(row)).length}</strong></span>
          <span><small>Lot</small><strong>${lot ? safe(lot.lot_no) : "Due"}</strong></span>
        </div>
        ${lotBox}
        <section class="v4-decision">${decisionHtml(decision, true)}</section>
        <div class="cm-actions">
          <button class="cm-single" type="button" data-single="${safe(unitId(row))}" ${lot || !decision.ready ? "disabled" : ""}>Single · Release Lot</button>
          <button class="cm-multi" type="button" data-multi="${safe(unitId(row))}" ${lot || isChild ? "disabled" : ""}>Multi Combo</button>
        </div>
      </article>
    `;
  }).join("");

  gallery.querySelectorAll("[data-single]").forEach(button => {
    button.onclick = () => {
      const row = units.find(unit => String(unitId(unit)) === String(button.dataset.single));
      openLot(row);
    };
  });

  gallery.querySelectorAll("[data-multi]").forEach(button => {
    button.onclick = () => {
      const row = units.find(unit => String(unitId(unit)) === String(button.dataset.multi));
      openSplit(row);
    };
  });

  renderStats();
}

function openSheet(sheet) {
  if (!sheet) return;
  sheet.classList.remove("cm-hidden");
  sheet.setAttribute("aria-hidden", "false");
  document.body.classList.add("cm-no-scroll");
}

function closeSheet(sheet) {
  if (!sheet) return;
  sheet.classList.add("cm-hidden");
  sheet.setAttribute("aria-hidden", "true");
  if (splitSheet?.classList.contains("cm-hidden") && lotSheet?.classList.contains("cm-hidden") && costSheet?.classList.contains("cm-hidden")) {
    document.body.classList.remove("cm-no-scroll");
  }
}

function childInputs() {
  return [...($("childRows")?.querySelectorAll(".cm-child-weight") || [])];
}

function updateChildTotal() {
  const total = childInputs().reduce((sum, input) => sum + Number(input.value || 0), 0);
  if ($("childWeightTotal")) $("childWeightTotal").textContent = `${total.toFixed(3)} kg`;
}

function renderChildRows() {
  const count = Math.max(2, Number($("childCount")?.value || 2));
  const parentCode = activeUnit ? unitCode(activeUnit) : "S";
  const oldValues = childInputs().map(input => input.value);
  if (!$("childRows")) return;

  $("childRows").innerHTML = Array.from({ length: count }, (_, index) => `
    <div class="cm-child-row">
      <div class="cm-child-code">${safe(parentCode)}${String.fromCharCode(65 + index)}</div>
      <label><span>Weight (kg) *</span><input class="cm-child-weight" type="number" min="0.001" step="0.001" value="${safe(oldValues[index] || "")}"></label>
    </div>
  `).join("");

  childInputs().forEach(input => { input.oninput = updateChildTotal; });
  updateChildTotal();
}

function equalChildSplit() {
  if (!activeUnit) return;
  const inputs = childInputs();
  if (!inputs.length) return;
  const total = unitWeight(activeUnit);
  const base = Math.floor((total / inputs.length) * 1000) / 1000;
  let used = 0;
  inputs.forEach((input, index) => {
    const value = index === inputs.length - 1 ? Number((total - used).toFixed(3)) : base;
    input.value = value.toFixed(3);
    used += value;
  });
  updateChildTotal();
}

function openSplit(row) {
  if (!row) return;
  activeUnit = row;
  setInputValue("splitParentId", unitId(row));
  const purchase = purchaseFor(unitPurchaseId(row));
  if ($("splitContext")) $("splitContext").textContent = `${purchaseNo(purchase)} · ${unitCode(row)}`;
  if ($("splitParentWeight")) $("splitParentWeight").textContent = `${unitWeight(row).toFixed(3)} kg`;
  setInputValue("childCount", "2");
  renderChildRows();
  equalChildSplit();
  openSheet(splitSheet);
}

function matrixValues() {
  const values = new Map();
  ($("cuttingMatrix")?.querySelectorAll(".cm-size-qty") || []).forEach(input => {
    values.set(`${input.dataset.colourId}|${input.dataset.size}`, input.value);
  });
  return values;
}

function renderMatrix() {
  if (!activeUnit || !$("cuttingMatrix")) return;
  const sizes = parseSizes();
  const oldValues = matrixValues();

  $("cuttingMatrix").innerHTML = coloursFor(unitPurchaseId(activeUnit)).map(colour => {
    const name = colour.colour_name || `Colour ${colour.colour_order || ""}`;
    const icon = colour.image_url ? `<img src="${safe(colour.image_url)}" alt="${safe(name)}">` : `<i>C</i>`;
    return `
      <article class="cm-matrix-card">
        <div class="cm-matrix-head">${icon}<strong>${safe(name)}</strong></div>
        <div class="cm-size-grid">
          ${sizes.map(size => `
            <label>
              <span>${safe(size)}</span>
              <input class="cm-size-qty" type="number" min="0" step="1" placeholder="0" value="${safe(oldValues.get(`${colour.id}|${size}`) || "")}" data-colour-id="${safe(colour.id)}" data-colour-name="${safe(name)}" data-size="${safe(size)}">
            </label>
          `).join("")}
        </div>
      </article>
    `;
  }).join("");

  $("cuttingMatrix").querySelectorAll(".cm-size-qty").forEach(input => { input.oninput = updatePieceTotals; });
  updatePieceTotals();
}

function updatePieceTotals() {
  const bundleQty = Math.max(1, Number($("bundleQty")?.value || 1));
  let pieces = 0;
  let bundles = 0;

  ($("cuttingMatrix")?.querySelectorAll(".cm-size-qty") || []).forEach(input => {
    const qty = Math.max(0, Math.floor(Number(input.value || 0)));
    pieces += qty;
    if (qty > 0) bundles += Math.ceil(qty / bundleQty);
  });

  if ($("totalPieces")) $("totalPieces").textContent = String(pieces);
  if ($("totalBundles")) $("totalBundles").textContent = String(bundles);
  updateCostPreview();
}

function updateWeightSettlement() {
  const cbWeight = activeUnit ? unitWeight(activeUnit) : 0;
  const fabricUsed = Number($("fabricUsed")?.value || 0);
  const wastage = Number($("wastageWeight")?.value || 0);
  const remnant = Number($("remnantWeight")?.value || 0);
  const settled = fabricUsed + wastage + remnant;
  const difference = cbWeight - settled;

  if ($("lotUnitWeight")) $("lotUnitWeight").textContent = `${cbWeight.toFixed(3)} kg`;
  if ($("settledWeight")) $("settledWeight").textContent = `${settled.toFixed(3)} kg`;
  if ($("weightDifference")) $("weightDifference").textContent = `${difference.toFixed(3)} kg`;
}

function selectedAdjustmentTypes() {
  const selected = [];
  if ($("sizeType")?.value === "big") selected.push({ key: "big", label: "Big Size", amount: Number(costSettings.big_adjustment || 0) });
  if ($("sleeveType")?.value === "full") selected.push({ key: "full_sleeve", label: "Full Sleeve", amount: Number(costSettings.full_sleeve_adjustment || 0) });
  if ($("borderType")?.value === "with") selected.push({ key: "border", label: "Border / Special", amount: Number(costSettings.border_adjustment || 0) });
  return selected;
}

function customAdjustmentValue() {
  if (costSettings.allow_custom_adjustment === false) return 0;
  return Number($("customAdjustment")?.value || 0);
}

function baseCostValue() {
  const input = $("baseCost");
  if (!input) return Number(costSettings.default_base_cost || 0);
  return Number(input.value || costSettings.default_base_cost || 0);
}

function calculatedCost() {
  const base = baseCostValue();
  const standardAdjustments = selectedAdjustmentTypes().reduce((sum, item) => sum + item.amount, 0);
  const custom = customAdjustmentValue();
  const perPiece = base + standardAdjustments + custom;
  const pieces = Number($("totalPieces")?.textContent || 0);
  return { base, standardAdjustments, custom, perPiece, pieces, total: perPiece * pieces };
}

function updateCostPreview() {
  const result = calculatedCost();
  const selected = selectedAdjustmentTypes();
  const amountFor = key => selected.find(item => item.key === key)?.amount || 0;
  const setText = (id, value) => {
    const el = $(id);
    if (el) el.textContent = money(value);
  };

  setText("sizeCostPreview", amountFor("big"));
  setText("sleeveCostPreview", amountFor("full_sleeve"));
  setText("borderCostPreview", amountFor("border"));
  setText("finalCostPreview", result.perPiece);
  setText("totalCostPreview", result.total);
  setText("costBasePreview", result.base);
  setText("costAdjustmentPreview", result.standardAdjustments + result.custom);
  setText("costPerPiecePreview", result.perPiece);
  setText("costTotalPreview", result.total);
}

function renderCostSettings() {
  setInputValue("settingBaseCost", costSettings.default_base_cost);
  setInputValue("settingBigAdjustment", costSettings.big_adjustment);
  setInputValue("settingFullAdjustment", costSettings.full_sleeve_adjustment);
  setInputValue("settingBorderAdjustment", costSettings.border_adjustment);
  const allowCustom = $("settingAllowCustom");
  if (allowCustom) allowCustom.checked = costSettings.allow_custom_adjustment !== false;
  setInputValue("baseCost", costSettings.default_base_cost);
  const customInput = $("customAdjustment");
  if (customInput) customInput.disabled = costSettings.allow_custom_adjustment === false;
  updateCostPreview();
}
// ===== REDZED CUTTING MASTER V33 PART 2 END ====
  
  // ===== REDZED CUTTING MASTER V33 PART 3 START =====

function openCostSettings() {
  renderCostSettings();
  openSheet(costSheet);
}

function lotDecisionForActiveUnit() {
  if (!activeUnit) return productDecision("");
  return productDecision(unitId(activeUnit));
}

function autofillProductDecision() {
  if (!activeUnit) return;
  const decision = lotDecisionForActiveUnit();
  const artNo = decision.art ? artNumber(decision.art) : "";
  const styleName = decision.art ? artStyle(decision.art) : "";
  const printNos = decision.noPrintRequired ? "N/A" : decision.prints.map(printNumber).filter(Boolean).join(", ");

  setInputValue("artNo", artNo);
  setInputValue("printNo", printNos);

  const styleInput = $("styleName");
  if (styleInput) styleInput.value = styleName || styleInput.value || "";

  const decisionBox = $("lotDecisionV4");
  if (decisionBox) decisionBox.innerHTML = decisionHtml(decision, false);

  const submitButton = $("lotForm")?.querySelector('button[type="submit"]');
  if (submitButton) submitButton.disabled = !decision.ready;
}

function nextLotNumber() {
  const year = new Date().getFullYear().toString().slice(-2);
  const numbers = lots.map(row => {
    const match = String(row.lot_no || "").match(/(\d+)$/);
    return match ? Number(match[1]) : 0;
  }).filter(Number.isFinite);
  const next = Math.max(0, ...numbers) + 1;
  return `LOT-${year}-${String(next).padStart(4, "0")}`;
}

function openLot(row) {
  if (!row) return;
  const decision = productDecision(unitId(row));
  if (!decision.ready) {
    say("Product Master decision incomplete. Art और Print पहले decide करें।", "error");
    return;
  }

  activeUnit = row;
  const purchase = purchaseFor(unitPurchaseId(row));
  setInputValue("lotUnitId", unitId(row));
  if ($("lotContext")) $("lotContext").textContent = `${purchaseNo(purchase)} · ${unitCode(row)}`;

  setInputValue("lotNo", nextLotNumber());
  setInputValue("lotDate", today());
  setInputValue("sizeSet", "L,XL,XXL");
  setInputValue("bundleQty", "1");
  setInputValue("styleName", "");
  setInputValue("lotNotes", "");
  setInputValue("fabricUsed", "");
  setInputValue("wastageWeight", "0");
  setInputValue("remnantWeight", "0");
  setSelectValue($("sizeType"), "small");
  setSelectValue($("sleeveType"), "half");
  setSelectValue($("borderType"), "without");

  autofillProductDecision();
  renderMatrix();
  updateWeightSettlement();
  updateCostPreview();
  openSheet(lotSheet);

  setTimeout(() => { $("lotNo")?.focus(); }, 80);
}

function cuttingEntries() {
  return [...($("cuttingMatrix")?.querySelectorAll(".cm-size-qty") || [])]
    .map(input => ({
      colour_id: input.dataset.colourId,
      colour_name: input.dataset.colourName,
      size_name: input.dataset.size,
      quantity: Math.max(0, Math.floor(Number(input.value || 0)))
    }))
    .filter(row => row.quantity > 0);
}

function validateLotForm() {
  if (!activeUnit) throw new Error("No CB child selected.");
  const decision = lotDecisionForActiveUnit();
  if (!decision.ready) throw new Error("Product Master Art/Print decision incomplete.");
  const lotNo = $("lotNo")?.value.trim();
  if (!lotNo) throw new Error("Lot No required.");
  const styleName = $("styleName")?.value.trim();
  if (!styleName) throw new Error("Style name required.");
  const sizes = parseSizes();
  const entries = cuttingEntries();
  const totalPieces = entries.reduce((sum, row) => sum + Number(row.quantity || 0), 0);
  return { decision, lotNo, styleName, sizes, entries, totalPieces };
}

function adjustmentDetails() {
  const selected = selectedAdjustmentTypes().map(item => ({ type: item.key, label: item.label, amount: item.amount }));
  const custom = customAdjustmentValue();
  if (custom !== 0) selected.push({ type: "custom", label: "Custom Adjustment", amount: custom });
  return selected;
}

function lotPayload(validation) {
  const result = calculatedCost();
  const decision = validation.decision;
  return {
    cb_unit_id: unitId(activeUnit),
    cb_id: unitPurchaseId(activeUnit),
    lot_no: validation.lotNo,
    lot_date: $("lotDate")?.value || today(),
    style_name: validation.styleName,
    art_no: decision.art ? artNumber(decision.art) : "",
    print_no: decision.noPrintRequired ? "N/A" : decision.prints.map(printNumber).filter(Boolean).join(", "),
    size_set: validation.sizes,
    planned_pcs: validation.totalPieces,
    bundle_qty: 1,
    base_cost_per_piece: result.base,
    adjustment_cost_per_piece: result.standardAdjustments + result.custom,
    final_cost_per_piece: result.perPiece,
    total_cutting_cost: result.total,
    adjustments: adjustmentDetails(),
    remarks: ($("lotNotes")?.value || $("remarks")?.value || "").trim() || null,
    status: "released"
  };
}

function breakupPayloads(lotId, validation) {
  return validation.entries.map(row => ({
    lot_id: lotId,
    cb_unit_id: unitId(activeUnit),
    colour_id: row.colour_id || null,
    colour_name: row.colour_name,
    size_name: row.size_name,
    quantity: row.quantity,
    bundle_qty: 1,
    bundle_count: row.quantity
  }));
}

async function createLot(event) {
  event.preventDefault();
  const client = getClient();
  if (!client) {
    say("Supabase client unavailable.", "error");
    return;
  }

  const submitButton = event.submitter || $("lotForm")?.querySelector('button[type="submit"]');

  try {
    if (submitButton) {
      submitButton.disabled = true;
      submitButton.textContent = "Releasing Lot...";
    }

    say("Lot release हो रहा है...", "info");
    const validation = validateLotForm();
    const payload = lotPayload(validation);

    const duplicate = await client.from("rr_cutting_lots_v3").select("id, lot_no").eq("lot_no", payload.lot_no).maybeSingle();
    if (duplicate.error) throw duplicate.error;
    if (duplicate.data) throw new Error(`Lot No ${payload.lot_no} already exists.`);

    const insertedLot = await client.from("rr_cutting_lots_v3").insert(payload).select("*").single();
    if (insertedLot.error) throw insertedLot.error;

    const lotRow = insertedLot.data;
    const breakupRows = breakupPayloads(lotRow.id, validation);

    if (breakupRows.length) {
      const insertedBreakup = await client.from("rr_cutting_breakup_v3").insert(breakupRows).select("*");
      if (insertedBreakup.error) {
        await client.from("rr_cutting_lots_v3").delete().eq("id", lotRow.id);
        throw insertedBreakup.error;
      }
      breakup.push(...(insertedBreakup.data || []));
    }

    lots.push(lotRow);
    closeSheet(lotSheet);
    say(`Lot ${lotRow.lot_no} successfully released.`, "success");
    renderGallery();
  } catch (error) {
    console.error("Lot release failed:", error);
    say(errorText(error), "error");
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = "Release Lot";
    }
    autofillProductDecision();
  }
}

function validateSplit() {
  if (!activeUnit) throw new Error("No parent CB selected.");
  if (activeUnit.parent_unit_id) throw new Error("A child CB cannot be split again from this screen.");
  if (lotForUnit(unitId(activeUnit))) throw new Error("Lot already released for this CB.");

  const weights = childInputs().map(input => Number(input.value || 0));
  if (weights.length < 2) throw new Error("At least two child batches required.");
  if (weights.some(weight => !Number.isFinite(weight) || weight <= 0)) throw new Error("Every child weight must be greater than zero.");

  const parentWeight = unitWeight(activeUnit);
  const childTotal = weights.reduce((sum, weight) => sum + weight, 0);
  const difference = Math.abs(parentWeight - childTotal);
  if (difference > 0.002) throw new Error(`Child total ${childTotal.toFixed(3)} kg must match parent weight ${parentWeight.toFixed(3)} kg.`);
  return { weights, parentWeight, childTotal };
}

function childCode(parentCode, index) {
  return `${parentCode}${String.fromCharCode(65 + index)}`;
}

function childPayloads(validation) {
  const parentId = unitId(activeUnit);
  const purchaseId = unitPurchaseId(activeUnit);
  const parentCode = unitCode(activeUnit);
  return validation.weights.map((weight, index) => ({
    purchase_id: purchaseId,
    cb_id: purchaseId,
    parent_unit_id: parentId,
    cb_code: childCode(parentCode, index),
    division_code: childCode(parentCode, index),
    division_index: index + 1,
    divided_weight: Number(weight.toFixed(3)),
    allocated_qty: Number(weight.toFixed(3)),
    is_final: true,
    status: "ready"
  }));
}

async function copyParentDecisionToChildren(client, children) {
  const source = assignmentForUnit(unitId(activeUnit));
  const parentAssignment = source.assignment;
  if (!parentAssignment || !children.length) return;

  const assignments = children.map(child => ({
    cb_id: unitId(child),
    art_id: parentAssignment.art_id,
    no_print_required: parentAssignment.no_print_required === true,
    print_required: parentAssignment.print_required !== false,
    print_status: parentAssignment.print_status || null
  }));

  const insertedAssignments = await client.from("rr_cb_art_assignments").insert(assignments).select("*");
  if (insertedAssignments.error) {
    console.warn("Child Art assignment copy failed:", insertedAssignments.error);
    return;
  }

  const oldPrintRows = productRefs.printAssignments
    .filter(row => String(row.assignment_id) === String(parentAssignment.id))
    .sort((a, b) => Number(a.sequence_no || 0) - Number(b.sequence_no || 0));

  const newAssignments = insertedAssignments.data || [];
  const newPrintRows = newAssignments.flatMap(assignment =>
    oldPrintRows.map(oldRow => ({
      assignment_id: assignment.id,
      print_id: oldRow.print_id,
      sequence_no: oldRow.sequence_no || 1
    }))
  );

  if (newPrintRows.length) {
    const insertedPrints = await client.from("rr_cb_print_assignments").insert(newPrintRows).select("*");
    if (insertedPrints.error) console.warn("Child Print assignment copy failed:", insertedPrints.error);
  }
}

async function createSplit(event) {
  event.preventDefault();
  const client = getClient();
  if (!client) {
    say("Supabase client unavailable.", "error");
    return;
  }

  const submitButton = event.submitter || $("splitForm")?.querySelector('button[type="submit"]');

  try {
    if (submitButton) {
      submitButton.disabled = true;
      submitButton.textContent = "Creating Children...";
    }

    say("Child batches create हो रहे हैं...", "info");
    const validation = validateSplit();
    const payloads = childPayloads(validation);

    const result = await client.from("rr_cb_divisions").insert(payloads).select("*");
    if (result.error) throw result.error;

    const createdChildren = result.data || [];

    const parentUpdate = await client.from("rr_cb_divisions").update({ is_final: false, status: "split" }).eq("id", unitId(activeUnit));
    if (parentUpdate.error) console.warn("Parent status update failed:", parentUpdate.error);

    await copyParentDecisionToChildren(client, createdChildren);

    units = units.map(row => String(unitId(row)) === String(unitId(activeUnit)) ? { ...row, is_final: false, status: "split" } : row);
    units.push(...createdChildren);

    await loadProductRefs(client);
    closeSheet(splitSheet);
    say(`${createdChildren.length} child batches successfully created.`, "success");
    renderGallery();
  } catch (error) {
    console.error("CB split failed:", error);
    say(errorText(error), "error");
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = "Create Children";
    }
  }
}

async function saveCostSettings(event) {
  event.preventDefault();
  const client = getClient();
  if (!client) {
    say("Supabase client unavailable.", "error");
    return;
  }

  const submitButton = event.submitter || $("costSettingsForm")?.querySelector('button[type="submit"]');

  try {
    if (submitButton) {
      submitButton.disabled = true;
      submitButton.textContent = "Saving...";
    }

    const payload = {
      settings_key: "default",
      default_base_cost: Number($("settingBaseCost")?.value || 0),
      big_adjustment: Number($("settingBigAdjustment")?.value || 0),
      full_sleeve_adjustment: Number($("settingFullAdjustment")?.value || 0),
      border_adjustment: Number($("settingBorderAdjustment")?.value || 0),
      allow_custom_adjustment: Boolean($("settingAllowCustom")?.checked)
    };

    const result = await client.from("rr_cutting_cost_settings_v3").upsert(payload, { onConflict: "settings_key" }).select("*").single();
    if (result.error) throw result.error;
    costSettings = { ...costSettings, ...result.data };
    renderCostSettings();
    closeSheet(costSheet);
    say("Cutting cost settings saved.", "success");
  } catch (error) {
    console.error("Cost settings save failed:", error);
    say(errorText(error), "error");
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = "Save Cost Settings";
    }
  }
}

async function markLotCompleted(lotId) {
  const client = getClient();
  if (!client) {
    say("Supabase client unavailable.", "error");
    return;
  }

  try {
    const result = await client.from("rr_cutting_lots_v3").update({ status: "completed", completed_at: new Date().toISOString() }).eq("id", lotId).select("*").single();
// ===== REDZED CUTTING MASTER V33 PART 3 END =====

    // ===== REDZED CUTTING MASTER V33 PART 4 START =====
    if (result.error) throw result.error;
    lots = lots.map(row => String(row.id) === String(lotId) ? result.data : row);
    say(`Lot ${result.data.lot_no} completed.`, "success");
    renderGallery();
  } catch (error) {
    console.error("Lot completion failed:", error);
    say(errorText(error), "error");
  }
}

async function loadCostSettings(client) {
  try {
    const result = await client.from("rr_cutting_cost_settings_v3").select("*").eq("settings_key", "default").maybeSingle();
    if (result.error) throw result.error;
    if (result.data) costSettings = { ...costSettings, ...result.data };
  } catch (error) {
    console.warn("Cutting cost settings unavailable:", error);
  }
  renderCostSettings();
}

async function loadPurchases(client) {
  const attempts = [
    { table: "rr_cb_purchases", query: () => client.from("rr_cb_purchases").select("*").order("created_at", { ascending: false }) },
    { table: "rr_purchase_master", query: () => client.from("rr_purchase_master").select("*").order("created_at", { ascending: false }) },
    { table: "rr_cb_master", query: () => client.from("rr_cb_master").select("*").order("created_at", { ascending: false }) }
  ];

  let lastError = null;
  for (const attempt of attempts) {
    const result = await attempt.query();
    if (!result.error) {
      console.info(`Purchases loaded from ${attempt.table}`);
      return result.data || [];
    }
    lastError = result.error;
  }
  throw lastError || new Error("Purchase Master table unavailable.");
}

async function loadUnits(client) {
  const tables = ["rr_cb_divisions", "rr_cb_units"];
  const allRows = [];

  for (const table of tables) {
    const result = await client.from(table).select("*").order("created_at", { ascending: true });
    if (result.error) {
      console.warn(`${table} unavailable:`, result.error);
      continue;
    }
    console.info(`${result.data?.length || 0} CB units loaded from ${table}`);
    allRows.push(...(result.data || []));
  }

  return [...new Map(allRows.map((row, index) => [
    String(row.id || row.division_id || row.unit_id || `${row.cb_code || row.unit_code}-${index}`),
    row
  ])).values()];
}

async function loadColours(client) {
  const attempts = [
    { table: "rr_cb_colours", query: () => client.from("rr_cb_colours").select("*").order("colour_order", { ascending: true }) },
    { table: "rr_purchase_colours", query: () => client.from("rr_purchase_colours").select("*").order("colour_order", { ascending: true }) },
    { table: "rr_cb_color_breakup", query: () => client.from("rr_cb_color_breakup").select("*").order("colour_order", { ascending: true }) }
  ];

  let lastError = null;
  for (const attempt of attempts) {
    const result = await attempt.query();
    if (!result.error) {
      console.info(`Colours loaded from ${attempt.table}`);
      return result.data || [];
    }
    lastError = result.error;
  }

  console.warn("CB colour table unavailable:", lastError);
  return [];
}

async function loadLots(client) {
  const result = await client.from("rr_cutting_lots_v3").select("*").order("created_at", { ascending: false });
  if (result.error) {
    if (result.error.code === "42P01" || String(result.error.message || "").toLowerCase().includes("does not exist")) {
      console.warn("rr_cutting_lots_v3 table not found.");
      return [];
    }
    throw result.error;
  }
  return result.data || [];
}

async function loadBreakup(client) {
  const result = await client.from("rr_cutting_breakup_v3").select("*").order("created_at", { ascending: false });
  if (result.error) {
    if (result.error.code === "42P01" || String(result.error.message || "").toLowerCase().includes("does not exist")) {
      console.warn("rr_cutting_breakup_v3 table not found.");
      return [];
    }
    throw result.error;
  }
  return result.data || [];
}

function normalizePurchaseRows(rows) {
  return (rows || []).map(row => ({
    ...row,
    id: row.id || row.purchase_id || row.cb_id,
    cb_no: row.cb_no || row.cb_code || row.purchase_no || row.purchase_code || row.lot_no
  }));
}

function normalizeUnitRows(rows) {
  return (rows || []).map((row, index) => ({
    ...row,
    id: row.id || row.division_id || row.unit_id,
    purchase_id: row.purchase_id || row.cb_id || row.parent_cb_id,
    cb_id: row.cb_id || row.purchase_id || row.parent_cb_id,
    cb_code: row.cb_code || row.division_code || row.unit_code || `S${index + 1}`,
    divided_weight: Number(row.divided_weight ?? row.allocated_qty ?? row.base_qty ?? row.weight ?? 0),
    is_final: row.is_final !== false
  }));
}

function normalizeColourRows(rows) {
  return (rows || []).map((row, index) => ({
    ...row,
    id: row.id || row.colour_id || row.color_id || `${row.cb_id || "cb"}-${index}`,
    cb_id: row.cb_id || row.purchase_id || row.parent_cb_id,
    colour_name: row.colour_name || row.color_name || row.name || `Colour ${index + 1}`,
    colour_order: Number(row.colour_order ?? row.color_order ?? row.sequence_no ?? index + 1),
    image_url: row.image_url || row.colour_image_url || row.color_image_url || row.swatch_url || ""
  }));
}

function normalizeLotRows(rows) {
  return (rows || []).map(row => ({
    ...row,
    cb_unit_id: row.cb_unit_id || row.unit_id || row.division_id,
    planned_pcs: Number(row.planned_pcs ?? row.total_pcs ?? row.pieces ?? 0),
    final_cost_per_piece: Number(row.final_cost_per_piece ?? row.cost_per_piece ?? 0),
    total_cutting_cost: Number(row.total_cutting_cost ?? row.total_cost ?? 0)
  }));
}
function buildUnitsFromProductRefs() {
  const map = new Map();

  productRefs.assignments.forEach((row, index) => {
    const id =
      row.division_id ||
      row.cb_unit_id ||
      row.unit_id ||
      row.child_id ||
      row.cb_id;

    if (!id) {
      return;
    }

    const key = String(id);

    if (map.has(key)) {
      return;
    }

    const purchaseId =
      row.cb_id ||
      row.purchase_id ||
      row.cb_purchase_id ||
      row.parent_cb_id ||
      id;

    map.set(key, {
      id,
      division_id: id,

      purchase_id: purchaseId,
      cb_id: purchaseId,

      cb_code:
        row.division_code ||
        row.cb_code ||
        row.child_code ||
        row.child_no ||
        row.dev_code ||
        row.dev_no ||
        `PM-${index + 1}`,

      division_code:
        row.division_code ||
        row.cb_code ||
        row.child_code ||
        row.child_no ||
        row.dev_code ||
        row.dev_no ||
        `PM-${index + 1}`,

      parent_unit_id:
        row.parent_unit_id ||
        row.parent_division_id ||
        row.parent_child_id ||
        null,

      divided_weight: Number(
        row.divided_weight ??
        row.allocated_qty ??
        row.weight ??
        0
      ),

      allocated_qty: Number(
        row.allocated_qty ??
        row.divided_weight ??
        row.weight ??
        0
      ),

      is_final: true,
      status: "ready",
      source: "product_master_assignment"
    });
  });

  return [...map.values()];
}
async function loadAllData() {
  const client = getClient();
  if (!client) throw new Error("Supabase client unavailable. Check config.js.");

  gallery?.setAttribute("aria-busy", "true");
  if (gallery) {
    gallery.innerHTML = `
      <article class="cm-empty">
        <div class="cm-spinner"></div>
        <h3>Loading Cutting Master Final V33</h3>
        <p>Connecting CB Children, Product Master and Lot data...</p>
      </article>
    `;
  }

  say("Cutting Master data load हो रहा है...", "info");

  const [purchaseRows, unitRows, colourRows, lotRows, breakupRows] = await Promise.all([
    withTimeout(loadPurchases(client), 12000, "Purchases loading"),
    withTimeout(loadUnits(client), 12000, "CB Children loading"),
    withTimeout(loadColours(client), 12000, "Colours loading"),
    withTimeout(loadLots(client), 12000, "Cutting Lots loading"),
    withTimeout(loadBreakup(client), 12000, "Cutting Breakup loading")
  ]);

  purchases = normalizePurchaseRows(purchaseRows);
  units = normalizeUnitRows(unitRows);
  colours = normalizeColourRows(colourRows);
  lots = normalizeLotRows(lotRows);
  breakup = breakupRows || [];

  await Promise.all([
    withTimeout(loadProductRefs(client), 12000, "Product Master references loading"),
    withTimeout(loadCostSettings(client), 12000, "Cost Settings loading")
  ]);
if (
    !units.filter(isFinal).length &&
    productRefs.assignments.length
  ) {
    console.warn(
      "No CB unit rows found. Building Cutting cards from Product Master assignments."
    );

    units = normalizeUnitRows(
      buildUnitsFromProductRefs()
    );
}
  
  renderGallery();
  say(`${units.filter(isFinal).length} final CB children loaded.`, "success");
}

async function refreshCuttingMaster() {
  const refreshButton = $("refreshCutting");
  try {
    if (refreshButton) {
      refreshButton.disabled = true;
      refreshButton.textContent = "Refreshing...";
    }
    await loadAllData();
  } catch (error) {
    console.error("Cutting Master refresh failed:", error);
    showFatalError(error);
  } finally {
    if (refreshButton) {
      refreshButton.disabled = false;
      refreshButton.textContent = "Refresh";
    }
  }
}

function resetLotAdjustments() {
  setSelectValue($("sizeType"), "small");
  setSelectValue($("sleeveType"), "half");
  setSelectValue($("borderType"), "without");
  setInputValue("customAdjustment", "0");
  setInputValue("baseCost", costSettings.default_base_cost);
  updateCostPreview();
}

function resetLotForm() {
  $("lotForm")?.reset();
  setInputValue("lotDate", today());
  setInputValue("sizeSet", "L,XL,XXL");
  setInputValue("bundleQty", "1");
  setInputValue("lotNotes", "");
  setInputValue("fabricUsed", "");
  setInputValue("wastageWeight", "0");
  setInputValue("remnantWeight", "0");
  if ($("cuttingMatrix")) $("cuttingMatrix").innerHTML = "";
  if ($("totalPieces")) $("totalPieces").textContent = "0";
  if ($("totalBundles")) $("totalBundles").textContent = "0";
  if ($("lotDecisionV4")) $("lotDecisionV4").innerHTML = "";
  resetLotAdjustments();
  updateWeightSettlement();
}

function resetSplitForm() {
  $("splitForm")?.reset();
  setInputValue("childCount", "2");
  if ($("childRows")) $("childRows").innerHTML = "";
  if ($("childWeightTotal")) $("childWeightTotal").textContent = "0.000 kg";
}

function closeAndResetSheet(sheet) {
  closeSheet(sheet);
  if (sheet === lotSheet) resetLotForm();
  if (sheet === splitSheet) resetSplitForm();
  activeUnit = null;
}

function bindCuttingMasterEvents() {
  const splitForm = $("splitForm");
  const lotForm = $("lotForm");
  const costForm = $("costSettingsForm") || $("costForm");

  if (splitForm) splitForm.onsubmit = createSplit;
  if (lotForm) lotForm.onsubmit = createLot;
  if (costForm) costForm.onsubmit = saveCostSettings;

  const childCount = $("childCount");
  if (childCount) childCount.onchange = () => { renderChildRows(); equalChildSplit(); };

  const equalSplitButton = $("equalChildSplit");
  if (equalSplitButton) equalSplitButton.onclick = equalChildSplit;

  const sizeSet = $("sizeSet");
  if (sizeSet) {
    sizeSet.onchange = renderMatrix;
    sizeSet.onblur = renderMatrix;
  }

  const bundleQty = $("bundleQty");
  if (bundleQty) bundleQty.oninput = updatePieceTotals;

  ["baseCost", "customAdjustment"].forEach(id => {
    const input = $(id);
    if (input) input.oninput = updateCostPreview;
  });

  ["sizeType", "sleeveType", "borderType"].forEach(id => {
    const input = $(id);
    if (input) input.onchange = updateCostPreview;
  });

  ["fabricUsed", "wastageWeight", "remnantWeight"].forEach(id => {
    const input = $(id);
    if (input) input.oninput = updateWeightSettlement;
  });

  const openCostButton = $("openCostSettings");
  if (openCostButton) openCostButton.onclick = openCostSettings;

  document.querySelectorAll("[data-close-split]").forEach(button => { button.onclick = () => closeAndResetSheet(splitSheet); });
  document.querySelectorAll("[data-close-lot]").forEach(button => { button.onclick = () => closeAndResetSheet(lotSheet); });
  document.querySelectorAll("[data-close-cost]").forEach(button => { button.onclick = () => closeSheet(costSheet); });

  const searchInput = $("cmSearch");
  if (searchInput) searchInput.oninput = renderGallery;

  const filters = $("cmFilters");
  if (filters) {
    filters.querySelectorAll("[data-filter]").forEach(button => {
      button.onclick = () => {
        currentFilter = button.dataset.filter || "all";
        filters.querySelectorAll("[data-filter]").forEach(item => {
          item.classList.toggle("is-active", item === button);
        });
        renderGallery();
      };
    });
  }

  const refreshButton = $("refreshCutting");
  if (refreshButton) refreshButton.onclick = refreshCuttingMaster;
}

async function startCuttingMaster() {
  try {
    ensureDecisionUi();
    bindCuttingMasterEvents();
    await withTimeout(loadAllData(), 30000, "Cutting Master loading");
    console.info("REDZED Cutting Master Clean Core V33 loaded.");
  } catch (error) {
    console.error("Cutting Master startup failed:", error);
    showFatalError(error);
  }
}

window.RRCuttingMaster = {
  version: "33.0-clean",
  state() {
    return { purchases, units, colours, lots, breakup, costSettings, productRefs, activeUnit };
  },
  actions: {
    startCuttingMaster,
    refreshCuttingMaster,
    renderGallery,
    openLot,
    openSplit,
    createLot,
    createSplit,
    updateCostPreview,
    updateWeightSettlement,
    renderMatrix,
    renderCostSettings,
    closeSheet,
    openSheet,
    showFatalError,
    say
  },
  helpers: {
    unitId,
    unitCode,
    unitWeight,
    purchaseFor,
    coloursFor,
    childrenFor,
    lotForUnit,
    productDecision,
    nextLotNumber
  },
  hooks: {
    beforeOpenLot: null,
    afterOpenLot: null,
    beforeCreateSplit: null,
    afterCreateSplit: null,
    beforeCreateLot: null,
    afterCreateLot: null,
    beforeRenderGallery: null,
    afterRenderGallery: null
  }
};

console.info("REDZED ERP Bridge V33 Ready");

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startCuttingMaster, { once: true });
} else {
  startCuttingMaster();
}

})();
// ===== REDZED CUTTING MASTER V33 PART 4 END =====
