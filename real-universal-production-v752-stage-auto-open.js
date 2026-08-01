(() => {
"use strict";

/*
 REDZED UPM V752 — ALTER TRANSPORT STAGE AUTO OPEN
 Additive frontend patch. Load AFTER V750.
 No SQL / mapping / quantity changes.
*/

const VERSION = "V752_STAGE_AUTO_OPEN";
const STAGES = {
  CM_REMAKE_READY: {
    label: "Receive Master · LM",
    buttonId: "remakeDeliveredBtn",
    rpcStage: "RECEIVE_FROM_MASTER",
    cellIndex: 7
  },
  LM_DELIVERY_PENDING: {
    label: "Deliver Karigar · LM",
    buttonId: "remakeCompleteBtn",
    rpcStage: "DELIVER_TO_KARIGAR",
    cellIndex: 8
  },
  KARIGAR_REMAKE_PENDING: {
    label: "Receive Karigar · LM",
    buttonId: "receiveKarigarBtn",
    rpcStage: "RECEIVE_FROM_KARIGAR",
    cellIndex: 10
  }
};

let busy = false;
let lastContext = null;

const $ = id => document.getElementById(id);
const upper = v => String(v || "").trim().toUpperCase();
const num = v => Number(v || 0);

function client() {
  const direct = [
    window.supabaseClient,
    window.supabaseDb,
    window.redzedSupabase,
    window.sb
  ].find(x => x && typeof x.rpc === "function");
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

function parseDebug() {
  const raw = $("debugOutput")?.textContent?.trim();
  if (!raw || !raw.startsWith("{")) return null;
  try {
    const parsed = JSON.parse(raw);
    lastContext = parsed?.context || null;
    return lastContext;
  } catch (_) {
    return lastContext;
  }
}

function cardColour(card) {
  const badge = card?.querySelector(".colour-title .badge, h3 .badge");
  return upper(badge?.textContent);
}

function rowSize(row) {
  return upper(row?.querySelector("td:first-child")?.textContent);
}

function findJourneyRow(journey) {
  const colour = upper(journey.colour_code);
  const size = upper(journey.size_code);

  for (const card of document.querySelectorAll(".colour-card")) {
    if (cardColour(card) !== colour) continue;
    for (const row of card.querySelectorAll("tr[data-row-index]")) {
      if (rowSize(row) === size) return { card, row };
    }
  }
  return null;
}

function ensureCardSelected(card) {
  let pick = card.querySelector(".work-pick, .assign-pick");
  if (!pick) return;

  pick.disabled = false;
  pick.checked = true;

  if (pick.classList.contains("assign-pick")) {
    pick.classList.remove("assign-pick");
    pick.classList.add("work-pick");
    pick.dataset.v752JourneyPick = "1";
    pick.title = "Active Alter journey stage";
  }
}

function makeStageInput(row, journey, meta) {
  const cells = row.querySelectorAll("td");
  const cell = cells[meta.cellIndex];
  if (!cell) return;

  let input = cell.querySelector(".v752-stage-input");
  if (!input) {
    // Keep any backend quantity display, add an action input underneath.
    input = document.createElement("input");
    input.type = "number";
    input.min = "0";
    input.step = "1";
    input.className = "v752-stage-input";
    input.style.width = "82px";
    input.style.marginTop = "5px";
    cell.appendChild(input);
  }

  input.disabled = false;
  input.max = String(num(journey.qty));
  input.placeholder = `Max ${num(journey.qty)}`;
  input.dataset.journeyId = journey.journey_id || "";
  input.dataset.colourCode = journey.colour_code || "";
  input.dataset.colourName = journey.colour_name || journey.colour_code || "";
  input.dataset.sizeCode = journey.size_code || "";
  input.dataset.rpcStage = meta.rpcStage;
  input.dataset.buttonId = meta.buttonId;

  // Do not silently submit; user sees and enters Qty.
  if (num(input.value) > num(journey.qty)) input.value = "";
  input.title = `${meta.label} · Available ${num(journey.qty)} PCS`;

  cell.classList.add("v752-active-stage-cell");
  row.classList.add("v752-active-stage-row");
}

function clearOldStageUi() {
  document.querySelectorAll(".v752-active-stage-cell").forEach(el =>
    el.classList.remove("v752-active-stage-cell")
  );
  document.querySelectorAll(".v752-active-stage-row").forEach(el =>
    el.classList.remove("v752-active-stage-row")
  );
  document.querySelectorAll(".v752-stage-input").forEach(input => {
    input.disabled = true;
    input.closest("td")?.classList.remove("v752-active-stage-cell");
  });
}

function syncStages() {
  const ctx = parseDebug();
  const journeys = Array.isArray(ctx?.active_alter_summary)
    ? ctx.active_alter_summary
    : [];

  clearOldStageUi();

  for (const journey of journeys) {
    const meta = STAGES[upper(journey.stage)];
    if (!meta) continue;

    const found = findJourneyRow(journey);
    if (!found) continue;

    ensureCardSelected(found.card);
    makeStageInput(found.row, journey, meta);

    const button = $(meta.buttonId);
    if (button) {
      button.disabled = false;
      button.dataset.v752Active = "1";
      button.title = `${meta.label} · ${journey.colour_code}/${journey.size_code} · ${journey.qty} PCS`;
    }
  }
}

function setMessage(text, type = "") {
  const box = $("formMsg");
  if (!box) return;
  box.textContent = text;
  box.className = `msg ${type}`.trim();
}

async function runStage(meta) {
  if (busy) return;

  const inputs = [...document.querySelectorAll(
    `.v752-stage-input[data-rpc-stage="${meta.rpcStage}"]`
  )].filter(input => num(input.value) > 0);

  if (!inputs.length) {
    setMessage(`Enter PCS in ${meta.label}.`, "error");
    return;
  }

  const ctx = parseDebug();
  const canonical = ctx?.lot?.canonical_lot_id;
  const department = $("dept")?.value;

  if (!canonical) {
    setMessage("Run Flow Debug once, then retry.", "error");
    return;
  }

  const rows = inputs.map(input => ({
    journey_id: input.dataset.journeyId || null,
    colour_code: input.dataset.colourCode,
    colour_name: input.dataset.colourName,
    size_code: input.dataset.sizeCode,
    qty: num(input.value)
  }));

  const sb = client();
  if (!sb) {
    setMessage("Connected Supabase client not found.", "error");
    return;
  }

  busy = true;
  document.querySelectorAll(".actions button").forEach(b => b.disabled = true);

  try {
    const { data, error } = await sb.rpc("rr_upm_alter_stage_v740", {
      p_stage: meta.rpcStage,
      p_canonical_lot_id: canonical,
      p_department_code: department,
      p_rows: rows,
      p_evidence_urls: [],
      p_physical_confirmed: false,
      p_line_man_id: null,
      p_remarks: `Universal Lot Form ${meta.label}`
    });

    if (error) throw error;

    setMessage(
      `${meta.label} saved. अगली Alter journey stage अब खुल रही है।`,
      "success"
    );

    // Existing page loader remains the source of truth.
    $("dept")?.dispatchEvent(new Event("change", { bubbles: true }));

    // Refresh debug/context after page's normal loader finishes.
    setTimeout(() => $("debugBtn")?.click(), 900);
    setTimeout(syncStages, 1500);

    return data;
  } catch (error) {
    console.error(error);
    setMessage(error?.message || String(error), "error");
  } finally {
    busy = false;
    document.querySelectorAll(".actions button").forEach(b => b.disabled = false);
    setTimeout(syncStages, 50);
  }
}

function bindButtons() {
  for (const meta of Object.values(STAGES)) {
    const button = $(meta.buttonId);
    if (!button || button.dataset.v752Bound === "1") continue;

    button.dataset.v752Bound = "1";
    button.addEventListener("click", event => {
      const active = document.querySelector(
        `.v752-stage-input[data-rpc-stage="${meta.rpcStage}"]:not(:disabled)`
      );
      if (!active) return; // Let old handler run when no V752 journey stage is active.

      event.preventDefault();
      event.stopImmediatePropagation();
      runStage(meta);
    }, true);
  }
}

function addStyles() {
  if ($("v752Style")) return;
  const style = document.createElement("style");
  style.id = "v752Style";
  style.textContent = `
    .v752-active-stage-row{
      outline:2px solid #35a7ff;
      outline-offset:-2px;
      background:#102b45!important;
    }
    .v752-active-stage-cell{
      background:#174f7d!important;
      box-shadow:inset 0 0 0 2px #50b8ff;
    }
    .v752-stage-input{
      background:#fff!important;
      color:#111!important;
      border:2px solid #35a7ff!important;
      font-weight:900!important;
      opacity:1!important;
    }
    @media(prefers-color-scheme:light){
      .v752-active-stage-row{background:#dff2ff!important}
      .v752-active-stage-cell{background:#bfe5ff!important}
    }
  `;
  document.head.appendChild(style);
}

function install() {
  addStyles();
  bindButtons();
  syncStages();

  const observer = new MutationObserver(() => {
    clearTimeout(install.timer);
    install.timer = setTimeout(() => {
      bindButtons();
      syncStages();
    }, 60);
  });

  observer.observe(document.body, { childList: true, subtree: true });
}

document.readyState === "loading"
  ? document.addEventListener("DOMContentLoaded", install)
  : install();

window.REDZED_UPM_V752 = {
  version: VERSION,
  sync: syncStages
};

console.info("REDZED UPM", VERSION);
})();