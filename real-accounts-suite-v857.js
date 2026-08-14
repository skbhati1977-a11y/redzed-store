(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const tabs = [
    { id: "pl", title: "P&L", table: "rr_profit_loss_v857", fallback: "rr_costing_effective_result_v850" },
    { id: "balance", title: "Balance Sheet", table: "rr_balance_sheet_v857", fallback: "rr_accounts_voucher_v847" },
    { id: "receivable", title: "Receivable", table: "rr_receivable_v857", fallback: "rr_fg_final_cpi_v787" },
    { id: "payment", title: "Payment", table: "rr_payment_ledger_v857", fallback: "rr_accounts_voucher_v847" },
    { id: "purchase", title: "Purchase", table: "rr_purchase_ledger_v857", fallback: "rr_cb_purchase_entries" },
    { id: "sales", title: "Sales", table: "rr_sales_ledger_v857", fallback: "rr_universal_sale_lot_v849" }
  ];
  let active = tabs[0];
  let rows = [];
  const safe = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const money = (v) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(Number(v || 0));
  const msg = (t, type = "") => { $("pageMessage").textContent = t || ""; $("pageMessage").className = `rr-message ${type}`.trim(); };

  async function requireAccess() {
    const { data, error } = await supabaseClient.auth.getSession();
    if (error || !data.session) {
      window.location.replace("real-login.html");
      throw new Error("Login required.");
    }
    const { data: profile, error: profileError } = await supabaseClient.from("rr_user_profiles").select("role_code,is_active").eq("auth_user_id", data.session.user.id).single();
    if (profileError || !profile?.is_active || !["owner", "admin", "accounts", "manager"].includes(profile.role_code)) throw new Error("Accounts access required.");
    $("ownerName").textContent = ["owner", "admin"].includes(profile.role_code) ? "SUPER ADMIN" : String(profile.role_code || "ACCOUNTS").toUpperCase();
  }

  function renderTabs() {
    $("tabs").innerHTML = tabs.map((tab) => `<button class="${tab.id === active.id ? "active" : ""}" data-tab="${safe(tab.id)}" type="button">${safe(tab.title)}</button>`).join("");
    document.querySelectorAll("[data-tab]").forEach((button) => button.onclick = () => { active = tabs.find((tab) => tab.id === button.dataset.tab) || active; renderTabs(); loadRows(); });
  }

  function amountOf(row) {
    for (const key of ["amount", "total_amount", "grand_total", "balance", "net_amount", "payable", "receivable", "cost_amount"]) {
      if (row[key] !== undefined && row[key] !== null && !Number.isNaN(Number(row[key]))) return Number(row[key]);
    }
    return 0;
  }

  function renderSummary(filtered) {
    const total = filtered.reduce((sum, row) => sum + amountOf(row), 0);
    const positive = filtered.filter((row) => amountOf(row) > 0).length;
    $("summary").innerHTML = [
      ["Rows", filtered.length],
      ["Amount", money(total)],
      ["Positive Rows", positive],
      ["Source", active.source || active.table]
    ].map(([k, v]) => `<div><small>${safe(k)}</small><b>${safe(v)}</b></div>`).join("");
  }

  function renderTable() {
    const q = $("searchBox").value.trim().toLowerCase();
    const filtered = rows.filter((row) => !q || JSON.stringify(row).toLowerCase().includes(q));
    $("rowCount").textContent = `${filtered.length} rows`;
    renderSummary(filtered);
    if (!filtered.length) {
      $("tableHost").innerHTML = '<p class="rr-muted">No rows found.</p>';
      return;
    }
    const keys = [...new Set(filtered.slice(0, 10).flatMap((row) => Object.keys(row || {})))].slice(0, 10);
    $("tableHost").innerHTML = `<div class="rf-table-wrap"><table class="rf-table"><thead><tr>${keys.map((key) => `<th>${safe(key.replaceAll("_", " ").toUpperCase())}</th>`).join("")}</tr></thead><tbody>${filtered.map((row) => `<tr>${keys.map((key) => `<td>${safe(row[key] ?? "-")}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
  }

  async function selectFrom(table) {
    return await supabaseClient.from(table).select("*").limit(100);
  }

  async function loadRows() {
    $("activeTitle").textContent = active.title;
    $("refreshBtn").disabled = true;
    msg("");
    try {
      let result = await selectFrom(active.table);
      active.source = active.table;
      if (result.error && active.fallback) {
        result = await selectFrom(active.fallback);
        active.source = active.fallback;
      }
      if (result.error) throw result.error;
      rows = result.data || [];
      renderTable();
      msg(`${active.title} loaded.`, "success");
    } catch (error) {
      console.warn(error);
      rows = [];
      renderTable();
      msg(error.message || "Accounts source unavailable.", "error");
    } finally {
      $("refreshBtn").disabled = false;
    }
  }

  $("refreshBtn").addEventListener("click", loadRows);
  $("searchBox").addEventListener("input", renderTable);
  $("logoutBtn").addEventListener("click", async () => {
    await supabaseClient.auth.signOut();
    window.location.replace("real-login.html");
  });

  document.addEventListener("DOMContentLoaded", async () => {
    try {
      await requireAccess();
      renderTabs();
      await loadRows();
    } catch (error) {
      console.error(error);
      msg(error.message || "Accounts Suite failed.", "error");
    }
  });
})();
