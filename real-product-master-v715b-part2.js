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
  col_no: index + 1,
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

/* Add Print Decided filter before Part 3 binds filter events */
const pmFilterRow = $("pmFilters");

if (
  pmFilterRow &&
  !pmFilterRow.querySelector('[data-filter="print_decided"]')
) {
  const printDecidedFilter = document.createElement("button");

  printDecidedFilter.className = "pm-filter";
  printDecidedFilter.type = "button";
  printDecidedFilter.dataset.filter = "print_decided";
  printDecidedFilter.textContent = "Print Decided";

  const purchaseFilter =
    pmFilterRow.querySelector('[data-filter="purchase"]');

  pmFilterRow.insertBefore(
    printDecidedFilter,
    purchaseFilter || null
  );
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

    if (currentFilter === "purchase") {
      filterMatches = purchases.length > 0;
    } else if (currentFilter === "planning") {
      filterMatches = !assignment;
    } else if (currentFilter === "ready_for_cutting") {
      filterMatches = Boolean(assignment);
    } else if (currentFilter === "print_decided") {
      filterMatches = assignedPrints.length > 0;
    } else if (currentFilter === "hold") {
      filterMatches = group.status === "hold";
    }

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
const assignedPrints =
  assignedPrintsForDivision(division.division_id);

const printNotApplicable =
  Boolean(assignment?.print_not_applicable);

const printDecisionComplete =
  printNotApplicable || assignedPrints.length > 0;

const colours = coloursFor(group.cb_id);

let items =
  carouselItemsForAssignment(art, assignedPrints);

if (!items.length && !art) {
  const colourImage =
    colours.find(row => row.image_url)?.image_url;

  if (colourImage) {
    items = [{
      url: colourImage,
      label: "CB COLOUR",
      kind: "colour"
    }];
  }
}

const instanceId =
  `division-${division.division_id}`;

const printCaption = printNotApplicable
  ? "N/A — No Print Required"
  : assignedPrints.length
    ? assignedPrints
        .map(row => row.print_no)
        .filter(Boolean)
        .join(" · ")
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
<div class="pm-caption-status-row">
  <span class="pm-progress-chip ${assignment ? "is-complete" : "is-due"}">
    ${assignment ? "✓ Art Decided" : "Art Due"}
  </span>

  <span class="pm-progress-chip ${printDecisionComplete ? "is-complete" : "is-due"}">
    ${
      printNotApplicable
        ? "✓ Print N/A"
        : assignedPrints.length
          ? "✓ Print Decided"
          : "Print Due"
    }
  </span>

  <span class="pm-progress-chip ${
    assignment && printDecisionComplete
      ? "is-next"
      : "is-due"
  }">
    Cutting Due
  </span>
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
     
