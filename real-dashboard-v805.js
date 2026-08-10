(() => {
  const $ = id => document.getElementById(id);

  async function boot() {
    try {
      const client = RR.getClient();
      const user = await RR.requireLogin();

      const { data: profile, error } = await client
        .from("rr_user_profiles")
        .select("full_name,role_code,access_status,is_active")
        .eq("auth_user_id", user.id)
        .maybeSingle();

      if (error) throw error;
      if (!profile || !profile.is_active || String(profile.access_status || "ACTIVE").toUpperCase() !== "ACTIVE") {
        throw new Error("Active user profile required.");
      }

      $("userBadge").textContent =
        `${profile.full_name || user.email || "User"} · ${RR.friendlyRole(profile.role_code)}`;
    } catch (e) {
      $("userBadge").textContent = e.message || "Login check failed";
    }
  }

  $("logoutBtn").addEventListener("click", async () => {
    try {
      await RR.getClient().auth.signOut();
      location.reload();
    } catch (e) {
      alert(e.message);
    }
  });

  boot();
})();
