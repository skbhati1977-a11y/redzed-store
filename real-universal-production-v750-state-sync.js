(() => {
"use strict";

/*
 REDZED UPM V750 — STATE SYNC CLEANUP
 Additive frontend patch. Load AFTER real-universal-production-v729.js.
 Does not change identity mapping, department mapping, quantities, or RPC signatures.
*/

const V = "V750_STATE_SYNC_CLEANUP";
console.info("REDZED UPM", V);

const selectedKeys = new Set();
let access = {
  resolved_role: "WORKER",
  owner_admin_override: false,
  manager_access: false
};

const $ = id => document.getElementById(id);
const upper = value => String(value || "").trim().toUpperCase();
const num = value => Number(value || 0);

function getClient() {
  const direct = [
    window.supabaseClient,
    window.supabaseDb,
    window.redzedSupabase,
    window.sb
  ].find(client => client && typeof client.rpc === "function");
  if (direct) return direct;

  for (const key of Object.getOwnPropertyNames(window)) {
    try {
      const value = window[key];
      if (value && typeof value === "object" &&
          typeof value.rpc === "function" && value.auth) return value;
    } catch (_) {}
  }
  return null;
}

async function loadAccess() {
  const client = getClient();
  if (!client) return;
  for (const fn of ["rr_upm_access_debug_v748", "rr_upm_access_debug_v747"]) {
    try {
      const { data, error } = await client.rpc(fn);
      if (!error && data) {
        access = {
          resolved_role: upper(data.resolved_role || data.context?.role_code || "WORKER"),
          owner_admin_override: Boolean(data.owner_admin_override),
          manager_access: Boolean(data.manager_access)
        };
        document.documentElement.dataset.upmAccess = access.resolved_role;
        return;
      }
    } catch (_) {}
  }
}

function cardKey(card) {
  return String(card?.dataset?.colourKey || "").trim();
}

function checkedCards() {
  return [...document.querySelectorAll(".colour-card")].filter(card => {
    const input = card.querySelector(".work-pick, .assign-pick");
    return Boolean(input?.checked);
  });
}

function rememberSelection(event) {
  const input = event.target.closest?.(".work-pick, .assign-pick");
  if (!input) return;
  const card = input.closest(".colour-card");
  const key = cardKey(card);
  if (!key) return;
  if (input.checked) selectedKeys.add(key);
  else selectedKeys.delete(key);
  syncCardSelection(card);
}

function isSubmittedCard(card) {
  const text = upper(card?.textContent);
  return text.includes("SUBMITTED HERE") ||
         text.includes("SUBMITTED / CAUGHT UP") ||
         card?.classList.contains("done");
}

function isAssignedCard(card) {
  const text = upper(card?.textContent);
  return Boolean(card?.classList.contains("assigned")) ||
         text.includes("ASSIGNED / IN PROGRESS") ||
         Boolean(card?.querySelector(".work-pick"));
}

function hasActiveAlter(card) {
  const text = upper(card?.textContent);
  const alterPendingCell = [...card.querySelectorAll("td")].some(td => {
    const value = Number(String(td.textContent || "").trim());
    return Number.isFinite(value) && value > 0;
  });
  return text.includes("ALTER PENDING") || alterPendingCell;
}

function ensureWorkBridge(card) {
  let bridge = card.querySelector(".v750-work-bridge");
  if (!bridge) {
    bridge = document.createElement("input");
    bridge.type = "checkbox";
    bridge.className = "work-pick v750-work-bridge";
    bridge.hidden = true;
    card.appendChild(bridge);
  }
  bridge.checked = true;
  bridge.disabled = false;
  return bridge;
}

function removeWorkBridge(card) {
  card.querySelector(".v750-work-bridge")?.remove();
}

function enableOwnerStageInputs(card) {
  if (!access.owner_admin_override) return;
  if (isSubmittedCard(card) && !hasActiveAlter(card)) return;

  card.querySelectorAll("tr[data-row-index]").forEach(row => {
    const cells = row.querySelectorAll("td");
    const alterPending = [...cells].some(cell => {
      const value = Number(String(cell.textContent || "").trim());
      return Number.isFinite(value) && value > 0;
    });

    const alter = row.querySelector(".alterEntry");
    const remakeIssue = row.querySelector(".remakeIssueEntry");
    const remakeComplete = row.querySelector(".remakeCompleteEntry");
    const damage = row.querySelector(".damageEntry");
    const damageSource = row.querySelector(".damageSource");

    if (alter && !isSubmittedCard(card)) alter.disabled = false;
    if (remakeIssue && (alterPending || num(remakeIssue.max) > 0)) remakeIssue.disabled = false;
    if (remakeComplete && num(remakeComplete.max) > 0) remakeComplete.disabled = false;
    if (damage) damage.disabled = false;
    if (damageSource) damageSource.disabled = false;
  });
}

function syncCardSelection(card) {
  if (!card) return;
  const key = cardKey(card);
  const visible = card.querySelector(".work-pick:not(.v750-work-bridge), .assign-pick");
  if (!visible) return;

  const submitted = isSubmittedCard(card);
  const assigned = isAssignedCard(card);
  const remembered = selectedKeys.has(key);

  if (submitted && !hasActiveAlter(card)) {
    visible.checked = false;
    visible.disabled = true;
    selectedKeys.delete(key);
    removeWorkBridge(card);
    return;
  }

  visible.disabled = false;
  if (remembered) visible.checked = true;

  // Assigned/running colours remain selectable for Alter, Damage and Submit.
  if (assigned && visible.classList.contains("assign-pick")) {
    visible.classList.remove("assign-pick");
    visible.classList.add("work-pick");
    visible.title = "Selected assigned Colour: Alter, Damage or Submit";
  }

  // Open Colour with an active Alter journey can be selected for management/Alter-stage action,
  // but it remains an assign-pick for normal Assignment.
  if (!assigned && access.owner_admin_override && hasActiveAlter(card) && visible.checked) {
    ensureWorkBridge(card);
  } else if (!assigned) {
    removeWorkBridge(card);
  }

  enableOwnerStageInputs(card);
}

function syncAll() {
  document.querySelectorAll(".colour-card").forEach(syncCardSelection);
}

function cardsWithPositiveInput(selector) {
  return [...document.querySelectorAll(".colour-card")].filter(card =>
    [...card.querySelectorAll(selector)].some(input => num(input.value) > 0)
  );
}

function prepareAction(buttonId) {
  const button = $(buttonId);
  if (!button) return;

  const selected = checkedCards();
  let candidates = selected;

  if (buttonId === "remakeIssueBtn") {
    const positive = cardsWithPositiveInput(".remakeIssueEntry");
    candidates = positive.length ? positive : selected;
  } else if (buttonId === "remakeCompleteBtn" || buttonId === "remakeDeliveredBtn") {
    const positive = cardsWithPositiveInput(".remakeCompleteEntry, .remakeIssueEntry");
    candidates = positive.length ? positive : selected;
  } else if (buttonId === "alterBtn") {
    const positive = cardsWithPositiveInput(".alterEntry");
    candidates = positive.length ? positive : selected;
  } else if (buttonId === "damageBtn") {
    const positive = cardsWithPositiveInput(".damageEntry");
    candidates = positive.length ? positive : selected;
  }

  candidates.forEach(card => {
    const visible = card.querySelector(".work-pick:not(.v750-work-bridge), .assign-pick");
    if (visible && !visible.disabled) {
      visible.checked = true;
      selectedKeys.add(cardKey(card));
    }
    if (access.owner_admin_override && (hasActiveAlter(card) || buttonId !== "submitBtn")) {
      ensureWorkBridge(card);
      enableOwnerStageInputs(card);
    }
  });

  // Submit must never bridge a merely open/unassigned Colour.
  if (buttonId === "submitBtn") {
    document.querySelectorAll(".colour-card").forEach(card => {
      if (!isAssignedCard(card)) removeWorkBridge(card);
    });
  }
}

function wireButtons() {
  [
    "alterBtn",
    "remakeIssueBtn",
    "remakeDeliveredBtn",
    "remakeCompleteBtn",
    "damageBtn",
    "submitBtn",
    "reassignBtn"
  ].forEach(id => {
    const button = $(id);
    if (!button || button.dataset.v750Capture === "1") return;
    button.dataset.v750Capture = "1";
    button.addEventListener("click", () => prepareAction(id), true);
  });

  const selectAll = $("selectAllBtn");
  if (selectAll && selectAll.dataset.v750Capture !== "1") {
    selectAll.dataset.v750Capture = "1";
    selectAll.addEventListener("click", () => {
      queueMicrotask(() => {
        const running = [...document.querySelectorAll(".colour-card")].filter(isAssignedCard);
        const targets = running.length
          ? running
          : [...document.querySelectorAll(".colour-card")].filter(card =>
              !isSubmittedCard(card) &&
              !card.classList.contains("waiting")
            );

        targets.forEach(card => {
          const input = card.querySelector(".work-pick:not(.v750-work-bridge), .assign-pick");
          if (!input || input.disabled) return;
          input.checked = true;
          selectedKeys.add(cardKey(card));
          syncCardSelection(card);
        });
      });
    }, true);
  }
}

function installObserver() {
  const observer = new MutationObserver(() => {
    clearTimeout(installObserver.timer);
    installObserver.timer = setTimeout(() => {
      wireButtons();
      syncAll();
    }, 20);
  });
  observer.observe(document.body, { childList: true, subtree: true });
}

document.addEventListener("change", rememberSelection, true);
document.addEventListener("DOMContentLoaded", async () => {
  await loadAccess();
  wireButtons();
  syncAll();
  installObserver();
});

if (document.readyState !== "loading") {
  loadAccess().finally(() => {
    wireButtons();
    syncAll();
    installObserver();
  });
}

window.REDZED_UPM_V750 = {
  version: V,
  getAccess: () => ({ ...access }),
  getSelectedColours: () => [...selectedKeys],
  resync: syncAll
};
})();
