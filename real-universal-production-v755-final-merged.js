(() => {
"use strict";

const VERSION = "V755_2_HARD_BOOT";
const $ = id => document.getElementById(id);
const upper = v => String(v || "").trim().toUpperCase();
const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[c]));

let activeCanonical = "";
let booted = false;
let syncTimer = null;

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

async function fetchMatrix(canonical, lotNo = "") {
  const sb = getClient();
  if (!sb) throw new Error("Connected Supabase client not found.");

  const { data, error } = await sb.rpc("rr_upm_lot_colour_matrix_v755", {
    p_canonical_lot_id: canonical || null,
    p_lot_no: lotNo || null
  });

  if (error) throw error;
  return data;
}

function statusClass(status) {
  const s = upper(status);
  if (s === "RUNNING") return "running";
  if (s === "ASSIGNED") return "assigned";
  if (s === "OPEN") return "open";
  return "legacy";
}

function alterShort(row) {
  const a = row?.alter_journey;
  if (!a || Number(a.qty || 0) <= 0) return "Alter NONE";
  return `${a.stage_label || a.stage} · ${a.qty} PCS · ${
    [a.responsible_name, a.responsible_role_short].filter(Boolean).join(" ")
  }`;
}

function showBootBadge(text, bad = false) {
  let badge = document.getElementById("v755HardBootBadge");
  if (!badge) {
    badge = document.createElement("div");
    badge.id = "v755HardBootBadge";
    badge.style.cssText = `
      position:fixed;right:12px;bottom:12px;z-index:99999;
      padding:9px 12px;border-radius:9px;font-weight:900;
      box-shadow:0 4px 18px #0008;
    `;
    document.body.appendChild(badge);
  }
  badge.textContent = text;
  badge.style.background = bad ? "#a9162a" : "#08783f";
  badge.style.color = "#fff";
  clearTimeout(showBootBadge.timer);
  showBootBadge.timer = setTimeout(() => badge.remove(), 4500);
}

async function renderBoardCard(card) {
  const canonical = card.dataset.lot || "";
  const lotNo = card.querySelector(".lot-no")?.textContent?.trim() || "";
  if (!canonical && !lotNo) return;

  const data = await fetchMatrix(canonical, lotNo);

  card.querySelectorAll(
    ".lot-live-list,.lot-live-status,.v753-route-bar,.v754-board-status,.v755-board-matrix"
  ).forEach(node => node.remove());

  let matrix = card.querySelector(".v7552-short-matrix");
  if (!matrix) {
    matrix = document.createElement("div");
    matrix.className = "v7552-short-matrix";
    const thumbs = card.querySelector(".thumbs");
    thumbs?.insertAdjacentElement("beforebegin", matrix);
  }

  matrix.innerHTML = (data?.colours || []).map(row => `
    <div class="v7552-short-row ${statusClass(row.ownership_status)}"
         data-v7552-canonical="${esc(data.canonical_lot_id)}"
         data-v7552-colour="${esc(row.colour_code)}"
         data-v7552-department="${esc(row.department_code)}">
      <b>${esc(row.colour_code)}</b>
      <span>${esc(row.department_name)}</span>
      <em>${esc(row.ownership_status)}</em>
      <small>${esc(alterShort(row))}</small>
    </div>
  `).join("");
}

function locateActiveCanonical() {
  if (activeCanonical) return activeCanonical;

  const lotNo = [...document.querySelectorAll("#identity .box")]
    .find(box => upper(box.querySelector("small")?.textContent) === "LOT NO")
    ?.querySelector("b")?.textContent?.trim();

  if (!lotNo) return "";

  const card = [...document.querySelectorAll(".lot-card")]
    .find(c => c.querySelector(".lot-no")?.textContent?.trim() === lotNo);

  return card?.dataset?.lot || "";
}

async function renderCheckinMatrix() {
  const traveller = $("traveller");
  if (!traveller || traveller.classList.contains("hidden")) return;

  const canonical = locateActiveCanonical();
  if (!canonical) return;

  const data = await fetchMatrix(canonical, "");

  let panel = $("v7552DetailedMatrix");
  if (!panel) {
    panel = document.createElement("section");
    panel.id = "v7552DetailedMatrix";
    panel.className = "v7552-detail-panel";
    const colours = $("colours");
    colours?.insertAdjacentElement("beforebegin", panel);
  }

  panel.innerHTML = `
    <div class="v7552-title">COLOUR × ACTIVE DEPARTMENT · DETAILED</div>
    <div class="v7552-wrap">
      <table>
        <thead>
          <tr>
            <th>Colour</th>
            <th>Active Department</th>
            <th>Status</th>
            <th>Worker</th>
            <th>Alter Journey</th>
            <th>Open</th>
          </tr>
        </thead>
        <tbody>
          ${(data?.colours || []).map(row => `
            <tr class="${statusClass(row.ownership_status)}">
              <td><b>${esc(row.colour_code)}</b></td>
              <td>${esc(row.department_name)}</td>
              <td>${esc(row.ownership_status)}</td>
              <td>${esc(row.worker_name || "Worker pending")}</td>
              <td>${esc(alterShort(row))}</td>
              <td>
                <button type="button"
                  class="v7552-open-colour"
                  data-v7552-colour="${esc(row.colour_code)}"
                  data-v7552-department="${esc(row.department_code)}">
                  OPEN
                </button>
              </td>
            </tr>
          `).join("")}
        </tbody>
      </table>
    </div>
  `;

  // Hide old manual department field; matrix is the navigation source.
  $("dept")?.closest(".field")?.classList.add("v7552-hide");
}

async function openDetailedColour(colour, department) {
  const dept = $("dept");

  if (dept && department) {
    const option = [...dept.options].find(
      o => upper(o.value) === upper(department)
    );

    if (option && dept.value !== option.value) {
      dept.value = option.value;
      dept.dispatchEvent(new Event("change", { bubbles: true }));
      await new Promise(resolve => setTimeout(resolve, 700));
    }
  }

  setTimeout(() => {
    const card = [...document.querySelectorAll(".colour-card")].find(c => {
      const heading = upper(c.querySelector(".colour-title")?.textContent);
      return new RegExp(`\\b${colour}\\b`).test(heading);
    });

    const pick = card?.querySelector(".work-pick,.assign-pick");
    if (pick && !pick.disabled) pick.checked = true;
    card?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, 250);
}

async function syncAll() {
  try {
    await Promise.all(
      [...document.querySelectorAll(".lot-card")].map(renderBoardCard)
    );
    await renderCheckinMatrix();

    if (!booted) {
      booted = true;
      showBootBadge("V755.2 ACTIVE");
    }
  } catch (error) {
    console.error(VERSION, error);
    showBootBadge(`V755.2 ERROR: ${error.message || error}`, true);
  }
}

function bindClicks() {
  document.addEventListener("click", event => {
    const openLot = event.target.closest("[data-open-lot],.lot-card");
    if (openLot) {
      const card = openLot.closest(".lot-card") || openLot;
      activeCanonical = card?.dataset?.lot || activeCanonical;
      setTimeout(syncAll, 900);
    }

    const row = event.target.closest(".v7552-short-row");
    if (row) {
      activeCanonical = row.dataset.v7552Canonical || activeCanonical;
      const card = row.closest(".lot-card");
      card?.querySelector("[data-open-lot],.checkin")?.click();
      setTimeout(() => openDetailedColour(
        upper(row.dataset.v7552Colour),
        upper(row.dataset.v7552Department)
      ), 900);
    }

    const detail = event.target.closest(".v7552-open-colour");
    if (detail) {
      event.preventDefault();
      openDetailedColour(
        upper(detail.dataset.v7552Colour),
        upper(detail.dataset.v7552Department)
      );
    }
  }, true);
}

function addStyles() {
  if ($("v7552Style")) return;

  const style = document.createElement("style");
  style.id = "v7552Style";
  style.textContent = `
    .lot-card{height:auto!important;min-height:285px!important}
    .v7552-short-matrix{display:grid;gap:5px;margin:8px 0}
    .v7552-short-row{
      display:grid;grid-template-columns:38px minmax(110px,1fr) 72px;
      gap:5px 8px;align-items:center;padding:6px 8px;
      border:1px solid #475160;border-radius:7px;
      background:#171d26;cursor:pointer
    }
    .v7552-short-row small{grid-column:1/-1;color:#c7d1df}
    .v7552-short-row em{font-style:normal;font-size:10px;font-weight:900}
    .v7552-short-row.running{background:#10432e;border-color:#38d58a}
    .v7552-short-row.assigned{background:#52350b;border-color:#ffb33e}
    .v7552-short-row.open{background:#122d4a;border-color:#5194df}
    .v7552-short-row.legacy{background:#4b1720;border-color:#e05263}

    .v7552-detail-panel{
      margin:10px 0;padding:10px;border:2px solid #506b91;
      border-radius:12px;background:#101723
    }
    .v7552-title{font-weight:950;color:#cfe4ff;margin-bottom:8px}
    .v7552-wrap{overflow:auto}
    .v7552-detail-panel table{min-width:850px!important}
    .v7552-detail-panel tr.running{background:#103d2c}
    .v7552-detail-panel tr.assigned{background:#49320d}
    .v7552-detail-panel tr.open{background:#122940}
    .v7552-open-colour{background:#204d80;border-color:#4c91dc}
    .v7552-hide{
      position:absolute!important;width:1px!important;height:1px!important;
      opacity:0!important;overflow:hidden!important;pointer-events:none!important
    }
  `;
  document.head.appendChild(style);
}

function install() {
  addStyles();
  bindClicks();
  syncAll();

  const observer = new MutationObserver(() => {
    clearTimeout(syncTimer);
    syncTimer = setTimeout(syncAll, 140);
  });

  observer.observe(document.body, { childList: true, subtree: true });
}

document.readyState === "loading"
  ? document.addEventListener("DOMContentLoaded", install)
  : install();

window.REDZED_UPM_V755_2 = {
  version: VERSION,
  sync: syncAll
};

console.info("REDZED UPM", VERSION);
})();