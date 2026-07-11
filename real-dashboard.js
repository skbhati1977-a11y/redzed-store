(() => {
  const ownerName = document.getElementById("ownerName");
  const welcomeText = document.getElementById("welcomeText");
  const logoutBtn = document.getElementById("logoutBtn");
  const refreshBtn = document.getElementById("refreshBtn");
  const message = document.getElementById("dashboardMessage");
  const lotList = document.getElementById("lotList");

  function setMessage(text, type = "") {
    message.textContent = text || "";
    message.className = `rr-message ${type}`.trim();
  }

  function safeText(value) {
    return String(value ?? "").replace(/[&<>"']/g, (char) => {
      const map = {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;"
      };

      return map[char];
    });
  }

  async function requireOwner() {
    const { data, error } = await supabaseClient.auth.getSession();

    if (error || !data.session) {
      window.location.replace("real-login.html");
      throw new Error("Login required.");
    }

    const user = data.session.user;

    const {
      data: profile,
      error: profileError
    } = await supabaseClient
      .from("rr_user_profiles")
      .select("full_name, role_code, is_active")
      .eq("auth_user_id", user.id)
      .single();

    if (
      profileError ||
      !profile?.is_active ||
      !["owner", "admin"].includes(profile.role_code)
    ) {
      await supabaseClient.auth.signOut();
      window.location.replace("real-login.html");
      throw new Error("Owner/Admin access required.");
    }

    ownerName.textContent = profile.full_name;
    welcomeText.textContent = `Welcome, ${profile.full_name}`;
  }

  async function countRows(table, filterCallback) {
    let query = supabaseClient
      .from(table)
      .select("*", {
        count: "exact",
        head: true
      });

    if (typeof filterCallback === "function") {
      query = filterCallback(query);
    }

    const { count, error } = await query;

    if (error) {
      throw error;
    }

    return count || 0;
  }

  async function loadStats() {
    const artPromise = countRows(
      "rr_art_master",
      (query) => query.eq("is_active", true)
    );

    const lotPromise = countRows(
      "rr_lots",
      (query) =>
        query.not(
          "status",
          "in",
          '("closed","cancelled")'
        )
    );

    const remakePromise = countRows(
      "rr_remakes",
      (query) =>
        query.not(
          "status",
          "in",
          '("merged","closed","cancelled")'
        )
    );

    const inventoryPromise = supabaseClient
      .from("rr_lot_inventory_summary")
      .select("available_pcs");

    const [
      arts,
      lots,
      remakes,
      inventory
    ] = await Promise.all([
      artPromise,
      lotPromise,
      remakePromise,
      inventoryPromise
    ]);

    if (inventory.error) {
      throw inventory.error;
    }

    const stock = (inventory.data || []).reduce(
      (sum, row) => {
        return sum + Number(row.available_pcs || 0);
      },
      0
    );

    document.getElementById("artCount").textContent = arts;
    document.getElementById("lotCount").textContent = lots;
    document.getElementById("remakeCount").textContent = remakes;
    document.getElementById("stockCount").textContent = stock;
  }

  async function loadLots() {
    const { data, error } = await supabaseClient
      .from("rr_live_lot_status")
      .select("*")
      .order("updated_at", {
        ascending: false
      })
      .limit(12);

    if (error) {
      throw error;
    }

    if (!data || data.length === 0) {
      lotList.innerHTML = `
        <p class="rr-muted">
          No production lots yet.
        </p>
      `;

      return;
    }

    lotList.innerHTML = data
      .map((lot) => {
        const itemName =
          lot.item_name ||
          lot.product_name ||
          "";

        const department =
          lot.current_department ||
          lot.current_department_code ||
          "";

        return `
          <article class="rr-list-row">

            <div>
              <strong>
                ${safeText(lot.lot_no)}
              </strong>

              <span>
                Art ${safeText(lot.art_no)}
                ·
                ${safeText(itemName)}
              </span>
            </div>

            <div class="rr-list-meta">
              <span>
                ${safeText(department)}
              </span>

              <b>
                ${safeText(lot.status)}
              </b>
            </div>

          </article>
        `;
      })
      .join("");
  }

  async function refreshDashboard() {
    setMessage("");

    if (refreshBtn) {
      refreshBtn.disabled = true;
      refreshBtn.textContent = "Loading...";
    }

    try {
      await Promise.all([
        loadStats(),
        loadLots()
      ]);
    } catch (error) {
      console.error(error);

      setMessage(
        error.message ||
        "Dashboard data could not load.",
        "error"
      );
    } finally {
      if (refreshBtn) {
        refreshBtn.disabled = false;
        refreshBtn.textContent = "Refresh";
      }
    }
  }

  if (logoutBtn) {
    logoutBtn.addEventListener(
      "click",
      async () => {
        await supabaseClient.auth.signOut();

        window.location.replace(
          "real-login.html"
        );
      }
    );
  }

  if (refreshBtn) {
    refreshBtn.addEventListener(
      "click",
      refreshDashboard
    );
  }

  (async () => {
    try {
      await requireOwner();
      await refreshDashboard();
    } catch (error) {
      console.error(error);

      setMessage(
        error.message ||
        "Access failed.",
        "error"
      );
    }
  })();
})();
