(() => {
"use strict";

const VERSION = "9134";
const FABRIC_RPC = "rr_get_mc1_fabric_options_v9134";

const safe = value => String(value ?? "").replace(/[&<>"']/g, c => ({
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#039;"
}[c]));
const kg = value => `${Number(value || 0).toFixed(3)} kg`;
const money = value => new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 2
}).format(Number(value || 0));

function client() {
  return window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;
}

function labelFor(row) {
  const qty = row.available_qty ?? row.current_qty ?? 0;
  const rate = row.avg_cost ?? row.avg_rate ?? 0;
  return `${row.fabric_name} · ${kg(qty)} · ${money(rate)}/kg`;
}

function render(select, rows) {
  const current = select.value;
  const options = rows
    .filter(row => row && row.fabric_name && row.is_active !== false)
    .sort((a, b) => String(a.fabric_name).localeCompare(String(b.fabric_name)))
    .map(row => {
      const id = row.id || row.matching_item_id || row.fabric_id;
      return `<option value="${safe(id)}">${safe(labelFor(row))}</option>`;
    })
    .join("");

  select.innerHTML = `<option value="">Select Matching Fabric</option>${options}<option value="__new__">+ New Matching Fabric Name</option>`;
  if ([...select.options].some(option => option.value === current)) select.value = current;
  select.dataset.realFactoryFabricDropdown = VERSION;
}

async function refreshDropdown() {
  const select = document.getElementById("mcFabricSelect");
  const sb = client();
  if (!select || !sb || typeof sb.rpc !== "function") return;

  try {
    const result = await sb.rpc(FABRIC_RPC);
    if (result.error) throw result.error;
    const rows = Array.isArray(result.data) ? result.data : [];
    if (rows.length) render(select, rows);
  } catch (error) {
    console.warn("MC fabric dropdown v9134 failed", error);
  }
}

function bind() {
  document.addEventListener("click", event => {
    if (event.target?.closest?.("#openMcNew,[data-open-mc]")) {
      setTimeout(refreshDropdown, 500);
      setTimeout(refreshDropdown, 1500);
    }
  }, true);

  const observer = new MutationObserver(() => {
    const sheet = document.getElementById("mcSheet");
    const select = document.getElementById("mcFabricSelect");
    if (sheet && select && !sheet.classList.contains("hidden")) refreshDropdown();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bind);
else bind();
})();
