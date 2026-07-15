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
  const frameText = printFrameSummary(print);
  const metaText = colours > 0
    ? `${colours} Colour${colours === 1 ? "" : "s"}`
    : "Print Master";

  return `
    <button class="pm-art-option pm-print-choice ${selected ? "is-selected" : ""}" type="button" data-select-print="${safe(print.id)}" aria-pressed="${selected ? "true" : "false"}">
      <span class="pm-art-option-image pm-print-choice-image">
        ${image ? `<img src="${safe(image)}" alt="${safe(print.print_no || "Print")}" loading="lazy">` : `<i>PRINT</i>`}
        ${selected ? `<b class="pm-print-choice-check">✓</b>` : ""}
      </span>
      <span class="pm-art-option-copy pm-print-choice-copy">
        <small>PRINT NUMBER</small>
        <strong>${safe(print.print_no || "")}</strong>
        <em>${safe(print.print_name || "Unnamed Print")}</em>
        <b>${safe(metaText)}</b>
        <span class="pm-print-frame-caption">${safe(frameText)}</span>
      </span>
    </button>`;
}

function renderPrintPicker() {
  const query = $("printSearch").value.trim().toLowerCase();

  const printNotApplicable = selectedPrintIds.some(
    id => String(id) === "__PRINT_NA__"
  );

  const list = printRows.filter(print => {
    if (print.is_active === false) return false;

    const frames = Array.isArray(print.frames)
      ? print.frames
      : [];

    const haystack = [
      print.print_no,
      print.print_name,
      print.short_note,
      print.notes,
      printFrameSummary(print),
      ...frames.map(frame =>
        `${frame.frame_no || ""} ${frame.frame_status || ""}`
      )
    ].join(" ").toLowerCase();

    return haystack.includes(query);
  });

  const printCards = list.length
    ? list.map(printPickerCardHtml).join("")
    : `<div class="pm-art-empty">
        No matching Print found in Print Master.
      </div>`;

  $("printPickerGrid").innerHTML = `
    <button
      class="pm-art-option pm-print-choice ${
        printNotApplicable ? "is-selected" : ""
      }"
      type="button"
      data-select-print-na
      aria-pressed="${printNotApplicable ? "true" : "false"}"
    >
      <span class="pm-art-option-image pm-print-choice-image">
        <i>N/A</i>

        ${
          printNotApplicable
            ? `<b class="pm-print-choice-check">✓</b>`
            : ""
        }
      </span>

      <span class="pm-art-option-copy pm-print-choice-copy">
        <small>PRINT DECISION</small>
        <strong>N/A — NO PRINT</strong>
        <em>No Print Required</em>
        <b>Final no-print decision</b>
      </span>
    </button>

    ${printCards}
  `;

  $("selectedPrintCount").textContent = printNotApplicable
    ? "Print N/A selected"
    : `${selectedPrintIds.length} selected`;

  $("printPickerGrid")
    .querySelector("[data-select-print-na]")
    ?.addEventListener("click", () => {
      selectedPrintIds = printNotApplicable
        ? []
        : ["__PRINT_NA__"];

      renderPrintPicker();
      renderSelectedArtPreview();
    });

  $("printPickerGrid")
    .querySelectorAll("[data-select-print]")
    .forEach(button => {
      button.addEventListener("click", () => {
        const id = button.dataset.selectPrint;

        selectedPrintIds = selectedPrintIds.filter(
          item => String(item) !== "__PRINT_NA__"
        );

        const index = selectedPrintIds.findIndex(
          item => String(item) === String(id)
        );

        if (index >= 0) {
          selectedPrintIds.splice(index, 1);
        } else {
          selectedPrintIds.push(id);
        }

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

  const printNotApplicable = selectedPrintIds.some(
    id => String(id) === "__PRINT_NA__"
  );

  const items = carouselItemsForAssignment(art, prints);

  preview.classList.remove("pm-hidden");

  preview.innerHTML = `
    <div class="pm-selected-carousel">
      ${carouselHtml(
        items,
        `selected-${art.id}`,
        "ART PHOTO"
      )}
    </div>

    <div class="pm-selected-art-copy">
      <small>FINAL SELECTION</small>

      <h3>${safe(art.art_no)}</h3>

      <p>
        ${safe(
          art.product_name ||
          art.item_name ||
          art.category ||
          ""
        )}
      </p>

      <div class="pm-linked-print-list">
        ${
          printNotApplicable
            ? `
              <span>
                <small>PRINT</small>
                <strong>N/A — No Print Required</strong>
                <em>Final no-print decision</em>
              </span>
            `
            : prints.length
              ? prints.map(print => `
                  <span>
                    <small>PRINT</small>
                    <strong>${safe(print.print_no)}</strong>
                    <em>${safe(print.print_name || "")}</em>
                  </span>
                `).join("")
              : `
                <span class="is-empty">
                  <strong>Print Due</strong>
                  <em>Select Print or choose N/A.</em>
                </span>
              `
        }
      </div>

      <div class="pm-fixed-flow-caption">
        <span class="pm-progress-chip is-complete">
          ✓ Art Decided
        </span>

        <span class="pm-progress-chip ${
          printNotApplicable || prints.length
            ? "is-complete"
            : "is-due"
        }">
          ${
            printNotApplicable
              ? "✓ Print N/A"
              : prints.length
                ? "✓ Print Decided"
                : "Print Due"
          }
        </span>

        <span class="pm-progress-chip ${
          printNotApplicable || prints.length
            ? "is-next"
            : "is-due"
        }">
          Cutting Due
        </span>
      </div>
    </div>
  `;

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
  selectedPrintIds = context.assignment?.print_not_applicable
  ? ["__PRINT_NA__"]
  : assignedPrintsForDivision(divisionId).map(
      print => String(print.id)
    );
  $("artAssignmentKicker").textContent = context.assignment ? "Change Art & Print" : "Assign Art & Print";
  $("artAssignmentTitle").textContent = context.division.division_code || `S${context.division.division_index}`;
  $("artCbNo").textContent = context.group.cb_no || "—";
  $("artCbChild").textContent = context.division.division_code || `S${context.division.division_index}`;
  $("artCbQty").textContent = qty(context.division.allocated_qty);
  $("artSearch").value = "";
  $("printSearch").value = "";
  artAssignmentSay("");
  renderArtPicker();
  renderPrintPicker();
  renderSelectedArtPreview();
  openSheet(artSheet);
}

async function saveArtPrintAssignmentRecord(cbUnitId, artId, printIds) {
  const printNotApplicable = (printIds || []).some(
    id => String(id) === "__PRINT_NA__"
  );

  const cleanPrintIds = [
    ...new Set(
      (printIds || [])
        .map(String)
        .filter(id => id && id !== "__PRINT_NA__")
    )
  ];

  let rpc = {
    data: null,
    error: null
  };

  if (!printNotApplicable) {
    rpc = await supabaseClient.rpc(
      "rr_save_cb_art_print_assignment",
      {
        p_cb_unit_id: cbUnitId,
        p_art_id: artId,
        p_print_ids: cleanPrintIds
      }
    );

    if (!rpc.error) {
      const resetNaResult = await supabaseClient
        .from("rr_cb_art_assignments")
        .update({
          print_not_applicable: false
        })
        .eq("cb_id", cbUnitId);

      if (resetNaResult.error) {
        throw resetNaResult.error;
      }

      return rpc.data;
    }
  }

  const missingRpc =
    printNotApplicable ||
    String(rpc.error?.code || "") === "PGRST202" ||
    /function|rpc|schema cache/i.test(
      rpc.error?.message || ""
    );

  if (!missingRpc) {
    throw rpc.error;
  }

  console.warn("V715 RPC unavailable; using owner direct-write fallback.", rpc.error);
  const existing = assignmentForDivision(cbUnitId);
  let assignmentResult;
  if (existing) {
    assignmentResult = await supabaseClient
      .from("rr_cb_art_assignments")
      .update({
  art_id: artId,
  print_not_applicable: printNotApplicable,
  status: "material_check",
  bypass_reason: null,
  bypassed_by: null,
  bypassed_at: null
})
      .eq("id", existing.id)
      .select()
      .single();
  } else {
    assignmentResult = await supabaseClient
      .from("rr_cb_art_assignments")
      .insert({
  cb_id: cbUnitId,
  art_id: artId,
  print_not_applicable: printNotApplicable,
  status: "material_check"
})
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

    const printNotApplicable = selectedPrintIds.some(
      id => String(id) === "__PRINT_NA__"
    );

    await saveArtPrintAssignmentRecord(
      activeArtDivisionId,
      selectedArtId,
      selectedPrintIds
    );

    const printText = printNotApplicable
      ? "Print N/A"
      : prints.length
        ? `${prints.length} Print${prints.length === 1 ? "" : "s"}`
        : "Print Due";

    artAssignmentSay(
      `Art ${art?.art_no || ""} and ${printText} saved.`,
      "success"
    );

    await loadData();
    closeSheet(artSheet);

    say(
      `Art ${art?.art_no || ""} and ${printText} decided. Cutting Due.`,
      "success"
    );
  } catch (error) {
    console.error(error);

    artAssignmentSay(
      error.message ||
        "Art and Print assignment could not be saved.",
      "error"
    );
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

console.info("REDZED Product Master V715B Print choice cards boot script loaded.");

(async () => {
  try {
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <div class="pm-spinner" aria-hidden="true"></div>
        <h3>Connecting Product Master V715B</h3>
        <p>Checking login and CB Purchase database…</p>
      </article>`;
    say("Starting Product Master V715B…");
    await waitForRuntime();
    await ensureOwnerAccess();
    say("");
    await withTimeout(loadData(), 30000, "Product Master database loading");
  } catch (error) {
    console.error("Product Master V715B boot failed:", error);
    $("openNewCb").disabled = true;
    gallery.setAttribute("aria-busy", "false");
    gallery.innerHTML = `
      <article class="pm-empty-card">
        <h3>Product Master could not start</h3>
        <p>${safe(error.message || "Unknown startup error")}</p>
      </article>`;
    say(`V715B error: ${error.message || "Product Master could not open."}`, "error");
  }
})();
})();
