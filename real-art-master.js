
(() => {
  const form = document.getElementById("artForm");
  const message = document.getElementById("artMessage");
  const cards = document.getElementById("artCards");
  const reloadButton = document.getElementById("reloadArts");
  const saveButton = document.getElementById("saveArtBtn");
  const cancelEdit = document.getElementById("cancelEdit");
  const formTitle = document.getElementById("formTitle");
  const preview = document.getElementById("imagePreview");
  const selectedFiles = document.getElementById("selectedFiles");
  const fileInputs = [
    document.getElementById("cameraFiles"),
    document.getElementById("galleryFiles")
  ];

  const costInputs = {
    cut: document.getElementById("cutCost"),
    print: document.getElementById("printCost"),
    sticker: document.getElementById("stickerCost"),
    kr: document.getElementById("krCost"),
    ov: document.getElementById("ovCost"),
    fld: document.getElementById("fldCost"),
    threadCut: document.getElementById("threadCutCost"),
    press: document.getElementById("pressCost"),
    pack: document.getElementById("packCost"),
    other: document.getElementById("otherCost")
  };

  let artRows = [];
  let summaryRows = [];
  let mediaMap = {};
  let queuedFiles = [];

  const setMessage = (text, type = "") => {
    message.textContent = text || "";
    message.className = `rr-message ${type}`.trim();
  };

  const totalCost = () =>
    Object.values(costInputs).reduce(
      (sum, input) => sum + RR.number(input.value),
      0
    );

  const updateTotal = () => {
    document.getElementById("makingTotal").textContent = RR.money(totalCost());
  };

  Object.values(costInputs).forEach((input) =>
    input.addEventListener("input", updateTotal)
  );

  const updateQueuedFiles = () => {
    queuedFiles = fileInputs.flatMap((input) => Array.from(input.files || []));
    selectedFiles.textContent = queuedFiles.length
      ? `${queuedFiles.length} image(s) ready`
      : "No new images selected";

    preview.innerHTML = queuedFiles
      .map((file) => `<img src="${URL.createObjectURL(file)}" alt="Selected image">`)
      .join("");
  };

  fileInputs.forEach((input) => input.addEventListener("change", updateQueuedFiles));

  async function loadData() {
    reloadButton.disabled = true;
    reloadButton.textContent = "Loading...";

    const [artsResult, summaryResult, media] = await Promise.all([
      supabaseClient
        .from("rr_art_master")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(200),
      supabaseClient
        .from("rr_art_cost_summary")
        .select("*")
        .order("art_no", { ascending: true }),
      RR.getMediaMap("art", "reference")
    ]);

    reloadButton.disabled = false;
    reloadButton.textContent = "Refresh";

    if (artsResult.error) throw artsResult.error;
    if (summaryResult.error) throw summaryResult.error;

    artRows = artsResult.data || [];
    summaryRows = summaryResult.data || [];
    mediaMap = media;
    renderCards();
  }

  function getSummary(artId) {
    return summaryRows.find((row) => String(row.art_id) === String(artId)) || {};
  }

  function getFirstValue(row, aliases, fallback = 0) {
    for (const key of aliases) {
      if (row[key] !== undefined && row[key] !== null) return row[key];
    }
    return fallback;
  }

  function renderCards() {
    if (!artRows.length) {
      cards.innerHTML = `<p class="rr-muted">No design saved yet.</p>`;
      return;
    }

    cards.innerHTML = artRows.map((art) => {
      const summary = getSummary(art.id);
      const images = mediaMap[String(art.id)] || [];
      const imageUrl = images[0]?.file_url || "";
      const processCost = getFirstValue(summary, [
        "total_making_cost", "making_cost", "total_process_cost", "process_cost"
      ], 0);

      return `
        <button class="rr-product-card rr-card-button" type="button" data-art-id="${RR.safeText(art.id)}">
          <div class="rr-card-image">
            ${imageUrl
              ? `<img src="${RR.safeText(imageUrl)}" alt="${RR.safeText(art.item_name || art.art_no)}">`
              : `<div class="rr-image-placeholder">DESIGN</div>`}
          </div>
          <div class="rr-card-body">
            <span class="rr-card-code">${RR.safeText(art.art_no)}</span>
            <h3>${RR.safeText(art.item_name || art.product_name || "Unnamed Design")}</h3>
            <div class="rr-card-data">
              <span>Process Cost</span>
              <strong>${RR.money(processCost)}</strong>
            </div>
             <div class="rr-card-data">
  <span>Flat Profit</span>
  <strong>${RR.money(art.default_margin || 0)}</strong>
</div>
          </div>
        </button>
      `;
    }).join("");

    cards.querySelectorAll("[data-art-id]").forEach((card) =>
      card.addEventListener("click", () => editArt(card.dataset.artId))
    );
  }

  async function editArt(id) {
    const art = artRows.find((row) => String(row.id) === String(id));
    if (!art) return;
    const summary = getSummary(id);

    document.getElementById("artId").value = art.id;
    document.getElementById("artNo").value = art.art_no || "";
    document.getElementById("itemName").value = art.item_name || art.product_name || "";
    document.getElementById("description").value = art.description || "";
    document.getElementById("defaultMargin").value = art.default_margin ?? 22;

    const costAliasMap = {
      cut: ["cutting_rate", "cut_cost"],
      print: ["printing_rate", "print_cost"],
      sticker: ["sticker_rate", "sticker_cost", "sticker"],
      kr: ["kr_rate", "kr_cost", "kr"],
      ov: ["ov_rate", "ov_cost", "ov"],
      fld: ["fld_rate", "fld_cost", "fld"],
      threadCut: ["thread_cut_rate", "thread_cut_cost", "th_cut_cost", "th_cut"],
      press: ["press_rate", "press_cost", "press"],
      pack: ["packing_rate", "pack_cost", "packing_cost", "pack"],
      other: ["other_rate", "other_cost", "others_cost", "others"]
    };

    for (const [key, aliases] of Object.entries(costAliasMap)) {
      costInputs[key].value = getFirstValue(summary, aliases, 0);
    }

    const existingImages = mediaMap[String(id)] || [];
    preview.innerHTML = existingImages
      .map((image) => `<img src="${RR.safeText(image.file_url)}" alt="Reference image">`)
      .join("");

    queuedFiles = [];
    fileInputs.forEach((input) => { input.value = ""; });
    selectedFiles.textContent = "No new images selected";
    formTitle.textContent = `Edit ${art.art_no}`;
    saveButton.textContent = "Update Design";
    cancelEdit.classList.remove("rr-hidden");
    updateTotal();
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function resetForm() {
    form.reset();
    document.getElementById("artId").value = "";
    Object.values(costInputs).forEach((input) => { input.value = "0"; });
    document.getElementById("defaultMargin").value = "22";
    fileInputs.forEach((input) => { input.value = ""; });
    queuedFiles = [];
    selectedFiles.textContent = "No new images selected";
    preview.innerHTML = "";
    formTitle.textContent = "Add Design";
    saveButton.textContent = "Save Design";
    cancelEdit.classList.add("rr-hidden");
    updateTotal();
  }

  async function saveCosts(artId) {
    const columns = await RR.getTableColumns("rr_art_costs");
    const aliases = {
      art_id: ["art_id"],
      cut: ["cutting_rate", "cut_cost"],
      print: ["printing_rate", "print_cost"],
      sticker: ["sticker_rate", "sticker_cost", "sticker"],
      kr: ["kr_rate", "kr_cost", "kr"],
      ov: ["ov_rate", "ov_cost", "ov"],
      fld: ["fld_rate", "fld_cost", "fld"],
      threadCut: ["thread_cut_rate", "thread_cut_cost", "th_cut_cost", "th_cut"],
      press: ["press_rate", "press_cost", "press"],
      pack: ["packing_rate", "pack_cost", "packing_cost", "pack"],
      other: ["other_rate", "other_cost", "others_cost", "others"]
    };

    const payload = {};
    const artColumn = RR.pickColumn(columns, aliases.art_id);
    if (!artColumn) throw new Error("rr_art_costs art_id column missing.");
    payload[artColumn] = artId;

    for (const [key, names] of Object.entries(aliases)) {
      if (key === "art_id") continue;
      const column = RR.pickColumn(columns, names);
      if (column) payload[column] = RR.number(costInputs[key].value);
    }

    const { data: existing, error: readError } = await supabaseClient
      .from("rr_art_costs")
      .select("*")
      .eq(artColumn, artId)
      .maybeSingle();
    if (readError) throw readError;

    const writeQuery = existing
      ? supabaseClient.from("rr_art_costs").update(payload).eq(artColumn, artId)
      : supabaseClient.from("rr_art_costs").insert(payload);

    const { error } = await writeQuery;
    if (error) throw error;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage("");
    saveButton.disabled = true;
    saveButton.textContent = "Saving...";

    try {
      const artColumns = await RR.getTableColumns("rr_art_master");
      const existingId = document.getElementById("artId").value;
      const payload = RR.filterPayload({
        art_no: document.getElementById("artNo").value.trim(),
        item_name: document.getElementById("itemName").value.trim(),
        product_name: document.getElementById("itemName").value.trim(),
        description: document.getElementById("description").value.trim(),
        default_margin: RR.number(document.getElementById("defaultMargin").value),
        is_active: true
      }, artColumns);

      let art;
      if (existingId) {
        const { data, error } = await supabaseClient
          .from("rr_art_master")
          .update(payload)
          .eq("id", existingId)
          .select()
          .single();
        if (error) throw error;
        art = data;
      } else {
        const { data, error } = await supabaseClient
          .from("rr_art_master")
          .insert(payload)
          .select()
          .single();
        if (error) throw error;
        art = data;
      }

      await saveCosts(art.id);

      for (const input of fileInputs) {
        const sourceType = input.id === "cameraFiles" ? "camera" : "gallery";
        for (const file of Array.from(input.files || [])) {
          await RR.uploadMedia({
            file,
            entityType: "art",
            entityId: art.id,
            mediaCategory: "reference",
            sourceType,
            visibilityScope: "factory",
            caption: `${art.art_no} reference`
          });
        }
      }

      setMessage("Design saved successfully.", "success");
      resetForm();
      await loadData();
    } catch (error) {
      console.error(error);
      setMessage(error.message || "Design could not be saved.", "error");
    } finally {
      saveButton.disabled = false;
      saveButton.textContent = document.getElementById("artId").value
        ? "Update Design"
        : "Save Design";
    }
  });

  cancelEdit.addEventListener("click", resetForm);
  reloadButton.addEventListener("click", () =>
    loadData().catch((error) => setMessage(error.message, "error"))
  );

  (async () => {
    try {
      await RR.requireOwner();
      await loadData();
      updateTotal();
    } catch (error) {
      console.error(error);
      setMessage(error.message || "Design Master could not open.", "error");
    }
  })();
})();
