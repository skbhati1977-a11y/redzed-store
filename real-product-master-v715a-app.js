(() => {
"use strict";

window.REDZED_PRODUCT_MASTER_BOOTED = true;
window.REDZED_PRODUCT_MASTER_VERSION = "715A";

const $ = id => document.getElementById(id);
const purchaseSheet = $("purchaseSheet");
const detailSheet = $("cbDetailSheet");
const artSheet = $("artAssignmentSheet");
const purchaseForm = $("purchaseForm");
const gallery = $("cbGallery");
const message = $("pmMessage");
const purchaseMessage = $("purchaseMessage");

let categories = [];
let galleryRows = [];
let purchaseRows = [];
let colourRows = [];
let rollRows = [];
let allocationRows = [];
let artRows = [];
let printRows = [];
let printAssignmentRows = [];
let assignmentRows = [];
let mediaRows = [];
let currentFilter = "all";
let dataReady = false;

let formMode = "create";
let activeCbId = null;
let activeDetailCbId = null;
let entrySequence = 0;
let formEntries = [];
let cbColourDrafts = [];
let activeArtDivisionId = null;
let selectedArtId = null;
let selectedPrintIds = [];
let cardColumnCount = Number(localStorage.getItem("redzedProductCardColumns") || 3);

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function safe(value) {
  if (typeof RR !== "undefined" && typeof RR.safeText === "function") {
    return RR.safeText(value ?? "");
  }
  return escapeHtml(value);
}

function money(value) {
  if (typeof RR !== "undefined" && typeof RR.money === "function") {
    return RR.money(Number(value || 0));
  }
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2
  }).format(Number(value || 0));
}

function qty(value) {
  return `${Number(value || 0).toFixed(3)} kg`;
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

function formatSaveError(error) {
  const parts = [
    error?.message,
    error?.details,
    error?.hint,
    error?.code ? `Code: ${error.code}` : ""
  ].filter(Boolean);
  return [...new Set(parts.map(part => String(part).trim()).filter(Boolean))].join(" — ")
    || "Purchase could not be saved.";
}

function showPurchaseMessage(text = "", type = "") {
  if (!purchaseMessage) return;
  purchaseMessage.textContent = text;
  purchaseMessage.className = `pm-save-message ${text ? "" : "pm-hidden"} ${type ? `is-${type}` : ""}`.trim();
}

function categoryById(id) {
  return categories.find(item => String(item.id) === String(id)) || null;
}

function categoryByCode(code) {
  return categories.find(item => item.category_code === code) || null;
}

function materialName(entry) {
  return categoryById(entry.materialCategoryId)?.category_name || "Material";
}

function getSelectedDivisionCount() {
  const value = $("divisionCount").value;
  if (value === "custom") {
    return Math.max(1, Math.min(50, Number($("customDivisionCount").value || 0)));
  }
  return Math.max(1, Number(value || 2));
}

function currentDivisionChoices() {
  if (formMode === "append") {
    return groupFor(activeCbId)?.divisions.map(row => ({
      index: Number(row.division_index || 0),
      id: row.division_id,
      label: row.division_code || `S${row.division_index}`
    })) || [];
  }

  return Array.from({ length: getSelectedDivisionCount() }, (_, index) => ({
    index: index + 1,
    id: null,
    label: `S${index + 1}`
  }));
}

function currentColourCount() {
  if (formMode === "append") return cbColourDrafts.length;
  return Math.max(1, Math.min(12, Number($("colourCount").value || 1)));
}

function defaultRollRowCount() {
  return Math.max(1, currentDivisionChoices().length || getSelectedDivisionCount());
}

function makeColourRollDraft(rollCount = defaultRollRowCount()) {
  return {
    rolls: Array.from({ length: Math.max(1, rollCount) }, () => ({ quantity: "" })),
    autoRollTemplate: true
  };
}

function isEmptyRollDraft(roll) {
  const raw = String(roll?.quantity ?? "").trim();
  return raw === "" || Number(raw) <= 0;
}

function syncAutoRollRows(colour, targetCount = defaultRollRowCount()) {
  if (!colour) return;
  if (!Array.isArray(colour.rolls) || !colour.rolls.length) {
    colour.rolls = [{ quantity: "" }];
  }

  // Once + Add Roll or × Remove is used, preserve that colour's uneven roll count.
  if (colour.autoRollTemplate === false) return;

  const target = Math.max(1, Number(targetCount || 1));
  while (colour.rolls.length < target) {
    colour.rolls.push({ quantity: "" });
  }

  // Never delete a row containing quantity when Division count is reduced.
  while (colour.rolls.length > target) {
    let removableIndex = -1;
    for (let index = colour.rolls.length - 1; index >= 1; index -= 1) {
      if (isEmptyRollDraft(colour.rolls[index])) {
        removableIndex = index;
        break;
      }
    }
    if (removableIndex < 0) break;
    colour.rolls.splice(removableIndex, 1);
  }
}

function syncAllAutoRollRows() {
  const target = defaultRollRowCount();
  formEntries.forEach(entry => {
    entry.colours.forEach(colour => syncAutoRollRows(colour, target));
  });
}

function ensureColourDrafts(count) {
  while (cbColourDrafts.length < count) {
    cbColourDrafts.push({
      name: "",
      imageUrl: "",
      mediaId: null,
      file: null,
      objectUrl: "",
      sourceType: "gallery",
      persistedId: null
    });
  }

  while (cbColourDrafts.length > count) {
    const removed = cbColourDrafts.pop();
    if (removed?.objectUrl) URL.revokeObjectURL(removed.objectUrl);
  }

  const defaultRows = defaultRollRowCount();
  formEntries.forEach(entry => {
    while (entry.colours.length < count) {
      entry.colours.push(makeColourRollDraft(defaultRows));
    }
    while (entry.colours.length > count) entry.colours.pop();
    entry.colours.forEach(colour => syncAutoRollRows(colour, defaultRows));
  });
}

function makeEntry({ regularLocked = false, categoryCode = null } = {}) {
  const defaultCategory = categoryCode
    ? categoryByCode(categoryCode)
    : categories.find(item => item.category_code !== "regular-cloth") || categories[0];

  return {
    key: `entry-${++entrySequence}`,
    regularLocked,
    materialCategoryId: defaultCategory?.id || "",
    vendorName: "",
    fabricName: "",
    billNo: "",
    billDate: localToday(),
    rate: "",
    allocationScope: "all",
    selectedDivisionIndexes: currentDivisionChoices().map(item => item.index),
    colours: Array.from(
      { length: currentColourCount() },
      () => makeColourRollDraft(defaultRollRowCount())
    )
  };
}

function clearDraftImages() {
  cbColourDrafts.forEach(item => {
    if (item.objectUrl) URL.revokeObjectURL(item.objectUrl);
  });
  cbColourDrafts = [];
}

function openSheet(sheet) {
  sheet.classList.remove("pm-hidden");
  sheet.setAttribute("aria-hidden", "false");
  document.body.classList.add("pm-no-scroll");
}

function closeSheet(sheet) {
  sheet.classList.add("pm-hidden");
  sheet.setAttribute("aria-hidden", "true");
  if (purchaseSheet.classList.contains("pm-hidden") && detailSheet.classList.contains("pm-hidden") && artSheet.classList.contains("pm-hidden")) {
    document.body.classList.remove("pm-no-scroll");
  }
}

function materialOptions(selectedId, locked) {
  return categories.map(category => {
    const selected = String(category.id) === String(selectedId);
    return `<option value="${safe(category.id)}" ${selected ? "selected" : ""}>${safe(category.category_name)}</option>`;
  }).join("");
}

function renderDivisionSelection(entry) {
  const choices = currentDivisionChoices();
  const selected = new Set(entry.selectedDivisionIndexes.map(Number));

  return `
    <div class="pm-allocation-box">
      <label><span>Material Allocation *</span></label>
      <div class="pm-allocation-row">
        <label class="pm-radio-chip">
          <input type="radio" name="scope-${entry.key}" value="all" ${entry.allocationScope === "all" ? "checked" : ""}>
          All Divisions
        </label>
        <label class="pm-radio-chip">
          <input type="radio" name="scope-${entry.key}" value="selected" ${entry.allocationScope === "selected" ? "checked" : ""}>
          Selected Divisions
        </label>
      </div>
      <div class="pm-selected-divisions ${entry.allocationScope === "selected" ? "" : "pm-hidden"}">
        ${choices.map(choice => `
          <label class="pm-check-chip">
            <input type="checkbox" value="${choice.index}" ${selected.has(choice.index) ? "checked" : ""}>
            ${safe(choice.label)}
          </label>
        `).join("")}
      </div>
    </div>
  `;
}

function colourPreview(index) {
  const colour = cbColourDrafts[index] || {};
  const source = colour.objectUrl || colour.imageUrl;
  return source
    ? `<img src="${safe(source)}" alt="${safe(colour.name || `Colour ${index + 1}`)}">`
    : `<span>＋</span>`;
}

function renderRolls(entry, colourIndex) {
  const rolls = entry.colours[colourIndex]?.rolls || [];
  return rolls.map((roll, rollIndex) => `
    <div class="pm-roll-row" data-roll-index="${rollIndex}">
      <b>Roll ${rollIndex + 1}</b>
      <input class="pm-roll-qty" type="number" inputmode="decimal" min="0" step="0.001" placeholder="Qty kg" value="${safe(roll.quantity)}">
      ${rollIndex > 0
        ? `<button class="pm-remove-roll" type="button" aria-label="Remove Roll ${rollIndex + 1}">×</button>`
        : `<span class="pm-roll-remove-spacer" aria-hidden="true"></span>`}
    </div>
  `).join("");
}

function renderColourCard(entry, entryIndex, colourIndex) {
  const draft = cbColourDrafts[colourIndex] || {};
  const isIdentitySource = formMode === "create" && entryIndex === 0;
  const displayName = draft.name || `Colour ${colourIndex + 1}`;

  return `
    <article class="pm-material-colour-card" data-colour-index="${colourIndex}">
      <div class="pm-colour-card-head">
        <div class="pm-colour-thumb">${colourPreview(colourIndex)}</div>
        <div class="pm-colour-main">
          ${isIdentitySource ? `
            <input class="pm-colour-name" type="text" placeholder="Colour ${colourIndex + 1} name" value="${safe(draft.name || "")}">
            <div class="pm-image-actions">
              <label>📷 Camera<input class="pm-colour-camera" type="file" accept="image/*" capture="environment"></label>
              <label>🖼 Gallery<input class="pm-colour-gallery" type="file" accept="image/jpeg,image/png,image/webp"></label>
            </div>
          ` : `
            <strong>${safe(displayName)}</strong>
            <small class="pm-muted-copy">Enter only the rolls used for this material.</small>
          `}
        </div>
      </div>

      <div class="pm-roll-list">${renderRolls(entry, colourIndex)}</div>
      <button class="pm-add-roll" type="button">+ Add Roll</button>
    </article>
  `;
}

function renderEntry(entry, entryIndex) {
  const canRemove = !(formMode === "create" && entryIndex === 0);
  const locked = entry.regularLocked;

  return `
    <article class="pm-purchase-entry" data-entry-key="${safe(entry.key)}">
      <div class="pm-purchase-entry-head">
        <h4>Purchase ${entryIndex + 1}</h4>
        ${canRemove ? `<button class="pm-remove-entry" type="button">Remove</button>` : ""}
      </div>

      <div class="pm-entry-fields">
        <label>
          <span>Material *</span>
          <select class="pm-material-select ${locked ? "pm-locked-material" : ""}" ${locked ? "disabled" : ""}>
            ${materialOptions(entry.materialCategoryId, locked)}
          </select>
        </label>

        <label>
          <span>Vendor Name *</span>
          <input class="pm-vendor-name" type="text" placeholder="Vendor name" value="${safe(entry.vendorName)}">
        </label>

        <label>
          <span>Fabric Name *</span>
          <input class="pm-fabric-name" type="text" placeholder="Fabric name" value="${safe(entry.fabricName)}">
        </label>

        <label>
          <span>Bill No *</span>
          <input class="pm-bill-no" type="text" placeholder="Bill number" value="${safe(entry.billNo)}">
        </label>

        <label>
          <span>Bill Date *</span>
          <input class="pm-bill-date" type="date" value="${safe(entry.billDate)}">
        </label>

        <label>
          <span>Rate / kg *</span>
          <input class="pm-rate" type="number" inputmode="decimal" min="0.0001" step="0.0001" placeholder="Rate" value="${safe(entry.rate)}">
        </label>
      </div>

      ${renderDivisionSelection(entry)}

      <div class="pm-material-colours">
        ${entry.colours.map((_, colourIndex) => renderColourCard(entry, entryIndex, colourIndex)).join("")}
      </div>
    </article>
  `;
}

function bindEntryEvents(entry, entryIndex, node) {
  const bindValue = (selector, key) => {
    const input = node.querySelector(selector);
    if (!input) return;
    const eventName = input.tagName === "SELECT" ? "change" : "input";
    input.addEventListener(eventName, () => {
      entry[key] = input.value;
      updateGrandSummary();
    });
  };

  bindValue(".pm-material-select", "materialCategoryId");
  bindValue(".pm-vendor-name", "vendorName");
  bindValue(".pm-fabric-name", "fabricName");
  bindValue(".pm-bill-no", "billNo");
  bindValue(".pm-bill-date", "billDate");
  bindValue(".pm-rate", "rate");

  node.querySelector(".pm-remove-entry")?.addEventListener("click", () => {
    formEntries = formEntries.filter(item => item.key !== entry.key);
    renderPurchaseEntries();
  });

  node.querySelectorAll(`input[name="scope-${entry.key}"]`).forEach(input => {
    input.addEventListener("change", () => {
      entry.allocationScope = input.value;
      if (entry.allocationScope === "all") {
        entry.selectedDivisionIndexes = currentDivisionChoices().map(item => item.index);
      }
      renderPurchaseEntries();
    });
  });

  const selectedBox = node.querySelector(".pm-selected-divisions");
  selectedBox?.querySelectorAll('input[type="checkbox"]').forEach(input => {
    input.addEventListener("change", () => {
      const selected = [...selectedBox.querySelectorAll('input[type="checkbox"]:checked')]
        .map(item => Number(item.value));
      entry.selectedDivisionIndexes = selected;
    });
  });

  node.querySelectorAll(".pm-material-colour-card").forEach(colourNode => {
    const colourIndex = Number(colourNode.dataset.colourIndex);

    colourNode.querySelector(".pm-colour-name")?.addEventListener("input", event => {
      cbColourDrafts[colourIndex].name = event.target.value;
    });

    colourNode.querySelectorAll('input[type="file"]').forEach(input => {
      input.addEventListener("change", () => {
        const file = input.files?.[0];
        if (!file) return;
        if (!file.type.startsWith("image/")) {
          say(`Colour ${colourIndex + 1}: select an image file.`, "error");
          input.value = "";
          return;
        }

        const draft = cbColourDrafts[colourIndex];
        if (draft.objectUrl) URL.revokeObjectURL(draft.objectUrl);
        draft.file = file;
        draft.objectUrl = URL.createObjectURL(file);
        draft.sourceType = input.classList.contains("pm-colour-camera") ? "camera" : "gallery";
        renderPurchaseEntries();
      });
    });

    colourNode.querySelectorAll(".pm-roll-row").forEach(rollNode => {
      const rollIndex = Number(rollNode.dataset.rollIndex);
      const rollInput = rollNode.querySelector(".pm-roll-qty");
      rollInput.addEventListener("input", () => {
        entry.colours[colourIndex].rolls[rollIndex].quantity = rollInput.value;
        updateGrandSummary();
      });

      rollNode.querySelector(".pm-remove-roll")?.addEventListener("click", () => {
        if (rollIndex === 0) return;
        const colour = entry.colours[colourIndex];
        colour.rolls.splice(rollIndex, 1);
        colour.autoRollTemplate = false;
        if (!colour.rolls.length) colour.rolls.push({ quantity: "" });
        renderPurchaseEntries();
      });
    });

    colourNode.querySelector(".pm-add-roll").addEventListener("click", () => {
      const colour = entry.colours[colourIndex];
      colour.rolls.push({ quantity: "" });
      colour.autoRollTemplate = false;
      renderPurchaseEntries();
    });
  });
}

function renderPurchaseEntries() {
  ensureColourDrafts(currentColourCount());
  const container = $("purchaseEntries");
  container.innerHTML = formEntries.map(renderEntry).join("");
  container.querySelectorAll(".pm-purchase-entry").forEach((node, index) => {
    bindEntryEvents(formEntries[index], index, node);
  });
  updateGrandSummary();
}

function entryRolls(entry) {
  const result = [];
  entry.colours.forEach((colour, colourIndex) => {
    colour.rolls.forEach((roll, rollIndex) => {
      const quantity = Number(roll.quantity || 0);
      if (quantity > 0) {
        result.push({
          colourIndex,
          rollNo: rollIndex + 1,
          quantity
        });
      }
    });
  });
  return result;
}

function entryQuantity(entry) {
  return entryRolls(entry).reduce((sum, roll) => sum + roll.quantity, 0);
}

function updateGrandSummary() {
  const totalQty = formEntries.reduce((sum, entry) => sum + entryQuantity(entry), 0);
  const totalAmount = formEntries.reduce(
    (sum, entry) => sum + entryQuantity(entry) * Number(entry.rate || 0),
    0
  );
  $("grandQty").textContent = qty(totalQty);
  $("grandAmount").textContent = money(totalAmount);
}

function resetCreateForm() {
  showPurchaseMessage();
  formMode = "create";
  activeCbId = null;
  entrySequence = 0;
  clearDraftImages();
  purchaseForm.reset();
  $("divisionCount").value = "2";
  $("colourCount").value = "6";
  $("customDivisionWrap").classList.add("pm-hidden");
  $("newCbIdentityCard").classList.remove("pm-hidden");
  $("existingCbContext").classList.add("pm-hidden");
  $("purchaseSheetKicker").textContent = "CB Purchase";
  $("purchaseSheetTitle").textContent = "New CB";
  $("savePurchaseBtn").textContent = "Create CB";
  $("cbRemarks").value = "";
  ensureColourDrafts(6);
  formEntries = [makeEntry({ regularLocked: true, categoryCode: "regular-cloth" })];
  renderPurchaseEntries();
}

function openCreateForm() {
  if (!dataReady || !categories.length) {
    say("Product Master data is not ready. Press Refresh and try again.", "error");
    return;
  }
  resetCreateForm();
  openSheet(purchaseSheet);
  window.setTimeout(() => $("cbNo").focus(), 80);
}

function openAppendForm(cbId) {
  showPurchaseMessage();
  const group = groupFor(cbId);
  if (!group) return;

  formMode = "append";
  activeCbId = cbId;
  entrySequence = 0;
  clearDraftImages();

  const existingColours = coloursFor(cbId);
  if (!existingColours.length) {
    say(`${group.cb_no}: colour records are missing.`, "error");
    return;
  }

  cbColourDrafts = existingColours.map(colour => ({
    name: colour.colour_name,
    imageUrl: colour.image_url || "",
    mediaId: colour.media_id || null,
    file: null,
    objectUrl: "",
    sourceType: "gallery",
    persistedId: colour.id
  }));

  $("newCbIdentityCard").classList.add("pm-hidden");
  $("existingCbContext").classList.remove("pm-hidden");
  $("existingCbName").textContent = group.cb_no;
  $("existingCbMeta").textContent = `${group.divisions.length} Divisions · ${cbColourDrafts.length} Colours`;
  $("purchaseSheetKicker").textContent = "Add Material Purchase";
  $("purchaseSheetTitle").textContent = group.cb_no;
  $("savePurchaseBtn").textContent = "Save Purchase";
  $("cbRemarks").value = "";

  formEntries = [makeEntry({ regularLocked: false, categoryCode: "cuff-collar" })];
  renderPurchaseEntries();
  closeSheet(detailSheet);
  openSheet(purchaseSheet);
}

function validateEntries() {
  if (!formEntries.length) throw new Error("Add at least one material purchase.");

  if (formMode === "create") {
    const regularId = categoryByCode("regular-cloth")?.id;
    if (!regularId || String(formEntries[0].materialCategoryId) !== String(regularId)) {
      throw new Error("First purchase must be Regular Cloth.");
    }
  }

  formEntries.forEach((entry, index) => {
    const number = index + 1;
    if (!entry.materialCategoryId) throw new Error(`Purchase ${number}: select Material.`);
    if (!entry.vendorName.trim()) throw new Error(`Purchase ${number}: enter Vendor Name.`);
    if (!entry.fabricName.trim()) throw new Error(`Purchase ${number}: enter Fabric Name.`);
    if (!entry.billNo.trim()) throw new Error(`Purchase ${number}: enter Bill No.`);
    if (!entry.billDate) throw new Error(`Purchase ${number}: select Bill Date.`);
    if (Number(entry.rate || 0) <= 0) throw new Error(`Purchase ${number}: enter Rate.`);
    if (entryQuantity(entry) <= 0) throw new Error(`Purchase ${number}: enter colour-wise roll quantity.`);

    if (entry.allocationScope === "selected" && !entry.selectedDivisionIndexes.length) {
      throw new Error(`Purchase ${number}: select at least one Division.`);
    }
  });

  if (formMode === "create") {
    cbColourDrafts.forEach((colour, index) => {
      if (!colour.name.trim()) throw new Error(`Enter Colour ${index + 1} name.`);
      if (!colour.file) throw new Error(`Select Colour ${index + 1} image.`);
      const colourQty = formEntries[0].colours[index].rolls.reduce(
        (sum, roll) => sum + Number(roll.quantity || 0),
        0
      );
      if (colourQty <= 0) {
        throw new Error(`Regular Cloth: enter roll quantity for ${colour.name.trim() || `Colour ${index + 1}`}.`);
      }
    });
  }
}

function selectedDivisionIds(entry, divisions) {
  const selectedIndexes = entry.allocationScope === "all"
    ? divisions.map(item => Number(item.division_index))
    : entry.selectedDivisionIndexes.map(Number);

  return divisions
    .filter(item => selectedIndexes.includes(Number(item.division_index)))
    .map(item => item.division_id || item.id);
}

function normalizeRpcId(data) {
  const raw = Array.isArray(data) ? data[0] : data;
  if (typeof raw === "string") return raw;
  return raw?.id || raw?.cb_id || raw?.rr_create_cb_v713 || raw?.result || null;
}

function normalizeMedia(result) {
  if (result?.error) throw result.error;
  let raw = result?.data ?? result;
  if (Array.isArray(raw)) raw = raw[0] || null;
  return raw || null;
}

async function uploadColourMedia(cbPurchaseId, index, name) {
  const draft = cbColourDrafts[index];
  if (!draft?.file) throw new Error(`Colour ${index + 1} image is missing.`);

  const result = await RR.uploadMedia({
    file: draft.file,
    entityType: "cb",
    entityId: cbPurchaseId,
    mediaCategory: "colour",
    sourceType: draft.sourceType,
    visibilityScope: "factory",
    caption: name
  });

  const media = normalizeMedia(result);
  if (!media) throw new Error(`Colour ${index + 1} image upload returned no result.`);
  return media;
}

async function insertPurchaseEntry(cbPurchaseId, entry, divisions, colours, entryNotes = null, skipAllocation = false) {
  const totalQuantity = entryQuantity(entry);
  const payload = {
    cb_id: cbPurchaseId,
    vendor_name: entry.vendorName.trim(),
    vendor_bill_no: entry.billNo.trim(),
    bill_date: entry.billDate,
    material_category_id: entry.materialCategoryId,
    fabric_name: entry.fabricName.trim(),
    allocation_scope: entry.allocationScope,
    entry_notes: entryNotes,
    quantity: Number(totalQuantity.toFixed(3)),
    rate: Number(entry.rate)
  };

  const { data, error } = await supabaseClient
    .from("rr_cb_purchase_entries")
    .insert(payload)
    .select("*")
    .single();

  if (error) throw error;

  const rolls = entryRolls(entry).map(roll => ({
    purchase_entry_id: data.id,
    cb_colour_id: colours[roll.colourIndex].id,
    roll_no: roll.rollNo,
    quantity: Number(roll.quantity.toFixed(3))
  }));

  if (rolls.length) {
    const { error: rollError } = await supabaseClient
      .from("rr_cb_purchase_rolls")
      .insert(rolls);
    if (rollError) throw rollError;
  }

  if (!skipAllocation) {
    const divisionIds = selectedDivisionIds(entry, divisions);
    if (!divisionIds.length) throw new Error("No division selected for material allocation.");

    const { error: allocationError } = await supabaseClient
      .rpc("rr_allocate_cb_purchase_entry", {
        p_purchase_entry_id: data.id,
        p_division_ids: divisionIds
      });

    if (allocationError) throw allocationError;
  }

  return data;
}

async function rollbackCreatedCb(cbPurchaseId, uploadedMedia) {
  const failures = [];
  async function attempt(label, action) {
    try {
      const result = await action();
      if (result?.error) throw result.error;
    } catch (error) {
      failures.push(`${label}: ${error.message || error}`);
    }
  }

  await attempt("purchase entries", () =>
    supabaseClient.from("rr_cb_purchase_entries").delete().eq("cb_id", cbPurchaseId)
  );
  await attempt("colour rows", () =>
    supabaseClient.from("rr_cb_colours").delete().eq("cb_id", cbPurchaseId)
  );
  await attempt("division rows", () =>
    supabaseClient.from("rr_cb_units").delete().eq("purchase_id", cbPurchaseId)
  );
  await attempt("fabric purchase", () =>
    supabaseClient.from("rr_fabric_purchases").delete().eq("id", cbPurchaseId)
  );

  if (typeof RR !== "undefined" && typeof RR.deleteMedia === "function") {
    for (const media of [...uploadedMedia].reverse()) {
      await attempt("uploaded media", () => RR.deleteMedia(media));
    }
  }
  return failures;
}

async function rollbackAppendedEntries(entryIds) {
  if (!entryIds.length) return [];
  const { error } = await supabaseClient
    .from("rr_cb_purchase_entries")
    .delete()
    .in("id", entryIds);
  return error ? [error.message || String(error)] : [];
}

async function saveCreateMode() {
  const cbNo = $("cbNo").value.trim().toUpperCase();
  const divisionCount = getSelectedDivisionCount();
  const colourCount = currentColourCount();
  const regularEntry = formEntries[0];
  const regularQuantity = entryQuantity(regularEntry);
  const regularAmount = regularQuantity * Number(regularEntry.rate);
  const regularRolls = entryRolls(regularEntry).length;
  const uploadedMedia = [];
  let cbPurchaseId = null;

  if (!cbNo) throw new Error("Enter CB No.");
  if ($("divisionCount").value === "custom" && !Number($("customDivisionCount").value || 0)) {
    throw new Error("Enter Custom Division count.");
  }
  if (divisionCount < 1 || divisionCount > 50) {
    throw new Error("Division count must be between 1 and 50.");
  }

  try {
    showPurchaseMessage("Creating CB identity and divisions…", "progress");
    const { data: rpcData, error: cbError } = await supabaseClient
      .rpc("rr_create_cb_v713", {
        p_cb_no: cbNo,
        p_division_count: divisionCount,
        p_colour_count: colourCount,
        p_regular_qty: Number(regularQuantity.toFixed(3)),
        p_regular_amount: Number(regularAmount.toFixed(2)),
        p_total_rolls: regularRolls,
        p_fabric_name: regularEntry.fabricName.trim(),
        p_regular_division_indexes: regularEntry.allocationScope === "all"
          ? currentDivisionChoices().map(item => item.index)
          : regularEntry.selectedDivisionIndexes.map(Number),
        p_remarks: $("cbRemarks").value.trim() || null
      });

    if (cbError) throw cbError;
    cbPurchaseId = normalizeRpcId(rpcData);
    if (!cbPurchaseId) throw new Error("CB was created but its ID was not returned.");

    const { data: divisionData, error: divisionError } = await supabaseClient
      .from("rr_cb_units")
      .select("*")
      .eq("purchase_id", cbPurchaseId)
      .order("division_index");
    if (divisionError) throw divisionError;

    const mediaByIndex = [];
    for (let index = 0; index < colourCount; index++) {
      showPurchaseMessage(`Uploading colour image ${index + 1} of ${colourCount}…`, "progress");
      const media = await uploadColourMedia(cbPurchaseId, index, cbColourDrafts[index].name.trim());
      uploadedMedia.push(media);
      mediaByIndex[index] = media;
    }

    const colourPayload = cbColourDrafts.map((draft, index) => {
      const media = mediaByIndex[index];
      return {
        cb_id: cbPurchaseId,
        colour_order: index + 1,
        colour_name: draft.name.trim(),
        suggested_colour_name: null,
        image_url: media?.file_url || media?.public_url || media?.url || null,
        media_id: media?.id || media?.media_id || null,
        is_confirmed: true
      };
    });

    showPurchaseMessage("Saving colour cards…", "progress");
    const { data: createdColours, error: colourError } = await supabaseClient
      .from("rr_cb_colours")
      .insert(colourPayload)
      .select("*")
      .order("colour_order");
    if (colourError) throw colourError;

    const divisions = (divisionData || []).map(row => ({
      ...row,
      division_id: row.id
    }));

    for (let entryIndex = 0; entryIndex < formEntries.length; entryIndex += 1) {
      showPurchaseMessage(`Saving purchase ${entryIndex + 1} of ${formEntries.length}…`, "progress");
      const entry = formEntries[entryIndex];
      await insertPurchaseEntry(
        cbPurchaseId,
        entry,
        divisions,
        createdColours,
        null,
        entryIndex === 0
      );
    }

    return { cbNo, cbPurchaseId };
  } catch (error) {
    if (cbPurchaseId) {
      const failures = await rollbackCreatedCb(cbPurchaseId, uploadedMedia);
      if (failures.length) {
        error.message = `${error.message} Automatic cleanup was incomplete; check Supabase records.`;
      }
    }
    throw error;
  }
}

async function saveAppendMode() {
  const group = groupFor(activeCbId);
  if (!group) throw new Error("CB could not be found.");

  const colours = coloursFor(activeCbId);
  const divisions = group.divisions;
  const insertedIds = [];

  try {
    for (const entry of formEntries) {
      const saved = await insertPurchaseEntry(
        activeCbId,
        entry,
        divisions,
        colours,
        $("cbRemarks").value.trim() || null
      );
      insertedIds.push(saved.id);
    }
    return { cbNo: group.cb_no, cbPurchaseId: activeCbId };
  } catch (error) {
    const failures = await rollbackAppendedEntries(insertedIds);
    if (failures.length) {
      error.message = `${error.message} Automatic cleanup was incomplete; check Supabase records.`;
    }
    throw error;
  }
}

purchaseForm.addEventListener("submit", async event => {
  event.preventDefault();
  const button = $("savePurchaseBtn");
  const originalLabel = button.textContent;
  button.disabled = true;
  button.textContent = "Saving…";
  say("");
  showPurchaseMessage("Checking entries…", "progress");

  try {
    if (
      typeof RR === "undefined" ||
      typeof RR.requireOwner !== "function" ||
      (formMode === "create" && typeof RR.uploadMedia !== "function")
    ) {
      throw new Error("real-common.js owner/media helpers are not available.");
    }

    await ensureOwnerAccess();
    validateEntries();

    const result = await withTimeout(
      formMode === "create" ? saveCreateMode() : saveAppendMode(),
      120000,
      formMode === "create" ? "CB save" : "Material purchase save"
    );

    showPurchaseMessage(
      formMode === "create"
        ? `CB ${result.cbNo} created successfully.`
        : `${result.cbNo} material purchase added successfully.`,
      "success"
    );

    closeSheet(purchaseSheet);
    say(
      formMode === "create"
        ? `CB ${result.cbNo} created successfully.`
        : `${result.cbNo} material purchase added successfully.`,
      "success"
    );

    try {
      await loadData();
    } catch (refreshError) {
      console.error("Saved, but refresh failed:", refreshError);
      say(`Saved successfully. Refresh warning: ${formatSaveError(refreshError)}`, "error");
    }
  } catch (error) {
    console.error("CB save failed:", error);
    const text = formatSaveError(error);
    showPurchaseMessage(text, "error");
    say(text, "error");
    if (navigator.vibrate) navigator.vibrate(120);
  } finally {
    button.disabled = false;
    button.textContent = originalLabel;
  }
});

function normalizeGalleryRow(row) {
  return {
    ...row,
    cb_id: row.cb_id,
    cb_no: row.cb_no || "",
    division_id: row.division_id || row.id,
    division_index: Number(row.division_index || 0),
    division_code: row.division_code || row.cb_code || "",
    division_status: row.division_status || "planning",
    allocated_qty: Number(row.allocated_qty || 0),
    allocated_amount: Number(row.allocated_amount || 0),
    base_qty: Number(row.base_qty ?? row.divided_weight ?? 0),
    base_amount: Number(row.base_amount ?? row.divided_amount ?? 0),
    created_at: row.created_at || ""
  };
}

async function loadGallerySource() {
  const viewResult = await supabaseClient
    .from("rr_product_gallery_view")
    .select("*");
  if (!viewResult.error) return (viewResult.data || []).map(normalizeGalleryRow);

  console.warn("rr_product_gallery_view unavailable; using table fallback.", viewResult.error);
  const [divisionResult, purchaseResult] = await Promise.all([
    supabaseClient.from("rr_cb_units").select("*"),
    supabaseClient.from("rr_fabric_purchases").select("*")
  ]);
  if (divisionResult.error) throw divisionResult.error;
  if (purchaseResult.error) throw purchaseResult.error;

  const purchaseMap = new Map((purchaseResult.data || []).map(row => [String(row.id), row]));
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
      cb_id: division.purchase_id,
      division_id: division.id,
      division_index: division.division_index,
      division_code: division.cb_code,
      division_status: statusMap[division.status] || "planning",
      allocated_qty: division.divided_weight,
      allocated_amount: division.divided_amount,
      base_qty: division.divided_weight,
      base_amount: division.divided_amount,
      cb_no: purchase.cb_no || division.cb_base_no,
      created_at: division.created_at || purchase.created_at
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

  galleryRows.forEach(row => {
    const key = String(row.cb_id);
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
    const divisionKey = String(row.division_id || row.division_code);
    if (!group.divisionMap.has(divisionKey)) group.divisionMap.set(divisionKey, row);

    if ((statusPriority[row.division_status] || 0) > (statusPriority[group.status] || 0)) {
      group.status = row.division_status;
    }
  });

  return [...groups.values()].map(group => {
    const divisions = [...group.divisionMap.values()].sort(
      (a, b) => Number(a.division_index || 0) - Number(b.division_index || 0)
    );
    return {
      ...group,
      divisions,
      quantity: divisions.reduce((sum, row) => sum + Number(row.allocated_qty || 0), 0),
      amount: divisions.reduce((sum, row) => sum + Number(row.allocated_amount || 0), 0)
    };
  }).sort((a, b) => {
    const dateCompare = String(b.created_at).localeCompare(String(a.created_at));
    if (dateCompare) return dateCompare;
    return String(b.cb_no).localeCompare(String(a.cb_no), undefined, { numeric: true });
  });
}

function groupFor(cbId) {
  return groupGalleryRows().find(group => String(group.cb_id) === String(cbId)) || null;
}

function purchasesFor(cbId) {
  return purchaseRows.filter(row => String(row.cb_id) === String(cbId));
}

function coloursFor(cbId) {
  return colourRows
    .filter(row => String(row.cb_id) === String(cbId))
    .sort((a, b) => Number(a.colour_order || 0) - Number(b.colour_order || 0));
}

function allocationsForDivision(divisionId) {
  return allocationRows.filter(row => String(row.division_id) === String(divisionId));
}

function purchaseById(id) {
  return purchaseRows.find(row => String(row.id) === String(id)) || null;
}

function normalizeKey(value) {
  return String(value ?? "").trim().toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function artById(id) {
  return artRows.find(row => String(row.id) === String(id)) || null;
}

function printById(id) {
  return printRows.find(row => String(row.id) === String(id)) || null;
}

function assignmentForDivision(divisionId) {
  return assignmentRows
    .filter(row => String(row.cb_id) === String(divisionId))
    .sort((a, b) => String(b.updated_at || b.created_at || "").localeCompare(String(a.updated_at || a.created_at || "")))[0] || null;
}

function assignedPrintsForDivision(divisionId) {
  const assignment = assignmentForDivision(divisionId);
  if (!assignment) return [];

  return printAssignmentRows
    .filter(row => String(row.assignment_id) === String(assignment.id))
    .sort((a, b) => Number(a.sequence_no || 0) - Number(b.sequence_no || 0))
    .map(row => printById(row.print_id))
    .filter(Boolean);
}

function selectedPrintRows() {
  return selectedPrintIds.map(id => printById(id)).filter(Boolean);
}

function mediaForEntity(entityId, kind) {
  const list = mediaRows.filter(row => String(row.entity_id) === String(entityId));
  return list.sort((a, b) => {
    const aKind = kind === "print" ? String(a.entity_type || "").toLowerCase() === "printing" : String(a.entity_type || "").toLowerCase() !== "printing";
    const bKind = kind === "print" ? String(b.entity_type || "").toLowerCase() === "printing" : String(b.entity_type || "").toLowerCase() !== "printing";
    if (aKind !== bKind) return aKind ? -1 : 1;
    if (Boolean(a.is_cover) !== Boolean(b.is_cover)) return a.is_cover ? -1 : 1;
    return Number(a.sort_order || 0) - Number(b.sort_order || 0);
  });
}

function artImageUrl(art) {
  if (!art) return "";
  return art.hero_image_url || art.image_url || art.artwork_url || art.reference_image_url || mediaForEntity(art.id, "art")[0]?.file_url || "";
}

function printImageUrl(print) {
  if (!print) return "";
  return print.artwork_url || print.garment_preview_url || print.image_url || mediaForEntity(print.id, "print")[0]?.file_url || "";
}

function carouselItemsForAssignment(art, prints = []) {
  if (!art && !prints.length) return [];
  const items = [];
  if (art) {
    items.push({
      url: artImageUrl(art),
      label: `ART ${art.art_no || ""}`,
      kind: "art"
    });
  }
  prints.forEach(print => {
    items.push({
      url: printImageUrl(print),
      label: `PRINT ${print.print_no || ""}`,
      kind: "print"
    });
  });
  return items;
}

function carouselHtml(items, instanceId, emptyLabel = "ART PHOTO") {
  if (!items.length) {
    return `<div class="pm-art-placeholder"><span>${safe(emptyLabel)}</span><small>Photo will pull from Master</small></div>`;
  }
  return `
    <div class="pm-swipe-track" data-carousel="${safe(instanceId)}">
      ${items.map((item, index) => `
        <figure class="pm-swipe-slide ${index === 0 ? "is-active" : ""}" data-slide-index="${index}">
          ${item.url
            ? `<img src="${safe(item.url)}" alt="${safe(item.label)}" loading="lazy">`
            : `<div class="pm-art-placeholder"><span>${safe(item.label)}</span><small>Photo not added in Master</small></div>`}
          <figcaption>${safe(item.label)}</figcaption>
        </figure>`).join("")}
    </div>
    ${items.length > 1 ? `
      <button class="pm-carousel-nav pm-carousel-prev" type="button" data-carousel-move="-1" aria-label="Previous photo">‹</button>
      <button class="pm-carousel-nav pm-carousel-next" type="button" data-carousel-move="1" aria-label="Next photo">›</button>
      <span class="pm-carousel-count" data-carousel-count>1/${items.length}</span>` : ""}`;
}

function bindCarousels(root) {
  root.querySelectorAll("[data-carousel-move]").forEach(button => {
    button.addEventListener("click", event => {
      event.preventDefault();
      event.stopPropagation();
      const holder = button.closest(".pm-card-hero,.pm-selected-carousel");
      const slides = [...holder.querySelectorAll(".pm-swipe-slide")];
      if (slides.length < 2) return;
      const current = Math.max(0, slides.findIndex(slide => slide.classList.contains("is-active")));
      const next = (current + Number(button.dataset.carouselMove || 1) + slides.length) % slides.length;
      slides.forEach((slide, index) => slide.classList.toggle("is-active", index === next));
      const counter = holder.querySelector("[data-carousel-count]");
      if (counter) counter.textContent = `${next + 1}/${slides.length}`;
    });
  });

  root.querySelectorAll(".pm-swipe-track").forEach(track => {
    let startX = null;
    track.addEventListener("pointerdown", event => { startX = event.clientX; });
    track.addEventListener("pointerup", event => {
      if (startX === null) return;
      const delta = event.clientX - startX;
      startX = null;
      if (Math.abs(delta) < 35) return;
      const holder = track.closest(".pm-card-hero,.pm-selected-carousel");
      holder?.querySelector(delta < 0 ? ".pm-carousel-next" : ".pm-carousel-prev")?.click();
    });
    track.addEventListener("pointercancel", () => { startX = null; });
  });
}

function divisionCards() {
  return groupGalleryRows().flatMap(group => group.divisions.map(division => ({
    group,
    division,
    assignment: assignmentForDivision(division.division_id)
  }))).sort((a, b) => {
    const dateCompare = String(b.division.created_at || b.group.created_at || "").localeCompare(String(a.division.created_at || a.group.created_at || ""));
    if (dateCompare) return dateCompare;
    return String(b.division.division_code || "").localeCompare(String(a.division.division_code || ""), undefined, { numeric: true });
  });
}

function applyCardColumns() {
  const valid = [2, 3, 4, 6];
  if (!valid.includes(cardColumnCount)) cardColumnCount = 3;
  gallery.classList.remove("pm-cols-2", "pm-cols-3", "pm-cols-4", "pm-cols-6");
  gallery.classList.add(`pm-cols-${cardColumnCount}`);
  if ($("pmCardColumns")) $("pmCardColumns").value = String(cardColumnCount);
}

function renderGallery() {
  const query = $("pmSearch").value.trim().toLowerCase();
  const cards = divisionCards().filter(({ group, division, assignment }) => {
    const art = assignment ? artById(assignment.art_id) : null;
    const assignedPrints = assignedPrintsForDivision(division.division_id);
    const purchases = purchasesFor(group.cb_id);
    const colours = coloursFor(group.cb_id);
    const searchText = [
      group.cb_no,
      division.division_code,
      art?.art_no,
      art?.product_name,
      art?.item_name,
      art?.category,
      ...assignedPrints.map(row => `${row.print_no || ""} ${row.print_name || ""}`),
      ...purchases.map(row => `${row.vendor_name || ""} ${row.vendor_bill_no || ""} ${row.fabric_name || ""}`),
      ...colours.map(row => row.colour_name || "")
    ].join(" ").toLowerCase();

    let filterMatches = currentFilter === "all";
    if (currentFilter === "purchase") filterMatches = purchases.length > 0;
    else if (currentFilter === "planning") filterMatches = !assignment;
    else if (currentFilter === "ready_for_cutting") filterMatches = Boolean(assignment);
    else if (currentFilter === "hold") filterMatches = group.status === "hold";
    return filterMatches && searchText.includes(query);
  });

  gallery.setAttribute("aria-busy", "false");
  applyCardColumns();
  if (!cards.length) {
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <div class="pm-empty-icon">＋</div>
        <h3>No CB Child found</h3>
        <p>Create a CB or change the search/filter.</p>
      </article>`;
    return;
  }

  gallery.innerHTML = cards.map(({ group, division, assignment }) => {
    const art = assignment ? artById(assignment.art_id) : null;
    const assignedPrints = assignedPrintsForDivision(division.division_id);
    const colours = coloursFor(group.cb_id);
    let items = carouselItemsForAssignment(art, assignedPrints);
    if (!items.length && !art) {
      const colourImage = colours.find(row => row.image_url)?.image_url;
      if (colourImage) items = [{ url: colourImage, label: "CB COLOUR", kind: "colour" }];
    }
    const instanceId = `division-${division.division_id}`;
    const printCaption = assignedPrints.length
      ? assignedPrints.map(row => row.print_no).filter(Boolean).join(" · ")
      : "No Print Selected";
    return `
      <article class="pm-work-card ${assignment ? "is-art-decided" : "is-art-due"}" data-open-art="${safe(division.division_id)}" tabindex="0" role="button" aria-label="${assignment ? "Change" : "Assign"} Art and Print for ${safe(division.division_code)}">
        <div class="pm-card-hero">
          ${carouselHtml(items, instanceId, art ? "ART PHOTO" : "ART DUE")}
        </div>
        <div class="pm-work-caption">
          <div class="pm-caption-id-row">
            <span><small>CB NO</small><strong>${safe(group.cb_no)}</strong></span>
            <span><small>CB CHILD</small><strong>${safe(division.division_code || `S${division.division_index}`)}</strong></span>
          </div>
          <div class="pm-caption-status-row">
            <span class="pm-progress-chip ${assignment ? "is-complete" : "is-due"}">${assignment ? "✓ Art Decided" : "Art Due"}</span>
            <span class="pm-progress-chip is-next">Cutting Due</span>
          </div>
          <h3>${art ? safe(art.art_no) : "Select Art Number"}</h3>
          <p class="pm-product-line">${safe(art?.product_name || art?.item_name || art?.category || "Art Master selection pending")}</p>
          <p class="pm-print-line"><small>PRINT</small>${safe(printCaption)}</p>
          <div class="pm-caption-metrics">
            <span><small>Qty</small><strong>${qty(division.allocated_qty)}</strong></span>
            <span><small>Amount</small><strong>${money(division.allocated_amount)}</strong></span>
          </div>
          <div class="pm-card-footer">
            <button class="pm-open-cb" type="button" data-open-parent="${safe(group.cb_id)}">CB Details</button>
            <button class="pm-assign-art" type="button" data-open-art-button="${safe(division.division_id)}">${assignment ? "Change Art & Print" : "Assign Art & Print"}</button>
          </div>
        </div>
      </article>`;
  }).join("");

  bindCarousels(gallery);
  gallery.querySelectorAll("[data-open-art]").forEach(card => {
    const open = event => {
      if (event.target.closest("button")) return;
      openArtAssignment(card.dataset.openArt);
    };
    card.addEventListener("click", open);
    card.addEventListener("keydown", event => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        openArtAssignment(card.dataset.openArt);
      }
    });
  });
  gallery.querySelectorAll("[data-open-art-button]").forEach(button => {
    button.addEventListener("click", event => {
      event.stopPropagation();
      openArtAssignment(button.dataset.openArtButton);
    });
  });
  gallery.querySelectorAll("[data-open-parent]").forEach(button => {
    button.addEventListener("click", event => {
      event.stopPropagation();
      openCbDetails(button.dataset.openParent);
    });
  });
}

function artAssignmentSay(text, type = "") {
  const node = $("artAssignmentMessage");
  node.textContent = text || "";
  node.className = `rr-message ${type}`.trim();
}

function divisionContext(divisionId) {
  for (const group of groupGalleryRows()) {
    const division = group.divisions.find(row => String(row.division_id) === String(divisionId));
    if (division) return { group, division, assignment: assignmentForDivision(divisionId) };
  }
  return null;
}

function artPickerCardHtml(art) {
  const image = artImageUrl(art);
  const selected = String(selectedArtId) === String(art.id);
  return `
    <button class="pm-art-option ${selected ? "is-selected" : ""}" type="button" data-select-art="${safe(art.id)}">
      <span class="pm-art-option-image">
        ${image ? `<img src="${safe(image)}" alt="${safe(art.art_no)}" loading="lazy">` : `<i>ART</i>`}
      </span>
      <span class="pm-art-option-copy">
        <small>ART NUMBER</small>
        <strong>${safe(art.art_no)}</strong>
        <em>${safe(art.product_name || art.item_name || art.category || "")}</em>
        <b>${safe(art.category || "Art Master")}</b>
      </span>
    </button>`;
}

function renderArtPicker() {
  const query = $("artSearch").value.trim().toLowerCase();
  const list = artRows.filter(art => {
    const haystack = [
      art.art_no,
      art.product_name,
      art.item_name,
      art.category,
      art.description
    ].join(" ").toLowerCase();
    return haystack.includes(query);
  });

  $("artPickerGrid").innerHTML = list.length
    ? list.map(artPickerCardHtml).join("")
    : `<div class="pm-art-empty">No matching Art found in Art Master.</div>`;

  $("artPickerGrid").querySelectorAll("[data-select-art]").forEach(button => {
    button.addEventListener("click", () => {
      selectedArtId = button.dataset.selectArt;
      renderArtPicker();
      renderSelectedArtPreview();
    });
  });
}

function printFrameSummary(print) {
  const frames = Array.isArray(print.frames) ? print.frames : [];
  if (frames.length) return frames.map(frame => frame.frame_no).filter(Boolean).join(" · ");
  if (Array.isArray(print.frame_labels) && print.frame_labels.length) return print.frame_labels.join(" · ");
  return "Frame details inside Print Master";
}

function printPickerCardHtml(print) {
  const image = printImageUrl(print);
  const selected = selectedPrintIds.some(id => String(id) === String(print.id));
  const colours = Number(print.design_colours ?? print.colours ?? 0);
  return `
    <button class="pm-print-option ${selected ? "is-selected" : ""}" type="button" data-select-print="${safe(print.id)}">
      <span class="pm-print-option-image">
        ${image ? `<img src="${safe(image)}" alt="${safe(print.print_no)}" loading="lazy">` : `<i>PRINT</i>`}
        ${selected ? `<b class="pm-print-selected-badge">✓ SELECTED</b>` : ""}
      </span>
      <span class="pm-print-option-copy">
        <small>PRINT NUMBER</small>
        <strong>${safe(print.print_no || "")}</strong>
        <em>${safe(print.print_name || "")}</em>
        <b>${colours > 0 ? `${colours} Colour${colours === 1 ? "" : "s"}` : "Print Master"}</b>
        <span>${safe(printFrameSummary(print))}</span>
      </span>
    </button>`;
}

function renderPrintPicker() {
  const query = $("printSearch").value.trim().toLowerCase();
  const list = printRows.filter(print => {
    if (print.is_active === false) return false;
    const frames = Array.isArray(print.frames) ? print.frames : [];
    const haystack = [
      print.print_no,
      print.print_name,
      print.short_note,
      print.notes,
      printFrameSummary(print),
      ...frames.map(frame => `${frame.frame_no || ""} ${frame.frame_status || ""}`)
    ].join(" ").toLowerCase();
    return haystack.includes(query);
  });

  $("printPickerGrid").innerHTML = list.length
    ? list.map(printPickerCardHtml).join("")
    : `<div class="pm-art-empty">No matching Print found in Print Master.</div>`;

  $("selectedPrintCount").textContent = `${selectedPrintIds.length} selected`;
  $("printPickerGrid").querySelectorAll("[data-select-print]").forEach(button => {
    button.addEventListener("click", () => {
      const id = button.dataset.selectPrint;
      const index = selectedPrintIds.findIndex(item => String(item) === String(id));
      if (index >= 0) selectedPrintIds.splice(index, 1);
      else selectedPrintIds.push(id);
      renderPrintPicker();
      renderSelectedArtPreview();
    });
  });
}

function renderSelectedArtPreview() {
  const preview = $("selectedArtPreview");
  const art = artById(selectedArtId);
  if (!art) {
    preview.classList.add("pm-hidden");
    preview.innerHTML = "";
    $("saveArtAssignment").disabled = true;
    return;
  }

  const prints = selectedPrintRows();
  const items = carouselItemsForAssignment(art, prints);
  preview.classList.remove("pm-hidden");
  preview.innerHTML = `
    <div class="pm-selected-carousel">
      ${carouselHtml(items, `selected-${art.id}`, "ART PHOTO")}
    </div>
    <div class="pm-selected-art-copy">
      <small>FINAL SELECTION</small>
      <h3>${safe(art.art_no)}</h3>
      <p>${safe(art.product_name || art.item_name || art.category || "")}</p>
      <div class="pm-linked-print-list">
        ${prints.length
          ? prints.map(print => `<span><small>PRINT</small><strong>${safe(print.print_no)}</strong><em>${safe(print.print_name || "")}</em></span>`).join("")
          : `<span class="is-empty"><strong>No Print Selected</strong><em>Save as a no-print Art when required.</em></span>`}
      </div>
      <div class="pm-fixed-flow-caption">
        <span class="pm-progress-chip is-complete">✓ Art Decided</span>
        <span class="pm-progress-chip is-next">Cutting Due</span>
      </div>
    </div>`;
  bindCarousels(preview);
  $("saveArtAssignment").disabled = false;
}

function openArtAssignment(divisionId) {
  const context = divisionContext(divisionId);
  if (!context) {
    say("CB Child not found.", "error");
    return;
  }
  activeArtDivisionId = divisionId;
  selectedArtId = context.assignment?.art_id || null;
  selectedPrintIds = assignedPrintsForDivision(divisionId).map(print => String(print.id));
  $("artAssignmentKicker").textContent = context.assignment ? "Change Art & Print" : "Assign Art & Print";
  $("artAssignmentTitle").textContent = context.division.division_code || `S${context.division.division_index}`;
  $("artCbNo").textContent = context.group.cb_no || "—";
  $("artCbChild").textContent = context.division.division_code || `S${context.division.division_index}`;
  $("artCbQty").textContent = qty(context.division.allocated_qty);
  $("artSearch").value = "";
  $("artSearch").value = "";
  $("printSearch").value = "";
  artAssignmentSay("");
  renderArtPicker();
  renderPrintPicker();
  renderSelectedArtPreview();
  openSheet(artSheet);
}

async function saveArtPrintAssignmentRecord(cbUnitId, artId, printIds) {
  const cleanPrintIds = [...new Set((printIds || []).map(String).filter(Boolean))];
  const rpc = await supabaseClient.rpc("rr_save_cb_art_print_assignment", {
    p_cb_unit_id: cbUnitId,
    p_art_id: artId,
    p_print_ids: cleanPrintIds
  });
  if (!rpc.error) return rpc.data;

  const missingRpc = String(rpc.error.code || "") === "PGRST202" || /function|rpc|schema cache/i.test(rpc.error.message || "");
  if (!missingRpc) throw rpc.error;

  console.warn("V715 RPC unavailable; using owner direct-write fallback.", rpc.error);
  const existing = assignmentForDivision(cbUnitId);
  let assignmentResult;
  if (existing) {
    assignmentResult = await supabaseClient
      .from("rr_cb_art_assignments")
      .update({ art_id: artId, status: "material_check", bypass_reason: null, bypassed_by: null, bypassed_at: null })
      .eq("id", existing.id)
      .select()
      .single();
  } else {
    assignmentResult = await supabaseClient
      .from("rr_cb_art_assignments")
      .insert({ cb_id: cbUnitId, art_id: artId, status: "material_check" })
      .select()
      .single();
  }
  if (assignmentResult.error) throw assignmentResult.error;

  const assignmentId = assignmentResult.data.id;
  const deleteResult = await supabaseClient
    .from("rr_cb_print_assignments")
    .delete()
    .eq("assignment_id", assignmentId);
  if (deleteResult.error) throw deleteResult.error;

  if (cleanPrintIds.length) {
    const insertResult = await supabaseClient
      .from("rr_cb_print_assignments")
      .insert(cleanPrintIds.map((printId, index) => ({
        assignment_id: assignmentId,
        print_id: printId,
        sequence_no: index + 1
      })));
    if (insertResult.error) throw insertResult.error;
  }

  const unitResult = await supabaseClient
    .from("rr_cb_units")
    .update({ status: "art_assigned" })
    .eq("id", cbUnitId);
  if (unitResult.error) throw unitResult.error;
  return assignmentResult.data;
}

async function saveSelectedArtAssignment() {
  if (!activeArtDivisionId || !selectedArtId) return;
  const button = $("saveArtAssignment");
  const original = button.textContent;
  button.disabled = true;
  button.textContent = "Saving…";
  artAssignmentSay("");
  try {
    const art = artById(selectedArtId);
    const prints = selectedPrintRows();
    await saveArtPrintAssignmentRecord(activeArtDivisionId, selectedArtId, selectedPrintIds);
    const printText = prints.length ? `${prints.length} Print${prints.length === 1 ? "" : "s"}` : "No Print";
    artAssignmentSay(`Art ${art?.art_no || ""} and ${printText} saved.`, "success");
    await loadData();
    closeSheet(artSheet);
    say(`Art ${art?.art_no || ""} and ${printText} decided. Cutting Due.`, "success");
  } catch (error) {
    console.error(error);
    artAssignmentSay(error.message || "Art and Print assignment could not be saved.", "error");
  } finally {
    button.disabled = !selectedArtId;
    button.textContent = original;
  }
}

function rollSummaryForPurchase(purchaseEntryId) {
  const colourMap = new Map(colourRows.map(colour => [String(colour.id), colour]));
  const grouped = new Map();

  rollRows
    .filter(row => String(row.purchase_entry_id) === String(purchaseEntryId))
    .sort((a, b) => Number(a.roll_no || 0) - Number(b.roll_no || 0))
    .forEach(row => {
      const key = String(row.cb_colour_id);
      if (!grouped.has(key)) grouped.set(key, []);
      grouped.get(key).push(row);
    });

  return [...grouped.entries()].map(([colourId, rolls]) => {
    const colour = colourMap.get(colourId);
    const rollText = rolls.map(row => `R${row.roll_no}: ${Number(row.quantity || 0).toFixed(3)}`).join(" · ");
    return `<span>${safe(colour?.colour_name || "Colour")}: ${safe(rollText)} kg</span>`;
  }).join("");
}

function renderCbDetails(cbId) {
  const group = groupFor(cbId);
  if (!group) return "<p>CB not found.</p>";
  const colours = coloursFor(cbId);
  const purchases = purchasesFor(cbId).sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)));

  const colourHtml = colours.map(colour => {
    const image = colour.image_url
      ? `<img src="${safe(colour.image_url)}" alt="${safe(colour.colour_name)}">`
      : `<i class="pm-colour-fallback">C</i>`;
    return `<span>${image}${safe(colour.colour_name)}</span>`;
  }).join("");

  const divisionHtml = group.divisions.map(division => {
    const allocations = allocationsForDivision(division.division_id);
    const assignment = assignmentForDivision(division.division_id);
    const art = assignment ? artById(assignment.art_id) : null;
    const assignedPrints = assignedPrintsForDivision(division.division_id);
    const materialChips = allocations.length
      ? allocations.map(allocation => {
          const purchase = purchaseById(allocation.purchase_entry_id);
          const category = categoryById(purchase?.material_category_id);
          return `<span>${safe(category?.category_name || "Material")} · ${qty(allocation.allocated_qty)}</span>`;
        }).join("")
      : `<span>Legacy allocation</span>`;
    const items = carouselItemsForAssignment(art, assignedPrints);

    return `
      <article class="pm-division-card ${assignment ? "is-art-decided" : ""}">
        <div class="pm-division-art-hero">
          <div class="pm-card-hero">${carouselHtml(items, `detail-${division.division_id}`, assignment ? "ART PHOTO" : "ART DUE")}</div>
        </div>
        <div class="pm-division-card-copy">
          <h4>${safe(division.division_code || `S${division.division_index}`)}</h4>
          <div class="pm-caption-status-row">
            <span class="pm-progress-chip ${assignment ? "is-complete" : "is-due"}">${assignment ? "✓ Art Decided" : "Art Due"}</span>
            <span class="pm-progress-chip is-next">Cutting Due</span>
          </div>
          <p class="pm-detail-art-no">${art ? `ART ${safe(art.art_no)}` : "Select Art Number"}</p>
          <p class="pm-detail-print-no">PRINT ${assignedPrints.length ? safe(assignedPrints.map(row => row.print_no).filter(Boolean).join(" · ")) : "No Print Selected"}</p>
          <div class="pm-division-card-metrics">
            <span><small>Total Qty</small><strong>${qty(division.allocated_qty)}</strong></span>
            <span><small>Total Amount</small><strong>${money(division.allocated_amount)}</strong></span>
          </div>
          <div class="pm-material-chip-list">${materialChips}</div>
          <button class="pm-assign-art pm-detail-assign" type="button" data-detail-art="${safe(division.division_id)}">${assignment ? "Change Art & Print" : "Assign Art & Print"}</button>
        </div>
      </article>`;
  }).join("");

  const historyHtml = purchases.length
    ? purchases.map(purchase => {
        const category = categoryById(purchase.material_category_id);
        return `
          <article class="pm-history-card">
            <div class="pm-history-card-head">
              <div>
                <h4>${safe(category?.category_name || "Material")}</h4>
                <p>${safe(purchase.fabric_name || "Fabric not recorded")} · ${safe(purchase.vendor_name)}</p>
                <p>Bill ${safe(purchase.vendor_bill_no)} · ${safe(purchase.bill_date)} · ${safe(purchase.allocation_scope || "all")} divisions</p>
              </div>
              <strong>${money(purchase.amount)}</strong>
            </div>
            <p>${qty(purchase.quantity)} × ${money(purchase.rate)}/kg</p>
            <div class="pm-roll-summary">${rollSummaryForPurchase(purchase.id) || "<span>Roll details not recorded</span>"}</div>
          </article>`;
      }).join("")
    : `<p class="pm-muted-copy">No purchase entry found.</p>`;

  return `
    <section class="pm-detail-summary">
      <span><small>Total Qty</small><strong>${qty(group.quantity)}</strong></span>
      <span><small>Total Amount</small><strong>${money(group.amount)}</strong></span>
    </section>

    <section class="pm-detail-section">
      <h3>Colours</h3>
      <div class="pm-detail-colours">${colourHtml || "No colours"}</div>
    </section>

    <section class="pm-detail-section">
      <h3>CB Child Art & Print Cards</h3>
      <div class="pm-division-card-grid">${divisionHtml}</div>
    </section>

    <section class="pm-detail-section">
      <h3>Purchase History</h3>
      <div class="pm-purchase-history">${historyHtml}</div>
    </section>`;
}

function bindDetailInteractions() {
  const body = $("cbDetailBody");
  bindCarousels(body);
  body.querySelectorAll("[data-detail-art]").forEach(button => {
    button.addEventListener("click", () => openArtAssignment(button.dataset.detailArt));
  });
}

function refreshOpenDetail() {
  if (!activeDetailCbId || detailSheet.classList.contains("pm-hidden")) return;
  $("cbDetailBody").innerHTML = renderCbDetails(activeDetailCbId);
  bindDetailInteractions();
}

function openCbDetails(cbId) {
  const group = groupFor(cbId);
  if (!group) return;
  activeDetailCbId = cbId;
  $("cbDetailTitle").textContent = group.cb_no;
  $("cbDetailBody").innerHTML = renderCbDetails(cbId);
  bindDetailInteractions();
  openSheet(detailSheet);
}

async function loadPrintSource() {
  const viewResult = await supabaseClient
    .from("rr_print_library_view")
    .select("*")
    .order("updated_at", { ascending: false });
  if (!viewResult.error) return viewResult.data || [];

  console.warn("rr_print_library_view unavailable; using rr_print_master.", viewResult.error);
  const tableResult = await supabaseClient
    .from("rr_print_master")
    .select("*")
    .order("updated_at", { ascending: false });
  if (tableResult.error) throw tableResult.error;
  return tableResult.data || [];
}

async function loadCbPrintAssignments() {
  const result = await supabaseClient
    .from("rr_cb_print_assignments")
    .select("id,assignment_id,print_id,sequence_no,created_at,updated_at")
    .order("sequence_no");
  if (result.error) {
    throw new Error(`Run V715 separate Art/Print SQL: ${result.error.message}`);
  }
  return result.data || [];
}

async function loadMasterMedia(arts, prints) {
  const ids = [...new Set([...arts, ...prints].map(row => String(row.id || "")).filter(Boolean))];
  if (!ids.length) return [];
  const result = [];
  for (let start = 0; start < ids.length; start += 80) {
    const chunk = ids.slice(start, start + 80);
    const query = await supabaseClient
      .from("rr_media")
      .select("id,entity_type,entity_id,media_category,file_url,file_name,caption,is_cover,sort_order,created_at")
      .in("entity_id", chunk);
    if (query.error) {
      console.warn("Master media could not load.", query.error);
      return result;
    }
    result.push(...(query.data || []));
  }
  return result;
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
      colourResult,
      rollResult,
      allocationResult,
      artResult,
      loadedPrintRows,
      assignmentResult,
      loadedPrintAssignments
    ] = await Promise.all([
      supabaseClient.from("rr_material_categories").select("*").eq("is_active", true).order("sort_order"),
      loadGallerySource(),
      supabaseClient.from("rr_cb_purchase_entries").select("*").order("created_at", { ascending: false }),
      supabaseClient.from("rr_cb_colours").select("*").order("colour_order"),
      supabaseClient.from("rr_cb_purchase_rolls").select("*").order("roll_no"),
      supabaseClient.from("rr_cb_material_allocations").select("*"),
      supabaseClient.from("rr_art_master").select("*").eq("is_active", true).order("updated_at", { ascending: false }),
      loadPrintSource(),
      supabaseClient.from("rr_cb_art_assignments").select("*").order("updated_at", { ascending: false }),
      loadCbPrintAssignments()
    ]);

    if (categoryResult.error) throw categoryResult.error;
    if (purchaseResult.error) throw purchaseResult.error;
    if (colourResult.error) throw colourResult.error;
    if (rollResult.error) throw new Error(`Run V713 SQL patch: ${rollResult.error.message}`);
    if (allocationResult.error) throw new Error(`Run V713 SQL patch: ${allocationResult.error.message}`);
    if (artResult.error) throw new Error(`Art Master could not load: ${artResult.error.message}`);
    if (assignmentResult.error) throw new Error(`Run V714 Art assignment SQL: ${assignmentResult.error.message}`);

    categories = categoryResult.data || [];
    galleryRows = loadedGalleryRows || [];
    purchaseRows = purchaseResult.data || [];
    colourRows = colourResult.data || [];
    rollRows = rollResult.data || [];
    allocationRows = allocationResult.data || [];
    artRows = artResult.data || [];
    printRows = loadedPrintRows || [];
    assignmentRows = assignmentResult.data || [];
    printAssignmentRows = loadedPrintAssignments || [];
    mediaRows = await loadMasterMedia(artRows, printRows);

    if (!categories.length) throw new Error("No active material categories were found.");
    dataReady = true;
    newCbButton.disabled = false;
    renderGallery();
    refreshOpenDetail();
  } catch (error) {
    dataReady = false;
    gallery.setAttribute("aria-busy", "false");
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <h3>Product Master could not load</h3>
        <p>${safe(error.message || "Unknown loading error")}</p>
      </article>`;
    throw error;
  } finally {
    refreshButton.disabled = false;
    refreshButton.textContent = "Refresh";
  }
}

$("openNewCb").addEventListener("click", openCreateForm);
$("addMaterialEntry").addEventListener("click", () => {
  formEntries.push(makeEntry({ regularLocked: false, categoryCode: "cuff-collar" }));
  renderPurchaseEntries();
});

$("divisionCount").addEventListener("change", () => {
  const custom = $("divisionCount").value === "custom";
  $("customDivisionWrap").classList.toggle("pm-hidden", !custom);
  const validIndexes = currentDivisionChoices().map(item => item.index);
  formEntries.forEach(entry => {
    if (entry.allocationScope === "all") entry.selectedDivisionIndexes = [...validIndexes];
    else entry.selectedDivisionIndexes = entry.selectedDivisionIndexes.filter(index => validIndexes.includes(index));
  });
  syncAllAutoRollRows();
  renderPurchaseEntries();
});

$("customDivisionCount").addEventListener("input", () => {
  const validIndexes = currentDivisionChoices().map(item => item.index);
  formEntries.forEach(entry => {
    if (entry.allocationScope === "all") entry.selectedDivisionIndexes = [...validIndexes];
  });
  syncAllAutoRollRows();
  renderPurchaseEntries();
});

$("colourCount").addEventListener("change", () => {
  ensureColourDrafts(currentColourCount());
  renderPurchaseEntries();
});

$("addPurchaseToCb").addEventListener("click", () => {
  if (activeDetailCbId) openAppendForm(activeDetailCbId);
});

purchaseSheet.querySelectorAll("[data-close-purchase-sheet]").forEach(button => {
  button.addEventListener("click", () => closeSheet(purchaseSheet));
});
detailSheet.querySelectorAll("[data-close-detail-sheet]").forEach(button => {
  button.addEventListener("click", () => closeSheet(detailSheet));
});
artSheet.querySelectorAll("[data-close-art-sheet]").forEach(button => {
  button.addEventListener("click", () => closeSheet(artSheet));
});
$("artSearch").addEventListener("input", renderArtPicker);
$("printSearch").addEventListener("input", renderPrintPicker);
$("saveArtAssignment").addEventListener("click", saveSelectedArtAssignment);

$("pmCardColumns").addEventListener("change", () => {
  cardColumnCount = Number($("pmCardColumns").value || 3);
  localStorage.setItem("redzedProductCardColumns", String(cardColumnCount));
  applyCardColumns();
});

document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return;
  if (!artSheet.classList.contains("pm-hidden")) closeSheet(artSheet);
  else if (!purchaseSheet.classList.contains("pm-hidden")) closeSheet(purchaseSheet);
  else if (!detailSheet.classList.contains("pm-hidden")) closeSheet(detailSheet);
});

$("pmSearch").addEventListener("input", renderGallery);
$("refreshCb").addEventListener("click", () => {
  withTimeout(loadData(), 30000, "Product Master refresh").catch(error => {
    console.error(error);
    say(error.message || "Refresh failed.", "error");
  });
});

$("pmFilters").querySelectorAll("[data-filter]").forEach(button => {
  button.addEventListener("click", () => {
    currentFilter = button.dataset.filter;
    $("pmFilters").querySelectorAll("[data-filter]").forEach(item => {
      item.classList.toggle("is-active", item === button);
    });
    renderGallery();
  });
});

function withTimeout(promise, milliseconds, label) {
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      const error = new Error(`${label} timed out after ${Math.round(milliseconds / 1000)} seconds.`);
      error.code = "PM_TIMEOUT";
      reject(error);
    }, milliseconds);

    Promise.resolve(promise).then(
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

 function getSupabaseClient() {
  let client = null;
  try {
    if (
      typeof supabaseClient !== "undefined" &&
      supabaseClient &&
      typeof supabaseClient.from === "function"
    ) {
      client = supabaseClient;
    }
  } catch (error) {
    console.warn("Direct Supabase client check failed", error);
  }

  if (!client) {
    const candidates = [
      window.supabaseClient,
      window.supabaseDb,
      window.redzedSupabase,
      window.sb
    ];
    client = candidates.find(candidate => candidate && typeof candidate.from === "function") || null;
  }

  if (client && !window.supabaseClient) window.supabaseClient = client;
  return client;
}

async function waitForRuntime() {
  const startedAt = Date.now();
  while (Date.now() - startedAt < 10000) {
    if (getSupabaseClient() && typeof RR !== "undefined" && RR) return;
    await new Promise(resolve => window.setTimeout(resolve, 100));
  }

  const missing = [];
  if (!getSupabaseClient()) missing.push("Supabase client from config.js");
  if (typeof RR === "undefined" || !RR) missing.push("RR from real-common.js");
  throw new Error(`Required runtime not found: ${missing.join(", ")}.`);
}

async function ensureOwnerAccess() {
  const client = getSupabaseClient();
  if (!client?.auth?.getSession) throw new Error("Supabase authentication is not available.");

  const sessionResult = await withTimeout(client.auth.getSession(), 10000, "Supabase session check");
  if (sessionResult?.error) throw sessionResult.error;
  const session = sessionResult?.data?.session || null;

  if (!session) {
    if (typeof RR.requireOwner !== "function") throw new Error("Owner login helper is not available.");
    await withTimeout(RR.requireOwner(), 10000, "Owner login check");
    return;
  }

  if (typeof RR.requireOwner === "function") {
    try {
      await withTimeout(RR.requireOwner(), 5000, "Owner permission check");
    } catch (error) {
      if (error?.code === "PM_TIMEOUT") {
        console.warn("Owner permission helper timed out; authenticated session exists and database RLS remains active.");
        return;
      }
      throw error;
    }
  }
}

console.info("REDZED Product Master V715A separate Art + Print boot script loaded.");

(async () => {
  try {
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <div class="pm-spinner" aria-hidden="true"></div>
        <h3>Connecting Product Master V715A</h3>
        <p>Checking login and CB Purchase database…</p>
      </article>`;
    say("Starting Product Master V715A…");
    await waitForRuntime();
    await ensureOwnerAccess();
    say("");
    await withTimeout(loadData(), 30000, "Product Master database loading");
  } catch (error) {
    console.error("Product Master V715A boot failed:", error);
    $("openNewCb").disabled = true;
    gallery.setAttribute("aria-busy", "false");
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <h3>Product Master could not start</h3>
        <p>${safe(error.message || "Unknown startup error")}</p>
      </article>`;
    say(`V715A error: ${error.message || "Product Master could not open."}`, "error");
  }
})();
})();
