(() => {
"use strict";

window.REDZED_PRODUCT_MASTER_BOOTED = true;
window.REDZED_PRODUCT_MASTER_VERSION = "713";

const $ = id => document.getElementById(id);
const purchaseSheet = $("purchaseSheet");
const detailSheet = $("cbDetailSheet");
const purchaseForm = $("purchaseForm");
const gallery = $("cbGallery");
const message = $("pmMessage");

let categories = [];
let galleryRows = [];
let purchaseRows = [];
let colourRows = [];
let rollRows = [];
let allocationRows = [];
let currentFilter = "all";
let dataReady = false;

let formMode = "create";
let activeCbId = null;
let activeDetailCbId = null;
let entrySequence = 0;
let formEntries = [];
let cbColourDrafts = [];

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

  formEntries.forEach(entry => {
    while (entry.colours.length < count) {
      entry.colours.push({ rolls: [{ quantity: "" }] });
    }
    while (entry.colours.length > count) entry.colours.pop();
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
    colours: Array.from({ length: currentColourCount() }, () => ({
      rolls: [{ quantity: "" }]
    }))
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
  if (purchaseSheet.classList.contains("pm-hidden") && detailSheet.classList.contains("pm-hidden")) {
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
      <button class="pm-remove-roll" type="button" aria-label="Remove roll">×</button>
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

      rollNode.querySelector(".pm-remove-roll").addEventListener("click", () => {
        entry.colours[colourIndex].rolls.splice(rollIndex, 1);
        if (!entry.colours[colourIndex].rolls.length) {
          entry.colours[colourIndex].rolls.push({ quantity: "" });
        }
        renderPurchaseEntries();
      });
    });

    colourNode.querySelector(".pm-add-roll").addEventListener("click", () => {
      entry.colours[colourIndex].rolls.push({ quantity: "" });
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

async function insertPurchaseEntry(cbPurchaseId, entry, divisions, colours, entryNotes = null) {
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

  const divisionIds = selectedDivisionIds(entry, divisions);
  if (!divisionIds.length) throw new Error("No division selected for material allocation.");

  const { error: allocationError } = await supabaseClient
    .rpc("rr_allocate_cb_purchase_entry", {
      p_purchase_entry_id: data.id,
      p_division_ids: divisionIds
    });

  if (allocationError) throw allocationError;
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
    const { data: rpcData, error: cbError } = await supabaseClient
      .rpc("rr_create_cb_v713", {
        p_cb_no: cbNo,
        p_division_count: divisionCount,
        p_colour_count: colourCount,
        p_regular_qty: Number(regularQuantity.toFixed(3)),
        p_regular_amount: Number(regularAmount.toFixed(2)),
        p_total_rolls: regularRolls,
        p_fabric_name: regularEntry.fabricName.trim(),
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

    for (const entry of formEntries) {
      await insertPurchaseEntry(cbPurchaseId, entry, divisions, createdColours, null);
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

  try {
    if (
      typeof RR === "undefined" ||
      typeof RR.requireOwner !== "function" ||
      (formMode === "create" && typeof RR.uploadMedia !== "function")
    ) {
      throw new Error("real-common.js owner/media helpers are not available.");
    }

    validateEntries();
    const result = formMode === "create"
      ? await saveCreateMode()
      : await saveAppendMode();

    closeSheet(purchaseSheet);
    say(
      formMode === "create"
        ? `CB ${result.cbNo} created successfully.`
        : `${result.cbNo} material purchase added successfully.`,
      "success"
    );
    await loadData();
  } catch (error) {
    console.error(error);
    say(error.message || "Purchase could not be saved.", "error");
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

function renderGallery() {
  const query = $("pmSearch").value.trim().toLowerCase();
  const groups = groupGalleryRows().filter(group => {
    const purchases = purchasesFor(group.cb_id);
    const colours = coloursFor(group.cb_id);
    const searchText = [
      group.cb_no,
      ...group.divisions.map(row => `${row.division_code || ""} ${row.lot_no || ""}`),
      ...purchases.map(row => {
        const category = categoryById(row.material_category_id);
        return `${row.vendor_name || ""} ${row.vendor_bill_no || ""} ${row.fabric_name || ""} ${category?.category_name || ""}`;
      }),
      ...colours.map(row => row.colour_name || "")
    ].join(" ").toLowerCase();

    let filterMatches = currentFilter === "all";
    if (currentFilter === "purchase") filterMatches = purchases.length > 0;
    else if (currentFilter !== "all") filterMatches = group.status === currentFilter;
    return filterMatches && searchText.includes(query);
  });

  gallery.setAttribute("aria-busy", "false");
  if (!groups.length) {
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <div class="pm-empty-icon">＋</div>
        <h3>No CB found</h3>
        <p>Create a new CB or change the search/filter.</p>
      </article>`;
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
      : `<span><i class="pm-colour-fallback">C</i>Colours pending</span>`;

    const divisionHtml = group.divisions.map(division =>
      `<span>${safe(division.division_code || `S${division.division_index}`)}</span>`
    ).join("");

    return `
      <article class="pm-cb-card">
        <div class="pm-card-top">
          <div>
            <span class="pm-status status-${safe(group.status)}">${safe(String(group.status).replaceAll("_", " "))}</span>
            <h3>${safe(group.cb_no)}</h3>
            <p>${group.divisions.length} Division${group.divisions.length === 1 ? "" : "s"} · ${colours.length} Colour${colours.length === 1 ? "" : "s"}</p>
          </div>
        </div>

        <div class="pm-card-colours">${colourHtml}</div>

        <div class="pm-card-metrics">
          <span><small>Total Qty</small><strong>${qty(group.quantity)}</strong></span>
          <span><small>Total Amount</small><strong>${money(group.amount)}</strong></span>
        </div>

        <div class="pm-division-preview">${divisionHtml}</div>

        <div class="pm-card-footer">
          <span>${purchases.length} Purchase Entr${purchases.length === 1 ? "y" : "ies"}</span>
          <button class="pm-open-cb" type="button" data-open-cb="${safe(group.cb_id)}">Open CB</button>
        </div>
      </article>`;
  }).join("");

  gallery.querySelectorAll("[data-open-cb]").forEach(button => {
    button.addEventListener("click", () => openCbDetails(button.dataset.openCb));
  });
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
    const materialChips = allocations.length
      ? allocations.map(allocation => {
          const purchase = purchaseById(allocation.purchase_entry_id);
          const category = categoryById(purchase?.material_category_id);
          return `<span>${safe(category?.category_name || "Material")} · ${qty(allocation.allocated_qty)}</span>`;
        }).join("")
      : `<span>Legacy allocation</span>`;

    return `
      <article class="pm-division-card">
        <h4>${safe(division.division_code || `S${division.division_index}`)}</h4>
        <div class="pm-division-card-metrics">
          <span><small>Total Qty</small><strong>${qty(division.allocated_qty)}</strong></span>
          <span><small>Total Amount</small><strong>${money(division.allocated_amount)}</strong></span>
        </div>
        <div class="pm-material-chip-list">${materialChips}</div>
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
      <h3>Division Cards</h3>
      <div class="pm-division-card-grid">${divisionHtml}</div>
    </section>

    <section class="pm-detail-section">
      <h3>Purchase History</h3>
      <div class="pm-purchase-history">${historyHtml}</div>
    </section>`;
}

function openCbDetails(cbId) {
  const group = groupFor(cbId);
  if (!group) return;
  activeDetailCbId = cbId;
  $("cbDetailTitle").textContent = group.cb_no;
  $("cbDetailBody").innerHTML = renderCbDetails(cbId);
  openSheet(detailSheet);
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
      allocationResult
    ] = await Promise.all([
      supabaseClient.from("rr_material_categories").select("*").eq("is_active", true).order("sort_order"),
      loadGallerySource(),
      supabaseClient.from("rr_cb_purchase_entries").select("*").order("created_at", { ascending: false }),
      supabaseClient.from("rr_cb_colours").select("*").order("colour_order"),
      supabaseClient.from("rr_cb_purchase_rolls").select("*").order("roll_no"),
      supabaseClient.from("rr_cb_material_allocations").select("*")
    ]);

    if (categoryResult.error) throw categoryResult.error;
    if (purchaseResult.error) throw purchaseResult.error;
    if (colourResult.error) throw colourResult.error;
    if (rollResult.error) throw new Error(`Run V713 SQL patch: ${rollResult.error.message}`);
    if (allocationResult.error) throw new Error(`Run V713 SQL patch: ${allocationResult.error.message}`);

    categories = categoryResult.data || [];
    galleryRows = loadedGalleryRows || [];
    purchaseRows = purchaseResult.data || [];
    colourRows = colourResult.data || [];
    rollRows = rollResult.data || [];
    allocationRows = allocationResult.data || [];

    if (!categories.length) throw new Error("No active material categories were found.");
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
  renderPurchaseEntries();
});

$("customDivisionCount").addEventListener("input", () => {
  const validIndexes = currentDivisionChoices().map(item => item.index);
  formEntries.forEach(entry => {
    if (entry.allocationScope === "all") entry.selectedDivisionIndexes = [...validIndexes];
  });
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

document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return;
  if (!purchaseSheet.classList.contains("pm-hidden")) closeSheet(purchaseSheet);
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

console.info("REDZED Product Master V713 boot script loaded.");

(async () => {
  try {
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <div class="pm-spinner" aria-hidden="true"></div>
        <h3>Connecting Product Master V713</h3>
        <p>Checking login and CB Purchase database…</p>
      </article>`;
    say("Starting Product Master V713…");
    await waitForRuntime();
    await ensureOwnerAccess();
    say("");
    await withTimeout(loadData(), 30000, "Product Master database loading");
  } catch (error) {
    console.error("Product Master V713 boot failed:", error);
    $("openNewCb").disabled = true;
    gallery.setAttribute("aria-busy", "false");
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <h3>Product Master could not start</h3>
        <p>${safe(error.message || "Unknown startup error")}</p>
      </article>`;
    say(`V713 error: ${error.message || "Product Master could not open."}`, "error");
  }
})();
})();
          
