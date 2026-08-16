(() => {
"use strict";

const VERSION = "9135";
const FABRIC_RPC = "rr_get_mc1_fabric_options_v9134";
const VENDOR_RPC = "rr_get_mc_vendor_options_v9135";

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

function labelForFabric(row) {
  const qty = row.available_qty ?? row.current_qty ?? 0;
  const rate = row.avg_cost ?? row.avg_rate ?? 0;
  return `${row.fabric_name} · ${kg(qty)} · ${money(rate)}/kg`;
}

function labelForVendor(row) {
  const bills = Number(row.bill_count || 0);
  const qty = Number(row.total_qty || 0);
  const value = Number(row.total_value || 0);
  return bills ? `${row.vendor_name} · ${bills} bill · ${kg(qty)} · ${money(value)}` : row.vendor_name;
}

function renderFabric(select, rows) {
  const current = select.value;
  const options = rows
    .filter(row => row && row.fabric_name && row.is_active !== false)
    .sort((a, b) => String(a.fabric_name).localeCompare(String(b.fabric_name)))
    .map(row => {
      const id = row.id || row.matching_item_id || row.fabric_id;
      return `<option value="${safe(id)}">${safe(labelForFabric(row))}</option>`;
    })
    .join("");

  select.innerHTML = `<option value="">Select Matching Fabric</option>${options}<option value="__new__">+ New Matching Fabric Name</option>`;
  if ([...select.options].some(option => option.value === current)) select.value = current;
  select.dataset.realFactoryFabricDropdown = VERSION;
}

function ensureVendorSelect(input) {
  if (!input || input.tagName === "SELECT") return input;
  const select = document.createElement("select");
  select.id = input.id;
  select.name = input.name || input.id;
  select.className = input.className;
  select.autocomplete = "off";
  select.innerHTML = `<option value="">Select Vendor</option><option value="__new_vendor__">+ New Vendor Name</option>`;
  input.replaceWith(select);
  return select;
}

function renderVendor(select, rows) {
  const current = select.value;
  const options = rows
    .filter(row => row && row.vendor_name && row.is_active !== false)
    .sort((a, b) => {
      const ab = Number(a.bill_count || 0) > 0 ? 0 : 1;
      const bb = Number(b.bill_count || 0) > 0 ? 0 : 1;
      return ab - bb || String(a.vendor_name).localeCompare(String(b.vendor_name));
    })
    .map(row => `<option value="${safe(row.vendor_name)}" data-ledger="${safe(row.supplier_ledger_id)}">${safe(labelForVendor(row))}</option>`)
    .join("");

  select.innerHTML = `<option value="">Select Vendor</option>${options}<option value="__new_vendor__">+ New Vendor Name</option>`;
  if ([...select.options].some(option => option.value === current)) select.value = current;
  select.dataset.realFactoryVendorDropdown = VERSION;
}

async function refreshFabricDropdown() {
  const select = document.getElementById("mcFabricSelect");
  const sb = client();
  if (!select || !sb || typeof sb.rpc !== "function") return;

  try {
    const result = await sb.rpc(FABRIC_RPC);
    if (result.error) throw result.error;
    const rows = Array.isArray(result.data) ? result.data : [];
    if (rows.length) renderFabric(select, rows);
  } catch (error) {
    console.warn("MC fabric dropdown v9135 failed", error);
  }
}

async function refreshVendorDropdown() {
  const select = ensureVendorSelect(document.getElementById("mcVendor"));
  const sb = client();
  if (!select || !sb || typeof sb.rpc !== "function") return;

  try {
    const result = await sb.rpc(VENDOR_RPC);
    if (result.error) throw result.error;
    const rows = Array.isArray(result.data) ? result.data : [];
    if (rows.length) renderVendor(select, rows);
  } catch (error) {
    console.warn("MC vendor dropdown v9135 failed", error);
  }
}

function refreshDropdowns() {
  refreshFabricDropdown();
  refreshVendorDropdown();
}

function bindNewVendor() {
  document.addEventListener("change", event => {
    const select = event.target?.closest?.("#mcVendor");
    if (!select || select.value !== "__new_vendor__") return;
    const name = window.prompt("New Vendor Name");
    if (!name || !name.trim()) {
      select.value = "";
      return;
    }
    const clean = name.trim();
    const option = new Option(clean, clean, true, true);
    select.add(option, select.options[select.options.length - 1]);
    select.value = clean;
  }, true);
}

function bind() {
  bindNewVendor();
  document.addEventListener("click", event => {
    if (event.target?.closest?.("#openMcNew,[data-open-mc]")) {
      setTimeout(refreshDropdowns, 500);
      setTimeout(refreshDropdowns, 1500);
    }
  }, true);

  const observer = new MutationObserver(() => {
    const sheet = document.getElementById("mcSheet");
    if (sheet && !sheet.classList.contains("hidden")) refreshDropdowns();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bind);
else bind();
})();
