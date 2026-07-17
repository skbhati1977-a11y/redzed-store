(() => {
  "use strict";

  window.REDZED_CUTTING_PATCH_VERSION = "5.0";

  const $ = id =>
    document.getElementById(id);

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

  const client = getClient();

  let refs = {
    units: [],
    assignments: [],
    printAssignments: [],
    arts: [],
    prints: [],
    media: []
  };

  let refsLoadedAt = 0;
  let refsLoadingPromise = null;

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
      error?.code
        ? `Code: ${error.code}`
        : ""
    ]
      .filter(Boolean)
      .join(" — ") ||
      "Cutting operation failed.";
  }

  function today() {
    const date = new Date();

    return [
      date.getFullYear(),
      String(
        date.getMonth() + 1
      ).padStart(2, "0"),
      String(
        date.getDate()
      ).padStart(2, "0")
    ].join("-");
  }

  function latestDate(row) {
    return String(
      row?.updated_at ||
      row?.created_at ||
      ""
    );
  }

  function unitId(row) {
    return (
      row?.id ||
      row?.division_id ||
      null
    );
  }

  function unitCode(row) {
    return (
      row?.cb_code ||
      row?.division_code ||
      (
        row?.division_index
          ? `S${row.division_index}`
          : "CB Child"
      )
    );
  }

  function unitById(id) {
    return refs.units.find(
      row =>
        String(unitId(row)) ===
        String(id)
    ) || null;
  }

  function parentUnit(row) {
    if (!row?.parent_unit_id) {
      return null;
    }

    return unitById(
      row.parent_unit_id
    );
  }

  function assignmentByUnit(id) {
    return refs.assignments
      .filter(
        row =>
          String(row.cb_id) ===
          String(id)
      )
      .sort(
        (a, b) =>
          latestDate(b)
            .localeCompare(
              latestDate(a)
            )
      )[0] || null;
  }

  function artById(id) {
    return refs.arts.find(
      row =>
        String(row.id) ===
        String(id)
    ) || null;
  }

  function printById(id) {
    return refs.prints.find(
      row =>
        String(row.id) ===
        String(id)
    ) || null;
  }

  function artNo(art) {
    return (
      art?.art_no ||
      art?.art_code ||
      art?.code ||
      art?.name ||
      ""
    );
  }

  function printNo(print) {
    return (
      print?.print_no ||
      print?.print_code ||
      print?.code ||
      print?.name ||
      ""
    );
  }

  function styleName(art) {
    return (
      art?.style_name ||
      art?.style ||
      art?.product_style ||
      art?.product_name ||
      art?.item_name ||
      art?.category_name ||
      art?.category ||
      ""
    );
  }

  function assignmentPrintIds(
    assignmentId
  ) {
    return refs.printAssignments
      .filter(
        row =>
          String(
            row.assignment_id
          ) ===
          String(assignmentId)
      )
      .sort(
        (a, b) =>
          Number(
            a.sequence_no || 0
          ) -
          Number(
            b.sequence_no || 0
          )
      )
      .map(
        row =>
          String(row.print_id)
      )
      .filter(Boolean);
  }

  /*
   * Normal child:
   * S1 uses direct Product Master decision.
   *
   * Combo child:
   * S1A / S1B / S1C inherit S1 decision.
   *
   * Deeper split:
   * Parent chain is checked recursively.
   */
  function decisionSource(unitIdValue) {
    let current =
      unitById(unitIdValue);

    let inherited = false;
    let depth = 0;

    const visited =
      new Set();

    while (
      current &&
      depth < 20
    ) {
      const currentId =
        String(unitId(current));

      if (
        visited.has(currentId)
      ) {
        break;
      }

      visited.add(currentId);

      const assignment =
        assignmentByUnit(
          currentId
        );

      if (assignment) {
        return {
          assignment,
          sourceUnit: current,
          inherited,
          depth
        };
      }

      current =
        parentUnit(current);

      inherited = true;
      depth += 1;
    }

    return {
      assignment: null,
      sourceUnit: null,
      inherited: false,
      depth: 0
    };
  }

  function mediaImagesFor(
    entityIds
  ) {
    const ids = new Set(
      entityIds
        .filter(Boolean)
        .map(String)
    );

    if (!ids.size) {
      return [];
    }

    return refs.media
      .filter(
        row =>
          ids.has(
            String(row.entity_id)
          )
      )
      .sort(
        (a, b) =>
          Number(
            Boolean(b.is_cover)
          ) -
            Number(
              Boolean(a.is_cover)
            ) ||
          Number(
            a.sort_order || 0
          ) -
            Number(
              b.sort_order || 0
            )
      )
      .map(
        row =>
          row.file_url
      )
      .filter(Boolean);
  }

  function directImagesFor(rows) {
    return rows
      .flatMap(row => [
        row?.hero_image_url,
        row?.image_url,
        row?.artwork_url,
        row?.garment_image_url,
        row?.garment_preview_url,
        row?.preview_url,
        row?.reference_image_url,
        row?.file_url
      ])
      .filter(Boolean);
  }

  function emptyDecision() {
    return {
      assignment: null,
      sourceUnit: null,
      art: null,
      prints: [],
      images: [],
      inherited: false,
      inheritanceDepth: 0,
      printNotApplicable: false,
      printStatus: "due",
      artStatus: "due",
      ready: false
    };
  }

  function buildDecision(
    assignment,
    sourceUnit,
    inherited,
    depth
  ) {
    if (!assignment) {
      return emptyDecision();
    }

    const art =
      artById(
        assignment.art_id
      );

    const printIds =
      assignmentPrintIds(
        assignment.id
      );

    const prints =
      printIds
        .map(printById)
        .filter(Boolean);

    const printNotApplicable =
      assignment
        .print_not_applicable ===
      true;

    const artStatus =
      assignment.art_id &&
      art
        ? "decided"
        : "due";

    const printStatus =
      printNotApplicable
        ? "na"
        : prints.length
          ? "decided"
          : "due";

    const ready =
      artStatus === "decided" &&
      (
        printStatus === "decided" ||
        printStatus === "na"
      );

    const entityIds = [
      art?.id,
      ...prints.map(
        print => print.id
      )
    ];

    const images = [
      ...new Set([
        ...directImagesFor([
          art,
          ...prints
        ]),
        ...mediaImagesFor(
          entityIds
        )
      ])
    ];

    return {
      assignment,
      sourceUnit,
      art,
      prints,
      images,
      inherited,
      inheritanceDepth:
        Number(depth || 0),
      printNotApplicable,
      printStatus,
      artStatus,
      ready
    };
  }

  function decision(unitIdValue) {
    const source =
      decisionSource(
        unitIdValue
      );

    if (!source.assignment) {
      return emptyDecision();
    }

    return buildDecision(
      source.assignment,
      source.sourceUnit,
      source.inherited,
      source.depth
    );
  }

  function printLabel(data) {
    if (
      data.printStatus === "na"
    ) {
      return (
        "N/A — No Print Required"
      );
    }

    if (
      data.printStatus ===
      "decided"
    ) {
      return (
        data.prints
          .map(printNo)
          .filter(Boolean)
          .join(", ") ||
        "Print Decided"
      );
    }

    return "Print Due";
  }

  function decisionStatus(data) {
    if (
      data.artStatus === "due"
    ) {
      return "Art Due";
    }

    if (
      data.printStatus === "due"
    ) {
      return "Print Due";
    }

    return "Ready for Cutting";
  }

  function inheritanceLabel(data) {
    if (
      !data.assignment
    ) {
      return "Missing";
    }

    if (!data.inherited) {
      return "Direct Child";
    }

    return `Inherited ${unitCode(
      data.sourceUnit
    )}`;
  }

  function isCuttingReady(
    unitIdValue
  ) {
    return decision(
      unitIdValue
    ).ready;
  }

  function wait(milliseconds) {
    return new Promise(
      resolve =>
        window.setTimeout(
          resolve,
          milliseconds
        )
    );
  }

  async function waitForBasePage() {
    const startedAt =
      Date.now();

    while (
      Date.now() - startedAt <
      15000
    ) {
      if (
        $("lotForm") &&
        $("divisionGallery") &&
        $("cuttingMatrix") &&
        getClient()
      ) {
        return;
      }

      await wait(100);
    }

    throw new Error(
      "Cutting Master base page did not become ready."
    );
  }
  function addUiStyles() {
    if ($("cuttingV5Style")) {
      return;
    }

    const style =
      document.createElement("style");

    style.id =
      "cuttingV5Style";

    style.textContent = `
      .v5-decision {
        margin: 12px 0;
        padding: 12px;
        border: 1px solid #3a3a44;
        border-radius: 14px;
        background: #0d0d11;
      }

      .v5-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        margin-bottom: 9px;
      }

      .v5-head small {
        color: #ff7b86;
        font-size: 10px;
        font-weight: 900;
        letter-spacing: .05em;
      }

      .v5-source {
        flex: 0 0 auto;
        padding: 4px 7px;
        border-radius: 999px;
        background: #24242b;
        color: #bbb;
        font-size: 10px;
        font-weight: 800;
      }

      .v5-ready {
        background: #14331f;
        color: #b9efc8;
      }

      .v5-due {
        background: #3a1a20;
        color: #ffc4c9;
      }

      .v5-meta {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 7px;
      }

      .v5-meta span {
        min-width: 0;
        padding: 9px;
        border-radius: 9px;
        background: #18181e;
        font-size: 12px;
      }

      .v5-meta small {
        display: block;
        margin-bottom: 4px;
        color: #999;
        font-size: 10px;
        font-weight: 800;
      }

      .v5-meta strong {
        display: block;
        overflow-wrap: anywhere;
      }

      .v5-images {
        display: flex;
        gap: 7px;
        overflow-x: auto;
        margin-top: 9px;
        padding-bottom: 2px;
      }

      .v5-images img {
        width: 72px;
        height: 72px;
        flex: 0 0 72px;
        object-fit: cover;
        object-position: center;
        border-radius: 10px;
      }

      .v5-error {
        color: #ffb6bd;
        font-size: 12px;
        line-height: 1.45;
      }

      .v5-message {
        margin: 0 0 10px;
        padding: 11px;
        border-radius: 12px;
        background: #17171d;
      }

      .v5-message.error {
        background: #3a1a20;
        color: #ffc4c9;
      }

      .v5-message.success {
        background: #14331f;
        color: #b9efc8;
      }

      .v5-message.progress {
        background: #332711;
        color: #ffe0a0;
      }

      .v5-hidden-not-ready {
        display: none !important;
      }

      @media (max-width: 620px) {
        .v5-meta {
          grid-template-columns: 1fr;
        }
      }
    `;

    document.head.appendChild(
      style
    );
  }

  function addUi() {
    addUiStyles();

    const bundle =
      $("bundleQty");

    if (bundle) {
      bundle.value = "1";

      bundle
        .closest("label")
        ?.style
        .setProperty(
          "display",
          "none"
        );
    }

    [
      "artNo",
      "printNo"
    ].forEach(id => {
      const input = $(id);

      if (input) {
        input.readOnly = true;
      }
    });

    const matrixCard =
      $("cuttingMatrix")
        ?.closest(
          ".cm-form-card"
        );

    const matrixNote =
      matrixCard
        ?.querySelector(
          ".cm-form-title p"
        );

    if (matrixNote) {
      matrixNote.textContent =
        "Each non-zero Colour × Size entry is exactly one bundle.";
    }

    const form =
      $("lotForm");

    const firstCard =
      form
        ?.querySelector(
          ".cm-form-card"
        );

    if (
      form &&
      firstCard &&
      !$("lotDecisionV5")
    ) {
      const box =
        document.createElement(
          "section"
        );

      box.id =
        "lotDecisionV5";

      box.className =
        "v5-decision";

      box.innerHTML = `
        <div class="v5-error">
          Open a cutting-ready CB Child to load Product Master decision.
        </div>
      `;

      firstCard.insertAdjacentElement(
        "afterend",
        box
      );
    }

    const sticky =
      form
        ?.querySelector(
          ".cm-sticky"
        );

    if (
      sticky &&
      !$("lotMessageV5")
    ) {
      const box =
        document.createElement(
          "div"
        );

      box.id =
        "lotMessageV5";

      box.className =
        "v5-message";

      box.hidden = true;

      sticky.insertAdjacentElement(
        "beforebegin",
        box
      );
    }
  }

  function message(
    text = "",
    type = ""
  ) {
    addUi();

    const box =
      $("lotMessageV5");

    if (!box) {
      return;
    }

    box.textContent =
      text;

    box.className =
      `v5-message ${type}`.trim();

    box.hidden =
      !text;

    if (text) {
      box.scrollIntoView({
        behavior: "smooth",
        block: "nearest"
      });
    }
  }

  async function loadPrints() {
    const view =
      await client
        .from(
          "rr_print_library_view"
        )
        .select("*");

    if (!view.error) {
      return view.data || [];
    }

    console.warn(
      "rr_print_library_view unavailable; using rr_print_master.",
      view.error
    );

    const table =
      await client
        .from(
          "rr_print_master"
        )
        .select("*");

    if (table.error) {
      throw table.error;
    }

    return table.data || [];
  }

  async function loadRefs(
    force = false
  ) {
    if (!client) {
      throw new Error(
        "Supabase client is unavailable."
      );
    }

    const age =
      Date.now() -
      refsLoadedAt;

    if (
      !force &&
      refsLoadedAt &&
      age < 5000
    ) {
      return refs;
    }

    if (
      refsLoadingPromise &&
      !force
    ) {
      return refsLoadingPromise;
    }

    refsLoadingPromise =
      (async () => {
        const [
          units,
          assignments,
          printAssignments,
          arts,
          prints,
          media
        ] = await Promise.all([
          client
            .from(
              "rr_cb_units"
            )
            .select("*"),

          client
            .from(
              "rr_cb_art_assignments"
            )
            .select("*"),

          client
            .from(
              "rr_cb_print_assignments"
            )
            .select("*")
            .order(
              "sequence_no"
            ),

          client
            .from(
              "rr_art_master"
            )
            .select("*"),

          loadPrints(),

          client
            .from(
              "rr_media"
            )
            .select("*")
        ]);

        for (
          const result of [
            units,
            assignments,
            printAssignments,
            arts,
            media
          ]
        ) {
          if (result.error) {
            throw result.error;
          }
        }

        refs = {
          units:
            units.data || [],

          assignments:
            assignments.data ||
            [],

          printAssignments:
            printAssignments.data ||
            [],

          arts:
            arts.data || [],

          prints,

          media:
            media.data || []
        };

        refsLoadedAt =
          Date.now();

        return refs;
      })();

    try {
      return await refsLoadingPromise;
    } finally {
      refsLoadingPromise =
        null;
    }
  }

  function decisionHtml(
    data,
    compact = false
  ) {
    if (
      !data.assignment ||
      !data.art
    ) {
      return `
        <div class="v5-head">
          <small>
            PRODUCT MASTER DECISION
          </small>

          <span class="v5-source v5-due">
            Missing
          </span>
        </div>

        <div class="v5-error">
          Art is not decided for this CB Child.
        </div>
      `;
    }

    const source =
      inheritanceLabel(data);

    const status =
      decisionStatus(data);

    const statusClass =
      data.ready
        ? "v5-ready"
        : "v5-due";

    const limit =
      compact
        ? 3
        : 6;

    return `
      <div class="v5-head">
        <small>
          PRODUCT MASTER DECISION
        </small>

        <span class="v5-source">
          ${safe(source)}
        </span>
      </div>

      <div class="v5-meta">
        <span>
          <small>Art No</small>

          <strong>
            ${safe(
              artNo(data.art) ||
              "—"
            )}
          </strong>
        </span>

        <span>
          <small>
            Print Decision
          </small>

          <strong>
            ${safe(
              printLabel(data)
            )}
          </strong>
        </span>

        <span>
          <small>Style</small>

          <strong>
            ${safe(
              styleName(
                data.art
              ) ||
              "—"
            )}
          </strong>
        </span>

        <span>
          <small>
            Cutting Status
          </small>

          <strong
            class="${statusClass}"
          >
            ${safe(status)}
          </strong>
        </span>
      </div>

      ${
        data.images.length
          ? `
            <div class="v5-images">
              ${data.images
                .slice(
                  0,
                  limit
                )
                .map(
                  url => `
                    <img
                      src="${safe(url)}"
                      alt="Art Print Reference"
                      loading="lazy"
                    >
                  `
                )
                .join("")}
            </div>
          `
          : ""
      }
    `;
  }

  async function fillLotDecision(
    unitIdValue
  ) {
    await loadRefs(true);

    const data =
      decision(
        unitIdValue
      );

    const box =
      $("lotDecisionV5");

    if (box) {
      box.innerHTML =
        decisionHtml(
          data,
          false
        );
    }

    if ($("artNo")) {
      $("artNo").value =
        data.art
          ? artNo(data.art)
          : "";
    }

    if ($("printNo")) {
      $("printNo").value =
        data.printStatus ===
        "na"
          ? "N/A"
          : data.prints
              .map(printNo)
              .filter(Boolean)
              .join(", ");
    }

    if (
      $("styleName") &&
      !$("styleName")
        .value
        .trim() &&
      data.art
    ) {
      $("styleName").value =
        styleName(data.art);
    }

    const releaseButton =
      $("releaseLotBtn");

    if (releaseButton) {
      releaseButton.disabled =
        !data.ready;
    }

    if (
      data.artStatus === "due"
    ) {
      message(
        "Art Due: Product Master me Art decide karein.",
        "error"
      );
    } else if (
      data.printStatus ===
      "due"
    ) {
      message(
        "Print Due: Print select karein ya explicitly N/A — No Print Required choose karein.",
        "error"
      );
    } else {
      message("");
    }

    return data;
  }

  function updateBundles() {
    const inputs = [
      ...document
        .querySelectorAll(
          "#cuttingMatrix .cm-size-qty"
        )
    ];

    let pieces = 0;
    let bundles = 0;

    inputs.forEach(input => {
      const quantity =
        Math.max(
          0,
          Math.floor(
            Number(
              input.value || 0
            )
          )
        );

      pieces += quantity;

      if (quantity > 0) {
        bundles += 1;
      }
    });

    if ($("totalPieces")) {
      $("totalPieces")
        .textContent =
        String(pieces);
    }

    if ($("totalBundles")) {
      $("totalBundles")
        .textContent =
        String(bundles);
    }

    if ($("bundleQty")) {
      $("bundleQty").value =
        "1";
    }
  }

  function breakupRows() {
    return [
      ...document
        .querySelectorAll(
          "#cuttingMatrix .cm-size-qty"
        )
    ]
      .map(input => ({
        cb_colour_id:
          input.dataset
            .colourId,

        colour_name:
          input.dataset
            .colourName,

        size_code:
          input.dataset.size,

        qty:
          Math.max(
            0,
            Math.floor(
              Number(
                input.value ||
                0
              )
            )
          )
      }))
      .filter(
        row =>
          row.qty > 0
      );
  }

  function selectedSizes() {
    return [
      ...new Set(
        String(
          $("sizeSet")
            ?.value ||
          ""
        )
          .split(",")
          .map(
            value =>
              value
                .trim()
                .toUpperCase()
          )
          .filter(Boolean)
      )
    ];
  }

  function unitWeight(row) {
    return Number(
      row?.divided_weight ??
      row?.allocated_qty ??
      row?.base_qty ??
      0
    );
  }
  function currentCostSnapshot() {
    const baseCost =
      Math.max(
        0,
        Number(
          $("baseCost")
            ?.value ||
          0
        )
      );

    const customAdjustment =
      Number(
        $("customAdjustment")
          ?.value ||
        0
      );

    return {
      baseCost,
      customAdjustment
    };
  }

  async function saveLot(event) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    addUi();

    const button =
      $("releaseLotBtn");

    const originalLabel =
      button?.textContent ||
      "Release Lot No";

    if (button) {
      button.disabled = true;
      button.textContent =
        "Releasing…";
    }

    message(
      "Checking Product Master decision and saving Lot…",
      "progress"
    );

    try {
      const unitIdValue =
        String(
          $("lotUnitId")
            ?.value ||
          ""
        ).trim();

      if (!unitIdValue) {
        throw new Error(
          "CB Child ID missing. Close the Lot form and reopen it."
        );
      }

      await loadRefs(true);

      const data =
        decision(
          unitIdValue
        );

      if (
        data.artStatus === "due" ||
        !data.art
      ) {
        throw new Error(
          "Art Due: Product Master me Art decide karein."
        );
      }

      if (
        data.printStatus ===
        "due"
      ) {
        throw new Error(
          "Print Due: Print select karein ya explicitly N/A — No Print Required choose karein."
        );
      }

      if (!data.ready) {
        throw new Error(
          "This CB Child is not ready for Cutting."
        );
      }

      const lotNo =
        String(
          $("lotNo")
            ?.value ||
          ""
        )
          .trim()
          .toUpperCase();

      const lotStyle =
        styleName(
          data.art
        ) ||
        String(
          $("styleName")
            ?.value ||
          ""
        ).trim();

      const sizeSet =
        selectedSizes();

      const breakup =
        breakupRows();

      const unit =
        unitById(
          unitIdValue
        );

      if (!unit) {
        throw new Error(
          "CB Child record could not be found."
        );
      }

      const weight =
        unitWeight(unit);

      const fabricUsed =
        Number(
          $("fabricUsed")
            ?.value ||
          0
        );

      const wastageWeight =
        Number(
          $("wastageWeight")
            ?.value ||
          0
        );

      const remnantWeight =
        Number(
          $("remnantWeight")
            ?.value ||
          0
        );

      const settledWeight =
        fabricUsed +
        wastageWeight +
        remnantWeight;

      const cost =
        currentCostSnapshot();

      if (!lotNo) {
        throw new Error(
          "Enter Lot No."
        );
      }

      if (!lotStyle) {
        throw new Error(
          "Style is missing in Product Master Art."
        );
      }

      if (!sizeSet.length) {
        throw new Error(
          "Enter Sizes."
        );
      }

      if (!breakup.length) {
        throw new Error(
          "Enter Colour × Size quantities."
        );
      }

      if (
        Math.abs(
          settledWeight -
          weight
        ) > 0.001
      ) {
        throw new Error(
          `Fabric Used + Wastage + Remnant must equal ${weight.toFixed(3)} kg.`
        );
      }

      const printValue =
        data.printStatus ===
        "na"
          ? "N/A"
          : data.prints
              .map(printNo)
              .filter(Boolean)
              .join(", ");

      const result =
        await client.rpc(
          "rr_release_single_lot_v3",
          {
            p_lot_no:
              lotNo,

            p_cb_unit_id:
              unitIdValue,

            p_release_date:
              $("lotDate")
                ?.value ||
              today(),

            p_style_name:
              lotStyle,

            p_art_no:
              artNo(
                data.art
              ) ||
              null,

            p_print_no:
              printValue ||
              null,

            p_operator_name:
              String(
                $("operatorName")
                  ?.value ||
                ""
              ).trim() ||
              null,

            p_size_set:
              sizeSet,

            /*
             * Locked V5 rule:
             * Every non-zero Colour × Size row
             * is treated as one bundle.
             */
            p_bundle_qty:
              1,

            p_fabric_used:
              fabricUsed,

            p_wastage_weight:
              wastageWeight,

            p_remnant_weight:
              remnantWeight,

            p_base_cost:
              cost.baseCost,

            p_size_type:
              $("sizeType")
                ?.value ||
              "small",

            p_sleeve_type:
              $("sleeveType")
                ?.value ||
              "half",

            p_border_type:
              $("borderType")
                ?.value ||
              "without",

            p_custom_adjustment:
              cost.customAdjustment,

            p_notes:
              String(
                $("lotNotes")
                  ?.value ||
                ""
              ).trim() ||
              null,

            p_breakup:
              breakup
          }
        );

      if (result.error) {
        throw result.error;
      }

      message(
        `Lot ${lotNo} saved successfully. ${breakup.length} Colour × Size entries = ${breakup.length} bundles.`,
        "success"
      );

      if (button) {
        button.textContent =
          "Lot Released";
      }

      await loadRefs(true);

      window.setTimeout(
        () => {
          window.location.reload();
        },
        900
      );
    } catch (error) {
      console.error(
        "Cutting Master V5 Lot save failed:",
        error
      );

      message(
        errorText(error),
        "error"
      );

      if (button) {
        button.disabled =
          false;

        button.textContent =
          originalLabel;
      }
    }
  }

  function cardUnitId(card) {
    const singleButton =
      card.querySelector(
        "[data-single]"
      );

    if (
      singleButton
        ?.dataset
        ?.single
    ) {
      return String(
        singleButton
          .dataset
          .single
      );
    }

    const multiButton =
      card.querySelector(
        "[data-multi]"
      );

    if (
      multiButton
        ?.dataset
        ?.multi
    ) {
      return String(
        multiButton
          .dataset
          .multi
      );
    }

    return "";
  }

  function cardLotReleased(card) {
    const singleButton =
      card.querySelector(
        "[data-single]"
      );

    return Boolean(
      singleButton?.disabled
    );
  }

  function addDecisionToCard(
    card,
    data
  ) {
    let box =
      card.querySelector(
        ".v5-decision"
      );

    if (!box) {
      box =
        document.createElement(
          "div"
        );

      box.className =
        "v5-decision";

      const actions =
        card.querySelector(
          ".cm-actions"
        );

      if (actions) {
        actions.insertAdjacentElement(
          "beforebegin",
          box
        );
      } else {
        card.appendChild(box);
      }
    }

    box.innerHTML =
      decisionHtml(
        data,
        true
      );
  }

  function hideNotReadyCard(
    card,
    data
  ) {
    const released =
      cardLotReleased(card);

    /*
     * Existing released Lots must remain visible,
     * even if an old Product Master decision is missing.
     *
     * New unreleased cards appear only when:
     * Art Decided AND
     * Print Decided / Explicit N/A.
     */
    const shouldHide =
      !released &&
      !data.ready;

    card.classList.toggle(
      "v5-hidden-not-ready",
      shouldHide
    );

    return shouldHide;
  }

  function updateVisibleEmptyState() {
    const gallery =
      $("divisionGallery");

    if (!gallery) {
      return;
    }

    const cards = [
      ...gallery.querySelectorAll(
        ".cm-card"
      )
    ];

    if (!cards.length) {
      return;
    }

    const visibleCards =
      cards.filter(
        card =>
          !card.classList.contains(
            "v5-hidden-not-ready"
          )
      );

    let empty =
      gallery.querySelector(
        ".v5-ready-empty"
      );

    if (
      !visibleCards.length
    ) {
      if (!empty) {
        empty =
          document.createElement(
            "article"
          );

        empty.className =
          "cm-empty v5-ready-empty";

        empty.innerHTML = `
          <h3>
            No Cutting-Ready CB Child
          </h3>

          <p>
            Product Master me Art aur Print decide karein, ya explicitly N/A — No Print Required select karein.
          </p>
        `;

        gallery.appendChild(
          empty
        );
      }

      empty.hidden = false;
    } else if (empty) {
      empty.hidden = true;
    }
  }

  async function decorateCards(
    force = false
  ) {
    try {
      await loadRefs(force);

      const gallery =
        $("divisionGallery");

      if (!gallery) {
        return;
      }

      const cards = [
        ...gallery.querySelectorAll(
          ".cm-card"
        )
      ];

      cards.forEach(card => {
        const unitIdValue =
          cardUnitId(card);

        if (!unitIdValue) {
          return;
        }

        const data =
          decision(
            unitIdValue
          );

        addDecisionToCard(
          card,
          data
        );

        hideNotReadyCard(
          card,
          data
        );
      });

      updateVisibleEmptyState();
    } catch (error) {
      console.warn(
        "Cutting Master V5 card decision loading skipped:",
        error
      );
    }
  }

  function bindLotOpening() {
    document.addEventListener(
      "click",
      event => {
        const button =
          event.target.closest(
            "[data-single]"
          );

        if (!button) {
          return;
        }

        const unitIdValue =
          String(
            button.dataset
              .single ||
            ""
          );

        window.setTimeout(
          async () => {
            try {
              addUi();

              const currentUnitId =
                String(
                  $("lotUnitId")
                    ?.value ||
                  unitIdValue
                );

              if (
                !currentUnitId
              ) {
                return;
              }

              await fillLotDecision(
                currentUnitId
              );

              updateBundles();
            } catch (error) {
              console.error(
                "Cutting Master V5 decision fill failed:",
                error
              );

              message(
                errorText(error),
                "error"
              );
            }
          },
          120
        );
      },
      true
    );
  }

  function bindBundleTracking() {
    document.addEventListener(
      "input",
      event => {
        if (
          event.target.matches(
            "#cuttingMatrix .cm-size-qty"
          )
        ) {
          window.setTimeout(
            updateBundles,
            0
          );
        }
      },
      true
    );

    const matrix =
      $("cuttingMatrix");

    if (matrix) {
      new MutationObserver(
        () => {
          window.setTimeout(
            updateBundles,
            0
          );
        }
      ).observe(
        matrix,
        {
          childList: true,
          subtree: true
        }
      );
    }
  }

  function bindGalleryTracking() {
    const gallery =
      $("divisionGallery");

    if (!gallery) {
      return;
    }

    let timer = 0;

    new MutationObserver(
      () => {
        window.clearTimeout(
          timer
        );

        timer =
          window.setTimeout(
            () => {
              decorateCards()
                .catch(
                  error =>
                    console.warn(
                      error
                    )
                );
            },
            250
          );
      }
    ).observe(
      gallery,
      {
        childList: true,
        subtree: true
      }
    );
  }
  function bindRefresh() {
    document.addEventListener(
      "click",
      event => {
        if (
          !event.target.closest(
            "#refreshCutting"
          )
        ) {
          return;
        }

        refsLoadedAt = 0;

        window.setTimeout(
          () => {
            decorateCards(true)
              .catch(error =>
                console.warn(
                  "V5 refresh decoration failed:",
                  error
                )
              );
          },
          900
        );
      },
      true
    );
  }

  function bindLotSubmit() {
    const form =
      $("lotForm");

    if (
      !form ||
      form.dataset.v5Bound ===
        "true"
    ) {
      return;
    }

    form.dataset.v5Bound =
      "true";

    /*
     * Capture mode stops the old V3 submit handler
     * before it can save manual Art / Print values.
     */
    form.addEventListener(
      "submit",
      saveLot,
      true
    );
  }

  function lockLotIdentityInputs() {
    [
      "artNo",
      "printNo"
    ].forEach(id => {
      const input = $(id);

      if (!input) {
        return;
      }

      input.readOnly = true;
      input.setAttribute(
        "aria-readonly",
        "true"
      );

      input.title =
        "Auto-filled from Product Master";
    });
  }

  function validateCurrentLotDecision() {
    const unitIdValue =
      String(
        $("lotUnitId")
          ?.value ||
        ""
      ).trim();

    if (!unitIdValue) {
      return null;
    }

    return decision(
      unitIdValue
    );
  }

  function protectReleaseButton() {
    const button =
      $("releaseLotBtn");

    if (!button) {
      return;
    }

    document.addEventListener(
      "click",
      event => {
        const clicked =
          event.target.closest(
            "#releaseLotBtn"
          );

        if (!clicked) {
          return;
        }

        const data =
          validateCurrentLotDecision();

        if (
          !data ||
          !data.ready
        ) {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();

          if (
            data?.artStatus ===
            "due"
          ) {
            message(
              "Art Due: Product Master me Art decide karein.",
              "error"
            );
          } else {
            message(
              "Print Due: Print select karein ya explicitly N/A — No Print Required choose karein.",
              "error"
            );
          }
        }
      },
      true
    );
  }

  function syncLotFormFields() {
    const form =
      $("lotForm");

    if (!form) {
      return;
    }

    const observer =
      new MutationObserver(
        () => {
          lockLotIdentityInputs();

          if ($("bundleQty")) {
            $("bundleQty").value =
              "1";
          }
        }
      );

    observer.observe(
      form,
      {
        childList: true,
        subtree: true,
        attributes: true
      }
    );
  }

  async function initialLoad() {
    await waitForBasePage();

    if (!client) {
      throw new Error(
        "Supabase client is unavailable."
      );
    }

    addUi();
    lockLotIdentityInputs();
    bindLotSubmit();
    bindLotOpening();
    bindBundleTracking();
    bindGalleryTracking();
    bindRefresh();
    protectReleaseButton();
    syncLotFormFields();

    await loadRefs(true);
    await decorateCards(true);

    updateBundles();

    console.info(
      "REDZED Cutting Master V5 integration loaded."
    );
  }

  async function start() {
    try {
      await initialLoad();
    } catch (error) {
      console.error(
        "REDZED Cutting Master V5 start failed:",
        error
      );

      const target =
        $("cmMessage");

      if (target) {
        target.textContent =
          `V5 error: ${errorText(error)}`;

        target.className =
          "rr-message error";
      }
    }
  }

  if (
    document.readyState ===
    "loading"
  ) {
    document.addEventListener(
      "DOMContentLoaded",
      start,
      {
        once: true
      }
    );
  } else {
    start();
  }
})();
