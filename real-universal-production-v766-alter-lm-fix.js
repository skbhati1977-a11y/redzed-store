(() => {
  "use strict";

  const VERSION = "V766_ALTER_LM_DROPDOWN_FIX";
  const $ = id => document.getElementById(id);
  const upper = value => String(value || "").trim().toUpperCase();
  const normalizeRole = value => upper(value).replace(/[\s-]+/g, "_");
  const asArray = value => Array.isArray(value) ? value : [];

  let currentCanonicalLotId = null;
  let lastCandidates = [];
  let lastEnrolment = null;
  let hydrateRun = 0;

  function client() {
    return window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;
  }

  function message(text, isError = false) {
    const box = $("alterEvidenceMsg");
    if (!box) return;
    box.textContent = text || "";
    box.className = `msg${isError ? " error" : ""}`;
  }

  function unwrapEnrolment(value) {
    if (!value) return null;
    if (Object.prototype.hasOwnProperty.call(value, "to_jsonb")) return value.to_jsonb || null;
    if (Object.prototype.hasOwnProperty.call(value, "row_to_json")) return value.row_to_json || null;
    return value;
  }

  function activeLineMen(rows) {
    const seen = new Set();
    return asArray(rows).filter(row => {
      const id = String(row?.worker_id || "");
      const role = normalizeRole(row?.role_code);
      const active = row?.is_active !== false && upper(row?.access_status || "ACTIVE") === "ACTIVE";
      if (!id || role !== "LINE_MAN" || !active || seen.has(id)) return false;
      seen.add(id);
      return true;
    });
  }

  function optionLabel(row) {
    return [row.worker_name, row.worker_code, row.department_code]
      .filter(Boolean)
      .join(" · ");
  }

  function ensureSearchInput(select) {
    let input = $("alterLineManSearch");
    if (input) return input;

    input = document.createElement("input");
    input.id = "alterLineManSearch";
    input.type = "search";
    input.autocomplete = "off";
    input.placeholder = "Search Lot Line Man";
    input.setAttribute("aria-label", "Search Lot Line Man");
    input.style.width = "100%";
    input.style.margin = "6px 0";
    select.parentElement.insertBefore(input, select);
    input.addEventListener("input", () => renderOptions(input.value));
    return input;
  }

  function renderOptions(query = "") {
    const select = $("alterLineManSelect");
    if (!select) return;

    const search = upper(query);
    const enrolledId = String(lastEnrolment?.person_id || "");
    const previous = String(select.value || "");
    const rows = lastCandidates.filter(row => !search || upper(optionLabel(row)).includes(search));

    select.innerHTML = "";

    if (!enrolledId) {
      const placeholder = new Option("Select Lot Line Man (mandatory)", "", true, !previous);
      placeholder.disabled = true;
      select.add(placeholder);
    }

    for (const row of rows) {
      const option = new Option(optionLabel(row), String(row.worker_id));
      option.dataset.roleCode = "LINE_MAN";
      select.add(option);
    }

    const desired = enrolledId || previous;
    if (desired && [...select.options].some(option => option.value === desired)) {
      select.value = desired;
    } else if (!enrolledId) {
      select.value = "";
    }

    // Existing Lot LM is shown and attached here. Real replacement must use CHANGE LOT LM.
    select.disabled = Boolean(enrolledId);
    const searchInput = $("alterLineManSearch");
    if (searchInput) searchInput.disabled = Boolean(enrolledId);
  }

  async function fetchContext() {
    const sb = client();
    const department = $("dept")?.value;
    if (!sb || !currentCanonicalLotId || !department) return null;

    const { data, error } = await sb.rpc("rr_upm_universal_form_v741", {
      p_canonical_lot_id: currentCanonicalLotId,
      p_department_code: department
    });
    if (error) throw error;
    return data || null;
  }

  async function hydrateLineManDropdown() {
    const modal = $("alterEvidenceModal");
    const select = $("alterLineManSelect");
    if (!modal || !select || modal.classList.contains("hidden")) return;

    const thisRun = ++hydrateRun;
    ensureSearchInput(select);
    message("Lot Line Man mapping verify हो रही है…");

    try {
      const context = await fetchContext();
      if (thisRun !== hydrateRun || modal.classList.contains("hidden")) return;

      const mapping = context?.mapping_context || {};
      lastEnrolment = unwrapEnrolment(mapping.line_man_enrolment);
      lastCandidates = activeLineMen(mapping.line_man_candidates);

      // Keep an active enrolled LM visible even when an older RPC omitted it from candidates.
      if (lastEnrolment?.person_id && !lastCandidates.some(row => String(row.worker_id) === String(lastEnrolment.person_id))) {
        lastCandidates.unshift({
          worker_id: lastEnrolment.person_id,
          worker_name: lastEnrolment.person_name_snapshot || "Enrolled Line Man",
          worker_code: lastEnrolment.worker_code_snapshot || "",
          department_code: lastEnrolment.department_code_snapshot || "",
          role_code: "LINE_MAN",
          is_active: true,
          access_status: "ACTIVE"
        });
      }

      if (!lastCandidates.length) {
        select.innerHTML = '<option value="">No active Line Man found</option>';
        select.disabled = true;
        message("Active Line Man नहीं मिला। Worker Directory में LINE_MAN role active करें।", true);
        return;
      }

      renderOptions("");

      if (lastEnrolment?.person_id) {
        message(`${lastEnrolment.person_name_snapshot || "Lot Line Man"} इस Lot का enrolled Line Man है। बदलने के लिए CHANGE LOT LM handover इस्तेमाल करें।`);
      } else {
        message("Lot Line Man चुनना mandatory है। Production worker अपने-आप Line Man नहीं बनेगा।");
      }
    } catch (error) {
      console.error(VERSION, error);
      message(error?.message || String(error), true);
    }
  }

  function validateBeforeSave(event) {
    const save = event.target.closest?.("#saveAlterEvidence");
    if (!save) return;

    const select = $("alterLineManSelect");
    const selectedId = String(select?.value || "");
    const enrolledId = String(lastEnrolment?.person_id || "");
    const selected = lastCandidates.find(row => String(row.worker_id) === selectedId);

    let error = "";
    if (!selectedId) error = "Lot Line Man selection mandatory है।";
    else if (!selected || normalizeRole(selected.role_code) !== "LINE_MAN") error = "केवल active Line Man select किया जा सकता है।";
    else if (enrolledId && selectedId !== enrolledId) error = "Lot Line Man बदलने के लिए CHANGE LOT LM handover इस्तेमाल करें।";

    if (error) {
      event.preventDefault();
      event.stopImmediatePropagation();
      message(error, true);
      select?.focus();
    }
  }

  // Capture the canonical Lot before the existing page's click handlers run.
  document.addEventListener("click", event => {
    const target = event.target.closest?.("[data-open-lot], .lot-card[data-lot]");
    const id = target?.dataset?.openLot || target?.dataset?.lot;
    if (id) currentCanonicalLotId = id;
  }, true);

  document.addEventListener("click", validateBeforeSave, true);

  const observer = new MutationObserver(() => {
    const modal = $("alterEvidenceModal");
    if (modal && !modal.classList.contains("hidden")) {
      queueMicrotask(hydrateLineManDropdown);
    }
  });

  function boot() {
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["class"]
    });
    console.info(`${VERSION} ready`);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
