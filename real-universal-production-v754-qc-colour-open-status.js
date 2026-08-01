(() => {
"use strict";

const VERSION = "V754_3_CANONICAL_QC_SOURCE_FIX";
const $ = id => document.getElementById(id);
const upper = v => String(v || "").trim().toUpperCase();
const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[c]));

function normDepartment(code) {
  const key = upper(code);
  return ["CHECKING","CHECK","QUALITY CHECK","QUALITY_CHECK","QA"].includes(key)
    ? "QC"
    : key;
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
  try { return JSON.parse(raw)?.context || null; }
  catch (_) { return null; }
}

function forceCanonicalColourNames(root = document) {
  root.querySelectorAll(".colour-card").forEach(card => {
    const title = card.querySelector(".colour-title");
    const code = upper(title?.textContent).match(/\bC\d+\b/)?.[0];
    if (!code) return;

    const heading = title?.querySelector("h3");
    if (heading) {
      const badge = heading.querySelector(".badge");
      heading.childNodes.forEach(node => {
        if (node.nodeType === Node.TEXT_NODE &&
            node.textContent.trim() &&
            !upper(node.textContent).includes(code)) {
          node.textContent = `${code} `;
        }
      });
      if (!upper(heading.textContent).includes(code)) {
        heading.insertAdjacentText("afterbegin", `${code} `);
      }
      if (badge) badge.textContent = code;
    }

    card.querySelectorAll("tbody tr").forEach(row => {
      const nameCells = row.querySelectorAll("[data-colour-name]");
      nameCells.forEach(cell => cell.textContent = code);
    });
  });
}

function removeCheckingOptions() {
  for (const select of [$("dept"), $("homeDept"), $("actionConfirmNextDept")]) {
    if (!select) continue;

    [...select.options].forEach(option => {
      const canonical = normDepartment(option.value);
      if (canonical === "QC") {
        if (upper(option.value) !== "QC") option.remove();
        else option.textContent = option.textContent.replace(/Checking/ig, "QC");
      }
    });
  }
}

async function loadWorkers(departmentCode) {
  const sb = getClient();
  if (!sb) return [];

  const { data, error } = await sb.rpc("rr_upm_worker_list_v754", {
    p_department_code: normDepartment(departmentCode)
  });
  if (error) {
    console.warn(VERSION, error);
    return [];
  }
  return Array.isArray(data) ? data : [];
}


function strictRouteForCard(card) {
  const code = upper(card.querySelector(".colour-title")?.textContent)
    .match(/\bC\d+\b/)?.[0] || "";

  const ctx = getContext();
  const rows = (ctx?.rows || []).filter(r => upper(r.colour_code) === code);

  const activeRow = rows.find(r =>
    r.assignment_id &&
    ["ASSIGNED","IN_PROGRESS","RUNNING"].includes(
      upper(r.assignment_status || r.status)
    )
  );

  if (activeRow) {
    return {
      locked: true,
      department_code: normDepartment(ctx?.department_code || ""),
      status: upper(activeRow.assignment_status || activeRow.status || "ASSIGNED")
    };
  }

  const lotColour = (ctx?.lot?.colours || [])
    .find(c => upper(c.colour_code) === code);

  const lockedDepartment = normDepartment(
    ctx?.route_locked_to ||
    ctx?.mapping_context?.route_locked_to ||
    lotColour?.current_department_code ||
    ""
  );

  if (lockedDepartment) {
    return {
      locked: true,
      department_code: lockedDepartment,
      status: "WAITING WORKER"
    };
  }

  // This is only a legacy exception. Normal Submit cannot create this state
  // because Next Department is mandatory.
  return {
    locked: false,
    department_code: "",
    status: "LEGACY UNLOCKED"
  };
}

async function refillVisibleWorkers() {
  document.querySelectorAll(".colour-card").forEach(async card => {
    const worker = card.querySelector(".colour-worker");
    if (!worker) return;

    const route = strictRouteForCard(card);
    const code = upper(card.querySelector(".colour-title")?.textContent)
      .match(/\bC\d+\b/)?.[0] || "";

    let locked = card.querySelector(".v753-card-department");
    const workerBlock = card.querySelector(".worker-block");

    if (!locked && workerBlock) {
      locked = document.createElement("label");
      locked.className = "v753-card-department";
      workerBlock.insertAdjacentElement("afterbegin", locked);
    }

    if (!route.locked) {
      if (locked) {
        locked.innerHTML = `
          Active Department
          <input value="LEGACY · DEPARTMENT NOT LOCKED · ${esc(code)}" disabled>
        `;
        locked.classList.add("v754-open-queue");
      }

      worker.innerHTML = `<option value="">Legacy record requires department repair</option>`;
      worker.disabled = true;
      card.classList.add("v754-open-card");
      return;
    }

    const dep = normDepartment(route.department_code);
    card.classList.remove("v754-open-card");

    if (locked) {
      locked.classList.remove("v754-open-queue");
      locked.innerHTML = `
        Active Department · Locked
        <input value="${esc(dep)} · ${esc(route.status)} · ${esc(code)}" disabled>
      `;
    }

    const rows = await loadWorkers(dep);
    const previous = worker.value;

    worker.innerHTML = `<option value="">Select ${esc(dep)} worker</option>` +
      rows.map(w => `<option value="${esc(w.worker_id)}"
        data-name="${esc(w.worker_name)}"
        data-code="${esc(w.worker_code)}">
        ${esc(w.worker_name)} · ${esc(w.worker_code)}
      </option>`).join("");

    if ([...worker.options].some(o => o.value === previous)) worker.value = previous;

    worker.disabled = rows.length === 0;
    if (!rows.length) {
      worker.innerHTML = `<option value="">No active worker mapped in ${esc(dep)}</option>`;
    }
  });
}

async function statusForCanonical(canonical) {
  const sb = getClient();
  if (!sb || !canonical) return null;
  const { data, error } = await sb.rpc("rr_upm_board_lot_status_v754", {
    p_canonical_lot_id: canonical
  });
  if (error) {
    console.warn(VERSION, error);
    return null;
  }
  return data;
}

function cardCanonical(card) {
  return card.dataset.canonicalLotId ||
    card.dataset.canonical ||
    card.getAttribute("data-lot-id") ||
    "";
}

function renderBoardStatuses(card, statuses) {
  let list = card.querySelector(".lot-live-list");
  if (!list) {
    list = document.createElement("div");
    list.className = "lot-live-list";
    card.querySelector(".thumbs")?.insertAdjacentElement("beforebegin", list);
  }

  list.innerHTML = (statuses || []).map(s => {
    const colour = upper(s.status_colour);
    const css = colour === "ORANGE" ? "orange"
      : colour === "RED" ? "red"
      : colour === "GREEN" ? "green"
      : "base";

    return `<div class="lot-live-status ${css}">
      <b>${esc(normDepartment(s.department_code))}</b>
      <span>${esc(s.board_detail || "")}</span>
    </div>`;
  }).join("");
}

async function refreshBoard() {
  for (const card of document.querySelectorAll(".lot-card")) {
    const canonical = cardCanonical(card);
    if (!canonical) continue;
    const data = await statusForCanonical(canonical);
    if (data) renderBoardStatuses(card, data.department_statuses);
  }
}

async function sync() {
  removeCheckingOptions();
  forceCanonicalColourNames();
  await refillVisibleWorkers();
  await refreshBoard();
}

function install() {
  sync();

  const observer = new MutationObserver(() => {
    clearTimeout(install.timer);
    install.timer = setTimeout(sync, 120);
  });
  observer.observe(document.body, { childList:true, subtree:true });
}

document.readyState === "loading"
  ? document.addEventListener("DOMContentLoaded", install)
  : install();

window.REDZED_UPM_V754 = { version: VERSION, sync };
console.info("REDZED UPM", VERSION);
})();