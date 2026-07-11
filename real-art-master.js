(() => {
  const form = document.getElementById("artForm");
  const message = document.getElementById("artMessage");
  const artList = document.getElementById("artList");
  const fabricSelect = document.getElementById("fabricId");
  const reloadButton = document.getElementById("reloadArts");

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
    const { data, error } =
      await supabaseClient.auth.getSession();

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
      .select("role_code, is_active")
      .eq("auth_user_id", user.id)
      .single();

    if (
      profileError ||
      !profile?.is_active ||
      !["owner", "admin"].includes(profile.role_code)
    ) {
      await supabaseClient.auth.signOut();

      window.location.replace(
        "real-login.html"
      );

      throw new Error(
        "Owner/Admin access required."
      );
    }
  }

  async function loadFabrics() {
    const { data, error } =
      await supabaseClient
        .from("rr_fabric_master")
        .select("id, fabric_name, gsm")
        .eq("is_active", true)
        .order("fabric_name");

    if (error) {
      throw error;
    }

    fabricSelect.innerHTML = `
      <option value="">
        Select fabric
      </option>
    `;

    (data || []).forEach((fabric) => {
      const option =
        document.createElement("option");

      option.value = fabric.id;

      option.textContent =
        fabric.fabric_name +
        (
          fabric.gsm
            ? ` · ${fabric.gsm} GSM`
            : ""
        );

      fabricSelect.appendChild(option);
    });
  }

  async function loadArts() {
    if (reloadButton) {
      reloadButton.disabled = true;
      reloadButton.textContent = "Loading...";
    }

    const { data, error } =
      await supabaseClient
        .from("rr_art_master")
        .select(`
          id,
          art_no,
          item_name,
          product_name,
          category,
          standard_sizes,
          default_box_qty,
          dealer_rate,
          mrp,
          is_active,
          created_at
        `)
        .order("created_at", {
          ascending: false
        })
        .limit(100);

    if (reloadButton) {
      reloadButton.disabled = false;
      reloadButton.textContent = "Refresh";
    }

    if (error) {
      throw error;
    }

    if (!data || data.length === 0) {
      artList.innerHTML = `
        <p class="rr-muted">
          No art created yet.
        </p>
      `;

      return;
    }

    artList.innerHTML = data
      .map((art) => {
        const sizes =
          Array.isArray(art.standard_sizes)
            ? art.standard_sizes.join(" / ")
            : "";

        return `
          <article class="rr-list-row">

            <div>

              <strong>
                Art ${safeText(art.art_no)}
              </strong>

              <span>
                ${safeText(
                  art.item_name ||
                  art.product_name ||
                  ""
                )}
              </span>

              <small>
                ${safeText(sizes)}
                ·
                ${safeText(
                  art.default_box_qty
                )} PCS
              </small>

            </div>

            <div class="rr-list-meta">

              <span>
                Dealer ₹${safeText(
                  art.dealer_rate
                )}
              </span>

              <b>
                MRP ₹${safeText(art.mrp)}
              </b>

            </div>

          </article>
        `;
      })
      .join("");
  }

  form.addEventListener(
    "submit",
    async (event) => {
      event.preventDefault();

      setMessage("");

      const submitButton =
        form.querySelector(
          'button[type="submit"]'
        );

      submitButton.disabled = true;
      submitButton.textContent = "Saving...";

      const sizes = document
        .getElementById("sizes")
        .value
        .split(",")
        .map((size) => size.trim())
        .filter(Boolean);

      const payload = {
        art_no: document
          .getElementById("artNo")
          .value
          .trim(),

        item_name: document
          .getElementById("itemName")
          .value
          .trim(),

        product_name: document
          .getElementById("productName")
          .value
          .trim(),

        category: document
          .getElementById("category")
          .value
          .trim(),

        fabric_id:
          fabricSelect.value || null,

        standard_sizes: sizes,

        default_box_qty: Number(
          document
            .getElementById("boxQty")
            .value
        ),

        dealer_rate: Number(
          document
            .getElementById("dealerRate")
            .value || 0
        ),

        mrp: Number(
          document
            .getElementById("mrp")
            .value || 0
        ),

        description: document
          .getElementById("description")
          .value
          .trim()
      };

      try {
        const { error } =
          await supabaseClient
            .from("rr_art_master")
            .insert(payload);

        if (error) {
          throw error;
        }

        setMessage(
          "Art saved successfully.",
          "success"
        );

        form.reset();

        document
          .getElementById("boxQty")
          .value = "18";

        await loadArts();

      } catch (error) {
        console.error(error);

        setMessage(
          error.message ||
          "Art could not be saved.",
          "error"
        );

      } finally {
        submitButton.disabled = false;
        submitButton.textContent = "Save Art";
      }
    }
  );

  if (reloadButton) {
    reloadButton.addEventListener(
      "click",
      async () => {
        try {
          await loadArts();
        } catch (error) {
          setMessage(
            error.message ||
            "Arts could not load.",
            "error"
          );
        }
      }
    );
  }

  (async () => {
    try {
      await requireOwner();

      await Promise.all([
        loadFabrics(),
        loadArts()
      ]);

    } catch (error) {
      console.error(error);

      setMessage(
        error.message ||
        "Could not open Art Master.",
        "error"
      );
    }
  })();
})();
