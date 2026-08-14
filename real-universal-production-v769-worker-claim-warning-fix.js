(() => {
  "use strict";

  const VERSION = "V769_WORKER_CLAIM_REASON_WARNING_GATE";
  const $ = id => document.getElementById(id);
  const upper = value => String(value || "").trim().toUpperCase();
  const esc = value => String(value ?? "").replace(/[&<>"']/g, char => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[char]);
  const positiveNumber = value => {
    const number = Number(String(value ?? "").replace(/[^0-9.-]/g, ""));
    return Number.isFinite(number) && number > 0 ? number : 0;
  };

  const WORKER_CLAIM_REASONS = [
    { value: "MAKING_FAULT", label: "Making Fault / Garment Making Defect" },
    { value: "STITCHING_CENTER_OUT", label: "Stitching Center Out / Alignment Fault" },
    { value: "SHORT_RECEIVE", label: "Short Receive · Worker ने कम PCS Receive किए" },
    { value: "SHORT_SUBMIT", label: "Short Submit · Worker ने कम PCS Submit किए" },
    { value: "WRONG_SIZE_COLOUR", label: "Wrong Size / Colour Mixing" },
    { value: "QUALITY_REJECT", label: "Quality Reject · Worker Process Fault" },
    { value: "PHYSICAL_PIECE_LOST", label: "Physical Piece Lost / Missing in Worker Hold" },
    { value: "ALTER_NOT_COMPLETED_BEFORE_DISPATCH", label: "Alter Dispatch से पहले Complete नहीं किया" },
    { value: "REMAKE_NOT_COMPLETED_BEFORE_DISPATCH", label: "Remake Dispatch से पहले Complete नहीं किया" },
    { value: "NO_RESPONSE_24H_AUTO_DAMAGE", label: "No Response within 24 Hours · Auto Alter-to-Damage" },
    { value: "OTHER_WORKER_FAULT", label: "Other Worker Responsibility" }
  ];

  const GATED_REASONS = {
    NO_RESPONSE_24H_AUTO_DAMAGE: {
      source: "ALTER",
      require24Hours: true,
      label: "No Response within 24 Hours"
    },
    ALTER_NOT_COMPLETED_BEFORE_DISPATCH: {
      source: "ALTER",
      require24Hours: false,
      label: "Alter Dispatch से पहले Complete नहीं किया"
    },
    REMAKE_NOT_COMPLETED_BEFORE_DISPATCH: {
      source: "REMAKE",
      require24Hours: false,
      label: "Remake Dispatch से पहले Complete नहीं किया"
    }
  };

  let currentCanonicalLotId = "";
  let patchScheduled = false;

  function client() {
    return window.supabaseClient
      || window.supabaseDb
      || window.redzedSupabase
      || window.sb
      || null;
  }

  function cssEscape(value) {
    if (globalThis.CSS?.escape) return CSS.escape(String(value));
    return String(value).replace(/["\\]/g, "\\$&");
  }

  function resolveCanonicalLotId() {
    if (currentCanonicalLotId) return currentCanonicalLotId;

    const lotNo = [...document.querySelectorAll("#identity .box")]
      .find(box => upper(box.querySelector("small")?.textContent) === "LOT NO")
      ?.querySelector("b")?.textContent?.trim();

    if (!lotNo) return "";
    const card = [...document.querySelectorAll(".lot-card[data-lot]")]
      .find(node => node.querySelector(".lot-no")?.textContent?.trim() === lotNo);

    if (card?.dataset?.lot) currentCanonicalLotId = String(card.dataset.lot);
    return currentCanonicalLotId;
  }

  function captureLotFromClick(event) {
    const target = event.target.closest?.("[data-open-lot], .lot-card[data-lot]");
    const id = target?.dataset?.openLot || target?.dataset?.lot;
    if (id) currentCanonicalLotId = String(id);
  }

  function createSearchableReason(host, items) {
    host.innerHTML = `
      <div class="v757-search-select v769-search-select">
        <input type="search" class="v757-search-input v769-worker-claim-input"
          placeholder="Search worker claim reason" autocomplete="off" spellcheck="false">
        <input type="hidden" class="v757-search-value v769-worker-claim-value">
        <button type="button" class="v757-search-toggle" aria-label="Open worker claim reasons">▼</button>
        <div class="v757-search-list" hidden></div>
      </div>`;

    const root = host.querySelector(".v769-search-select");
    const input = host.querySelector(".v769-worker-claim-input");
    const hidden = host.querySelector(".v769-worker-claim-value");
    const toggle = host.querySelector(".v757-search-toggle");
    const list = host.querySelector(".v757-search-list");

    const render = query => {
      const search = upper(query);
      const filtered = items.filter(item =>
        !search || upper(`${item.label} ${item.value}`).includes(search)
      );
      list.innerHTML = filtered.length
        ? filtered.map(item => `
          <button type="button" class="v757-search-option"
            data-value="${esc(item.value)}">${esc(item.label)}</button>`).join("")
        : '<div class="v757-search-empty">No matching worker claim reason</div>';
      list.hidden = false;
    };

    const choose = item => {
      hidden.value = item.value;
      input.value = item.label;
      root.classList.add("has-value");
      list.hidden = true;
      host.dispatchEvent(new CustomEvent("v769reasonchange", {
        bubbles: true,
        detail: item
      }));
    };

    input.addEventListener("focus", () => render(input.value));
    input.addEventListener("input", () => {
      hidden.value = "";
      root.classList.remove("has-value");
      render(input.value);
    });
    toggle.addEventListener("click", () => {
      if (list.hidden) render(input.value);
      else list.hidden = true;
      input.focus();
    });
    list.addEventListener("click", event => {
      const option = event.target.closest(".v757-search-option");
      if (!option) return;
      const item = items.find(entry => entry.value === option.dataset.value);
      if (item) choose(item);
    });
    document.addEventListener("click", event => {
      if (!root.contains(event.target)) list.hidden = true;
    });

    return {
      getValue: () => hidden.value,
      clear: () => {
        hidden.value = "";
        input.value = "";
        root.classList.remove("has-value");
        list.hidden = true;
      }
    };
  }

  function isDamagePanel(panel) {
    return Boolean(panel?.querySelector(".v759-responsibility-box")
      && panel.querySelector(".v759-damage-size"));
  }

  function setGateNote(panel, text, type = "") {
    const note = panel.querySelector(".v769-warning-note");
    if (!note) return;
    note.textContent = text || "";
    note.className = `v769-warning-note ${type}`.trim();
  }

  function syncModeUi(panel) {
    const mode = panel.querySelector(".v759-responsibility-mode")?.value || "WORKER_CLAIM";
    const workerWrap = panel.querySelector(".v769-worker-claim-wrap");
    if (workerWrap) workerWrap.hidden = mode !== "WORKER_CLAIM";

    if (mode !== "WORKER_CLAIM") {
      const baseHost = panel.querySelector(".v759-no-claim-reason-host");
      const baseHidden = baseHost?.querySelector(".v757-search-value");
      const baseInput = baseHost?.querySelector(".v757-search-input");
      const workerCodes = new Set(WORKER_CLAIM_REASONS.map(item => item.value));
      if (baseHidden && workerCodes.has(baseHidden.value)) {
        baseHidden.value = "";
        if (baseInput) baseInput.value = "";
      }
      setGateNote(panel, "No-Claim mode में existing No-Claim Reason mandatory रहेगा.");
      return;
    }

    const reason = panel.querySelector(".v769-worker-claim-value")?.value || "";
    const gate = GATED_REASONS[reason];
    if (!gate) {
      setGateNote(panel, "Worker Claim Reason mandatory है. Claim current responsible holder पर backend rule के अनुसार लगेगा.");
      return;
    }

    const timing = gate.require24Hours
      ? "पहली 2 warnings के बाद, first warning से 24 घंटे पूरे होने पर तीसरी attempt में Alter Damage बनेगा."
      : "पहली 2 warnings के बाद तीसरी attempt में selected hold Damage बनेगा.";
    setGateNote(panel, `${gate.label}: ${timing}`, "warn");
  }

  function patchDamagePanel(panel) {
    if (!isDamagePanel(panel) || panel.dataset.v769Ready === "1") return;

    const responsibilityBox = panel.querySelector(".v759-responsibility-box");
    const noClaimWrap = panel.querySelector(".v759-no-claim-wrap");
    if (!responsibilityBox || !noClaimWrap) return;

    const workerWrap = document.createElement("div");
    workerWrap.className = "v769-worker-claim-wrap";
    workerWrap.innerHTML = `
      <label>Worker Claim Reason <b class="v769-required">MANDATORY</b></label>
      <div class="v769-worker-claim-reason-host"></div>`;
    noClaimWrap.insertAdjacentElement("beforebegin", workerWrap);

    const note = document.createElement("div");
    note.className = "v769-warning-note";
    responsibilityBox.insertAdjacentElement("afterend", note);

    const controller = createSearchableReason(
      workerWrap.querySelector(".v769-worker-claim-reason-host"),
      WORKER_CLAIM_REASONS
    );
    panel._v769WorkerReason = controller;

    panel.querySelectorAll(".v759-mode").forEach(button => {
      button.addEventListener("click", () => queueMicrotask(() => syncModeUi(panel)));
    });
    workerWrap.addEventListener("v769reasonchange", () => syncModeUi(panel));

    panel.dataset.v769Ready = "1";
    syncModeUi(panel);
  }

  function patchDamagePanels(root = document) {
    if (root.matches?.(".v756-inline-action")) patchDamagePanel(root);
    root.querySelectorAll?.(".v756-inline-action").forEach(patchDamagePanel);
  }

  function schedulePatch(root = document) {
    if (patchScheduled) return;
    patchScheduled = true;
    queueMicrotask(() => {
      patchScheduled = false;
      patchDamagePanels(root);
    });
  }

  function panelContext(panel) {
    const inlineRow = panel.closest(".v756-inline-row");
    const actionRow = inlineRow?.previousElementSibling?.classList.contains("v756-colour-row")
      ? inlineRow.previousElementSibling
      : panel.closest("tr")?.previousElementSibling;
    const colourCode = upper(
      actionRow?.dataset?.v756Colour
      || panel.querySelector(".v756-inline-head b")?.textContent?.match(/\bC\d+\b/i)?.[0]
    );
    const departmentCode = upper(
      actionRow?.dataset?.v756Department
      || $("dept")?.value
    );

    const card = [...document.querySelectorAll(".colour-card")].find(node =>
      upper(node.querySelector(".colour-title")?.textContent).includes(colourCode)
    );
    const workerSelect = card?.querySelector(".colour-worker");
    const workerId = workerSelect?.value || "";
    const workerName = workerSelect?.selectedOptions?.[0]?.textContent?.trim() || "";

    return {
      canonicalLotId: resolveCanonicalLotId(),
      departmentCode,
      colourCode,
      workerId,
      workerName
    };
  }

  function selectedDamageItems(panel) {
    return [...panel.querySelectorAll(".v759-damage-size")].map(item => {
      const qty = positiveNumber(item.querySelector(".v759-damage-qty")?.value);
      const source = upper(item.querySelector(".v759-damage-source")?.value);
      const engineIndex = item.dataset.engineRow || "";
      const engineRow = engineIndex
        ? document.querySelector(`[data-row-index="${cssEscape(engineIndex)}"]`)
        : null;
      const sizeCode = upper(
        engineRow?.querySelector("td:first-child")?.textContent
        || item.querySelector("b")?.textContent
      );
      return { item, qty, source, sizeCode };
    }).filter(row => row.qty > 0);
  }

  function copyReasonIntoExistingDamagePayload(panel, mode, reason) {
    const baseHidden = panel.querySelector(
      ".v759-no-claim-reason-host .v757-search-value"
    );
    if (!baseHidden) return;

    // V759 always sends reasonSearch.getValue(). For WORKER_CLAIM we place the
    // selected worker reason in the same payload field immediately before save.
    if (mode === "WORKER_CLAIM") baseHidden.value = reason;
  }

  async function callWarningGate(context, item, reasonCode, gate) {
    const sb = client();
    if (!sb || typeof sb.rpc !== "function") {
      throw new Error("Connected Supabase client नहीं मिला.");
    }
    if (!context.canonicalLotId) throw new Error("Canonical Lot ID नहीं मिला.");
    if (!context.departmentCode) throw new Error("Department mapping नहीं मिला.");
    if (!context.colourCode) throw new Error("Colour mapping नहीं मिला.");
    if (!item.sizeCode) throw new Error("Size mapping नहीं मिला.");

    const { data, error } = await sb.rpc("rr_upm_worker_claim_warning_gate_v769", {
      p_canonical_lot_id: context.canonicalLotId,
      p_department_code: context.departmentCode,
      p_colour_code: context.colourCode,
      p_size_code: item.sizeCode,
      p_worker_id: context.workerId || null,
      p_reason_code: reasonCode,
      p_qty: item.qty,
      p_require_24_hours: Boolean(gate.require24Hours),
      p_metadata: {
        source_bucket: item.source,
        worker_name: context.workerName || null,
        ui_version: VERSION
      }
    });

    if (error) {
      const message = [error.message, error.details, error.hint, error.code]
        .filter(Boolean).join(" — ");
      throw new Error(message || String(error));
    }
    return data || {};
  }

  function warningMessage(result, context, item) {
    const prefix = `${context.colourCode} / ${item.sizeCode}`;
    const action = upper(result.action);
    if (action === "WARNING_1") {
      return `${prefix}: पहली warning दर्ज हुई. Alter/Remake holder को तुरंत complete करने को कहें.`;
    }
    if (action === "WARNING_2") {
      return `${prefix}: दूसरी और अंतिम warning दर्ज हुई. अगली eligible attempt पर Worker Claim Damage बनेगा.`;
    }
    if (action === "WAIT_24H") {
      const remaining = Number(result.remaining_hours || 0).toFixed(1);
      return `${prefix}: 2 warnings दर्ज हैं, लेकिन 24 घंटे पूरे नहीं हुए. लगभग ${remaining} घंटे बाकी हैं.`;
    }
    if (action === "ALLOW_DAMAGE") {
      return `${prefix}: Final warning gate complete. Selected ${item.source} hold अब Damage में convert होकर Worker Claim बनेगा.`;
    }
    return `${prefix}: ${result.message || action || "Warning status updated."}`;
  }

  async function runWarningGate(panel, button, reasonCode, gate, selectedItems) {
    const context = panelContext(panel);
    const results = [];

    for (const item of selectedItems) {
      const result = await callWarningGate(context, item, reasonCode, gate);
      results.push({ item, result });
    }

    const blocked = results.filter(({ result }) => !result.allowed);
    if (blocked.length) {
      const messages = results.map(({ item, result }) => warningMessage(result, context, item));
      setGateNote(panel, messages.join(" "), "warn");
      alert(messages.join("\n\n"));
      return false;
    }

    const finalMessages = results.map(({ item, result }) => warningMessage(result, context, item));
    setGateNote(panel, finalMessages.join(" "), "success");
    alert(
      `FINAL WORKER CLAIM ALERT\n\n${finalMessages.join("\n")}\n\n` +
      "अब existing Damage engine ALTER/REMAKE balance को Damage में register करेगा."
    );

    button.dataset.v769Bypass = "1";
    button.disabled = false;
    button.click();
    return true;
  }

  function validateDamageSaveCapture(event) {
    const button = event.target.closest?.(".v756-inline-save");
    if (!button) return;

    const panel = button.closest(".v756-inline-action");
    if (!isDamagePanel(panel)) return;
    patchDamagePanel(panel);

    const mode = panel.querySelector(".v759-responsibility-mode")?.value || "WORKER_CLAIM";
    if (button.dataset.v769Bypass === "1") {
      delete button.dataset.v769Bypass;
      const reason = panel.querySelector(".v769-worker-claim-value")?.value || "";
      copyReasonIntoExistingDamagePayload(panel, mode, reason);
      return;
    }

    if (mode !== "WORKER_CLAIM") return;

    const reasonCode = panel.querySelector(".v769-worker-claim-value")?.value || "";
    if (!reasonCode) {
      event.preventDefault();
      event.stopImmediatePropagation();
      setGateNote(panel, "Worker Claim Reason select करना mandatory है.", "error");
      panel.querySelector(".v769-worker-claim-input")?.focus();
      alert("Worker Claim Reason select करें.");
      return;
    }

    const selectedItems = selectedDamageItems(panel);
    if (!selectedItems.length) {
      // Base V759 will show the standard quantity validation.
      copyReasonIntoExistingDamagePayload(panel, mode, reasonCode);
      return;
    }

    const gate = GATED_REASONS[reasonCode];
    if (!gate) {
      copyReasonIntoExistingDamagePayload(panel, mode, reasonCode);
      return;
    }

    const wrongSource = selectedItems.find(item => item.source !== gate.source);
    if (wrongSource) {
      event.preventDefault();
      event.stopImmediatePropagation();
      const message = `${gate.label} reason केवल ${gate.source} hold balance पर लागू होगा. ` +
        `${wrongSource.sizeCode} में source ${wrongSource.source || "EMPTY"} है.`;
      setGateNote(panel, message, "error");
      alert(message);
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    button.disabled = true;
    const oldText = button.textContent;
    button.textContent = "CHECKING WARNINGS...";

    let continuedToDamageSave = false;
    runWarningGate(panel, button, reasonCode, gate, selectedItems)
      .then(continued => {
        continuedToDamageSave = Boolean(continued);
      })
      .catch(error => {
        console.error(VERSION, error);
        const text = error?.message || String(error);
        setGateNote(panel, text, "error");
        alert(
          `${text}\n\nV769 SQL install न होने पर REAL_FACTORY_V769_WORKER_CLAIM_WARNING_GATE.sql Run करें.`
        );
      })
      .finally(() => {
        if (!continuedToDamageSave && button.isConnected) {
          button.disabled = false;
          button.textContent = oldText;
        }
      });
  }

  function installStyles() {
    if ($("v769WorkerClaimStyles")) return;
    const style = document.createElement("style");
    style.id = "v769WorkerClaimStyles";
    style.textContent = `
      .v769-worker-claim-wrap{display:grid;gap:7px;margin-top:8px}
      .v769-required{font-size:10px;color:#ffce57;border:1px solid #8c6720;border-radius:999px;padding:2px 6px;margin-left:5px}
      .v769-warning-note{margin:9px 0;padding:9px 11px;border-left:4px solid #3d7db6;background:#111a27;border-radius:7px;font-size:13px;line-height:1.45}
      .v769-warning-note.warn{border-left-color:#d79b22;background:#211b0c}
      .v769-warning-note.error{border-left-color:#df4254;background:#251014}
      .v769-warning-note.success{border-left-color:#32bb72;background:#0f2118}
      .v769-search-select{position:relative}
    `;
    document.head.appendChild(style);
  }

  function boot() {
    installStyles();
    document.addEventListener("click", captureLotFromClick, true);
    document.addEventListener("click", validateDamageSaveCapture, true);

    const observer = new MutationObserver(mutations => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType !== 1) continue;
          if (node.matches?.(".v756-inline-row,.v756-inline-action")
            || node.querySelector?.(".v756-inline-action")) {
            schedulePatch(node);
            return;
          }
        }
      }
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
