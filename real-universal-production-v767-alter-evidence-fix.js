(() => {
  "use strict";

  const VERSION = "V767_ALTER_EVIDENCE_STABLE_LM";
  const $ = id => document.getElementById(id);
  const upper = value => String(value || "").trim().toUpperCase();
  const normalizeRole = value => upper(value).replace(/[\s-]+/g, "_");
  const asArray = value => Array.isArray(value) ? value : [];

  let currentCanonicalLotId = "";
  let lastCandidates = [];
  let lastEnrolment = null;
  let modalOpenSequence = 0;
  let modalWasVisible = false;
  let scheduledTimer = null;
  let activeHydration = null;
  let hydrationKey = "";

  function client() {
    return window.supabaseClient
      || window.supabaseDb
      || window.redzedSupabase
      || window.sb
      || null;
  }

  function setEvidenceMessage(text, isError = false) {
    const box = $("alterEvidenceMsg");
    if (!box) return;

    const nextText = text || "";
    const nextClass = `msg${isError ? " error" : ""}`;
    if (box.textContent !== nextText) box.textContent = nextText;
    if (box.className !== nextClass) box.className = nextClass;
  }

  function unwrapEnrolment(value) {
    if (!value) return null;
    if (Object.prototype.hasOwnProperty.call(value, "to_jsonb")) {
      return value.to_jsonb || null;
    }
    if (Object.prototype.hasOwnProperty.call(value, "row_to_json")) {
      return value.row_to_json || null;
    }
    return value;
  }

  function activeLineMen(rows) {
    const seen = new Set();

    return asArray(rows).filter(row => {
      const id = String(row?.worker_id || row?.person_id || "");
      const role = normalizeRole(
        row?.role_code
        || row?.worker_role_code
        || row?.role
        || "LINE_MAN"
      );
      const status = upper(row?.access_status || row?.status || "ACTIVE");
      const active = row?.is_active !== false
        && !["INACTIVE", "DISABLED", "CLOSED", "DELETED"].includes(status);

      if (!id || role !== "LINE_MAN" || !active || seen.has(id)) return false;
      seen.add(id);
      return true;
    }).map(row => ({
      ...row,
      worker_id: row.worker_id || row.person_id,
      role_code: "LINE_MAN"
    }));
  }

  function optionLabel(row) {
    return [
      row.worker_name || row.person_name_snapshot || row.name,
      row.worker_code || row.worker_code_snapshot,
      row.department_code || row.department_code_snapshot
    ].filter(Boolean).join(" · ");
  }

  function resolveCanonicalLotId() {
    if (currentCanonicalLotId) return currentCanonicalLotId;

    const lotNo = $("identity")
      ?.querySelector(".box:first-child b")
      ?.textContent
      ?.trim();

    if (!lotNo) return "";

    const card = [...document.querySelectorAll(".lot-card[data-lot]")]
      .find(node => node.querySelector(".lot-no")?.textContent?.trim() === lotNo);

    if (card?.dataset?.lot) currentCanonicalLotId = card.dataset.lot;
    return currentCanonicalLotId;
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

    select.parentElement?.insertBefore(input, select);
    input.addEventListener("input", () => renderOptions(input.value));
    return input;
  }

  function renderOptions(query = "") {
    const select = $("alterLineManSelect");
    if (!select) return;

    const search = upper(query);
    const enrolledId = String(lastEnrolment?.person_id || "");
    const previous = String(select.value || "");
    const rows = lastCandidates.filter(row =>
      !search || upper(optionLabel(row)).includes(search)
    );

    select.replaceChildren();

    if (!enrolledId) {
      const placeholder = new Option(
        "Select Lot Line Man (mandatory)",
        "",
        true,
        !previous
      );
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

    const lockedToEnrolledLm = Boolean(enrolledId);
    select.disabled = lockedToEnrolledLm;

    const searchInput = $("alterLineManSearch");
    if (searchInput) {
      searchInput.disabled = lockedToEnrolledLm;
      if (lockedToEnrolledLm) searchInput.value = "";
    }
  }

  async function fetchContext(canonicalLotId, departmentCode) {
    const sb = client();
    if (!sb || typeof sb.rpc !== "function") {
      throw new Error("Connected Supabase client नहीं मिला।");
    }

    const { data, error } = await sb.rpc("rr_upm_universal_form_v741", {
      p_canonical_lot_id: canonicalLotId,
      p_department_code: departmentCode
    });

    if (error) throw error;
    return data || null;
  }

  function prepareLoadingUi() {
    const select = $("alterLineManSelect");
    if (!select) return;

    ensureSearchInput(select);
    select.replaceChildren(new Option("Loading active Lot Line Man…", ""));
    select.disabled = true;

    const searchInput = $("alterLineManSearch");
    if (searchInput) {
      searchInput.value = "";
      searchInput.disabled = true;
    }

    setEvidenceMessage("Lot Line Man mapping verify हो रही है…");
  }

  async function hydrateLineManDropdown(force = false) {
    const modal = $("alterEvidenceModal");
    const select = $("alterLineManSelect");
    if (!modal || !select || modal.classList.contains("hidden")) return;

    const canonicalLotId = resolveCanonicalLotId();
    const departmentCode = String($("dept")?.value || "").trim();
    const key = `${modalOpenSequence}|${canonicalLotId}|${upper(departmentCode)}`;

    if (!force && hydrationKey === key) return;
    if (activeHydration?.key === key) return activeHydration.promise;

    if (!canonicalLotId) {
      setEvidenceMessage("Current Lot reference नहीं मिला। Lot बंद करके दोबारा CHECK IN करें।", true);
      return;
    }
    if (!departmentCode) {
      setEvidenceMessage("Current Department नहीं मिला।", true);
      return;
    }

    const sequenceAtStart = modalOpenSequence;
    prepareLoadingUi();

    const promise = (async () => {
      try {
        const context = await fetchContext(canonicalLotId, departmentCode);

        if (
          modal.classList.contains("hidden")
          || sequenceAtStart !== modalOpenSequence
        ) return;

        const mapping = context?.mapping_context || {};
        lastEnrolment = unwrapEnrolment(mapping.line_man_enrolment);
        lastCandidates = activeLineMen(mapping.line_man_candidates);

        if (
          lastEnrolment?.person_id
          && !lastCandidates.some(row =>
            String(row.worker_id) === String(lastEnrolment.person_id)
          )
        ) {
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
          select.replaceChildren(new Option("No active Line Man found", ""));
          select.disabled = true;
          const searchInput = $("alterLineManSearch");
          if (searchInput) searchInput.disabled = true;
          setEvidenceMessage(
            "Active Line Man नहीं मिला। Worker Directory में LINE_MAN role active करें।",
            true
          );
          hydrationKey = key;
          return;
        }

        renderOptions("");
        hydrationKey = key;

        if (lastEnrolment?.person_id) {
          setEvidenceMessage(
            `${lastEnrolment.person_name_snapshot || "Lot Line Man"} इस Lot का enrolled Line Man है।`
          );
        } else {
          setEvidenceMessage(
            "Lot Line Man चुनना mandatory है। Production worker अपने-आप Line Man नहीं बनेगा।"
          );
        }
      } catch (error) {
        console.error(VERSION, error);
        hydrationKey = "";
        select.replaceChildren(new Option("Line Man load failed", ""));
        select.disabled = true;
        setEvidenceMessage(error?.message || String(error), true);
      } finally {
        if (activeHydration?.key === key) activeHydration = null;
      }
    })();

    activeHydration = { key, promise };
    return promise;
  }

  function scheduleHydration(force = false) {
    if (scheduledTimer) clearTimeout(scheduledTimer);
    scheduledTimer = setTimeout(() => {
      scheduledTimer = null;
      hydrateLineManDropdown(force);
    }, 25);
  }

  function validateBeforeSave(event) {
    const save = event.target.closest?.("#saveAlterEvidence");
    if (!save) return;

    const select = $("alterLineManSelect");
    const selectedId = String(select?.value || "");
    const enrolledId = String(lastEnrolment?.person_id || "");
    const selected = lastCandidates.find(row =>
      String(row.worker_id) === selectedId
    );

    let error = "";
    if (activeHydration) {
      error = "Lot Line Man mapping अभी load हो रही है। एक क्षण बाद Save करें।";
    } else if (!selectedId) {
      error = "Lot Line Man selection mandatory है।";
    } else if (!selected || normalizeRole(selected.role_code) !== "LINE_MAN") {
      error = "केवल active Line Man select किया जा सकता है।";
    } else if (enrolledId && selectedId !== enrolledId) {
      error = "Lot Line Man बदलने के लिए CHANGE LOT LM handover इस्तेमाल करें।";
    }

    if (!error) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    setEvidenceMessage(error, true);
    select?.focus();
  }

  function captureLotFromClick(event) {
    const target = event.target.closest?.("[data-open-lot], .lot-card[data-lot]");
    const id = target?.dataset?.openLot || target?.dataset?.lot;
    if (id) currentCanonicalLotId = String(id);
  }

  function bindModalTransitionObserver() {
    const modal = $("alterEvidenceModal");
    if (!modal) return;

    modalWasVisible = !modal.classList.contains("hidden");

    const observer = new MutationObserver(() => {
      const visible = !modal.classList.contains("hidden");
      if (visible === modalWasVisible) return;

      modalWasVisible = visible;
      if (visible) {
        modalOpenSequence += 1;
        hydrationKey = "";
        lastCandidates = [];
        lastEnrolment = null;
        scheduleHydration(true);
      } else {
        modalOpenSequence += 1;
        hydrationKey = "";
        lastCandidates = [];
        lastEnrolment = null;
        activeHydration = null;
        if (scheduledTimer) {
          clearTimeout(scheduledTimer);
          scheduledTimer = null;
        }
      }
    });

    // IMPORTANT: only the modal's own class is observed. Internal DOM changes
    // are intentionally not observed, preventing the old recursive RPC loop.
    observer.observe(modal, {
      attributes: true,
      attributeFilter: ["class"]
    });
  }

  function boot() {
    document.addEventListener("click", captureLotFromClick, true);
    document.addEventListener("click", validateBeforeSave, true);

    document.addEventListener("click", event => {
      if (event.target.closest?.("#alterBtn")) scheduleHydration(true);
    }, true);

    $("dept")?.addEventListener("change", () => {
      hydrationKey = "";
      if (!$("alterEvidenceModal")?.classList.contains("hidden")) {
        scheduleHydration(true);
      }
    });

    bindModalTransitionObserver();
    console.info(`${VERSION} ready`);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
