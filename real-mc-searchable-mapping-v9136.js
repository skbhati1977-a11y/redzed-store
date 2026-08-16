(() => {
"use strict";

const VERSION = "9136";
const FABRIC_RPC = "rr_get_mc1_fabric_options_v9134";
const VENDOR_RPC = "rr_get_mc_vendor_options_v9135";
let fabricRows = [];
let vendorRows = [];

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

function byId(id) {
  return document.getElementById(id);
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

function addButton(id, text, afterEl, onClick) {
  if (!afterEl || byId(id)) return;
  const button = document.createElement("button");
  button.id = id;
  button.type = "button";
  button.className = "secondary tiny";
  button.textContent = text;
  button.style.marginTop = "8px";
  button.addEventListener("click", onClick);
  afterEl.insertAdjacentElement("afterend", button);
}

function ensureFabricSearch() {
  const select = byId("mcFabricSelect");
  if (!select) return null;
  select.style.display = "none";

  let input = byId("mcFabricSearch");
  if (!input) {
    input = document.createElement("input");
    input.id = "mcFabricSearch";
    input.setAttribute("list", "mcFabricSearchList");
    input.placeholder = "Search Matching Fabric";
    input.autocomplete = "off";
    select.insertAdjacentElement("afterend", input);
    const list = document.createElement("datalist");
    list.id = "mcFabricSearchList";
    input.insertAdjacentElement("afterend", list);
    input.addEventListener("input", () => {
      const match = fabricRows.find(row => labelForFabric(row) === input.value || row.fabric_name === input.value);
      select.value = match ? String(match.id || match.matching_item_id || match.fabric_id || "") : "";
      select.dispatchEvent(new Event("change", { bubbles: true }));
    });
  }

  addButton("mcAddFabricBtn9136", "+ New Matching Fabric Name", input, () => {
    select.value = "__new__";
    select.dispatchEvent(new Event("change", { bubbles: true }));
    const wrap = byId("mcNewFabricWrap");
    if (wrap) wrap.classList.remove("hidden");
    setTimeout(() => byId("mcNewFabric")?.focus(), 50);
  });
  return input;
}

function renderFabricSearch(rows) {
  fabricRows = rows
    .filter(row => row && row.fabric_name && row.is_active !== false)
    .sort((a, b) => String(a.fabric_name).localeCompare(String(b.fabric_name)));
  const input = ensureFabricSearch();
  const list = byId("mcFabricSearchList");
  if (!input || !list) return;
  list.innerHTML = fabricRows.map(row => `<option value="${safe(labelForFabric(row))}"></option>`).join("");
  input.dataset.realFactoryFabricSearch = VERSION;
}

function ensureVendorSearch() {
  const input = byId("mcVendor");
  if (!input) return null;
  input.setAttribute("list", "mcVendorSearchList");
  input.placeholder = "Search Vendor";
  input.autocomplete = "off";
  let list = byId("mcVendorSearchList");
  if (!list) {
    list = document.createElement("datalist");
    list.id = "mcVendorSearchList";
    input.insertAdjacentElement("afterend", list);
  }
  addButton("mcAddVendorBtn9136", "+ New Vendor Name", input, () => {
    input.value = "";
    input.placeholder = "Type New Vendor Name";
    input.focus();
  });
  return input;
}

function renderVendorSearch(rows) {
  vendorRows = rows
    .filter(row => row && row.vendor_name && row.is_active !== false)
    .sort((a, b) => {
      const ab = Number(a.bill_count || 0) > 0 ? 0 : 1;
      const bb = Number(b.bill_count || 0) > 0 ? 0 : 1;
      return ab - bb || String(a.vendor_name).localeCompare(String(b.vendor_name));
    });
  const input = ensureVendorSearch();
  const list = byId("mcVendorSearchList");
  if (!input || !list) return;
  list.innerHTML = vendorRows
    .map(row => `<option value="${safe(row.vendor_name)}" label="${safe(labelForVendor(row))}"></option>`)
    .join("");
  input.dataset.realFactoryVendorSearch = VERSION;
}

async function refreshFabricSearch() {
  const sb = client();
  if (!sb || typeof sb.rpc !== "function") return;
  try {
    const result = await sb.rpc(FABRIC_RPC);
    if (result.error) throw result.error;
    renderFabricSearch(Array.isArray(result.data) ? result.data : []);
  } catch (error) {
    console.warn("MC fabric searchable mapping v9136 failed", error);
  }
}

async function refreshVendorSearch() {
  const sb = client();
  if (!sb || typeof sb.rpc !== "function") return;
  try {
    const result = await sb.rpc(VENDOR_RPC);
    if (result.error) throw result.error;
    renderVendorSearch(Array.isArray(result.data) ? result.data : []);
  } catch (error) {
    console.warn("MC vendor searchable mapping v9136 failed", error);
  }
}

function refreshAll() {
  ensureFabricSearch();
  ensureVendorSearch();
  refreshFabricSearch();
  refreshVendorSearch();
}

function bind() {
  document.addEventListener("click", event => {
    if (event.target?.closest?.("#openMcNew,[data-open-mc]")) {
      setTimeout(refreshAll, 400);
      setTimeout(refreshAll, 1300);
    }
  }, true);

  const observer = new MutationObserver(() => {
    const sheet = byId("mcSheet");
    if (sheet && !sheet.classList.contains("hidden")) refreshAll();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bind);
else bind();
})();
