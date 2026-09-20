const path = require("path");
const { test, expect } = require("@playwright/test");
const { roles } = require("./roles");

for (const role of roles) {
  test.describe(role.slug, () => {
    test.use({ storageState: path.join("playwright", ".auth", `${role.slug}.json`) });

    test("reuses an authenticated, role-correct session", async ({ page }) => {
      await page.goto("/real-dashboard-v9182.html?mode=TEST");
      await expect(page).not.toHaveURL(/real-login\.html/);
      const result = await page.evaluate(async () => {
        const client = window.supabaseClient;
        let session = await client.auth.getSession();
        if (!session.data?.session) session = await client.auth.refreshSession();
        const userId = session.data?.session?.user?.id;
        if (!userId) return { authenticated: false };
        const profile = await client
          .from("rr_user_profiles")
          .select("role_code,is_active,access_status")
          .eq("auth_user_id", userId)
          .single();
        if (profile.error) throw new Error(profile.error.message);
        return { authenticated: true, ...profile.data };
      });
      expect(result.authenticated).toBe(true);
      expect(result.is_active).toBe(true);
      expect(role.allowedRoles).toContain(String(result.role_code || "").toLowerCase());
    });
  });
}

