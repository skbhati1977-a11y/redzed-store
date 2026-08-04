(() => {
  "use strict";

  const VERSION = "V770_ALTER_RECEIVER_ROUTING";
  const $ = id => document.getElementById(id);
  const upper = value => String(value || "").trim().toUpperCase();
  const normalizeRole = value => upper(value).replace(/[^A-Z0-9]+/g, "_");
  const asArray = value => Array.isArray(value) ? value : [];

  let currentCanonicalLotId = "";
  let candidates = [];
  let actorLineMan = null;
  let actorRole = "";
  let loadingPromise = null;
  let openSequence = 0;
  let lastVisible = false;
  let timer = null;

  function client() {
    return window.supabaseClient
      || window.supabaseDb
      || window.redzedSupabase
      || window.sb
      || null;
  }

  function setMessage(text, isError = false) {
    const box = $("alterEvidenceMsg");
    if (!box) return;
    box.textContent = text || "";
    box.className = `msg${isError ? " error" : ""}`;
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

    if (card?.dataset?.lot) currentCanonicalLotId = String(card.dataset.lot);
    return currentCanonicalLotId;
  }

  function normalizeCandidate(row) {
    const workerId = row?.worker_id || row?.person_id || "";
    const role = normalizeRole(
      row?.role_code
      || row?.worker_role_code
      || row?.role
      || "LINE_MAN"
    );
    const status = upper(row?.access_status || row?.status || "ACTIVE");
    const isActive = row?.is_active !== false
      && !["INACTIVE", "DISABLED", "CLOSED", "DELETED"].includes(status);

    if (!workerId || role !== "LINE_MAN" || !isActive) return null;

    return {
      ...row,
      worker_id: String(workerId),
      role_code: "LINE_MAN"
    };
  }

  function activeLineMen(rows) {
    const seen = new Set();
    return asArray(rows)
      .map(normalizeCandidate)
      .filter(Boolean)
      .filter(row => {
        if (seen.has(row.worker_id)) return false;
        seen.add(row.worker_id);
        return true;
      });
  }

  function candidateLabel(row) {
    return [
      row?.worker_name || row?.person_name_snapshot || row?.name,
      row?.worker_code || row?.worker_code_snapshot,
      "LINE MAN"
    ].filter(Boolean).join(" · ");
  }

  function candidateId(row) {
    return String(row?.worker_id || row?.person_id || "");
  }

  function ensureSearchInput(select) {
    let input = $("alterLineManSearch");
    if (input) return input;

    input = document.createElement("input");
    input.id = "alterLineManSearch";
    input.type = "search";
    input.autocomplete = "off";
    input.placeholder = "Search Alter Receiver Line Man";
    input.setAttribute("aria-label", "Search Alter Receiver Line Man");
    input.style.width = "100%";
    input.style.margin = "6px 0";

    select.parentElement?.insertBefore(input, select);
    input.addEventListener("input", () => renderOptions(input.value));
    return input;
  }

  function updatePhysicalLabel(selfAssigned) {
    const label = $("physicalEvidenceLabel");
    if (!label) return;
    label.textContent = selfAssigned
      ? "Physical Alter Piece मेरे पास है"
      : "Physical Alter Piece selected Line Man को handover किया है";
  }

  function updateRuleNote(selfAssigned) {
    const note = $("alterReceiverRule");
    if (!note) return;

    note.textContent = selfAssigned
      ? "आप active Line Man ID से logged in हैं। यह नई Alter journey अपने-आप आपके hold में assign होगी।"
      : "हर नई Alter journey में जिस active Line Man को piece भेजना है, उसे अलग से select करना mandatory है। पिछली journey का Line Man reuse नहीं होगा।";
  }

  function renderOptions(query = "") {
    const select = $("alterLineManSelect");
    if (!select) return;

    const search = upper(query);
    const selfId = candidateId(actorLineMan);
    const rows = candidates.filter(row =>
      !search || upper(candidateLabel(row)).includes(search)
    );

    select.replaceChildren();

    if (!selfId) {
      const placeholder = new Option(
        "Select Alter Receiver Line Man (mandatory)",
        "",
        true,
        true
      );
      placeholder.disabled = true;
      select.add(placeholder);
    }

    for (const row of rows) {
      const option = new Option(candidateLabel(row), candidateId(row));
      option.dataset.roleCode = "LINE_MAN";
      select.add(option);
    }

    const searchInput = ensureSearchInput(select);

    if (selfId) {
      if (![...select.options].some(option => option.value === selfId)) {
        const selfOption = new Option(candidateLabel(actorLineMan), selfId);
        selfOption.dataset.roleCode = "LINE_MAN";
        select.add(selfOption, 0);
      }
      select.value = selfId;
      select.disabled = true;
      searchInput.value = "";
      searchInput.disabled = true;
      updatePhysicalLabel(true);
      updateRuleNote(true);
      setMessage(
        `${candidateLabel(actorLineMan)}: अपनी Line Man ID से Alter Fill करने के कारण यह नई journey आपके hold में auto-assign होगी.`
      );
    } else {
      // Deliberately blank on every modal opening. No enrolled/previous LM default.
      select.value = "";
      select.disabled = false;
      searchInput.disabled = false;
      updatePhysicalLabel(false);
      updateRuleNote(false);
      setMessage(
        "Alter Receiver Line Man चुनना mandatory है। Selected Line Man इसी journey का holder बनेगा; permanent Lot LM enrolment नहीं बदलेगा।"
      );
    }
  }

  async function fetchReceiverContext(canonicalLotId) {
    const sb = client();
    if (!sb || typeof sb.rpc !== "function") {
      throw new Error("Connected Supabase client नहीं मिला।");
    }

    const { data, error } = await sb.rpc("rr_upm_alter_receiver_context_v770", {
      p_canonical_lot_id: canonicalLotId || null
    });

    if (error) throw error;
    return data || {};
  }

  function prepareLoadingUi() {
    const select = $("alterLineManSelect");
    if (!select) return;

    const search = ensureSearchInput(select);
    search.value = "";
    search.disabled = true;
    select.replaceChildren(new Option("Loading active Line Men…", ""));
    select.disabled = true;
    updatePhysicalLabel(false);
    setMessage("Active Line Man और logged-in user mapping verify हो रही है…");
  }

  async function hydrateForOpen(sequence) {
    const modal = $("alterEvidenceModal");
    if (!modal || modal.classList.contains("hidden")) return;

    const canonicalLotId = resolveCanonicalLotId();
    if (!canonicalLotId) {
      setMessage("Current Lot reference नहीं मिला। Lot बंद करके दोबारा CHECK IN करें।", true);
      return;
    }

    prepareLoadingUi();

    loadingPromise = (async () => {
      try {
        const context = await fetchReceiverContext(canonicalLotId);
        if (
          sequence !== openSequence
          || $("alterEvidenceModal")?.classList.contains("hidden")
        ) return;

        actorRole = normalizeRole(context?.actor_role);
        candidates = activeLineMen(context?.line_man_candidates);
        actorLineMan = normalizeCandidate(context?.actor_line_man);

        if (actorRole === "LINE_MAN" && !actorLineMan) {
          throw new Error(
            "Login role LINE_MAN है, लेकिन active Line Man worker mapping नहीं मिली। Worker Directory mapping ठीक करें।"
          );
        }

        if (actorLineMan && !candidates.some(row => candidateId(row) === candidateId(actorLineMan))) {
          candidates.unshift(actorLineMan);
        }

        if (!candidates.length) {
          const select = $("alterLineManSelect");
          select?.replaceChildren(new Option("No active Line Man found", ""));
          if (select) select.disabled = true;
          setMessage(
            "Active Line Man नहीं मिला। Worker Directory में LINE_MAN role active करें।",
            true
          );
          return;
        }

        renderOptions("");
      } catch (error) {
        console.error(VERSION, error);
        candidates = [];
        actorLineMan = null;
        const select = $("alterLineManSelect");
        select?.replaceChildren(new Option("Line Man load failed", ""));
        if (select) select.disabled = true;
        setMessage(error?.message || String(error), true);
      } finally {
        loadingPromise = null;
      }
    })();

    return loadingPromise;
  }

  function scheduleHydration() {
    if (timer) clearTimeout(timer);
    const sequence = openSequence;
    timer = setTimeout(() => {
      timer = null;
      hydrateForOpen(sequence);
    }, 20);
  }

  function validateBeforeSave(event) {
    const button = event.target.closest?.("#saveAlterEvidence");
    if (!button) return;

    const select = $("alterLineManSelect");
    const selectedId = String(select?.value || "");
    const selected = candidates.find(row => candidateId(row) === selectedId);
    const selfId = candidateId(actorLineMan);

    let error = "";
    if (loadingPromise) {
      error = "Line Man mapping अभी load हो रही है। एक क्षण बाद Save करें।";
    } else if (actorRole === "LINE_MAN" && (!selfId || selectedId !== selfId)) {
      error = "Line Man login से Alter Fill करने पर journey आपकी अपनी ID पर ही auto-assign होगी।";
    } else if (!selectedId) {
      error = "जिस Line Man को Alter भेजना है, उसे select करना mandatory है।";
    } else if (!selected || normalizeRole(selected.role_code) !== "LINE_MAN") {
      error = "केवल active Line Man को Alter receiver बनाया जा सकता है।";
    }

    if (!error) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    setMessage(error, true);
    select?.focus();
  }

  function captureLot(event) {
    const node = event.target.closest?.("[data-open-lot], .lot-card[data-lot]");
    const id = node?.dataset?.openLot || node?.dataset?.lot;
    if (id) currentCanonicalLotId = String(id);
  }

  function bindModalObserver() {
    const modal = $("alterEvidenceModal");
    if (!modal) return;

    lastVisible = !modal.classList.contains("hidden");

    const observer = new MutationObserver(() => {
      const visible = !modal.classList.contains("hidden");
      if (visible === lastVisible) return;
      lastVisible = visible;
      openSequence += 1;

      if (visible) {
        candidates = [];
        actorLineMan = null;
        actorRole = "";
        const search = $("alterLineManSearch");
        if (search) search.value = "";
        scheduleHydration();
      } else {
        candidates = [];
        actorLineMan = null;
        actorRole = "";
        loadingPromise = null;
        if (timer) {
          clearTimeout(timer);
          timer = null;
        }
      }
    });

    // Only visibility/class changes are observed; modal contents are not observed.
    observer.observe(modal, {
      attributes: true,
      attributeFilter: ["class"]
    });
  }

  function boot() {
    document.addEventListener("click", captureLot, true);
    document.addEventListener("click", validateBeforeSave, true);

    $("dept")?.addEventListener("change", () => {
      if (!$("alterEvidenceModal")?.classList.contains("hidden")) {
        openSequence += 1;
        scheduleHydration();
      }
    });

    bindModalObserver();
    console.info(`${VERSION} ready`);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
