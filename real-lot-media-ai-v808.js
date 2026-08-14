(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const TABLE = "rr_lot_media_v808";

  function safe(value) {
    return String(value ?? "").replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;"
    }[char]));
  }

  function msg(text, type = "") {
    $("pageMessage").textContent = text || "";
    $("pageMessage").className = `rr-message ${type}`.trim();
  }

  function first(row, keys, fallback = "") {
    for (const key of keys) {
      const value = row?.[key];
      if (value !== null && value !== undefined && String(value).trim() !== "") return value;
    }
    return fallback;
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
    if (profileError || !profile?.is_active || !["owner", "admin", "manager", "packing", "sales"].includes(profile.role_code)) {
      await supabaseClient.auth.signOut();
      window.location.replace("real-login.html");
      throw new Error("Authorized access required.");
    }
    $("ownerName").textContent = ["owner", "admin"].includes(profile.role_code) ? "SUPER ADMIN" : String(profile.role_code).toUpperCase();
  }

  function imageSrc(row) {
    return first(row, ["image_url", "media_url", "original_url", "variant_url", "public_url"]);
  }

  function render(rows) {
    $("rowCount").textContent = `${rows.length} rows`;
    $("mediaGrid").innerHTML = rows.length ? rows.map((row) => {
      const src = imageSrc(row);
      return `
        <article class="rf-media-card">
          ${src ? `<img src="${safe(src)}" alt="Lot media">` : '<div class="rr-muted">No image URL</div>'}
          <div class="rf-media-head"><strong>${safe(first(row, ["lot_no", "lot_number"], "Lot"))}</strong><span>${safe(first(row, ["publish_status", "approval_status", "status"], "PENDING_APPROVAL"))}</span></div>
          <div class="rf-media-meta">
            <span>Type: ${safe(first(row, ["media_type", "image_type", "type"], "-"))}</span>
            <span>Group: ${safe(first(row, ["generation_group", "generation_group_id", "ai_group_id"], "-"))}</span>
            <span>Created: ${safe(first(row, ["created_at", "uploaded_at"], "-"))}</span>
          </div>
          <div class="rf-media-actions">
            ${row.id ? `<button class="rr-btn rr-btn-secondary" data-approve="${safe(row.id)}" type="button">Approve</button><button class="rr-btn rr-btn-secondary" data-publish="${safe(row.id)}" type="button">Publish</button>` : ""}
          </div>
        </article>
      `;
    }).join("") : '<p class="rr-muted">No media rows found.</p>';

    document.querySelectorAll("[data-approve]").forEach((button) => {
      button.addEventListener("click", () => updateStatus(button.dataset.approve, "APPROVED"));
    });
    document.querySelectorAll("[data-publish]").forEach((button) => {
      button.addEventListener("click", () => updateStatus(button.dataset.publish, "PUBLISHED"));
    });
  }

  async function loadRows() {
    $("refreshBtn").disabled = true;
    $("refreshBtn").textContent = "Loading...";
    msg("");
    try {
      const { data, error } = await supabaseClient
        .from(TABLE)
        .select("*")
        .order("created_at", { ascending: false })
        .limit(80);
      if (error) throw error;
      render(data || []);
      msg("Lot media loaded.", "success");
    } catch (error) {
      console.error(error);
      render([]);
      msg(error.message || "Lot media load failed.", "error");
    } finally {
      $("refreshBtn").disabled = false;
      $("refreshBtn").textContent = "Refresh";
    }
  }

  async function saveMedia() {
    const lotNo = $("lotNo").value.trim();
    const imageUrl = $("imageUrl").value.trim();
    if (!lotNo || !imageUrl) {
      msg("Lot No. aur Image URL required.", "error");
      return;
    }

    $("saveMediaBtn").disabled = true;
    try {
      const payload = {
        lot_no: lotNo,
        media_type: $("mediaType").value,
        image_url: imageUrl,
        approval_status: "PENDING_APPROVAL",
        publish_status: "DRAFT",
        data_mode: "TEST"
      };
      const { error } = await supabaseClient.from(TABLE).insert(payload);
      if (error) throw error;
      $("imageUrl").value = "";
      msg("Final photo saved in TEST media queue.", "success");
      await loadRows();
    } catch (error) {
      console.error(error);
      msg(error.message || "Media save failed.", "error");
    } finally {
      $("saveMediaBtn").disabled = false;
    }
  }

  async function updateStatus(id, status) {
    try {
      const patch = status === "PUBLISHED"
        ? { publish_status: "PUBLISHED" }
        : { approval_status: "APPROVED" };
      const { error } = await supabaseClient.from(TABLE).update(patch).eq("id", id);
      if (error) throw error;
      msg(`${status} saved.`, "success");
      await loadRows();
    } catch (error) {
      console.error(error);
      msg(error.message || "Status update failed.", "error");
    }
  }

  $("refreshBtn").addEventListener("click", loadRows);
  $("saveMediaBtn").addEventListener("click", saveMedia);
  $("logoutBtn").addEventListener("click", async () => {
    await supabaseClient.auth.signOut();
    window.location.replace("real-login.html");
  });

  document.addEventListener("DOMContentLoaded", async () => {
    try {
      await requireOwner();
      await loadRows();
    } catch (error) {
      console.error(error);
      msg(error.message || "Page load failed.", "error");
    }
  });
})();
