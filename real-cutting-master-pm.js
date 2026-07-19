// ===== REDZED CUTTING MASTER PM CORE PART 1 START =====

(() => {
"use strict";

/*
  REDZED REAL — Cutting Master PM Core V1
  Source locked to Product Master V717 cards.
  Active files:
  1. real-cutting-master-final.html
  2. real-cutting-master-pm.js
*/

const $ = id => document.getElementById(id);

const gallery = $("divisionGallery");
const message = $("cmMessage");
const lotSheet = $("lotSheet");
const splitSheet = $("splitSheet");
const costSheet = $("costSheet");

let galleryRows = [];
let purchaseRows = [];
let colourRows = [];
let artRows = [];
let printRows = [];
let assignmentRows = [];
let printAssignmentRows = [];
let mediaRows = [];
let lotRows = [];
let breakupRows = [];

let currentFilter = "all";
let activeCard = null;

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

function money(value) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2
  }).format(Number(value || 0));
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

  return {
    ...row,
    cb_id: cbId,
    division_id: divisionId,

    division_index: Number(
      row.division_index ||
      row.batch_index ||
      0
    ),

    division_code:
      row.division_code ||
      row.cb_child ||
      row.child_code ||
      row.child_no ||
      row.cb_code ||
      row.unit_code ||
      `CB-${divisionId}`,

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
      row.cb_code ||
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
  const viewResult = await client
    .from("rr_product_gallery_view")
    .select("*");

  if (!viewResult.error) {
    return (viewResult.data || [])
      .map(normalizeGalleryRow);
  }

  console.warn(
    "rr_product_gallery_view unavailable; using fallback.",
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

// ===== REDZED CUTTING MASTER PM CORE PART 1 END =====
// ===== REDZED CUTTING MASTER PM CORE PART 2 START =====

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
    .flatMap(group =>
      group.divisions.map(division => ({
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

function lotForDivision(divisionId) {
  return (
    lotRows.find(
      row =>
        String(row.cb_unit_id) === String(divisionId) ||
        String(row.division_id) === String(divisionId) ||
        String(row.cb_division_id) === String(divisionId)
    ) || null
  );
}

function cardDecision(card) {
  const art = card.assignment
    ? artById(card.assignment.art_id)
    : null;

  const prints = assignedPrintsForDivision(
    card.division.division_id
  );

  const ready = Boolean(card.assignment && art);

  return {
    art,
    prints,
    ready,
    artNo: artNo(art),
    printNo: printText(prints),
    styleName: styleNameFromArt(art)
  };
}

function cardState(card) {
  const lot = lotForDivision(
    card.division.division_id
  );

  if (lot?.status === "completed") return "completed";
  if (lot) return "released";

  const decision = cardDecision(card);

  if (!decision.ready) return "art_due";

  return "ready";
}

function cardSearchText(card) {
  const decision = cardDecision(card);
  const purchases = purchasesFor(card.group.cb_id);
  const colours = coloursFor(card.group.cb_id);

  return [
    card.group.cb_no,
    card.division.division_code,
    decision.artNo,
    decision.styleName,
    decision.printNo,

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
  if (currentFilter === "planning") return state === "art_due";
  if (currentFilter === "child") return true;
  if (currentFilter === "child_batches") return true;

  return true;
}

function injectStyles() {
  if ($("cmPmStyle")) return;

  const style = document.createElement("style");
  style.id = "cmPmStyle";

  style.textContent = `
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
    @media(max-width:620px){
      .cm-pm-decision{grid-template-columns:1fr}
      .cm-size-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
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

  const artDue = cards.filter(
    card => cardState(card) === "art_due"
  ).length;

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
      <small>Art Due</small>
      <strong>${artDue}</strong>
    </article>

    <article>
      <small>Completed</small>
      <strong>${completed}</strong>
    </article>
  `;
}

// ===== REDZED CUTTING MASTER PM CORE PART 2 END =====
  
 // ===== REDZED CUTTING MASTER PM CORE PART 3 START =====

let comboDevRows = [];
let currentLotMode = "single";
let matrixQtyMemory = new Map();

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
      const lot = lotForDivision(
        card.division.division_id
      );

      const colours = coloursFor(card.group.cb_id);
      const purchases = purchasesFor(card.group.cb_id);

      const items = carouselItemsForAssignment(
        decision.art,
        decision.prints
      );

      return `
        <article class="cm-card">
          <span class="cm-chip chip-${safe(state)}">
            ${safe(state)}
          </span>

          <h3>${safe(card.group.cb_no || "CB")}</h3>

          <p>
            ${safe(card.division.division_code || "CB Child")}
          </p>

          ${imageStripHtml(items, colours)}

          <div class="cm-pm-decision">
            <span>
              <small>Art No</small>
              <strong>${safe(decision.artNo || "ART DUE")}</strong>
            </span>

            <span>
              <small>Print No</small>
              <strong>${safe(decision.printNo || "N/A")}</strong>
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
              <strong>
                ${Number(card.division.allocated_qty || 0).toFixed(3)} kg
              </strong>
            </span>

            <span>
              <small>Purchase</small>
              <strong>${purchases.length}</strong>
            </span>

            <span>
              <small>Lot</small>
              <strong>${lot ? safe(lot.lot_no) : "Due"}</strong>
            </span>
          </div>

          ${
            lot
              ? `
                <div class="cm-lot-box">
                  <h4>LOT ${safe(lot.lot_no)}</h4>

                  <p>${safe(lot.style_name || "")}</p>

                  <p>
                    ${Number(lot.planned_pcs || 0)} pcs ·
                    ${safe(lot.status || "released")}
                  </p>

                  <div class="cm-lot-cost">
                    <span>
                      Final / Pc:
                      <strong>${money(lot.final_cost_per_piece || 0)}</strong>
                    </span>

                    <span>
                      Total:
                      <strong>${money(lot.total_cutting_cost || 0)}</strong>
                    </span>
                  </div>
                </div>
              `
              : `
                <div class="cm-lot-box">
                  <h4>Permanent Lot No Due</h4>
                  <p>
                    Product Master card ready होने के बाद Cutting Lot release करें.
                  </p>
                </div>
              `
          }

          <div class="cm-actions">
            <button
              type="button"
              data-release-lot="${safe(card.division.division_id)}"
              ${!decision.ready || lot ? "disabled" : ""}
            >
              Single · Release Lot
            </button>
          </div>
        </article>
      `;
    })
    .join("");

  gallery
    .querySelectorAll("[data-release-lot]")
    .forEach(button => {
      button.addEventListener("click", () => {
        openLotByDivision(button.dataset.releaseLot);
      });
    });

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
      return match ? Number(match[1]) : 0;
    })
    .filter(Number.isFinite);

  const next = Math.max(0, ...nums) + 1;

  return `LOT-${year}-${String(next).padStart(4, "0")}`;
}

function openLotByDivision(divisionId) {
  const card = divisionCards().find(
    item =>
      String(item.division.division_id) ===
      String(divisionId)
  );

  if (!card) {
    say("Product Master card not found.", "error");
    return;
  }

  const decision = cardDecision(card);

  if (!decision.ready) {
    say(
      "Art decision missing. Product Master में Art decide करें.",
      "error"
    );

    return;
  }

  activeCard = card;
  currentLotMode = "single";
  matrixQtyMemory = new Map();

  const sizes = sizesForCard(card);

  setInputValue("lotUnitId", card.division.division_id);
  setInputValue("lotNo", nextLotNumber());
  setInputValue("lotDate", today());
  setInputValue("styleName", decision.styleName);
  setInputValue("artNo", decision.artNo);
  setInputValue("printNo", decision.printNo);
  setInputValue("sizeSet", sizes.join(","));
  setInputValue("bundleQty", "1");
  setInputValue("lotNotes", "");
  setInputValue("fabricUsed", "");
  setInputValue("wastageWeight", "0");
  setInputValue("remnantWeight", "0");

  if ($("lotContext")) {
    $("lotContext").textContent =
      `${card.group.cb_no} · ${card.division.division_code}`;
  }

  ["artNo", "printNo"].forEach(id => {
    const input = $(id);

    if (input) {
      input.readOnly = true;
    }
  });

  const bundle = $("bundleQty");

  if (bundle) {
    bundle.value = "1";
    bundle.readOnly = true;
  }

  ensureComboUi();
  hideLegacyOwnerCosting();
  setLotMode("single");
  setComboDefaults();

  buildComboDevRows({
    keepManual: false,
    autoDistribute: true,
    resetMatrix: true
  });

  renderCuttingMatrix();
  updateWeightSettlement();
  updateCostPreview();

  openSheet(lotSheet);
}

function ensureComboUi() {
  if ($("cmComboPanel")) {
    return;
  }

  const form = $("lotForm");

  if (!form) {
    return;
  }

  const firstCard = form.querySelector(".cm-form-card") || form;

  const panel = document.createElement("section");
  panel.id = "cmComboPanel";
  panel.className = "cm-form-card";

  panel.innerHTML = `
    <h3>Cutting Lot Decision</h3>

    <div class="cm-actions">
      <button
        id="cmLotTypeSingle"
        type="button"
        class="cm-secondary is-active"
      >
        Single Lot
      </button>

      <button
        id="cmLotTypeMulti"
        type="button"
        class="cm-secondary"
      >
        Multi Lot
      </button>
    </div>

    <section id="cmSinglePanel">
      <h3>Single Lot Setup</h3>

      <div class="cm-grid-3">
        <label>
          <span>Size Combo</span>
          <select id="cmSingleSizeCombo"></select>
        </label>

        <label>
          <span>Sleeve</span>
          <select id="cmSingleSleeve">
            <option value="Half">Half Sleeve</option>
            <option value="Full">Full Sleeve</option>
          </select>
        </label>

        <label>
          <span>Border</span>
          <select id="cmSingleBorder">
            <option value="Without Border">Without Border</option>
            <option value="With Border">With Border</option>
          </select>
        </label>
      </div>

      <div class="cm-grid-3">
        <label>
          <span>Matching Cloth Qty</span>
          <input
            id="cmSingleMatchingQty"
            type="number"
            min="0"
            step="0.001"
            placeholder="0"
          >
        </label>

        <label>
          <span>Matching Cloth Avg Cost</span>
          <input
            id="cmSingleMatchingAvgCost"
            type="number"
            min="0"
            step="0.01"
            placeholder="₹ / kg or meter"
          >
        </label>

        <label>
          <span>Cutting Pcs</span>
          <input
            id="cmSingleCuttingPcs"
            type="number"
            min="0"
            step="1"
            placeholder="0"
          >
        </label>
      </div>
    </section>

    <section id="cmMultiPanel" class="cm-hidden">
      <h3>Multi Dev / Sub-dev Setup</h3>

      <div class="cm-grid-3">
        <label>
          <span>Dev Count</span>
          <select id="cmDevCount">
            <option value="2">2 Dev</option>
            <option value="3">3 Dev</option>
            <option value="4">4 Dev</option>
            <option value="custom">Custom</option>
          </select>
        </label>

        <label>
          <span>Custom Dev Count</span>
          <input
            id="cmCustomDevCount"
            type="number"
            min="2"
            step="1"
            placeholder="2"
          >
        </label>

        <label>
          <span>Total Parent Cutting Pcs</span>
          <input
            id="cmParentCuttingPcs"
            type="number"
            min="0"
            step="1"
            placeholder="0"
          >
        </label>
      </div>

      <div class="cm-actions">
        <button
          id="cmBuildDevRows"
          type="button"
          class="cm-secondary"
        >
          Build Dev Cards
        </button>

        <button
          id="cmEqualDevPcs"
          type="button"
          class="cm-secondary"
        >
          Equal Dev Pcs
        </button>
      </div>

      <div id="cmDevRows"></div>
    </section>
  `;

  firstCard.insertAdjacentElement("afterend", panel);

  fillSizeComboOptions("cmSingleSizeCombo");

  $("cmLotTypeSingle")?.addEventListener("click", () => {
    setLotMode("single");
  });

  $("cmLotTypeMulti")?.addEventListener("click", () => {
    setLotMode("multi");
  });

  [
    "cmSingleSizeCombo",
    "cmSingleSleeve",
    "cmSingleBorder"
  ].forEach(id => {
    $(id)?.addEventListener("change", () => {
      matrixQtyMemory = new Map();

      buildComboDevRows({
        keepManual: false,
        autoDistribute: true,
        resetMatrix: true
      });

      renderCuttingMatrix();
      updateCostPreview();
    });
  });

  [
    "cmSingleMatchingQty",
    "cmSingleMatchingAvgCost"
  ].forEach(id => {
    $(id)?.addEventListener("input", () => {
      buildComboDevRows({
        keepManual: true,
        autoDistribute: false,
        resetMatrix: false
      });

      updateCostPreview();
    });
  });

  $("cmSingleCuttingPcs")?.addEventListener("input", () => {
    matrixQtyMemory = new Map();

    buildComboDevRows({
      keepManual: true,
      autoDistribute: true,
      resetMatrix: true
    });

    renderCuttingMatrix();
    updatePieceTotals();
    updateCostPreview();
  });

  [
    "cmDevCount",
    "cmCustomDevCount"
  ].forEach(id => {
    $(id)?.addEventListener("change", () => {
      matrixQtyMemory = new Map();

      buildComboDevRows({
        keepManual: true,
        autoDistribute: true,
        resetMatrix: true
      });

      renderCuttingMatrix();
      updateCostPreview();
    });

    $(id)?.addEventListener("input", () => {
      matrixQtyMemory = new Map();

      buildComboDevRows({
        keepManual: true,
        autoDistribute: true,
        resetMatrix: true
      });

      renderCuttingMatrix();
      updateCostPreview();
    });
  });

  $("cmParentCuttingPcs")?.addEventListener("input", () => {
    matrixQtyMemory = new Map();

    distributeDevPcs();
    renderDevRows();
    renderCuttingMatrix();
    updatePieceTotals();
    updateCostPreview();
  });

  $("cmBuildDevRows")?.addEventListener("click", () => {
    matrixQtyMemory = new Map();

    buildComboDevRows({
      keepManual: true,
      autoDistribute: true,
      resetMatrix: true
    });

    renderCuttingMatrix();
    updateCostPreview();
  });

  $("cmEqualDevPcs")?.addEventListener("click", () => {
    matrixQtyMemory = new Map();

    distributeDevPcs();
    renderDevRows();
    renderCuttingMatrix();
    updatePieceTotals();
    updateCostPreview();
  });
}

function hideLegacyOwnerCosting() {
  const base = $("baseCost");

  const card =
    base?.closest(".cm-form-card") ||
    base?.closest("section") ||
    null;

  if (card && card.id !== "cmComboPanel") {
    card.style.display = "none";
  }
}

function setLotMode(mode) {
  currentLotMode = mode === "multi" ? "multi" : "single";

  $("cmLotTypeSingle")?.classList.toggle(
    "is-active",
    currentLotMode === "single"
  );

  $("cmLotTypeMulti")?.classList.toggle(
    "is-active",
    currentLotMode === "multi"
  );

  $("cmSinglePanel")?.classList.toggle(
    "cm-hidden",
    currentLotMode !== "single"
  );

  $("cmMultiPanel")?.classList.toggle(
    "cm-hidden",
    currentLotMode !== "multi"
  );

  matrixQtyMemory = new Map();

  buildComboDevRows({
    keepManual: false,
    autoDistribute: true,
    resetMatrix: true
  });

  renderCuttingMatrix();
  updatePieceTotals();
  updateCostPreview();
}

function fillSizeComboOptions(id) {
  const select = $(id);

  if (!select) {
    return;
  }

  select.innerHTML = SIZE_COMBO_OPTIONS
    .map(
      option => `
        <option value="${safe(option)}">
          ${safe(option)}
        </option>
      `
    )
    .join("");
}

function fillSizeComboSelect(select, value) {
  if (!select) return;

  select.innerHTML = SIZE_COMBO_OPTIONS
    .map(
      option => `
        <option
          value="${safe(option)}"
          ${option === value ? "selected" : ""}
        >
          ${safe(option)}
        </option>
      `
    )
    .join("");
}

function setComboDefaults() {
  const singleSize = $("cmSingleSizeCombo");

  if (singleSize) {
    singleSize.value = DEFAULT_SIZE_COMBO;
  }

  if ($("cmSingleSleeve")) {
    $("cmSingleSleeve").value = "Half";
  }

  if ($("cmSingleBorder")) {
    $("cmSingleBorder").value = "Without Border";
  }

  setInputValue("cmSingleMatchingQty", "");
  setInputValue("cmSingleMatchingAvgCost", "");
  setInputValue("cmSingleCuttingPcs", "");

  if ($("cmDevCount")) {
    $("cmDevCount").value = "2";
  }

  setInputValue("cmCustomDevCount", "");
  setInputValue("cmParentCuttingPcs", "");
}

function readArtAverageCost() {
  const decision = activeCard
    ? cardDecision(activeCard)
    : {};

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
  const mode = selectValue("cmDevCount");

  if (mode === "custom") {
    return Math.max(
      2,
      Math.floor(numberValue("cmCustomDevCount") || 2)
    );
  }

  return Math.max(
    2,
    Math.floor(Number(mode || 2))
  );
}

function defaultDevSizeCombo(index) {
  const defaults = [
    "M.L.XL",
    "2XL.3XL.4XL",
    "L.XL.XXL",
    "M.L.XL.XXL"
  ];

  return defaults[index] || DEFAULT_SIZE_COMBO;
}

function devKey(row) {
  return [
    row.dev_no,
    row.size_combo,
    row.sleeve,
    row.border
  ].join("|");
}

function singleRowFromInputs(old = {}) {
  const sizeCombo =
    selectValue("cmSingleSizeCombo") ||
    DEFAULT_SIZE_COMBO;

  return {
    ...old,
    lot_mode: "single",
    dev_no: "SINGLE",
    size_combo: sizeCombo,
    sizes: sizesFromText(sizeCombo),
    sleeve: selectValue("cmSingleSleeve") || "Half",
    border: selectValue("cmSingleBorder") || "Without Border",
    cutting_pcs: Math.max(
      0,
      Math.floor(numberValue("cmSingleCuttingPcs"))
    ),
    matching_consumption: numberValue("cmSingleMatchingQty"),
    matching_avg_cost: numberValue("cmSingleMatchingAvgCost"),
    custom_adjustment: Number(old.custom_adjustment || 0)
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
    comboDevRows = [
      singleRowFromInputs(
        options.keepManual
          ? existing.get("SINGLE") || {}
          : {}
      )
    ];

    return;
  }

  const count = devCount();
  const rows = [];

  for (let index = 0; index < count; index += 1) {
    const devNo = `D${index + 1}`;
    const old = options.keepManual
      ? existing.get(devNo) || {}
      : {};

    const sizeCombo =
      old.size_combo ||
      defaultDevSizeCombo(index);

    rows.push({
      ...old,
      lot_mode: "multi",
      dev_no: devNo,
      size_combo: sizeCombo,
      sizes: sizesFromText(sizeCombo),
      sleeve: old.sleeve || "Half",
      border: old.border || "Without Border",
      cutting_pcs: Number(old.cutting_pcs || 0),
      matching_consumption: Number(old.matching_consumption || 0),
      matching_avg_cost: Number(old.matching_avg_cost || 0),
      custom_adjustment: Number(old.custom_adjustment || 0)
    });
  }

  comboDevRows = rows;

  if (options.autoDistribute) {
    distributeDevPcs();
  }

  renderDevRows();
}

function renderDevRows() {
  const holder = $("cmDevRows");

  if (!holder) {
    return;
  }

  if (currentLotMode !== "multi") {
    holder.innerHTML = "";
    return;
  }

  if (!comboDevRows.length) {
    holder.innerHTML = `
      <div class="cm-empty">
        <p>No Dev cards. Select Dev Count.</p>
      </div>
    `;
    return;
  }

  holder.innerHTML = comboDevRows
    .map((row, index) => `
      <article class="cm-matrix-card" data-dev-card="${index}">
        <div class="cm-matrix-head">
          <strong>${safe(row.dev_no)}</strong>
          <span>
            ${safe(row.size_combo)} ·
            ${safe(row.sleeve)} ·
            ${safe(row.border)}
          </span>
        </div>

        <div class="cm-grid-3">
          <label>
            <span>Size Combo</span>
            <select
              class="cm-dev-size"
              data-dev-index="${index}"
            ></select>
          </label>

          <label>
            <span>Sleeve</span>
            <select
              class="cm-dev-sleeve"
              data-dev-index="${index}"
            >
              <option value="Half">Half Sleeve</option>
              <option value="Full">Full Sleeve</option>
            </select>
          </label>

                    <label>
            <span>Border</span>
            <select
              class="cm-dev-border"
              data-dev-index="${index}"
            >
              <option value="Without Border">Without Border</option>
              <option value="With Border">With Border</option>
            </select>
          </label>
        </div>

        <div class="cm-grid-3">
          <label>
            <span>Matching Cloth Qty</span>
            <input
              class="cm-dev-match-cons"
              type="number"
              min="0"
              step="0.001"
              value="${Number(row.matching_consumption || 0)}"
              data-dev-index="${index}"
            >
          </label>

          <label>
            <span>Matching Cloth Avg Cost</span>
            <input
              class="cm-dev-match-cost"
              type="number"
              min="0"
              step="0.01"
              value="${Number(row.matching_avg_cost || 0)}"
              data-dev-index="${index}"
            >
          </label>

          <label>
            <span>Cutting Pcs</span>
            <input
              class="cm-dev-pcs"
              type="number"
              min="0"
              step="1"
              value="${Number(row.cutting_pcs || 0)}"
              data-dev-index="${index}"
            >
          </label>
        </div>

        <div class="cm-grid-2">
          <label>
            <span>Custom Adjustment / Pc</span>
            <input
              class="cm-dev-custom"
              type="number"
              step="0.01"
              value="${Number(row.custom_adjustment || 0)}"
              data-dev-index="${index}"
            >
          </label>

          <label>
            <span>Dev Cost Preview</span>
            <input
              class="cm-dev-cost-preview"
              type="text"
              readonly
              value="${safe(devCostText(row))}"
            >
          </label>
        </div>
      </article>
    `)
    .join("");

  holder
    .querySelectorAll(".cm-dev-size")
    .forEach(select => {
      const index = Number(select.dataset.devIndex);

      fillSizeComboSelect(
        select,
        comboDevRows[index]?.size_combo || DEFAULT_SIZE_COMBO
      );

      select.addEventListener("change", () => {
        updateDevRowFromInput(select, {
          resetMatrix: true
        });
      });
    });

  holder
    .querySelectorAll(".cm-dev-sleeve")
    .forEach(select => {
      const index = Number(select.dataset.devIndex);
      select.value = comboDevRows[index]?.sleeve || "Half";

      select.addEventListener("change", () => {
        updateDevRowFromInput(select, {
          resetMatrix: true
        });
      });
    });

  holder
    .querySelectorAll(".cm-dev-border")
    .forEach(select => {
      const index = Number(select.dataset.devIndex);
      select.value = comboDevRows[index]?.border || "Without Border";

      select.addEventListener("change", () => {
        updateDevRowFromInput(select, {
          resetMatrix: true
        });
      });
    });

  holder
    .querySelectorAll("[data-dev-index]")
    .forEach(input => {
      if (
        input.classList.contains("cm-dev-size") ||
        input.classList.contains("cm-dev-sleeve") ||
        input.classList.contains("cm-dev-border")
      ) {
        return;
      }

      input.addEventListener("input", () => {
        updateDevRowFromInput(input);
      });
    });

  updatePieceTotals();
}

function updateDevRowFromInput(input, options = {}) {
  const index = Number(input.dataset.devIndex);
  const row = comboDevRows[index];

  if (!row) {
    return;
  }

  if (input.classList.contains("cm-dev-size")) {
    row.size_combo = input.value || DEFAULT_SIZE_COMBO;
    row.sizes = sizesFromText(row.size_combo);
  }

  if (input.classList.contains("cm-dev-sleeve")) {
    row.sleeve = input.value || "Half";
  }

  if (input.classList.contains("cm-dev-border")) {
    row.border = input.value || "Without Border";
  }

  if (input.classList.contains("cm-dev-match-cons")) {
    row.matching_consumption = Number(input.value || 0);
  }

  if (input.classList.contains("cm-dev-match-cost")) {
    row.matching_avg_cost = Number(input.value || 0);
  }

  if (input.classList.contains("cm-dev-pcs")) {
    row.cutting_pcs = Math.max(
      0,
      Math.floor(Number(input.value || 0))
    );

    clearMatrixMemoryForDev(row.dev_no);
  }

  if (input.classList.contains("cm-dev-custom")) {
    row.custom_adjustment = Number(input.value || 0);
  }

  if (options.resetMatrix) {
    clearMatrixMemoryForDev(row.dev_no);
    renderDevRows();
    renderCuttingMatrix();
  } else {
    const card = input.closest("[data-dev-card]");
    const preview = card?.querySelector(".cm-dev-cost-preview");

    if (preview) {
      preview.value = devCostText(row);
    }
  }

  updatePieceTotals();
  updateCostPreview();
}

function distributeDevPcs() {
  if (currentLotMode !== "multi") {
    return;
  }

  const total = Math.max(
    0,
    Math.floor(numberValue("cmParentCuttingPcs"))
  );

  if (!comboDevRows.length || total <= 0) {
    return;
  }

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
    if (key.startsWith(`${devNo}|`)) {
      matrixQtyMemory.delete(key);
    }
  });
}

function sizeFactorForCombo(row) {
  if (row.lot_mode !== "multi") {
    return 0;
  }

  const combo = String(row.size_combo || "").toUpperCase();

  if (SMALL_SIZE_COMBOS.has(combo)) {
    return -5;
  }

  if (BIG_SIZE_COMBOS.has(combo)) {
    return 5;
  }

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

function matchingCostFor(row) {
  return Number(row.matching_consumption || 0) *
    Number(row.matching_avg_cost || 0);
}

function devCost(row) {
  const base = Number(readArtAverageCost() || 0);

  const perPiece =
    base +
    sizeFactorForCombo(row) +
    sleeveFactorFor(row) +
    borderFactorFor(row) +
    Number(row.custom_adjustment || 0);

  const matchingTotal = matchingCostFor(row);
  const pcs = Number(row.cutting_pcs || 0);

  const matchingPerPiece =
    pcs > 0
      ? matchingTotal / pcs
      : 0;

  return {
    base,
    perPiece,
    matchingTotal,
    matchingPerPiece,
    finalPerPiece: perPiece + matchingPerPiece,
    total:
      perPiece * pcs +
      matchingTotal
  };
}

function devCostText(row) {
  const cost = devCost(row);

  return `${money(cost.finalPerPiece)} / pc · ${money(cost.total)}`;
}

function matrixInputs() {
  return [
    ...($("cuttingMatrix")?.querySelectorAll(".cm-size-qty") || [])
  ];
}

function parseSizes() {
  if (comboDevRows.length) {
    return [
      ...new Set(
        comboDevRows.flatMap(row => row.sizes)
      )
    ];
  }

  return sizesFromText(DEFAULT_SIZE_COMBO);
}

function matrixColours() {
  if (!activeCard) return [];

  const list = coloursFor(activeCard.group.cb_id);

  if (list.length) return list;

  return [
    {
      id: "",
      colour_name: "Default Colour",
      image_url: "",
      colour_order: 1
    }
  ];
}

function matrixKey(dev, colour, size) {
  return [
    dev.dev_no,
    colour.id || colour.colour_name || "",
    size
  ].join("|");
}

function autoQtyForCell(dev, colourIndex, sizeIndex, colourCount) {
  const sizeCount = dev.sizes.length || 1;
  const totalCells = Math.max(1, colourCount * sizeCount);

  const pcs = Math.max(
    0,
    Math.floor(Number(dev.cutting_pcs || 0))
  );

  const base = Math.floor(pcs / totalCells);
  const remainder = pcs - base * totalCells;

  const flatIndex = colourIndex * sizeCount + sizeIndex;
  const lastIndex = totalCells - 1;

  return base + (flatIndex === lastIndex ? remainder : 0);
}

function renderCuttingMatrix() {
  const holder = $("cuttingMatrix");

  if (!holder || !activeCard) return;

  const colours = matrixColours();

  if (!comboDevRows.length) {
    buildComboDevRows({
      keepManual: true,
      autoDistribute: true
    });
  }

  holder.innerHTML = comboDevRows
    .map((dev, devIndex) => {
      return `
        <article class="cm-matrix-card">
          <div class="cm-matrix-head">
            <strong>${safe(dev.dev_no)}</strong>
            <span>
              ${safe(dev.size_combo)} ·
              ${safe(dev.sleeve)} ·
              ${safe(dev.border)}
            </span>
          </div>

          ${colours
            .map((colour, colourIndex) => {
              const colourName =
                colour.colour_name ||
                colour.color_name ||
                "Colour";

              return `
                <div class="cm-matrix-card">
                  <div class="cm-matrix-head">
                    ${
                      colour.image_url
                        ? `
                          <img
                            src="${safe(colour.image_url)}"
                            alt="${safe(colourName)}"
                          >
                        `
                        : `<strong>●</strong>`
                    }

                    <strong>${safe(colourName)}</strong>
                  </div>

                  <div class="cm-size-grid">
                    ${dev.sizes
                      .map((size, sizeIndex) => {
                        const key = matrixKey(dev, colour, size);

                        const qty = matrixQtyMemory.has(key)
                          ? matrixQtyMemory.get(key)
                          : autoQtyForCell(
                              dev,
                              colourIndex,
                              sizeIndex,
                              colours.length
                            );

                        return `
                          <label>
                            <span>${safe(size)}</span>

                            <input
                              class="cm-size-qty"
                              type="number"
                              min="0"
                              step="1"
                              value="${qty || ""}"
                              data-dev-index="${devIndex}"
                              data-dev-no="${safe(dev.dev_no)}"
                              data-size-combo="${safe(dev.size_combo)}"
                              data-sleeve="${safe(dev.sleeve)}"
                              data-border="${safe(dev.border)}"
                              data-colour-id="${safe(colour.id || "")}"
                              data-colour-name="${safe(colourName)}"
                              data-size="${safe(size)}"
                              data-matrix-key="${safe(key)}"
                            >
                          </label>
                        `;
                      })
                      .join("")}
                  </div>
                </div>
              `;
            })
            .join("")}
        </article>
      `;
    })
    .join("");

  matrixInputs().forEach(input => {
    input.addEventListener("input", () => {
      matrixQtyMemory.set(
        input.dataset.matrixKey,
        Math.max(
          0,
          Math.floor(Number(input.value || 0))
        )
      );

      updatePieceTotals();
      updateCostPreview();
    });
  });

  updatePieceTotals();
}

function cuttingEntries() {
  return matrixInputs()
    .map(input => {
      const devIndex = Number(input.dataset.devIndex);
      const dev = comboDevRows[devIndex] || {};

      return {
        dev_no: input.dataset.devNo || dev.dev_no || "",
        lot_mode: dev.lot_mode || currentLotMode,
        size_combo: input.dataset.sizeCombo || dev.size_combo || "",
        sleeve: input.dataset.sleeve || dev.sleeve || "",
        border: input.dataset.border || dev.border || "",
        colour_id: input.dataset.colourId || null,
        colour_name: input.dataset.colourName || "",
        size_name: input.dataset.size || "",
        quantity: Math.max(
          0,
          Math.floor(Number(input.value || 0))
        )
      };
    })
    .filter(row => row.quantity > 0);
}

function updatePieceTotals() {
  const pieces = cuttingEntries().reduce(
    (sum, row) => sum + row.quantity,
    0
  );

  if ($("totalPieces")) {
    $("totalPieces").textContent = String(pieces);
  }

  if ($("totalBundles")) {
    $("totalBundles").textContent = String(pieces);
  }

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
    const total = comboDevRows.reduce(
      (sum, row) => sum + devCost(row).total,
      0
    );

    const pcs = Number(
      $("totalPieces")?.textContent || 0
    );

    const final =
      pcs > 0
        ? total / pcs
        : 0;

    return {
      base: Number(readArtAverageCost() || 0),
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

  if (el) {
    el.textContent = money(value);
  }
}

function updateCostPreview() {
  const result = costResult();

  setMoneyText("sizeCostPreview", 0);
  setMoneyText("sleeveCostPreview", 0);
  setMoneyText("borderCostPreview", 0);
  setMoneyText("finalCostPreview", result.final);
  setMoneyText("totalCostPreview", result.total);

  setMoneyText("costBasePreview", result.base);
  setMoneyText("costAdjustmentPreview", result.adjustmentTotal);
  setMoneyText("costPerPiecePreview", result.final);
  setMoneyText("costTotalPreview", result.total);
}

// ===== REDZED CUTTING MASTER PM CORE PART 3 END =====

 // ===== REDZED CUTTING MASTER PM CORE PART 4 START =====

function validateLot() {
  if (!activeCard) {
    throw new Error("No Product Master card selected.");
  }

  const decision = cardDecision(activeCard);

  if (!decision.ready) {
    throw new Error("Art decision missing.");
  }

  const lotNo = readText("lotNo");

  if (!lotNo) {
    throw new Error("Lot No required.");
  }

  const styleName = readText("styleName");

  if (!styleName) {
    throw new Error("Style name required.");
  }

  const entries = cuttingEntries();

  const totalPieces = entries.reduce(
    (sum, row) => sum + row.quantity,
    0
  );

  if (totalPieces <= 0) {
    throw new Error("Colour × Size cutting quantity required.");
  }

  return {
    decision,
    lotNo,
    styleName,
    sizes: parseSizes(),
    entries,
    totalPieces
  };
}

function lotPayload(valid) {
  const cost = costResult();

  const notes = [
    readText("lotNotes"),
    readText("operatorName")
      ? `Operator: ${readText("operatorName")}`
      : ""
  ]
    .filter(Boolean)
    .join("\n");

  return {
    cb_unit_id: activeCard.division.division_id,
    cb_id: activeCard.group.cb_id,

    lot_no: valid.lotNo,
    lot_date: readText("lotDate") || today(),

    style_name: valid.styleName,
    art_no: valid.decision.artNo,
    print_no: valid.decision.printNo,

    size_set: valid.sizes,
    planned_pcs: valid.totalPieces,
    bundle_qty: 1,

    base_cost_per_piece: cost.base,
    adjustment_cost_per_piece: cost.adjustmentTotal,
    final_cost_per_piece: cost.final,
    total_cutting_cost: cost.total,

    adjustments: cost.adjustments,
    remarks: notes || null,

    status: "released"
  };
}

function breakupPayloads(lotId, valid) {
  return valid.entries.map(row => ({
    lot_id: lotId,
    cb_unit_id: activeCard.division.division_id,

    colour_id: row.colour_id,
    colour_name: row.colour_name,
    size_name: row.size_name,

    quantity: row.quantity,
    bundle_qty: 1,
    bundle_count: row.quantity
  }));
}

async function createLot(event = {}) {
  event?.preventDefault?.();

  const client = getClient();

  if (!client) {
    say("Supabase client unavailable.", "error");
    return;
  }

  if (createLot.busy) {
    return;
  }

  createLot.busy = true;

  const button =
    event.submitter ||
    $("lotForm")?.querySelector('button[type="submit"]') ||
    $("lotForm")?.querySelector("button");

  try {
    if (button) {
      button.disabled = true;
      button.textContent = "Releasing Lot...";
    }

    say("Cutting Lot save हो रहा है...", "info");

    const valid = validateLot();
    const payload = lotPayload(valid);

    const duplicate = await client
      .from("rr_cutting_lots_v3")
      .select("id, lot_no")
      .eq("lot_no", payload.lot_no)
      .maybeSingle();

    if (duplicate.error) {
      throw duplicate.error;
    }

    if (duplicate.data) {
      throw new Error(
        `Lot No ${payload.lot_no} already exists.`
      );
    }

    const insertedLot = await client
      .from("rr_cutting_lots_v3")
      .insert(payload)
      .select("*")
      .single();

    if (insertedLot.error) {
      throw insertedLot.error;
    }

    const lot = insertedLot.data;

    const insertedBreakup = await client
      .from("rr_cutting_breakup_v3")
      .insert(breakupPayloads(lot.id, valid))
      .select("*");

    if (insertedBreakup.error) {
      await client
        .from("rr_cutting_lots_v3")
        .delete()
        .eq("id", lot.id);

      throw insertedBreakup.error;
    }

    lotRows.unshift(lot);
    breakupRows.unshift(...(insertedBreakup.data || []));

    closeSheet(lotSheet);
    activeCard = null;

    renderGallery();

    say(
      `Lot ${lot.lot_no} released successfully.`,
      "success"
    );
  } catch (error) {
    console.error(error);
    say(errorText(error), "error");
  } finally {
    createLot.busy = false;

    if (button) {
      button.disabled = false;
      button.textContent = "Release Lot";
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
    costSettings.default_base_cost
  );

  if ($("customAdjustment")) {
    $("customAdjustment").disabled =
      costSettings.allow_custom_adjustment === false;
  }
}

async function loadAllData() {
  const client = getClient();

  if (!client) {
    throw new Error(
      "Supabase client unavailable. Check config.js."
    );
  }

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

  const [
    loadedGalleryRows,
    purchaseResult,
    colourResult,
    artResult,
    loadedPrintRows,
    assignmentResult,
    printAssignmentResult,
    loadedMediaRows,
    lotResult,
    breakupResult
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

    optionalRows(client, "rr_media"),

    selectRows(client, "rr_cutting_lots_v3", {
      order: "created_at",
      ascending: false
    }),

    selectRows(client, "rr_cutting_breakup_v3", {
      order: "created_at",
      ascending: false
    })
  ]);

  galleryRows = loadedGalleryRows || [];
  purchaseRows = requiredData(purchaseResult, "Purchase rows");
  colourRows = requiredData(colourResult, "Colour rows");
  artRows = requiredData(artResult, "Art Master");
  printRows = loadedPrintRows || [];
  assignmentRows = requiredData(assignmentResult, "Art assignments");
  printAssignmentRows = requiredData(
    printAssignmentResult,
    "Print assignments"
  );
  mediaRows = loadedMediaRows || [];
  lotRows = requiredData(lotResult, "Cutting lots");
  breakupRows = requiredData(breakupResult, "Cutting breakup");

  await loadCostSettings(client);

  renderGallery();

  console.info("REDZED Cutting Master PM Core loaded", {
    galleryRows: galleryRows.length,
    purchaseRows: purchaseRows.length,
    colourRows: colourRows.length,
    artRows: artRows.length,
    printRows: printRows.length,
    assignmentRows: assignmentRows.length,
    printAssignmentRows: printAssignmentRows.length,
    mediaRows: mediaRows.length,
    lotRows: lotRows.length,
    breakupRows: breakupRows.length
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
  $("lotForm")?.addEventListener(
    "submit",
    createLot
  );

  $("lotForm")
    ?.querySelectorAll("button")
    .forEach(button => {
      const text = String(
        button.textContent || ""
      ).toLowerCase();

      if (!text.includes("release")) {
        return;
      }

      button.addEventListener("click", event => {
        event.preventDefault();

        createLot({
          preventDefault() {},
          submitter: button
        });
      });
    });

  $("cmSearch")?.addEventListener(
    "input",
    renderGallery
  );

  $("sizeSet")?.addEventListener(
    "change",
    renderCuttingMatrix
  );

  $("sizeSet")?.addEventListener(
    "blur",
    renderCuttingMatrix
  );

  [
    "fabricUsed",
    "wastageWeight",
    "remnantWeight"
  ].forEach(id => {
    $(id)?.addEventListener(
      "input",
      updateWeightSettlement
    );
  });

  [
    "baseCost",
    "customAdjustment"
  ].forEach(id => {
    $(id)?.addEventListener(
      "input",
      updateCostPreview
    );
  });

  [
    "sizeType",
    "sleeveType",
    "borderType"
  ].forEach(id => {
    $(id)?.addEventListener(
      "change",
      updateCostPreview
    );
  });

  $("refreshCutting")?.addEventListener(
    "click",
    refreshCuttingMaster
  );

  $("cmFilters")
    ?.querySelectorAll("[data-filter]")
    .forEach(button => {
      button.addEventListener("click", () => {
        currentFilter =
          button.dataset.filter ||
          "all";

        $("cmFilters")
          ?.querySelectorAll("[data-filter]")
          .forEach(item => {
            item.classList.toggle(
              "is-active",
              item === button
            );
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

  $("splitForm")?.addEventListener(
    "submit",
    event => {
      event.preventDefault();

      say(
        "Multi combo next phase में connect होगा. अभी Single Lot locked है.",
        "info"
      );
    }
  );

  $("costSettingsForm")?.addEventListener(
    "submit",
    event => {
      event.preventDefault();

      say(
        "Cost settings currently loaded from database. Save phase later connect होगा.",
        "info"
      );
    }
  );
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
  version: "pm-core-v1-u1",

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
      breakupRows,
      currentFilter,
      activeCard
    };
  },

  refresh: refreshCuttingMaster
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

// ===== REDZED CUTTING MASTER PM CORE PART 4 END =====
