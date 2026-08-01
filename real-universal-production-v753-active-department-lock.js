(() => {
"use strict";

const VERSION = "V753_ACTIVE_DEPARTMENT_LOCK";
const $ = id => document.getElementById(id);
const upper = v => String(v || "").trim().toUpperCase();
const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[c]));

let routeMap = new Map();
let workerCache = new Map();
let busy = false;

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

function colourCodeFromCard(card) {
  const match = upper(card?.querySelector(".colour-title")?.textContent).match(/\bC\d+\b/);
  return match ? match[0] : "";
}

function departmentName(code) {
  const option = [...($("dept")?.options || [])]
    .find(o => upper(o.value) === upper(code));
  return option?.textContent?.trim() || code || "OPEN";
}

function buildFallbackRoutes() {
  const ctx = getContext();
  const map = new Map();

  for (const colour of (ctx?.lot?.colours || [])) {
    const code = upper(colour.colour_code);
    if (!code) continue;
    map.set(code, {
      colour_code: code,
      department_code: upper(colour.current_department_code || ""),
      status: upper(colour.status || "PENDING")
    });
  }

  return map;
}

async function loadRoutes() {
  const ctx = getContext();
  const canonical = ctx?.lot?.canonical_lot_id;
  const fallback = buildFallbackRoutes();

  if (!canonical) {
    routeMap = fallback;
    return;
  }

  const sb = getClient();
  if (!sb) {
    routeMap = fallback;
    return;
  }

  try {
    const { data, error } = await sb.rpc("rr_upm_board_lot_status_v743", {
      p_canonical_lot_id: canonical
    });
    if (error) throw error;

    const map = new Map(fallback);
    for (const dep of (data?.department_statuses || [])) {
      const depCode = upper(dep.department_code);
      for (const code of (dep.running_codes || [])) {
        map.set(upper(code), { colour_code: upper(code), department_code: depCode, status: "RUNNING" });
      }
      for (const code of (dep.assigned_codes || [])) {
        map.set(upper(code), { colour_code: upper(code), department_code: depCode, status: "ASSIGNED" });
      }
      for (const code of (dep.submitted_codes || [])) {
        if (!map.has(upper(code))) {
          map.set(upper(code), { colour_code: upper(code), department_code: depCode, status: "SUBMITTED" });
        }
      }
    }
    routeMap = map;
  } catch (error) {
    console.warn(VERSION, "Board route fallback used", error);
    routeMap = fallback;
  }
}

async function workersFor(departmentCode) {
  const dep = upper(departmentCode);
  if (!dep) return [];
  if (workerCache.has(dep)) return workerCache.get(dep);

  const sb = getClient();
  if (!sb) return [];

  try {
    const { data, error } = await sb.rpc("rr_upm_worker_list_v8_3", {
      p_department_code: dep
    });
    if (error) throw error;
    const rows = Array.isArray(data) ? data : [];
    workerCache.set(dep, rows);
    return rows;
  } catch (error) {
    console.warn(VERSION, "Worker load failed", dep, error);
    workerCache.set(dep, []);
    return [];
  }
}

function ensureRouteBar() {
  let bar = $("v753RouteBar");
  if (bar) return bar;

  bar = document.createElement("div");
  bar.id = "v753RouteBar";
  bar.className = "v753-route-bar";

  const anchor = document.querySelector(".bulk-assign");
  anchor?.insertAdjacentElement("beforebegin", bar);
  return bar;
}

async function switchToColour(code) {
  const route = routeMap.get(upper(code));
  const dep = upper(route?.department_code);
  if (!dep) return;

  const dept = $("dept");
  if (dept && [...dept.options].some(o => upper(o.value) === dep)) {
    if (upper(dept.value) !== dep) {
      dept.value = dep;
      dept.dispatchEvent(new Event("change", { bubbles: true }));
      await new Promise(resolve => setTimeout(resolve, 650));
    }
  }

  setTimeout(() => {
    const card = [...document.querySelectorAll(".colour-card")]
      .find(c => colourCodeFromCard(c) === upper(code));

    const pick = card?.querySelector(".work-pick, .assign-pick");
    if (pick && !pick.disabled) pick.checked = true;
    card?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, 250);
}

function renderRouteBar() {
  const bar = ensureRouteBar();
  if (!bar) return;

  const entries = [...routeMap.values()]
    .sort((a, b) => a.colour_code.localeCompare(b.colour_code, undefined, { numeric: true }));

  if (!entries.length) {
    bar.innerHTML = "";
    return;
  }

  bar.innerHTML = `
    <div class="v753-route-title">COLOUR ACTIVE DEPARTMENT · LOCKED</div>
    <div class="v753-route-chips">
      ${entries.map(item => {
        const dep = upper(item.department_code);
        const status = upper(item.status);
        return `<button type="button"
          class="v753-route-chip ${status === "RUNNING" ? "running" : status === "ASSIGNED" ? "assigned" : status === "SUBMITTED" ? "submitted" : "open"}"
          data-v753-colour="${esc(item.colour_code)}">
          <b>${esc(item.colour_code)}</b>
          <span>${esc(departmentName(dep))}</span>
          <small>${esc(status || "OPEN")}</small>
        </button>`;
      }).join("")}
    </div>`;

  bar.querySelectorAll("[data-v753-colour]").forEach(button => {
    button.onclick = () => switchToColour(button.dataset.v753Colour);
  });
}

function hideManualDepartment() {
  const dept = $("dept");
  const field = dept?.closest(".field");
  if (!field) return;
  field.classList.add("v753-hidden-department");
}

function addLockedDepartmentToCards() {
  document.querySelectorAll(".colour-card").forEach(async card => {
    const code = colourCodeFromCard(card);
    if (!code) return;

    const route = routeMap.get(code);
    const dep = upper(route?.department_code || $("dept")?.value);
    const workerBlock = card.querySelector(".worker-block");
    if (!workerBlock) return;

    let locked = workerBlock.querySelector(".v753-card-department");
    if (!locked) {
      locked = document.createElement("label");
      locked.className = "v753-card-department";
      workerBlock.insertAdjacentElement("afterbegin", locked);
    }

    locked.innerHTML = `
      Active Department · Locked
      <input value="${esc(departmentName(dep))} · ${esc(code)}" disabled>
    `;

    const workers = await workersFor(dep);
    const workerSelect = card.querySelector(".colour-worker");
    if (!workerSelect || workerSelect.disabled) return;

    const oldValue = workerSelect.value;
    workerSelect.innerHTML = `<option value="">Select ${esc(departmentName(dep))} worker</option>` +
      workers.map(worker => `
        <option value="${esc(worker.worker_id)}"
          data-name="${esc(worker.worker_name || "")}"
          data-code="${esc(worker.worker_code || "")}">
          ${esc(worker.worker_name || "Unnamed")}
          ${worker.worker_code ? ` · ${esc(worker.worker_code)}` : ""}
        </option>`).join("");

    if ([...workerSelect.options].some(o => o.value === oldValue)) {
      workerSelect.value = oldValue;
    }

    if (!workers.length) {
      workerSelect.innerHTML = `<option value="">No active worker mapped in ${esc(departmentName(dep))}</option>`;
      workerSelect.disabled = true;
    }
  });
}

async function refillBulkWorkerForVisibleCards() {
  const cards = [...document.querySelectorAll(".colour-card")];
  const firstCode = colourCodeFromCard(cards[0]);
  const dep = upper(routeMap.get(firstCode)?.department_code || $("dept")?.value);
  if (!dep) return;

  const workers = await workersFor(dep);
  const select = $("bulkWorker");
  if (!select) return;

  const old = select.value;
  select.innerHTML = `<option value="">Select ${esc(departmentName(dep))} worker</option>` +
    workers.map(worker => `
      <option value="${esc(worker.worker_id)}"
        data-name="${esc(worker.worker_name || "")}"
        data-code="${esc(worker.worker_code || "")}">
        ${esc(worker.worker_name || "Unnamed")}
        ${worker.worker_code ? ` · ${esc(worker.worker_code)}` : ""}
      </option>`).join("");

  if ([...select.options].some(o => o.value === old)) select.value = old;

  if (!workers.length) {
    select.innerHTML = `<option value="">No active worker mapped in ${esc(departmentName(dep))}</option>`;
    select.disabled = true;
  } else {
    select.disabled = false;
  }
}

function autoSelectSingleVisibleColour() {
  const cards = [...document.querySelectorAll(".colour-card")]
    .filter(card => !card.classList.contains("hidden"));

  if (cards.length !== 1) return;

  const pick = cards[0].querySelector(".work-pick, .assign-pick");
  if (pick && !pick.disabled) pick.checked = true;
}

async function sync() {
  if (busy) return;
  busy = true;
  try {
    hideManualDepartment();
    await loadRoutes();
    renderRouteBar();
    await addLockedDepartmentToCards();
    await refillBulkWorkerForVisibleCards();
    autoSelectSingleVisibleColour();
  } finally {
    busy = false;
  }
}

function addStyles() {
  if ($("v753Style")) return;
  const style = document.createElement("style");
  style.id = "v753Style";
  style.textContent = `
    .v753-hidden-department{
      position:absolute!important;
      width:1px!important;
      height:1px!important;
      overflow:hidden!important;
      opacity:0!important;
      pointer-events:none!important;
    }
    .v753-route-bar{
      margin:10px 0;
      border:1px solid #42536d;
      border-radius:12px;
      padding:10px;
      background:#101827;
    }
    .v753-route-title{
      font-size:12px;
      font-weight:950;
      color:#cfe3ff;
      margin-bottom:8px;
    }
    .v753-route-chips{
      display:flex;
      gap:7px;
      flex-wrap:wrap;
    }
    .v753-route-chip{
      display:grid;
      grid-template-columns:auto auto;
      gap:2px 8px;
      align-items:center;
      min-width:128px;
      text-align:left;
      border-width:2px;
    }
    .v753-route-chip b{font-size:14px}
    .v753-route-chip span{font-weight:900}
    .v753-route-chip small{grid-column:1/-1;opacity:.85}
    .v753-route-chip.running{background:#0b653b;border-color:#40d78b}
    .v753-route-chip.assigned{background:#8b5605;border-color:#ffb23f}
    .v753-route-chip.submitted{background:#76202c;border-color:#ff7182}
    .v753-route-chip.open{background:#202733;border-color:#596477}
    .worker-block{
      grid-template-columns:minmax(180px,240px) minmax(190px,290px) minmax(190px,290px)!important;
    }
    .v753-card-department input{
      background:#111a27!important;
      color:#9ec5ff!important;
      border-color:#4774a9!important;
      font-weight:950!important;
      opacity:1!important;
    }
    @media(max-width:900px){
      .worker-block{grid-template-columns:1fr!important}
    }
  `;
  document.head.appendChild(style);
}

function install() {
  addStyles();
  sync();

  const observer = new MutationObserver(() => {
    clearTimeout(install.timer);
    install.timer = setTimeout(sync, 100);
  });
  observer.observe(document.body, { childList: true, subtree: true });
}

document.readyState === "loading"
  ? document.addEventListener("DOMContentLoaded", install)
  : install();

window.REDZED_UPM_V753 = {
  version: VERSION,
  sync,
  routes: () => [...routeMap.values()]
};

console.info("REDZED UPM", VERSION);
})();