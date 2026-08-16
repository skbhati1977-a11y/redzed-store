(() => {
  "use strict";

  const VIEW = "rr_cb_new_regular_purchase_options_v1";
  const VENDOR_LIST_ID = "cbRegularPurchaseVendorHistoryV9133";
  const FABRIC_LIST_ID = "cbRegularPurchaseFabricHistoryV9133";
  let options = { vendors: [], fabrics: [] };
  let observer = null;
  let rollSyncScheduled = false;
  let loadStarted = false;

  function client() {
    try {
      if (window.RR?.getClient) return RR.getClient();
    } catch (_) {}
    return window.supabaseClient || window.supabaseDb || window.redzedSupabase || window.sb || null;
  }

  function uniq(rows, type) {
    const seen = new Set();
    return rows
      .filter(r => String(r.option_type || "").toUpperCase() === type)
      .map(r => String(r.option_value || "").trim())
      .filter(Boolean)
      .filter(v => {
        const k = v.toLocaleLowerCase();
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
      })
      .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base", numeric: true }));
  }

  function ensureDataList(id, values) {
    let list = document.getElementById(id);
    if (!list) {
      list = document.createElement("datalist");
      list.id = id;
      document.body.appendChild(list);
    }
    const html = values.map(v => `<option value="${String(v).replaceAll("&", "&amp;").replaceAll('"', "&quot;")}"></option>`).join("");
    if (list.innerHTML !== html) list.innerHTML = html;
  }

  function dispatchInput(input, value) {
    input.value = value;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function addNewButton(input, kind) {
    const cls = kind === "vendor" ? "cb-add-new-vendor-v9133" : "cb-add-new-fabric-v9133";
    if (input.parentElement?.querySelector(`.${cls}`)) return;

    const button = document.createElement("button");
    button.type = "button";
    button.className = `secondary tiny ${cls}`;
    button.style.marginTop = "6px";
    button.textContent = kind === "vendor" ? "+ Add New Vendor" : "+ Add New Fabric";
    button.addEventListener("click", () => {
      const label = kind === "vendor" ? "New Vendor Name" : "New Fabric / Material Name";
      const value = window.prompt(label, input.value || "");
      if (value == null) return;
      const clean = value.trim();
      if (!clean) return;
      dispatchInput(input, clean);
      input.focus();
    });
    input.insertAdjacentElement("afterend", button);
  }

  function wantedDefaultRollCount() {
    const division = document.getElementById("divisionCount");
    return Math.max(1, Number(division?.value || 1));
  }

  function syncOneMissingDefaultRoll() {
    rollSyncScheduled = false;
    const host = document.getElementById("materialList");
    if (!host) return;
    const wanted = wantedDefaultRollCount();

    for (const set of host.querySelectorAll(".roll-set")) {
      const current = set.querySelectorAll("[data-roll]").length;
      if (current < wanted) {
        const add = set.querySelector(".add-roll");
        if (add) {
          add.click();
          scheduleRollSync();
        }
        return;
      }
    }
  }

  function scheduleRollSync() {
    if (rollSyncScheduled) return;
    rollSyncScheduled = true;
    requestAnimationFrame(syncOneMissingDefaultRoll);
  }

  function enhanceMaterialRows() {
    const host = document.getElementById("materialList");
    if (!host) return;

    ensureDataList(VENDOR_LIST_ID, options.vendors);
    ensureDataList(FABRIC_LIST_ID, options.fabrics);

    host.querySelectorAll(".material-row").forEach(row => {
      const vendor = row.querySelector(".mat-vendor");
      const fabric = row.querySelector(".mat-fabric");
      if (vendor) {
        vendor.setAttribute("list", VENDOR_LIST_ID);
        vendor.setAttribute("autocomplete", "off");
        addNewButton(vendor, "vendor");
      }
      if (fabric) {
        fabric.setAttribute("list", FABRIC_LIST_ID);
        fabric.setAttribute("autocomplete", "off");
        addNewButton(fabric, "fabric");
      }
    });

    scheduleRollSync();
  }

  async function loadOptionsOnce() {
    if (loadStarted) return;
    const c = client();
    if (!c?.from) {
      setTimeout(loadOptionsOnce, 300);
      return;
    }
    loadStarted = true;
    const { data, error } = await c.from(VIEW).select("option_type,option_value,last_used_at");
    if (error) {
      console.warn("CB regular purchase mapping unavailable", error);
      return;
    }
    const rows = data || [];
    options.vendors = uniq(rows, "VENDOR");
    options.fabrics = uniq(rows, "FABRIC");
    enhanceMaterialRows();
  }

  function bindDivisionRollSync() {
    const division = document.getElementById("divisionCount");
    if (!division || division.dataset.rollSyncV9133 === "1") return;
    division.dataset.rollSyncV9133 = "1";
    division.addEventListener("input", scheduleRollSync);
    division.addEventListener("change", scheduleRollSync);
  }

  function boot() {
    bindDivisionRollSync();
    enhanceMaterialRows();

    const host = document.getElementById("materialList");
    if (host && !observer) {
      observer = new MutationObserver(mutations => {
        const relevant = mutations.some(m => [...m.addedNodes].some(n => n.nodeType === 1 && (n.matches?.(".material-row,.roll-set,[data-roll]") || n.querySelector?.(".material-row,.roll-set,[data-roll]"))));
        if (!relevant) return;
        bindDivisionRollSync();
        enhanceMaterialRows();
      });
      observer.observe(host, { childList: true, subtree: true });
    }

    loadOptionsOnce();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
