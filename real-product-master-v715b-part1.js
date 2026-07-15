(() => {
"use strict";

window.REDZED_PRODUCT_MASTER_BOOTED = true;
window.REDZED_PRODUCT_MASTER_VERSION = "715B";

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
let cuttingComboRows = [];
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
