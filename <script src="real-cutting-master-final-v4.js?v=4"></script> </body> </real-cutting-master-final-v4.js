(() => {
  "use strict";

  const $ = id => document.getElementById(id);
  const client = (() => {
    try {
      if (typeof supabaseClient !== "undefined" && supabaseClient?.from) {
        return supabaseClient;
      }
    } catch (_) {}

    return [
      window.supabaseClient,
      window.supabaseDb,
      window.redzedSupabase,
      window.sb
    ].find(item => item?.from) || null;
  })();

  let refs = {
    units: [],
    assignments: [],
    printAssignments: [],
    arts: [],
    prints: [],
    media: []
  };

  function safe(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function errorText(error) {
    return [
      error?.message,
      error?.details,
      error?.hint,
      error?.code ? `Code: ${error.code}` : ""
    ].filter(Boolean).join(" — ") || "Lot could not be saved.";
  }

  function today() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }

  function addUi() {
    if (!$("cuttingV4Style")) {
      const style = document.createElement("style");
      style.id = "cuttingV4Style";
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
        .v4-message{margin:0 0 10px;padding:11px;border-radius:12px;background:#17171d}
        .v4-message.error{background:#3a1a20;color:#ffc4c9}
        .v4-message.success{background:#14331f;color:#b9efc8}
        .v4-message.progress{background:#332711;color:#ffe0a0}
        @media(max-width:620px){.v4-meta{grid-template-columns:1fr}}
      `;
      document.head.appendChild(style);
    }

    const bundle = $("bundleQty");
    if (bundle) {
      bundle.value = "1";
      bundle.closest("label")?.style.setProperty("display", "none");
    }

    ["artNo", "printNo"].forEach(id => {
      const input = $(id);
      if (input) input.readOnly = true;
    });

    const title = $("cuttingMatrix")
      ?.closest(".cm-form-card")
      ?.querySelector(".cm-form-title p");

    if (title) {
      title.textContent =
        "Each non-zero Colour × Size entry is exactly one bundle.";
    }

    const form = $("lotForm");
    const firstCard = form?.querySelector(".cm-form-card");

    if (form && firstCard && !$("lotDecisionV4")) {
      const box = document.createElement("section");
      box.id = "lotDecisionV4";
      box.className = "v4-decision";
      box.innerHTML = `<div class="v4-error">Open a CB Child to load Product Master decision.</div>`;
      firstCard.insertAdjacentElement("afterend", box);
    }

    const sticky = form?.querySelector(".cm-sticky");

    if (sticky && !$("lotMessageV4")) {
      const box = document.createElement("div");
      box.id = "lotMessageV4";
      box.className = "v4-message";
      box.hidden = true;
      sticky.insertAdjacentElement("beforebegin", box);
    }
  }

  function message(text = "", type = "") {
    addUi();
    const box = $("lotMessageV4");
    if (!box) return;
    box.textContent = text;
    box.className = `v4-message ${type}`.trim();
    box.hidden = !text;
    if (text) box.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  async function loadPrints() {
    const view = await client.from("rr_print_library_view").select("*");
    if (!view.error) return view.data || [];

    const table = await client.from("rr_print_master").select("*");
    if (table.error) throw table.error;
    return table.data || [];
  }

  async function loadRefs() {
    if (!client) throw new Error("Supabase client is unavailable.");

    const [
      units,
      assignments,
      printAssignments,
      arts,
      prints,
      media
    ] = await Promise.all([
      client.from("rr_cb_units").select("*"),
      client.from("rr_cb_art_assignments").select("*"),
      client.from("rr_cb_print_assignments").select("*").order("sequence_no"),
      client.from("rr_art_master").select("*"),
      loadPrints(),
      client.from("rr_media").select("*")
    ]);

    for (const result of [units, assignments, printAssignments, arts, media]) {
      if (result.error) throw result.error;
    }

    refs = {
      units: units.data || [],
      assignments: assignments.data || [],
      printAssignments: printAssignments.data || [],
      arts: arts.data || [],
      prints,
      media: media.data || []
    };
  }
    function unitById(id) {
    return refs.units.find(row => String(row.id) === String(id)) || null;
  }

  function assignmentByUnit(id) {
    return refs.assignments.find(
      row => String(row.cb_id) === String(id)
    ) || null;
  }

  function decision(id) {
    const direct = assignmentByUnit(id);

    if (direct) {
      return buildDecision(direct, false);
    }

    const parentId = unitById(id)?.parent_unit_id;
    const inherited = parentId ? assignmentByUnit(parentId) : null;

    return inherited
      ? buildDecision(inherited, true)
      : { assignment: null, art: null, prints: [], images: [], inherited: false };
  }

  function buildDecision(assignment, inherited) {
    const art = refs.arts.find(
      row => String(row.id) === String(assignment.art_id)
    ) || null;

    const printIds = refs.printAssignments
      .filter(row => String(row.assignment_id) === String(assignment.id))
      .sort((a, b) => Number(a.sequence_no || 0) - Number(b.sequence_no || 0))
      .map(row => String(row.print_id));

    const prints = printIds
      .map(id => refs.prints.find(row => String(row.id) === id))
      .filter(Boolean);

    const entityIds = new Set(
      [art?.id, ...prints.map(row => row.id)]
        .filter(Boolean)
        .map(String)
    );

    const directImages = [art, ...prints].flatMap(row => [
      row?.image_url,
      row?.artwork_url,
      row?.garment_image_url,
      row?.garment_preview_url,
      row?.preview_url,
      row?.reference_image_url,
      row?.file_url
    ]).filter(Boolean);

    const mediaImages = refs.media
      .filter(row => entityIds.has(String(row.entity_id)))
      .sort((a, b) =>
        Number(Boolean(b.is_cover)) - Number(Boolean(a.is_cover)) ||
        Number(a.sort_order || 0) - Number(b.sort_order || 0)
      )
      .map(row => row.file_url)
      .filter(Boolean);

    return {
      assignment,
      art,
      prints,
      images: [...new Set([...directImages, ...mediaImages])],
      inherited
    };
  }

  function artNo(art) {
    return art?.art_no || art?.art_code || art?.code || art?.name || "";
  }

  function printNo(print) {
    return print?.print_no || print?.print_code || print?.code || print?.name || "";
  }

  function styleName(art) {
    return (
      art?.style_name ||
      art?.style ||
      art?.product_style ||
      art?.category_name ||
      art?.category ||
      ""
    );
  }

  function decisionHtml(data, compact = false) {
    if (!data.assignment || !data.art) {
      return `
        <div class="v4-head">
          <small>PRODUCT MASTER DECISION</small>
          <span class="v4-source">Missing</span>
        </div>
        <div class="v4-error">
          Art is not decided for this CB Child. Product Master me Art decide karein.
        </div>
      `;
    }

    const prints = data.prints.map(printNo).filter(Boolean);
    const source = data.inherited ? "Inherited Parent" : "Direct Child";
    const limit = compact ? 3 : 6;

    return `
      <div class="v4-head">
        <small>PRODUCT MASTER DECISION</small>
        <span class="v4-source">${safe(source)}</span>
      </div>
      <div class="v4-meta">
        <span><small>Art No</small><strong>${safe(artNo(data.art) || "—")}</strong></span>
        <span><small>Print No</small><strong>${safe(prints.join(", ") || "No Print")}</strong></span>
        <span><small>Style</small><strong>${safe(styleName(data.art) || "—")}</strong></span>
        <span><small>Status</small><strong>${safe(data.assignment.status || "Decided")}</strong></span>
      </div>
      ${data.images.length ? `
        <div class="v4-images">
          ${data.images.slice(0, limit).map(url =>
            `<img src="${safe(url)}" alt="Art Print Reference" loading="lazy">`
          ).join("")}
        </div>
      ` : ""}
    `;
  }

  async function fillLotDecision(unitId) {
    await loadRefs();

    const data = decision(unitId);
    const box = $("lotDecisionV4");

    if (box) box.innerHTML = decisionHtml(data, false);
    if ($("artNo")) $("artNo").value = data.art ? artNo(data.art) : "";
    if ($("printNo")) {
      $("printNo").value = data.prints.map(printNo).filter(Boolean).join(", ");
    }

    if ($("styleName") && !$("styleName").value.trim() && data.art) {
      $("styleName").value = styleName(data.art);
    }

    if ($("releaseLotBtn")) {
      $("releaseLotBtn").disabled = !data.assignment || !data.art;
    }

    if (!data.assignment || !data.art) {
      message(
        "Art decision missing. Product Master me Art decide karke phir Lot release karein.",
        "error"
      );
    } else {
      message("");
    }
  }
    function updateBundles() {
    const inputs = [...document.querySelectorAll("#cuttingMatrix .cm-size-qty")];
    let pieces = 0;
    let bundles = 0;

    inputs.forEach(input => {
      const qty = Math.max(0, Math.floor(Number(input.value || 0)));
      pieces += qty;
      if (qty > 0) bundles += 1;
    });

    if ($("totalPieces")) $("totalPieces").textContent = String(pieces);
    if ($("totalBundles")) $("totalBundles").textContent = String(bundles);
    if ($("bundleQty")) $("bundleQty").value = "1";
  }

  function rows() {
    return [...document.querySelectorAll("#cuttingMatrix .cm-size-qty")]
      .map(input => ({
        cb_colour_id: input.dataset.colourId,
        colour_name: input.dataset.colourName,
        size_code: input.dataset.size,
        qty: Math.max(0, Math.floor(Number(input.value || 0)))
      }))
      .filter(row => row.qty > 0);
  }

  function sizes() {
    return [...new Set(
      String($("sizeSet")?.value || "")
        .split(",")
        .map(value => value.trim().toUpperCase())
        .filter(Boolean)
    )];
  }

  async function saveLot(event) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    addUi();

    const button = $("releaseLotBtn");
    const original = button?.textContent || "Release Lot No";

    if (button) {
      button.disabled = true;
      button.textContent = "Releasing…";
    }

    message("Checking and saving Lot…", "progress");

    try {
      const unitId = String($("lotUnitId")?.value || "").trim();
      if (!unitId) throw new Error("CB Child ID missing. Close and reopen.");

      await loadRefs();
      const data = decision(unitId);

      if (!data.assignment || !data.art) {
        throw new Error("Art decision missing in Product Master.");
      }

      const lotNo = String($("lotNo")?.value || "").trim().toUpperCase();
      const lotStyle = styleName(data.art) || String($("styleName")?.value || "").trim();
      const breakup = rows();
      const sizeSet = sizes();
      const unit = unitById(unitId);
      const weight = Number(
        unit?.divided_weight ??
        unit?.allocated_qty ??
        unit?.base_qty ??
        0
      );

      const used = Number($("fabricUsed")?.value || 0);
      const waste = Number($("wastageWeight")?.value || 0);
      const remnant = Number($("remnantWeight")?.value || 0);
      const settled = used + waste + remnant;

      if (!lotNo) throw new Error("Enter Lot No.");
      if (!lotStyle) throw new Error("Style missing in Product Master Art.");
      if (!sizeSet.length) throw new Error("Enter Sizes.");
      if (!breakup.length) throw new Error("Enter Colour × Size quantities.");

      if (Math.abs(settled - weight) > 0.001) {
        throw new Error(
          `Used + Wastage + Remnant must equal ${weight.toFixed(3)} kg.`
        );
      }

      const result = await client.rpc("rr_release_single_lot_v3", {
        p_lot_no: lotNo,
        p_cb_unit_id: unitId,
        p_release_date: $("lotDate")?.value || today(),
        p_style_name: lotStyle,
        p_art_no: artNo(data.art) || null,
        p_print_no: data.prints.map(printNo).filter(Boolean).join(", ") || null,
        p_operator_name: String($("operatorName")?.value || "").trim() || null,
        p_size_set: sizeSet,
        p_bundle_qty: 1,
        p_fabric_used: used,
        p_wastage_weight: waste,
        p_remnant_weight: remnant,
        p_base_cost: Math.max(0, Number($("baseCost")?.value || 0)),
        p_size_type: $("sizeType")?.value || "small",
        p_sleeve_type: $("sleeveType")?.value || "half",
        p_border_type: $("borderType")?.value || "without",
        p_custom_adjustment: Number($("customAdjustment")?.value || 0),
        p_notes: String($("lotNotes")?.value || "").trim() || null,
        p_breakup: breakup
      });

      if (result.error) throw result.error;

      message(
        `Lot ${lotNo} saved. ${breakup.length} Colour × Size entries = ${breakup.length} bundles.`,
        "success"
      );

      if (button) button.textContent = "Lot Released";

      setTimeout(() => window.location.reload(), 900);
    } catch (error) {
      console.error(error);
      message(errorText(error), "error");

      if (button) {
        button.disabled = false;
        button.textContent = original;
      }
    }
  }
    async function decorateCards() {
    try {
      await loadRefs();

      document.querySelectorAll(".cm-card").forEach(card => {
        const button = card.querySelector("[data-single]");
        const unitId = button?.dataset.single;
        if (!unitId) return;

        let box = card.querySelector(".v4-decision");

        if (!box) {
          box = document.createElement("div");
          box.className = "v4-decision";
          card.querySelector(".cm-actions")?.insertAdjacentElement("beforebegin", box);
        }

        box.innerHTML = decisionHtml(decision(unitId), true);
      });
    } catch (error) {
      console.warn("Card decision pull skipped:", error);
    }
  }

  function start() {
    addUi();

    const form = $("lotForm");

    if (form && !form.dataset.v4Bound) {
      form.dataset.v4Bound = "true";
      form.addEventListener("submit", saveLot, true);
    }

    document.addEventListener("click", event => {
      const button = event.target.closest("[data-single]");

      if (button) {
        setTimeout(() => {
          addUi();
          const unitId = String($("lotUnitId")?.value || button.dataset.single || "");
          if (unitId) fillLotDecision(unitId);
          updateBundles();
        }, 120);
      }

      if (event.target.closest("#refreshCutting")) {
        setTimeout(decorateCards, 900);
      }
    }, true);

    document.addEventListener("input", event => {
      if (event.target.matches("#cuttingMatrix .cm-size-qty")) {
        setTimeout(updateBundles, 0);
      }
    }, true);

    const matrix = $("cuttingMatrix");
    if (matrix) {
      new MutationObserver(() => setTimeout(updateBundles, 0))
        .observe(matrix, { childList: true, subtree: true });
    }

    const gallery = $("divisionGallery");
    if (gallery) {
      new MutationObserver(() => setTimeout(decorateCards, 250))
        .observe(gallery, { childList: true, subtree: true });
    }

    decorateCards();
    updateBundles();
    console.info("REDZED Cutting Master V4 patch loaded.");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
