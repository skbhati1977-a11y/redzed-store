
(() => {
  const editor = document.getElementById("productEditor");
  const form = document.getElementById("productForm");
  const message = document.getElementById("productMessage");
  const cards = document.getElementById("productCards");
  const artSelect = document.getElementById("artSelect");
  const purchaseSelect = document.getElementById("purchaseSelect");
  const designReference = document.getElementById("designReference");
  const productPreview = document.getElementById("productImagePreview");
  const productFiles = [
    document.getElementById("productCamera"),
    document.getElementById("productGallery")
  ];

  let arts = [];
  let summaries = [];
  let products = [];
  let materialSummaries = [];
  let artMedia = {};
  let productMedia = {};
  let assignments = [];

  const setMessage = (text, type = "") => {
    message.textContent = text || "";
    message.className = `rr-message ${type}`.trim();
  };

  const firstValue = (row, aliases, fallback = 0) => {
    for (const key of aliases) {
      if (row && row[key] !== undefined && row[key] !== null) return row[key];
    }
    return fallback;
  };

  function getArtSummary(artId) {
    return summaries.find((row) => String(row.art_id) === String(artId)) || {};
  }

  function getAssignment(cbId) {
    return assignments.find((row) =>
      String(firstValue(row, ["cb_id", "cb_unit_id", "product_id"], "")) === String(cbId)
    ) || {};
  }

  function getAssignedArtId(cbId) {
    return firstValue(getAssignment(cbId), ["art_id", "design_id"], "");
  }

  function selectedArt() {
    return arts.find((row) => String(row.id) === String(artSelect.value));
  }

  function updateDesignReference() {
    const art = selectedArt();
    if (!art) {
      designReference.innerHTML = `
        <div class="rr-image-placeholder">Select Design</div>
        <div><span>Design reference</span><h3>Nothing selected</h3>
        <p class="rr-muted">Process cost and reference image will appear here.</p></div>`;
      updatePriceSummary();
      return;
    }

    const images = artMedia[String(art.id)] || [];
    const summary = getArtSummary(art.id);
    const processCost = firstValue(summary, [
      "total_making_cost", "making_cost", "total_process_cost", "process_cost"
    ], 0);

    designReference.innerHTML = `
      ${images[0]?.file_url
        ? `<img src="${RR.safeText(images[0].file_url)}" alt="${RR.safeText(art.item_name)}">`
        : `<div class="rr-image-placeholder">DESIGN</div>`}
      <div>
        <span>${RR.safeText(art.art_no)}</span>
        <h3>${RR.safeText(art.item_name || art.product_name || "")}</h3>
        <p class="rr-muted">Process Cost: ${RR.money(processCost)} · Pricing Rule: ${RR.safeText(art.default_margin || 0)}%</p>
      </div>`;
    updatePriceSummary();
  }

  function calculateMaterialCost() {
    const dividedAmount = RR.number(document.getElementById("dividedAmount").value);
    const estimatedPcs = RR.number(document.getElementById("estimatedPcs").value);
    const accessories = RR.number(document.getElementById("accessoriesCost").value);
    if (estimatedPcs > 0) return dividedAmount / estimatedPcs + accessories;
    return accessories;
  }

  function updatePriceSummary() {
    const art = selectedArt();
    const summary = art ? getArtSummary(art.id) : {};
    const processCost = firstValue(summary, [
      "total_making_cost", "making_cost", "total_process_cost", "process_cost"
    ], 0);
    const materialCost = calculateMaterialCost();
    const productionCost = RR.number(processCost) + RR.number(materialCost);
    const margin = RR.number(art?.default_margin);
    const sellingPrice = productionCost * (1 + margin / 100);

    document.getElementById("processCostDisplay").textContent = RR.money(processCost);
    document.getElementById("materialCostDisplay").textContent = RR.money(materialCost);
    document.getElementById("productionCostDisplay").textContent = RR.money(productionCost);
    document.getElementById("sellingPriceDisplay").textContent = RR.money(sellingPrice);
  }

  ["dividedAmount", "estimatedPcs", "accessoriesCost"].forEach((id) =>
    document.getElementById(id).addEventListener("input", updatePriceSummary)
  );
  artSelect.addEventListener("change", updateDesignReference);

  function updateProductPreview() {
    const files = productFiles.flatMap((input) => Array.from(input.files || []));
    productPreview.innerHTML = files
      .map((file) => `<img src="${URL.createObjectURL(file)}" alt="Selected product image">`)
      .join("");
  }
  productFiles.forEach((input) => input.addEventListener("change", updateProductPreview));

  async function loadData() {
    const [
      artsResult,
      summaryResult,
      productResult,
      materialResult,
      purchasesResult,
      assignmentResult,
      referenceMedia,
      finalMedia
    ] = await Promise.all([
      supabaseClient.from("rr_art_master").select("*").eq("is_active", true).order("art_no"),
      supabaseClient.from("rr_art_cost_summary").select("*"),
      supabaseClient.from("rr_cb_units").select("*").order("created_at", { ascending: false }),
      supabaseClient.from("rr_cb_material_cost_summary").select("*"),
      supabaseClient.from("rr_fabric_purchases").select("*").order("purchase_date", { ascending: false }),
      supabaseClient.from("rr_cb_art_assignments").select("*"),
      RR.getMediaMap("art", "reference"),
      RR.getMediaMap("cb", "final")
    ]);

    for (const result of [artsResult, summaryResult, productResult, materialResult, purchasesResult]) {
      if (result.error) throw result.error;
    }

    arts = artsResult.data || [];
    summaries = summaryResult.data || [];
    products = productResult.data || [];
    materialSummaries = materialResult.data || [];
    assignments = assignmentResult.error ? [] : (assignmentResult.data || []);
    artMedia = referenceMedia;
    productMedia = finalMedia;

    artSelect.innerHTML = `<option value="">Select design</option>` +
      arts.map((art) => `<option value="${RR.safeText(art.id)}">${RR.safeText(art.art_no)} · ${RR.safeText(art.item_name || art.product_name || "")}</option>`).join("");

    purchaseSelect.innerHTML = `<option value="">Select purchase</option>` +
      (purchasesResult.data || []).map((purchase) => {
        const label = firstValue(purchase, ["purchase_no"], purchase.id);
        const weight = firstValue(purchase, ["total_weight"], "");
        return `<option value="${RR.safeText(purchase.id)}">${RR.safeText(label)}${weight ? ` · ${RR.safeText(weight)} kg` : ""}</option>`;
      }).join("");

    renderCards();
  }

  function renderCards() {
    if (!products.length) {
      cards.innerHTML = `<p class="rr-muted">No product created yet. Tap “Add Product”.</p>`;
      return;
    }

    cards.innerHTML = products.map((cb) => {
      const material = materialSummaries.find((row) => String(row.cb_id) === String(cb.id)) || {};
      const artId = getAssignedArtId(cb.id);
      const art = arts.find((row) => String(row.id) === String(artId));
      const artSummary = getArtSummary(artId);
      const processCost = firstValue(artSummary, ["total_making_cost", "making_cost"], 0);
      const materialCost = firstValue(material, ["total_material_cost_per_piece"], 0);
      const productionCost = RR.number(processCost) + RR.number(materialCost);
      const margin = RR.number(art?.default_margin);
      const sellingPrice = productionCost * (1 + margin / 100);
      const images = productMedia[String(cb.id)] || [];
      const fallbackImages = artMedia[String(artId)] || [];
      const imageUrl = images[0]?.file_url || fallbackImages[0]?.file_url || "";

      return `
        <button class="rr-product-card rr-card-button" type="button" data-cb-id="${RR.safeText(cb.id)}">
          <div class="rr-card-image">
            ${imageUrl
              ? `<img src="${RR.safeText(imageUrl)}" alt="${RR.safeText(cb.cb_code)}">`
              : `<div class="rr-image-placeholder">PRODUCT</div>`}
            ${images.length ? `<span class="rr-image-count">📷 ${images.length}</span>` : ""}
          </div>
          <div class="rr-card-body">
            <span class="rr-card-code">${RR.safeText(cb.cb_code || cb.cb_base_no || "Product")}</span>
            <h3>${RR.safeText(art?.item_name || art?.product_name || "Design not linked")}</h3>
            <div class="rr-card-tags">
              <span>${RR.safeText(cb.sleeve_type || "full")}</span>
              <span>${RR.safeText(cb.size_family || "regular")}</span>
            </div>
            <div class="rr-card-data"><span>Production Cost</span><strong>${RR.money(productionCost)}</strong></div>
            <div class="rr-card-data rr-selling"><span>Selling Price</span><strong>${RR.money(sellingPrice)}</strong></div>
            <div class="rr-card-data"><span>Estimated Stock</span><strong>${RR.safeText(cb.estimated_pcs || cb.actual_pcs || 0)} PCS</strong></div>
          </div>
        </button>`;
    }).join("");

    cards.querySelectorAll("[data-cb-id]").forEach((card) =>
      card.addEventListener("click", () => openEdit(card.dataset.cbId))
    );
  }

  function openEditor() {
    editor.classList.remove("rr-hidden");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function resetForm() {
    form.reset();
    document.getElementById("cbId").value = "";
    document.getElementById("colourCount").value = "1";
    document.getElementById("productFormTitle").textContent = "Add Product";
    productPreview.innerHTML = "";
    updateDesignReference();
  }

  async function openEdit(id) {
    resetForm();
    const cb = products.find((row) => String(row.id) === String(id));
    if (!cb) return;

    document.getElementById("cbId").value = cb.id;
    document.getElementById("cbCode").value = cb.cb_code || cb.cb_base_no || "";
    purchaseSelect.value = cb.purchase_id || "";
    document.getElementById("sizeFamily").value = cb.size_family || "regular";
    document.getElementById("sleeveType").value = cb.sleeve_type || "full";
    document.getElementById("dividedRolls").value = cb.divided_rolls || 0;
    document.getElementById("dividedWeight").value = cb.divided_weight || 0;
    document.getElementById("dividedAmount").value = cb.divided_amount || 0;
    document.getElementById("estimatedPcs").value = cb.estimated_pcs || 0;
    document.getElementById("cbNotes").value = cb.notes || "";
    artSelect.value = getAssignedArtId(cb.id) || "";

    const material = materialSummaries.find((row) => String(row.cb_id) === String(cb.id)) || {};
    document.getElementById("accessoriesCost").value =
      firstValue(material, ["accessories_cost_per_piece"], 0);
    document.getElementById("consumptionPerPiece").value =
      firstValue(material, ["consumption_per_piece"], 0);
    document.getElementById("wastagePercent").value =
      firstValue(material, ["wastage_percent"], 0);

    const images = productMedia[String(cb.id)] || [];
    productPreview.innerHTML = images
      .map((image) => `<img src="${RR.safeText(image.file_url)}" alt="Final product image">`)
      .join("");

    document.getElementById("productFormTitle").textContent = `Edit ${cb.cb_code || cb.cb_base_no}`;
    updateDesignReference();
    openEditor();
  }

  async function saveAssignment(cbId, artId) {
    if (!artId) return;
    const columns = await RR.getTableColumns("rr_cb_art_assignments");
    const cbColumn = RR.pickColumn(columns, ["cb_id", "cb_unit_id", "product_id"]);
    const artColumn = RR.pickColumn(columns, ["art_id", "design_id"]);
    if (!cbColumn || !artColumn) return;

    const { error: deleteError } = await supabaseClient
      .from("rr_cb_art_assignments")
      .delete()
      .eq(cbColumn, cbId);
    if (deleteError) throw deleteError;

    const payload = { [cbColumn]: cbId, [artColumn]: artId };
    if (columns.has("status")) payload.status = "material_check";

    const { error } = await supabaseClient
      .from("rr_cb_art_assignments")
      .insert(payload);
    if (error) throw error;
  }

  async function saveCosting(cbId) {
    let columns;
    try {
      columns = await RR.getTableColumns("rr_cb_costing");
    } catch (_) {
      return;
    }
    if (!columns.size) return;

    const cbColumn = RR.pickColumn(columns, ["cb_id", "cb_unit_id"]);
    if (!cbColumn) return;

    const payload = { [cbColumn]: cbId };
    const consumptionColumn = RR.pickColumn(columns, ["consumption_per_piece", "fabric_consumption_per_piece"]);
    const accessoriesColumn = RR.pickColumn(columns, ["accessories_cost_per_piece", "matching_cost_per_piece", "other_material_cost_per_piece"]);
    const wastageColumn = RR.pickColumn(columns, ["wastage_percent", "wastage_pct"]);
    const notesColumn = RR.pickColumn(columns, ["notes"]);

    if (consumptionColumn) payload[consumptionColumn] = RR.number(document.getElementById("consumptionPerPiece").value);
    if (accessoriesColumn) payload[accessoriesColumn] = RR.number(document.getElementById("accessoriesCost").value);
    if (wastageColumn) payload[wastageColumn] = RR.number(document.getElementById("wastagePercent").value);
    if (notesColumn) payload[notesColumn] = document.getElementById("cbNotes").value.trim();

    const { data: existing, error: findError } = await supabaseClient
      .from("rr_cb_costing")
      .select("*")
      .eq(cbColumn, cbId)
      .maybeSingle();
    if (findError) throw findError;

    const query = existing?.id
      ? supabaseClient.from("rr_cb_costing").update(payload).eq("id", existing.id)
      : supabaseClient.from("rr_cb_costing").insert(payload);
    const { error } = await query;
    if (error) throw error;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const saveButton = document.getElementById("saveProductBtn");
    saveButton.disabled = true;
    saveButton.textContent = "Saving...";
    setMessage("");

    try {
      const cbColumns = await RR.getTableColumns("rr_cb_units");
      const existingId = document.getElementById("cbId").value;
      const code = document.getElementById("cbCode").value.trim();

      const payload = RR.filterPayload({
        purchase_id: purchaseSelect.value || null,
        cb_base_no: code,
        cb_code: code,
        division_count: 1,
        division_index: 1,
        divided_rolls: RR.number(document.getElementById("dividedRolls").value),
        divided_weight: RR.number(document.getElementById("dividedWeight").value),
        divided_amount: RR.number(document.getElementById("dividedAmount").value),
        status: "open",
        sleeve_type: document.getElementById("sleeveType").value,
        size_family: document.getElementById("sizeFamily").value,
        estimated_pcs: RR.number(document.getElementById("estimatedPcs").value),
        notes: document.getElementById("cbNotes").value.trim()
      }, cbColumns);

      let cb;
      if (existingId) {
        const { data, error } = await supabaseClient
          .from("rr_cb_units")
          .update(payload)
          .eq("id", existingId)
          .select()
          .single();
        if (error) throw error;
        cb = data;
      } else {
        const { data, error } = await supabaseClient
          .from("rr_cb_units")
          .insert(payload)
          .select()
          .single();
        if (error) throw error;
        cb = data;
      }

      await saveAssignment(cb.id, artSelect.value);
      await saveCosting(cb.id);

      const colourCount = Math.max(1, RR.number(document.getElementById("colourCount").value, 1));
      let colourResult = await supabaseClient.rpc("rr_create_cb_colours", {
        p_cb_id: cb.id,
        p_colour_count: colourCount
      });
      if (colourResult.error && String(colourResult.error.message).includes("p_colour_count")) {
        colourResult = await supabaseClient.rpc("rr_create_cb_colours", {
          p_cb_id: cb.id,
          p_count: colourCount
        });
      }
      if (colourResult.error) throw colourResult.error;

      for (const input of productFiles) {
        const sourceType = input.id === "productCamera" ? "camera" : "gallery";
        for (const file of Array.from(input.files || [])) {
          await RR.uploadMedia({
            file,
            entityType: "cb",
            entityId: cb.id,
            mediaCategory: "final",
            sourceType,
            visibilityScope: "customer",
            caption: "Product image"
          });
        }
      }

      setMessage("Product saved successfully.", "success");
      resetForm();
      editor.classList.add("rr-hidden");
      await loadData();
    } catch (error) {
      console.error(error);
      setMessage(error.message || "Product could not be saved.", "error");
    } finally {
      saveButton.disabled = false;
      saveButton.textContent = "Save Product";
    }
  });

  document.getElementById("addProductBtn").addEventListener("click", () => {
    resetForm();
    openEditor();
  });
  document.getElementById("closeProductEditor").addEventListener("click", () =>
    editor.classList.add("rr-hidden")
  );
  document.getElementById("reloadProducts").addEventListener("click", () =>
    loadData().catch((error) => setMessage(error.message, "error"))
  );

  (async () => {
    try {
      await RR.requireOwner();
      await loadData();
      updatePriceSummary();
    } catch (error) {
      console.error(error);
      setMessage(error.message || "Product Master could not open.", "error");
    }
  })();
})();
