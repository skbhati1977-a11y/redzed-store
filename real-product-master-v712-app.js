(() => {
"use strict";

window.REDZED_PRODUCT_MASTER_BOOTED = true;
window.REDZED_PRODUCT_MASTER_VERSION = "712";

const $ = id => document.getElementById(id);

const sheet = $("newCbSheet");
const form = $("newCbForm");
const gallery = $("cbGallery");
const message = $("pmMessage");

let categories = [];
let galleryRows = [];
let purchaseRows = [];
let colourRows = [];
let currentFilter = "all";
let colourFiles = new Map();
let dataReady = false;

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function safe(value) {
  if (
    typeof RR !== "undefined" &&
    typeof RR.safeText === "function"
  ) {
    return RR.safeText(value ?? "");
  }
  return escapeHtml(value);
}

function money(value) {
  if (
    typeof RR !== "undefined" &&
    typeof RR.money === "function"
  ) {
    return RR.money(Number(value || 0));
  }

  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2
  }).format(Number(value || 0));
}

function localToday() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function say(text, type = "") {
  message.textContent = text || "";
  message.className = `rr-message ${type}`.trim();
}

function openSheet() {
  if (!dataReady || !categories.length) {
    say("Material categories are not ready. Press Refresh and try again.", "error");
    return;
  }

  sheet.classList.remove("pm-hidden");
  sheet.setAttribute("aria-hidden", "false");
  document.body.classList.add("pm-no-scroll");
  window.setTimeout(() => $("cbNo").focus(), 80);
}

function closeSheet() {
  sheet.classList.add("pm-hidden");
  sheet.setAttribute("aria-hidden", "true");
  document.body.classList.remove("pm-no-scroll");
}

function materialOptions(selectedId = "", selectedCode = "regular-cloth") {
  return categories.map(category => {
    const selected =
      selectedId
        ? String(category.id) === String(selectedId)
        : category.category_code === selectedCode;

    return `
      <option value="${safe(category.id)}" ${selected ? "selected" : ""}>
        ${safe(category.category_name)}
      </option>
    `;
  }).join("");
}

function regularCategoryId() {
  return categories.find(
    category => category.category_code === "regular-cloth"
  )?.id || "";
}

function updateBillRowAmount(row) {
  const quantity = Number(row.querySelector(".bill-qty").value || 0);
  const rate = Number(row.querySelector(".bill-rate").value || 0);
  const amountNode = row.querySelector(".pm-bill-amount strong");
  if (amountNode) {
    amountNode.textContent = money(quantity * rate);
  }
  updateBillSummary();
}

function addBill(data = {}) {
  const row = document.createElement("article");
  row.className = "pm-bill-row";

  row.innerHTML = `
    <label>
      <span>Vendor *</span>
      <input
        class="bill-vendor"
        type="text"
        placeholder="Vendor name"
        value="${safe(data.vendor_name || "")}"
      >
    </label>

    <label>
      <span>Bill No *</span>
      <input
        class="bill-no"
        type="text"
        placeholder="Bill number"
        value="${safe(data.vendor_bill_no || "")}"
      >
    </label>

    <label>
      <span>Bill Date *</span>
      <input
        class="bill-date"
        type="date"
        value="${safe(data.bill_date || localToday())}"
      >
    </label>

    <label>
      <span>Material *</span>
      <select class="bill-material">
        ${materialOptions(
          data.material_category_id || "",
          data.category_code || "regular-cloth"
        )}
      </select>
    </label>

    <label>
      <span>Qty *</span>
      <input
        class="bill-qty"
        type="number"
        inputmode="decimal"
        min="0.001"
        step="0.001"
        placeholder="Qty"
        value="${data.quantity ?? ""}"
      >
    </label>

    <label>
      <span>Rate *</span>
      <input
        class="bill-rate"
        type="number"
        inputmode="decimal"
        min="0.0001"
        step="0.0001"
        placeholder="Rate"
        value="${data.rate ?? ""}"
      >
    </label>

    <div class="pm-bill-amount">
      <small>Bill Amount</small>
      <strong>${money(Number(data.quantity || 0) * Number(data.rate || 0))}</strong>
    </div>

    <button class="pm-remove-bill" type="button">Remove Bill</button>
  `;

  row.querySelector(".pm-remove-bill").onclick = () => {
    row.remove();
    updateBillSummary();
  };

  [
    row.querySelector(".bill-qty"),
    row.querySelector(".bill-rate"),
    row.querySelector(".bill-material")
  ].forEach(input => {
    input.addEventListener("input", () => updateBillRowAmount(row));
    input.addEventListener("change", () => updateBillRowAmount(row));
  });

  $("billRows").appendChild(row);
  updateBillRowAmount(row);
}

function getBills() {
  return [...$("billRows").querySelectorAll(".pm-bill-row")]
    .map(row => ({
      vendor_name: row.querySelector(".bill-vendor").value.trim(),
      vendor_bill_no: row.querySelector(".bill-no").value.trim(),
      bill_date: row.querySelector(".bill-date").value || localToday(),
      material_category_id: row.querySelector(".bill-material").value,
      quantity: Number(row.querySelector(".bill-qty").value || 0),
      rate: Number(row.querySelector(".bill-rate").value || 0)
    }))
    .filter(row =>
      row.vendor_name ||
      row.vendor_bill_no ||
      row.quantity ||
      row.rate
    );
}

function updateBillSummary() {
  if (!categories.length) return;

  const regularId = String(regularCategoryId());
  const regularBills = getBills().filter(
    row => String(row.material_category_id) === regularId
  );

  const quantity = regularBills.reduce(
    (sum, row) => sum + row.quantity,
    0
  );

  const amount = regularBills.reduce(
    (sum, row) => sum + (row.quantity * row.rate),
    0
  );

  $("billSummary").innerHTML = `
    <span>
      <small>Regular Bill Qty</small>
      <strong>${quantity.toFixed(3)} kg</strong>
    </span>
    <span>
      <small>Regular Bill Amount</small>
      <strong>${money(amount)}</strong>
    </span>
  `;
}

function collectColourNames() {
  const result = new Map();

  $("colourSlots")
    .querySelectorAll(".pm-colour-slot")
    .forEach(slot => {
      result.set(
        Number(slot.dataset.index),
        slot.querySelector(".pm-colour-name").value.trim()
      );
    });

  return result;
}

function renderColourSlots() {
  const count = Math.max(1, Number($("colourCount").value || 1));
  const oldNames = collectColourNames();

  for (const [index, entry] of [...colourFiles.entries()]) {
    if (index >= count) {
      if (entry.url) URL.revokeObjectURL(entry.url);
      colourFiles.delete(index);
    }
  }

  $("colourSlots").innerHTML = Array.from(
    { length: count },
    (_, index) => {
      const existing = colourFiles.get(index);
      const preview = existing?.url
        ? `<img src="${safe(existing.url)}" alt="Colour ${index + 1}">`
        : `<span>＋</span>`;

      return `
        <article class="pm-colour-slot" data-index="${index}">
          <div class="pm-colour-preview">${preview}</div>

          <input
            class="pm-colour-name"
            type="text"
            placeholder="Colour ${index + 1} name"
            value="${safe(oldNames.get(index) || "")}"
          >

          <div class="pm-colour-actions">
            <label>
              📷 Camera
              <input
                class="pm-colour-camera"
                type="file"
                accept="image/*"
                capture="environment"
              >
            </label>

            <label>
              🖼 Gallery
              <input
                class="pm-colour-gallery"
                type="file"
                accept="image/jpeg,image/png,image/webp"
              >
            </label>
          </div>
        </article>
      `;
    }
  ).join("");

  $("colourSlots")
    .querySelectorAll(".pm-colour-slot")
    .forEach(slot => {
      const index = Number(slot.dataset.index);

      slot.querySelectorAll('input[type="file"]').forEach(input => {
        input.onchange = () => {
          const file = input.files?.[0];
          if (!file) return;

          if (!file.type.startsWith("image/")) {
            say(`Colour ${index + 1}: select an image file.`, "error");
            input.value = "";
            return;
          }

          const previous = colourFiles.get(index);
          if (previous?.url) URL.revokeObjectURL(previous.url);

          const url = URL.createObjectURL(file);

          colourFiles.set(index, {
            file,
            url,
            sourceType: input.classList.contains("pm-colour-camera")
              ? "camera"
              : "gallery"
          });

          slot.querySelector(".pm-colour-preview").innerHTML =
            `<img src="${safe(url)}" alt="Colour ${index + 1}">`;
        };
      });
    });
}

function updateRegularPreview() {
  const quantity = Number($("regularQty").value || 0);
  const amount = Number($("regularAmount").value || 0);
  const divisions = Math.max(1, Number($("divisionCount").value || 1));

  $("avgRatePreview").textContent = quantity
    ? `${money(amount / quantity)}/kg`
    : "₹0/kg";

  $("divisionPreview").textContent =
    `${(quantity / divisions).toFixed(3)} kg`;
}

function clearColourFiles() {
  colourFiles.forEach(entry => {
    if (entry.url) URL.revokeObjectURL(entry.url);
  });
  colourFiles.clear();
}

function resetForm() {
  form.reset();
  $("divisionCount").value = "3";
  $("colourCount").value = "6";
  $("billRows").innerHTML = "";
  clearColourFiles();
  addBill({ category_code: "regular-cloth" });
  renderColourSlots();
  updateRegularPreview();
  updateBillSummary();
}

function normalizeGalleryRow(row) {
  return {
    ...row,
    cb_id: row.cb_id,
    cb_no: row.cb_no || "",
    division_id: row.division_id || row.id,
    division_code: row.division_code || "",
    division_status: row.division_status || row.status || "planning",
    allocated_qty: Number(
      row.allocated_qty ??
      row.regular_allocated_qty ??
      row.quantity ??
      0
    ),
    allocated_amount: Number(
      row.allocated_amount ??
      row.regular_allocated_amount ??
      row.amount ??
      0
    ),
    lot_no: row.lot_no || "",
    created_at: row.created_at || ""
  };
}

async function loadGallerySource() {
  const viewResult = await supabaseClient
    .from("rr_product_gallery_view")
    .select("*");

  if (!viewResult.error) {
    return (viewResult.data || []).map(normalizeGalleryRow);
  }

  console.warn(
    "rr_product_gallery_view unavailable; using table fallback.",
    viewResult.error
  );

  const [divisionResult, purchaseResult] = await Promise.all([
    supabaseClient.from("rr_cb_units").select("*"),
    supabaseClient.from("rr_fabric_purchases").select("*")
  ]);

  if (divisionResult.error) throw divisionResult.error;
  if (purchaseResult.error) throw purchaseResult.error;

  const purchaseMap = new Map(
    (purchaseResult.data || []).map(row => [String(row.id), row])
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
    const purchase = purchaseMap.get(String(division.purchase_id)) || {};

    return normalizeGalleryRow({
      ...division,
      cb_id: division.purchase_id,
      division_id: division.id,
      division_code: division.cb_code || "",
      division_status: statusMap[division.status] || "planning",
      allocated_qty: Number(division.divided_weight || 0),
      allocated_amount: Number(division.divided_amount || 0),
      cb_no: purchase.cb_no || division.cb_base_no || "",
      created_at: division.created_at || purchase.created_at || ""
    });
  });
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

  for (const row of galleryRows) {
    const key = String(row.cb_id);

    if (!groups.has(key)) {
      groups.set(key, {
        cb_id: row.cb_id,
        cb_no: row.cb_no,
        status: row.division_status || "planning",
        created_at: row.created_at || "",
        divisionMap: new Map()
      });
    }

    const group = groups.get(key);
    const divisionKey = String(row.division_id || row.division_code);

    if (!group.divisionMap.has(divisionKey)) {
      group.divisionMap.set(divisionKey, row);
    }

    const currentPriority = statusPriority[group.status] || 0;
    const nextPriority = statusPriority[row.division_status] || 0;

    if (nextPriority > currentPriority) {
      group.status = row.division_status;
    }

    if (!group.created_at && row.created_at) {
      group.created_at = row.created_at;
    }
  }

  return [...groups.values()]
    .map(group => {
      const divisions = [...group.divisionMap.values()]
        .sort((a, b) =>
          String(a.division_code).localeCompare(
            String(b.division_code),
            undefined,
            { numeric: true }
          )
        );

      return {
        ...group,
        divisions,
        quantity: divisions.reduce(
          (sum, row) => sum + Number(row.allocated_qty || 0),
          0
        ),
        amount: divisions.reduce(
          (sum, row) => sum + Number(row.allocated_amount || 0),
          0
        )
      };
    })
    .sort((a, b) => {
      const dateCompare = String(b.created_at).localeCompare(
        String(a.created_at)
      );
      if (dateCompare) return dateCompare;

      return String(b.cb_no).localeCompare(
        String(a.cb_no),
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

function divisionLabel(group, division) {
  const fullCode = String(division.division_code || "");
  const prefix = `${group.cb_no} `;

  if (group.cb_no && fullCode.startsWith(prefix)) {
    return fullCode.slice(prefix.length);
  }

  return fullCode || "Division";
}

function renderGallery() {
  const query = $("pmSearch").value.trim().toLowerCase();

  const groups = groupGalleryRows().filter(group => {
    const purchases = purchasesFor(group.cb_id);
    const colours = coloursFor(group.cb_id);

    const searchText = [
      group.cb_no,
      ...group.divisions.map(row =>
        `${row.division_code || ""} ${row.lot_no || ""}`
      ),
      ...purchases.map(row =>
        `${row.vendor_name || ""} ${row.vendor_bill_no || ""}`
      ),
      ...colours.map(row => row.colour_name || "")
    ].join(" ").toLowerCase();

    let filterMatches = currentFilter === "all";

    if (currentFilter === "purchase") {
      filterMatches = purchases.length > 0;
    } else if (currentFilter !== "all") {
      filterMatches = group.status === currentFilter;
    }

    return filterMatches && searchText.includes(query);
  });

  gallery.setAttribute("aria-busy", "false");

  if (!groups.length) {
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <div class="pm-empty-icon">＋</div>
        <h3>No CB found</h3>
        <p>Create a new cloth purchase or change the search/filter.</p>
      </article>
    `;
    return;
  }

  gallery.innerHTML = groups.map(group => {
    const purchases = purchasesFor(group.cb_id);
    const colours = coloursFor(group.cb_id);

    const colourHtml = colours.length
      ? colours.map(colour => {
          const name = colour.colour_name || `Colour ${colour.colour_order}`;
          const icon = colour.image_url
            ? `<img src="${safe(colour.image_url)}" alt="${safe(name)}" loading="lazy">`
            : `<i class="pm-colour-fallback">C</i>`;

          return `<span>${icon}${safe(name)}</span>`;
        }).join("")
      : `<span><i class="pm-colour-fallback">C</i>Colour images pending</span>`;

    const divisionHtml = group.divisions.map(division => `
      <button type="button" disabled title="Division details will open in V703">
        ${safe(divisionLabel(group, division))}
      </button>
    `).join("");

    return `
      <article class="pm-cb-card">
        <div class="pm-card-top">
          <div>
            <span class="pm-status status-${safe(group.status)}">
              ${safe(String(group.status).replaceAll("_", " "))}
            </span>
            <h3>${safe(group.cb_no)}</h3>
            <p>
              ${group.divisions.length}
              Division${group.divisions.length === 1 ? "" : "s"}
              ·
              ${colours.length}
              Colour${colours.length === 1 ? "" : "s"}
            </p>
          </div>
        </div>

        <div class="pm-card-colours">${colourHtml}</div>

        <div class="pm-card-metrics">
          <span>
            <small>Regular Qty</small>
            <strong>${group.quantity.toFixed(3)} kg</strong>
          </span>
          <span>
            <small>Amount</small>
            <strong>${money(group.amount)}</strong>
          </span>
        </div>

        <div class="pm-division-preview">${divisionHtml}</div>

        <div class="pm-card-footer">
          <span>
            ${purchases.length}
            Bill Entr${purchases.length === 1 ? "y" : "ies"}
          </span>
          <button type="button" disabled>Open in V703</button>
        </div>
      </article>
    `;
  }).join("");
}

async function loadData() {
  const refreshButton = $("refreshCb");
  const newCbButton = $("openNewCb");

  refreshButton.disabled = true;
  refreshButton.textContent = "Loading…";
  newCbButton.disabled = true;
  gallery.setAttribute("aria-busy", "true");

  try {
    const [
      categoryResult,
      loadedGalleryRows,
      purchaseResult,
      colourResult
    ] = await Promise.all([
      supabaseClient
        .from("rr_material_categories")
        .select("*")
        .eq("is_active", true)
        .order("sort_order"),

      loadGallerySource(),

      supabaseClient
        .from("rr_cb_purchase_entries")
        .select("*")
        .order("created_at", { ascending: false }),

      supabaseClient
        .from("rr_cb_colours")
        .select("*")
        .order("colour_order")
    ]);

    if (categoryResult.error) throw categoryResult.error;
    if (purchaseResult.error) throw purchaseResult.error;
    if (colourResult.error) throw colourResult.error;

    categories = categoryResult.data || [];
    galleryRows = loadedGalleryRows || [];
    purchaseRows = purchaseResult.data || [];
    colourRows = colourResult.data || [];

    if (!categories.length) {
      throw new Error("No active material categories were found.");
    }

    dataReady = true;
    newCbButton.disabled = false;
    renderGallery();
  } catch (error) {
    dataReady = false;
    gallery.setAttribute("aria-busy", "false");
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <h3>Product Master could not load</h3>
        <p>${safe(error.message || "Unknown loading error")}</p>
      </article>
    `;
    throw error;
  } finally {
    refreshButton.disabled = false;
    refreshButton.textContent = "Refresh";
  }
}

function normalizeRpcId(data) {
  const raw = Array.isArray(data) ? data[0] : data;

  if (typeof raw === "string") return raw;

  return (
    raw?.id ||
    raw?.cb_id |
