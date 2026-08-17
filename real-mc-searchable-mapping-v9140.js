(() => {
"use strict";

const VERSION = "9148";
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
const normalize = value => String(value ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "");
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

function installStyles() {
  if (byId("mcSearchableMappingStyle9148")) return;
  const style = document.createElement("style");
  style.id = "mcSearchableMappingStyle9148";
  style.textContent = `
    .mc-search-wrap-9140{position:relative}
    .mc-suggest-9140{position:absolute;left:0;right:0;top:calc(100% + 4px);z-index:3000;display:none;max-height:260px;overflow:auto;border:1px solid #5b3b3f;border-radius:12px;background:#35241e;box-shadow:0 18px 42px rgba(0,0,0,.45)}
    .mc-suggest-9140.open{display:block}
    .mc-suggest-9140 button{width:100%;display:block;text-align:left;border:0;border-bottom:1px solid rgba(255,255,255,.12);border-radius:0;background:transparent;color:#fff;padding:11px 12px;font-weight:800}
    .mc-suggest-9140 button:last-child{border-bottom:0}
    .mc-suggest-9140 small{display:block;margin-top:3px;color:#d0c3bd;font-weight:600}
    .mc-add-row-9140{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}
    .mc-add-row-9140 button{flex:1}
    .sheet-head div>p:not(.kicker){display:none!important}
    .sheet-panel.mc-fill-focus-9140 .sheet-head{display:none!important}
    .sheet-panel.mc-fill-focus-9140{padding-top:10px!important}
  `;
  document.head.appendChild(style);
}

function wrapInput(input, listId) {
  if (!input) return null;
  let wrap = input.closest(".mc-search-wrap-9140");
  if (!wrap) {
    wrap = document.createElement("div");
    wrap.className = "mc-search-wrap-9140";
    input.insertAdjacentElement("beforebegin", wrap);
    wrap.appendChild(input);
  }
  let list = byId(listId);
  if (!list) {
    list = document.createElement("div");
    list.id = listId;
    list.className = "mc-suggest-9140";
    wrap.appendChild(list);
  }
  return { wrap, list };
}

function addButton(id, text, afterEl, onClick) {
  if (!afterEl || byId(id)) return;
  let row = afterEl.parentElement?.querySelector(".mc-add-row-9140");
  if (!row) {
    row = document.createElement("div");
    row.className = "mc-add-row-9140";
    afterEl.parentElement?.appendChild(row);
  }
  const button = document.createElement("button");
  button.id = id;
  button.type = "button";
  button.className = "primary tiny";
  button.textContent = text;
  button.addEventListener("click", onClick);
  row.appendChild(button);
}

function renderSuggestions(input, list, rows, labelFn, pickFn, emptyText) {
  const q = normalize(input.value);
  const ranked = rows
    .map(row => {
      const primary = row.fabric_name || row.vendor_name || "";
      const label = labelFn(row);
      const hay = normalize(`${primary} ${label}`);
      const score = !q ? 1 : normalize(primary).startsWith(q) ? 0 : hay.includes(q) ? 1 : 9;
      return { row, label, score };
    })
    .filter(item => item.score < 9)
    .sort((a, b) => a.score - b.score || a.label.localeCompare(b.label))
    .slice(0, 12);

  if (!ranked.length) {
    list.innerHTML = `<button type="button" disabled>${safe(emptyText)}</button>`;
    list.classList.add("open");
    return;
  }

  list.innerHTML = ranked.map((item, index) => {
    const name = item.row.fabric_name || item.row.vendor_name || "";
    return `<button type="button" data-index="${index}">${safe(name)}<small>${safe(item.label)}</small></button>`;
  }).join("");
  list.querySelectorAll("button[data-index]").forEach(button => {
    button.addEventListener("mousedown", event => {
      event.preventDefault();
      pickFn(ranked[Number(button.dataset.index)].row);
      list.classList.remove("open");
    });
  });
  list.classList.add("open");
}

function ensureFabricSearch() {
  const select = byId("mcFabricSelect");
  if (!select) return null;
  select.style.display = "none";

  let input = byId("mcFabricSearch");
  if (!input) {
    input = document.createElement("input");
    input.id = "mcFabricSearch";
    input.placeholder = "Search Matching Fabric";
    input.autocomplete = "off";
    select.insertAdjacentElement("afterend", input);
  }
  input.removeAttribute("list");
  const parts = wrapInput(input, "mcFabricSuggest9140");
  if (!parts) return input;

  const pick = row => {
    input.value = row.fabric_name || labelForFabric(row);
    select.value = String(row.id || row.matching_item_id || row.fabric_id || "");
    const wrap = byId("mcNewFabricWrap");
    const newInput = byId("mcNewFabric");
    if (wrap) wrap.classList.add("hidden");
    if (newInput) newInput.value = "";
    select.dispatchEvent(new Event("change", { bubbles: true }));
  };
  input.oninput = () => {
    const typed = String(input.value || "").trim();
    const exact = fabricRows.find(row => normalize(row.fabric_name) === normalize(typed));
    const newInput = byId("mcNewFabric");
    const wrap = byId("mcNewFabricWrap");
    if (exact) {
      select.value = String(exact.id || exact.matching_item_id || exact.fabric_id || "");
      if (newInput) newInput.value = "";
      if (wrap) wrap.classList.add("hidden");
    } else {
      select.value = typed ? "__new__" : "";
      if (newInput) newInput.value = typed;
      if (wrap) wrap.classList.toggle("hidden", !typed);
    }
    select.dispatchEvent(new Event("change", { bubbles: true }));
    renderSuggestions(input, parts.list, fabricRows, labelForFabric, pick, "No matching fabric");
  };
  input.onfocus = () => renderSuggestions(input, parts.list, fabricRows, labelForFabric, pick, "No matching fabric");
  input.onblur = () => setTimeout(() => parts.list.classList.remove("open"), 160);

  addButton("mcAddFabricBtn9140", "+ New Matching Fabric Name", input, () => {
    select.value = "__new__";
    select.dispatchEvent(new Event("change", { bubbles: true }));
    const wrap = byId("mcNewFabricWrap");
    const newInput = byId("mcNewFabric");
    if (wrap) wrap.classList.remove("hidden");
    if (newInput && input.value.trim()) newInput.value = input.value.trim();
    setTimeout(() => newInput?.focus(), 50);
  });
  return input;
}

function renderFabricSearch(rows) {
  fabricRows = rows
    .filter(row => row && row.fabric_name && row.is_active !== false)
    .sort((a, b) => String(a.fabric_name).localeCompare(String(b.fabric_name)));
  const input = ensureFabricSearch();
  if (input) input.dataset.realFactoryFabricSearch = VERSION;
}

function ensureVendorSearch() {
  const input = byId("mcVendor");
  if (!input) return null;
  input.removeAttribute("list");
  input.placeholder = "Search Vendor";
  input.autocomplete = "off";
  const parts = wrapInput(input, "mcVendorSuggest9140");
  if (!parts) return input;

  const pick = row => {
    input.value = row.vendor_name || "";
    input.dataset.supplierLedgerId = row.supplier_ledger_id || "";
  };
  input.oninput = () => {
    input.dataset.supplierLedgerId = "";
    renderSuggestions(input, parts.list, vendorRows, labelForVendor, pick, "No matching vendor");
  };
  input.onfocus = () => renderSuggestions(input, parts.list, vendorRows, labelForVendor, pick, "No matching vendor");
  input.onblur = () => setTimeout(() => parts.list.classList.remove("open"), 160);

  addButton("mcAddVendorBtn9140", "+ New Vendor Name", input, () => {
    input.value = "";
    input.dataset.supplierLedgerId = "";
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
  if (input) input.dataset.realFactoryVendorSearch = VERSION;
}

async function refreshFabricSearch() {
  const sb = client();
  if (!sb || typeof sb.rpc !== "function") return;
  try {
    const result = await sb.rpc(FABRIC_RPC);
    if (result.error) throw result.error;
    renderFabricSearch(Array.isArray(result.data) ? result.data : []);
  } catch (error) {
    console.warn("MC fabric searchable mapping v9148 failed", error);
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
    console.warn("MC vendor searchable mapping v9148 failed", error);
  }
}

function refreshAll() {
  installStyles();
  ensureFabricSearch();
  ensureVendorSearch();
  refreshFabricSearch();
  refreshVendorSearch();
}

function bindFillFocusHeader() {
  document.addEventListener("focusin", event => {
    if (!event.target?.matches?.("input,select,textarea")) return;
    event.target.closest?.(".sheet-panel")?.classList.add("mc-fill-focus-9140");
  }, true);
  document.addEventListener("focusout", event => {
    const panel = event.target?.closest?.(".sheet-panel");
    if (!panel) return;
    setTimeout(() => {
      if (!panel.contains(document.activeElement) || !document.activeElement?.matches?.("input,select,textarea")) {
        panel.classList.remove("mc-fill-focus-9140");
      }
    }, 120);
  }, true);
}

function bind() {
  installStyles();
  bindFillFocusHeader();
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
