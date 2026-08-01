(() => {
"use strict";

const VERSION = "V752_2_FINAL_RECEIVE_PROGRESS";

const STAGES = {
  CM_REMAKE_READY: {
    label: "Receive Master · LM",
    buttonId: "remakeDeliveredBtn",
    rpcStage: "RECEIVE_FROM_MASTER",
    inputClass: "remakeDeliveredEntry",
    fallbackCellIndex: 7
  },
  LM_DELIVERY_PENDING: {
    label: "Deliver Karigar · LM",
    buttonId: "remakeCompleteBtn",
    rpcStage: "DELIVER_TO_KARIGAR",
    inputClass: "remakeCompleteEntry",
    fallbackCellIndex: 8
  },
  KARIGAR_REMAKE_PENDING: {
    label: "Receive Karigar · LM",
    buttonId: "receiveKarigarBtn",
    rpcStage: "RECEIVE_FROM_KARIGAR",
    inputClass: "receiveKarigarEntry",
    fallbackCellIndex: 10
  }
};

let busy = false;

const $ = id => document.getElementById(id);
const upper = v => String(v || "").trim().toUpperCase();
const qty = v => Number(v || 0);


function progressKey(canonical, colour, size) {
  return `rr_upm_final_receive:${canonical}:${upper(colour)}:${upper(size)}`;
}

function readProgressTotal(key, fallback) {
  const saved = Number(sessionStorage.getItem(key) || 0);
  const current = qty(fallback);
  const total = Math.max(saved, current);
  sessionStorage.setItem(key, String(total));
  return total;
}

function flashProgress(text, type = "success") {
  let box = document.getElementById("v752ProgressFlash");
  if (!box) {
    box = document.createElement("div");
    box.id = "v752ProgressFlash";
    box.className = "v752-progress-flash";
    document.querySelector(".actions")?.insertAdjacentElement("afterend", box);
  }

  box.textContent = text;
  box.className = `v752-progress-flash ${type}`;
  box.hidden = false;

  clearTimeout(flashProgress.timer);
  flashProgress.timer = setTimeout(() => {
    box.hidden = true;
    box.textContent = "";
  }, 3200);
}

function getClient() {
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

function getContext() {
  const raw = $("debugOutput")?.textContent?.trim();
  if (!raw || !raw.startsWith("{")) return null;
  try {
    return JSON.parse(raw)?.context || null;
  } catch (_) {
    return null;
  }
}

function cardCode(card) {
  const title = card.querySelector(".colour-title");
  if (!title) return "";
  const match = upper(title.textContent).match(/\bC\d+\b/);
  return match ? match[0] : "";
}

function rowSize(row) {
  const first = row.querySelector("td");
  return upper(first?.textContent);
}

function findCardAndRow(journey) {
  const wantedColour = upper(journey.colour_code);
  const wantedSize = upper(journey.size_code);

  for (const card of document.querySelectorAll(".colour-card")) {
    if (cardCode(card) !== wantedColour) continue;

    // Do not depend on data-row-index; live rows may not have it.
    const rows = card.querySelectorAll("tbody tr, .size-wrap tr");
    for (const row of rows) {
      if (row.querySelector("th")) continue;
      if (rowSize(row) === wantedSize) return { card, row };
    }
  }
  return null;
}

function selectJourneyCard(card) {
  const pick = card.querySelector(".work-pick, .assign-pick");
  if (!pick) return;

  pick.disabled = false;
  pick.checked = true;

  if (pick.classList.contains("assign-pick")) {
    pick.classList.remove("assign-pick");
    pick.classList.add("work-pick");
  }

  pick.dataset.v752Journey = "1";
}

function activateInput(row, journey, meta) {
  const cells = [...row.querySelectorAll("td")];
  const targetCell = cells[meta.fallbackCellIndex];
  if (!targetCell) return null;

  // Prefer the existing production input in that stage column.
  let input =
    targetCell.querySelector(`.${meta.inputClass}`) ||
    targetCell.querySelector('input[type="number"]');

  // Only create if the existing renderer produced no input at all.
  if (!input) {
    input = document.createElement("input");
    input.type = "number";
    input.step = "1";
    targetCell.appendChild(input);
  }

  input.classList.add("v752-stage-input", meta.inputClass);
  input.disabled = false;
  input.readOnly = false;
  input.min = "0";
  input.max = String(qty(journey.qty));
  input.placeholder = "PCS";
  input.dataset.journeyId = journey.journey_id || "";
  input.dataset.colourCode = journey.colour_code || "";
  input.dataset.colourName = journey.colour_name || journey.colour_code || "";
  input.dataset.sizeCode = journey.size_code || "";
  input.dataset.rpcStage = meta.rpcStage;
  input.dataset.availableQty = String(qty(journey.qty));
  input.dataset.progressColour = journey.colour_code || "";
  input.dataset.progressSize = journey.size_code || "";

  targetCell.classList.add("v752-active-stage-cell");
  row.classList.add("v752-active-stage-row");

  return input;
}

function resetStageUi() {
  document.querySelectorAll(".v752-active-stage-row")
    .forEach(el => el.classList.remove("v752-active-stage-row"));

  document.querySelectorAll(".v752-active-stage-cell")
    .forEach(el => el.classList.remove("v752-active-stage-cell"));

  document.querySelectorAll(".v752-stage-input").forEach(input => {
    input.disabled = true;
  });
}

function sync() {
  const ctx = getContext();
  const journeys = Array.isArray(ctx?.active_alter_summary)
    ? ctx.active_alter_summary
    : [];

  resetStageUi();

  for (const journey of journeys) {
    const meta = STAGES[upper(journey.stage)];
    if (!meta) continue;

    const found = findCardAndRow(journey);
    if (!found) {
      console.warn(VERSION, "Journey row not found", journey);
      continue;
    }

    selectJourneyCard(found.card);
    const input = activateInput(found.row, journey, meta);

    const button = $(meta.buttonId);
    if (button && input) {
      button.disabled = false;
      button.dataset.v752Active = "1";
      button.title =
        `${meta.label} · ${journey.colour_code}/${journey.size_code} · ${journey.qty} PCS`;
    }
  }
}

function showMessage(text, type = "") {
  const box = $("formMsg");
  if (!box) return;
  box.textContent = text;
  box.className = `msg ${type}`.trim();
}

async function submitStage(meta) {
  if (busy) return;

  const inputs = [...document.querySelectorAll(
    `.v752-stage-input[data-rpc-stage="${meta.rpcStage}"]:not(:disabled)`
  )].filter(input => qty(input.value) > 0);

  if (!inputs.length) {
    showMessage(`Enter Qty for ${meta.label}.`, "error");
    return;
  }

  const ctx = getContext();
  const canonical = ctx?.lot?.canonical_lot_id;
  const department = $("dept")?.value;

  if (!canonical) {
    showMessage("Run Flow Debug once and retry.", "error");
    return;
  }

  const finalReceiveSnapshot = meta.rpcStage === "RECEIVE_FROM_KARIGAR"
    ? inputs.map(input => {
        const available = qty(input.dataset.availableQty || input.max);
        const submitted = qty(input.value);
        const key = progressKey(
          canonical,
          input.dataset.progressColour,
          input.dataset.progressSize
        );
        const total = readProgressTotal(key, available);
        return { key, total, available, submitted };
      })
    : [];

  const rows = inputs.map(input => ({
    journey_id: input.dataset.journeyId || null,
    colour_code: input.dataset.colourCode,
    colour_name: input.dataset.colourName,
    size_code: input.dataset.sizeCode,
    qty: qty(input.value)
  }));

  const sb = getClient();
  if (!sb) {
    showMessage("Connected Supabase client not found.", "error");
    return;
  }

  busy = true;

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

    if (meta.rpcStage === "RECEIVE_FROM_KARIGAR" && finalReceiveSnapshot.length) {
      const snap = finalReceiveSnapshot[0];
      const remaining = Math.max(snap.available - snap.submitted, 0);
      const deposited = Math.min(snap.total - remaining, snap.total);

      if (remaining > 0) {
        sessionStorage.setItem(snap.key, String(snap.total));
        flashProgress(
          `Karigar se jama ${deposited}/${snap.total} PCS · Pending ${remaining} PCS`,
          "pending"
        );
      } else {
        flashProgress(`Complete · ${snap.total}/${snap.total} PCS`, "complete");
        setTimeout(() => sessionStorage.removeItem(snap.key), 3400);
      }
    } else {
      flashProgress(`${meta.label} saved`, "complete");
    }

    showMessage(
      `${meta.label} saved. Next journey stage is opening.`,
      "success"
    );

    $("dept")?.dispatchEvent(new Event("change", { bubbles: true }));

    setTimeout(() => $("debugBtn")?.click(), 800);
    setTimeout(sync, 1400);

    return data;
  } catch (error) {
    console.error(VERSION, error);
    showMessage(error?.message || String(error), "error");
  } finally {
    busy = false;
    setTimeout(sync, 50);
  }
}

function bindButtons() {
  for (const meta of Object.values(STAGES)) {
    const button = $(meta.buttonId);
    if (!button || button.dataset.v7521Bound === "1") continue;

    button.dataset.v7521Bound = "1";

    button.addEventListener("click", event => {
      const active = document.querySelector(
        `.v752-stage-input[data-rpc-stage="${meta.rpcStage}"]:not(:disabled)`
      );

      if (!active) return;

      event.preventDefault();
      event.stopImmediatePropagation();
      submitStage(meta);
    }, true);
  }
}

function addStyle() {
  if ($("v7521Style")) return;

  const style = document.createElement("style");
  style.id = "v7521Style";
  style.textContent = `
    .v752-active-stage-row{
      outline:2px solid #39aaff;
      outline-offset:-2px;
      background:#102b45!important;
    }
    .v752-active-stage-cell{
      background:#174f7d!important;
      box-shadow:inset 0 0 0 2px #58beff;
    }
    .v752-stage-input:not(:disabled){
      background:#fff!important;
      color:#111!important;
      border:2px solid #39aaff!important;
      font-weight:900!important;
      opacity:1!important;
      cursor:text!important;
    }
    .v752-progress-flash{
      margin:8px 0;
      padding:10px 12px;
      border-radius:9px;
      font-weight:900;
      animation:v752Flash .55s ease-in-out 2;
    }
    .v752-progress-flash.pending{
      background:#4b3b11;
      border:1px solid #c79524;
      color:#ffe49a;
    }
    .v752-progress-flash.complete{
      background:#123c2b;
      border:1px solid #2ea66d;
      color:#c9ffe4;
    }
    @keyframes v752Flash{
      0%,100%{opacity:1}
      50%{opacity:.35}
    }
  `;
  document.head.appendChild(style);
}

function install() {
  addStyle();
  bindButtons();
  sync();

  const observer = new MutationObserver(() => {
    clearTimeout(install.timer);
    install.timer = setTimeout(() => {
      bindButtons();
      sync();
    }, 80);
  });

  observer.observe(document.body, { childList: true, subtree: true });
}

document.readyState === "loading"
  ? document.addEventListener("DOMContentLoaded", install)
  : install();

window.REDZED_UPM_V752_1 = {
  version: VERSION,
  sync
};

console.info("REDZED UPM", VERSION);
})();