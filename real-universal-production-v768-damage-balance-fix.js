(() => {
  "use strict";

  const VERSION = "V768_DAMAGE_BUCKET_BALANCE_SYNC";
  const number = value => {
    const parsed = Number(String(value ?? "").replace(/[^0-9.-]/g, ""));
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  };

  let scheduled = false;
  let patching = false;

  function ensureAlterForm() {
    if (document.getElementById("alterEvidenceModal")) return;

    const modal = document.createElement("div");
    modal.id = "alterEvidenceModal";
    modal.className = "modal hidden";
    modal.innerHTML = `
      <section class="sheet" style="height:auto;max-height:95vh">
        <div class="top">
          <h2>Alter Fill Evidence</h2>
          <button id="closeAlterEvidence" type="button">Close</button>
        </div>
        <p class="msg">Live camera evidence 1–3 images mandatory. Physical piece submission must be confirmed.</p>
        <label class="field">
          <span>Camera Evidence</span>
          <input id="alterEvidenceFiles" type="file" accept="image/*" capture="environment" multiple>
        </label>
        <label class="field">
          <span>Lot Line Man</span>
          <select id="alterLineManSelect" required>
            <option value="">Select Lot Line Man (mandatory)</option>
          </select>
        </label>
        <video id="liveCamera" autoplay playsinline class="camera-video hidden"></video>
        <canvas id="cameraCanvas" class="hidden"></canvas>
        <div class="actions">
          <button id="startCamera" type="button">OPEN LIVE CAMERA</button>
          <button id="captureCamera" type="button" class="warning" disabled>CAPTURE PHOTO</button>
          <button id="stopCamera" type="button" disabled>STOP CAMERA</button>
        </div>
        <div id="alterEvidencePreview" class="entry-images"></div>
        <label style="display:flex;gap:10px;align-items:center;margin:12px 0">
          <input id="physicalEvidenceSubmitted" type="checkbox" style="width:20px;height:20px">
          <span>Physical Alter Piece मेरे पास है</span>
        </label>
        <div class="actions">
          <button id="saveAlterEvidence" class="warning" type="button">SAVE ALTER FILL</button>
        </div>
        <p id="alterEvidenceMsg" class="msg"></p>
      </section>`;
    document.body.appendChild(modal);
  }

  // V769 page lost the ALTER modal markup while the existing ALTER JS handlers
  // remained active. Restore only that missing form before DOMContentLoaded so
  // the original production/ALTER handlers bind normally.
  ensureAlterForm();

  function findEngineRow(index) {
    if (index == null || index === "") return null;
    const safe = globalThis.CSS?.escape ? CSS.escape(String(index)) : String(index).replace(/"/g, '\\"');
    return document.querySelector(`[data-row-index="${safe}"]`);
  }

  function balancesFromEngineRow(row) {
    if (!row) return { PENDING: 0, ALTER: 0, REMAKE: 0 };

    const cells = row.querySelectorAll("td");
    const goodQty = number(cells[2]?.textContent);
    const directPendingMax = number(row.querySelector(".alterEntry")?.getAttribute("max"));

    return {
      // Backend PENDING means current assignment/worker pending balance.
      // It is not the global Good Qty shown in the table.
      PENDING: Math.min(goodQty, directPendingMax),
      ALTER: number(cells[4]?.textContent),
      REMAKE: number(cells[9]?.textContent)
    };
  }

  function sourceLabel(source, qty) {
    return ({
      PENDING: `Current Worker Pending · Max ${qty}`,
      ALTER: `Alter Pending · Max ${qty}`,
      REMAKE: `Remake Pending · Max ${qty}`
    })[source] || source;
  }

  function syncItem(item, force = false) {
    if (!item || (item.dataset.v768Ready === "1" && !force)) return;

    const engineRow = findEngineRow(item.dataset.engineRow);
    const balances = balancesFromEngineRow(engineRow);
    const oldSelect = item.querySelector(".v759-damage-source");
    const input = item.querySelector(".v759-damage-qty");
    const label = item.querySelector(".v759-damage-max");
    if (!oldSelect || !input || !label) return;

    const previous = oldSelect.value;
    const select = document.createElement("select");
    select.className = oldSelect.className;
    select.setAttribute("aria-label", "Damage source balance");

    for (const source of ["PENDING", "ALTER", "REMAKE"]) {
      const qty = balances[source];
      if (qty <= 0) continue;
      const option = new Option(sourceLabel(source, qty), source);
      option.dataset.maximum = String(qty);
      select.add(option);
    }

    if (!select.options.length) {
      const option = new Option("No hold balance available", "");
      option.disabled = true;
      option.selected = true;
      select.add(option);
    } else if ([...select.options].some(option => option.value === previous)) {
      select.value = previous;
    }

    oldSelect.replaceWith(select);

    const applyMaximum = () => {
      const source = select.value;
      const maximum = number(balances[source]);
      input.max = String(maximum);
      input.disabled = maximum <= 0;
      if (number(input.value) > maximum) input.value = String(maximum);
      if (maximum <= 0) input.value = "0";
      label.textContent = maximum > 0
        ? `Actual ${source} hold balance: ${maximum} PCS`
        : "Current worker/state hold balance: 0 PCS";
    };

    select.addEventListener("change", applyMaximum);
    item.dataset.v768Pending = String(balances.PENDING);
    item.dataset.v768Alter = String(balances.ALTER);
    item.dataset.v768Remake = String(balances.REMAKE);
    item.dataset.v768Ready = "1";
    applyMaximum();
  }

  function addPanelNote(panel) {
    if (!panel || panel.querySelector(".v768-damage-balance-note")) return;
    const firstSize = panel.querySelector(".v759-damage-size");
    if (!firstSize) return;

    const note = document.createElement("div");
    note.className = "v759-damage-rule v768-damage-balance-note";
    note.textContent = "Damage केवल उस worker/state के actual hold balance से save होगा. Global Good Qty को PENDING balance नहीं माना जाएगा.";
    firstSize.closest(".v756-size-grid")?.before(note);
  }

  function patchDamagePanels() {
    if (patching) return;
    patching = true;
    try {
      document.querySelectorAll(".v759-damage-size").forEach(item => syncItem(item));
      document.querySelectorAll(".v756-inline-panel, .v756-inline-action, .v756-inline-wrap")
        .forEach(addPanelNote);
    } finally {
      patching = false;
    }
  }

  function schedulePatch() {
    if (scheduled) return;
    scheduled = true;
    queueMicrotask(() => {
      scheduled = false;
      patchDamagePanels();
    });
  }

  function validateDamageSave(event) {
    const button = event.target.closest?.(".v756-inline-save");
    if (!button) return;
    const panel = button.closest(".v756-inline-panel, .v756-inline-action, .v756-inline-wrap")
      || button.parentElement?.parentElement;
    const items = [...(panel?.querySelectorAll?.(".v759-damage-size") || [])];
    if (!items.length) return;

    for (const item of items) {
      syncItem(item, true);
      const select = item.querySelector(".v759-damage-source");
      const input = item.querySelector(".v759-damage-qty");
      const qty = number(input?.value);
      if (qty <= 0) continue;

      const source = select?.value || "";
      const maximum = number(input?.max);
      const size = findEngineRow(item.dataset.engineRow)
        ?.querySelector("td:first-child")?.textContent?.trim() || "Size";

      if (!source || maximum <= 0 || qty > maximum) {
        event.preventDefault();
        event.stopImmediatePropagation();
        alert(`${size}: Damage ${qty} current hold balance ${maximum} से ज्यादा है. Refresh करके सही source/qty चुनें.`);
        return;
      }
    }
  }

  function boot() {
    ensureAlterForm();
    document.addEventListener("click", validateDamageSave, true);

    const observer = new MutationObserver(mutations => {
      if (mutations.some(mutation => [...mutation.addedNodes].some(node =>
        node.nodeType === 1 && (
          node.matches?.(".v759-damage-size, .v756-inline-panel, .v756-inline-action, .v756-inline-wrap")
          || node.querySelector?.(".v759-damage-size")
        )
      ))) schedulePatch();
    });

    observer.observe(document.body, { childList: true, subtree: true });
    patchDamagePanels();
    console.info(`${VERSION} ready`);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
