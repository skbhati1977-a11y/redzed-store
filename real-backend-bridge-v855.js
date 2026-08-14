(() => {
  "use strict";

  const cfg = window.REAL_FACTORY_BRIDGE || {};
  const state = { rows: {}, profile: null };
  const $ = (id) => document.getElementById(id);

  function safe(value) {
    return String(value ?? "").replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;"
    }[char]));
  }

  function label(value) {
    return String(value || "")
      .replace(/^rr_/, "")
      .replace(/_v\d+.*$/i, "")
      .replaceAll("_", " ")
      .toUpperCase();
  }

  function setMessage(text, type = "") {
    const node = $("bridgeMessage");
    if (!node) return;
    node.textContent = text || "";
    node.className = `rr-message ${type}`.trim();
  }

  function displayValue(value) {
    if (Array.isArray(value)) return `${value.length} item(s)`;
    if (value && typeof value === "object") return JSON.stringify(value);
    if (value === null || value === undefined || value === "") return "-";
    return String(value);
  }

  function primaryText(row) {
    return row.lot_no || row.lot_number || row.art_no || row.worker_name || row.voucher_no ||
      row.buyer_name || row.item_name || row.name || row.id || "Record";
  }

  function secondaryText(row) {
    return row.status || row.activation_status || row.publish_status || row.data_mode ||
      row.department_code || row.stock_status || row.created_at || "";
  }

  function columnKeys(rows) {
    const keys = [];
    rows.slice(0, 10).forEach((row) => {
      Object.keys(row || {}).forEach((key) => {
        if (!keys.includes(key)) keys.push(key);
      });
    });
    return keys.slice(0, 10);
  }

  function renderTable(target, rows) {
    const host = $(target);
    if (!host) return;

    if (!rows.length) {
      host.innerHTML = '<p class="rr-muted">No rows found.</p>';
      return;
    }

    const keys = columnKeys(rows);
    host.innerHTML = `
      <div class="rf-bridge-table-wrap">
        <table class="rf-bridge-table">
          <thead><tr>${keys.map((key) => `<th>${safe(label(key))}</th>`).join("")}</tr></thead>
          <tbody>
            ${rows.map((row) => `
              <tr>${keys.map((key) => `<td>${safe(displayValue(row[key]))}</td>`).join("")}</tr>
            `).join("")}
          </tbody>
        </table>
      </div>
    `;
  }

  function renderCards(target, rows) {
    const host = $(target);
    if (!host) return;

    if (!rows.length) {
      host.innerHTML = '<p class="rr-muted">No rows found.</p>';
      return;
    }

    host.innerHTML = rows.map((row) => {
      const keys = columnKeys([row]).filter((key) => !["id", "created_at", "updated_at"].includes(key)).slice(0, 6);
      return `
        <article class="rf-bridge-card">
          <div class="rf-bridge-card-head">
            <strong>${safe(primaryText(row))}</strong>
            <span>${safe(secondaryText(row))}</span>
          </div>
          <div class="rf-bridge-fields">
            ${keys.map((key) => `
              <div><small>${safe(label(key))}</small><b>${safe(displayValue(row[key]))}</b></div>
            `).join("")}
          </div>
        </article>
      `;
    }).join("");
  }

  async function requireOwner() {
    const { data, error } = await supabaseClient.auth.getSession();
    if (error || !data.session) {
      window.location.replace("real-login.html");
      throw new Error("Login required.");
    }

    const { data: profile, error: profileError } = await supabaseClient
      .from("rr_user_profiles")
      .select("role_code, is_active")
      .eq("auth_user_id", data.session.user.id)
      .single();

    if (profileError || !profile?.is_active || !["owner", "admin", "manager", "accounts", "sales", "store", "packing"].includes(profile.role_code)) {
      await supabaseClient.auth.signOut();
      window.location.replace("real-login.html");
      throw new Error("Authorized access required.");
    }

    state.profile = profile;
    const owner = $("ownerName");
    if (owner) owner.textContent = ["owner", "admin"].includes(profile.role_code) ? "SUPER ADMIN" : label(profile.role_code);
  }

  async function fetchSource(source) {
    let query = supabaseClient.from(source.table).select(source.select || "*");

    if (source.modeColumn) query = query.eq(source.modeColumn, "TEST");
    if (source.statusColumn && source.statusValue) query = query.eq(source.statusColumn, source.statusValue);
    if (source.orderBy) query = query.order(source.orderBy, { ascending: source.ascending === true });
    query = query.limit(source.limit || 80);

    const { data, error } = await query;
    if (error) throw error;
    const rows = data || [];
    if (!source.onlyExplicitDue) return rows;

    return rows.filter((row) => {
      return Object.entries(row || {}).some(([key, value]) => {
        const name = String(key || "").toLowerCase();
        const text = String(value || "").trim().toUpperCase();
        return text === "DUE" && !name.includes("implicit");
      });
    });
  }

  async function loadAll() {
    setMessage("");
    const refresh = $("refreshBtn");
    if (refresh) {
      refresh.disabled = true;
      refresh.textContent = "Loading...";
    }

    try {
      for (const source of cfg.sources || []) {
        const rows = await fetchSource(source);
        state.rows[source.key] = rows;
        if (source.render === "cards") renderCards(source.target, rows);
        else renderTable(source.target, rows);
      }
      setMessage("Latest backend data loaded.", "success");
    } catch (error) {
      console.error(error);
      setMessage(error.message || "Backend data load failed.", "error");
    } finally {
      if (refresh) {
        refresh.disabled = false;
        refresh.textContent = "Refresh";
      }
    }
  }

  async function runConfiguredAction(button) {
    const action = (cfg.actions || []).find((item) => item.id === button.dataset.action);
    if (!action) return;

    const oldText = button.textContent;
    button.disabled = true;
    button.textContent = "Running...";
    setMessage("");

    try {
      const args = typeof action.args === "function" ? action.args() : (action.args || {});
      const { data, error } = await supabaseClient.rpc(action.rpc, args);
      if (error) throw error;
      setMessage(action.success || `Action completed: ${JSON.stringify(data ?? {})}`, "success");
      await loadAll();
    } catch (error) {
      console.error(error);
      setMessage(error.message || "Action failed.", "error");
    } finally {
      button.disabled = false;
      button.textContent = oldText;
    }
  }

  function bind() {
    const refresh = $("refreshBtn");
    if (refresh) refresh.addEventListener("click", loadAll);

    const logout = $("logoutBtn");
    if (logout) {
      logout.addEventListener("click", async () => {
        await supabaseClient.auth.signOut();
        window.location.replace("real-login.html");
      });
    }

    document.querySelectorAll("[data-action]").forEach((button) => {
      button.addEventListener("click", () => runConfiguredAction(button));
    });
  }

  document.addEventListener("DOMContentLoaded", async () => {
    try {
      bind();
      await requireOwner();
      await loadAll();
    } catch (error) {
      console.error(error);
      setMessage(error.message || "Page load failed.", "error");
    }
  });
})();
