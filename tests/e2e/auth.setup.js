const path = require("path");
const { test: setup, expect } = require("@playwright/test");
const { roles, credentials } = require("./roles");

for (const role of roles) {
  setup(`authenticate ${role.slug}`, async ({ page }) => {
    const { email, password } = credentials(role);
    await page.goto("/real-login.html");
    await page.locator("#email").fill(email);
    await page.locator("#password").fill(password);
    await page.locator("#loginBtn").click();
    await expect(page).not.toHaveURL(/real-login\.html/, { timeout: 30_000 });

    const identity = await page.evaluate(async () => {
      const client = window.supabaseClient;
      const session = await client.auth.getSession();
      if (session.error || !session.data?.session) {
        throw new Error(session.error?.message || "Session missing after login");
      }
      const profile = await client
        .from("rr_user_profiles")
        .select("id,full_name,role_code,is_active,access_status")
        .eq("auth_user_id", session.data.session.user.id)
        .single();
      if (profile.error) throw new Error(profile.error.message);
      return profile.data;
    });

    expect(identity.is_active).toBe(true);
    expect(String(identity.access_status || "ACTIVE").toUpperCase()).toBe("ACTIVE");
    expect(role.allowedRoles).toContain(String(identity.role_code || "").toLowerCase());
    await page.context().storageState({
      path: path.join("playwright", ".auth", `${role.slug}.json`)
    });
  });
}

