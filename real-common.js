// REAL FACTORY · Common Frontend V805
(() => {
  const cfg = window.RR_CONFIG || {};

  function assertConfig() {
    if (!cfg.supabaseUrl || !cfg.supabaseAnonKey ||
        String(cfg.supabaseUrl).includes("PASTE_") ||
        String(cfg.supabaseAnonKey).includes("PASTE_")) {
      throw new Error("config.js me Supabase URL aur anon key set kijiye.");
    }
  }

  function getClient() {
    if (window.RR?.supabase) return window.RR.supabase;
    assertConfig();
    if (!window.supabase?.createClient) {
      throw new Error("Supabase JS library load nahi hui.");
    }
    const client = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
    window.RR = window.RR || {};
    window.RR.supabase = client;
    return client;
  }

  async function getSessionUser() {
    const client = getClient();
    const { data, error } = await client.auth.getUser();
    if (error) throw error;
    return data?.user || null;
  }

  async function requireLogin() {
    const user = await getSessionUser();
    if (!user) {
      throw new Error("Login required. Pehle REAL FACTORY me sign in kijiye.");
    }
    return user;
  }

  function friendlyRole(role) {
    const r = String(role || "").trim().toLowerCase();
    if (r === "owner" || r === "super_admin" || r === "super admin") return "Super Admin";
    if (r === "admin") return "Admin";
    if (r === "department_head") return "Department Head";
    if (r === "line_man" || r === "line_manager") return "Line Man";
    if (r === "cutting_master") return "Cutting Master";
    return r ? r.replaceAll("_", " ").replace(/\b\w/g, c => c.toUpperCase()) : "User";
  }

  function money(n) {
    return "₹" + Number(n || 0).toLocaleString("en-IN", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  function escapeHtml(s) {
    return String(s ?? "").replace(/[&<>"']/g, m => ({
      "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
    }[m]));
  }

  // Global Enter → Next eligible field rule for genuine entry forms only.
  function enableEnterNext(container) {
    if (!container) return;
    container.addEventListener("keydown", (e) => {
      if (e.key !== "Enter" || e.shiftKey || e.ctrlKey || e.altKey || e.metaKey) return;
      const t = e.target;
      if (!t || !["INPUT","SELECT"].includes(t.tagName)) return;
      if (t.type === "search" || t.type === "file" || t.type === "hidden") return;
      if (t.closest("[data-no-enter-next='true']")) return;

      const eligible = [...container.querySelectorAll(
        "input:not([type=hidden]):not([type=file]):not([type=search]), select, button[data-enter-submit='true']"
      )].filter(x =>
        !x.disabled &&
        x.tabIndex !== -1 &&
        x.offsetParent !== null &&
        !x.readOnly
      );

      const i = eligible.indexOf(t);
      if (i < 0) return;
      e.preventDefault();
      const next = eligible[i + 1];
      if (next) {
        next.focus();
        if (next.tagName === "INPUT") next.select?.();
      } else {
        const submit = container.querySelector("button[data-enter-submit='true']");
        submit?.click();
      }
    });
  }

  function enableZeroClean(container=document) {
    container.querySelectorAll('input[type="number"]').forEach(input => {
      input.addEventListener("focus", () => {
        if (Number(input.value || 0) === 0) input.value = "";
      });
      input.addEventListener("blur", () => {
        if (String(input.value).trim() === "") input.value = "0";
      });
    });
  }

  window.RR = window.RR || {};
  Object.assign(window.RR, {
    getClient,
    getSessionUser,
    requireLogin,
    friendlyRole,
    money,
    escapeHtml,
    enableEnterNext,
    enableZeroClean
  });
})();
