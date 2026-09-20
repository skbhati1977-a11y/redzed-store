const { test: setup, expect } = require("@playwright/test");
const { authFile, bootstrap } = require("./session");

setup("authenticate TEST Super Admin", async ({ page }) => {
  await bootstrap(page);
  await page.goto("/real-dashboard-v9182.html?mode=TEST");
  const identity = await page.evaluate(async () => {
    const result = await window.supabaseClient.rpc("rr_upm_effective_identity_v200");
    if (result.error) throw new Error(result.error.message);
    return result.data;
  });
  expect(["OWNER", "SUPER_ADMIN"]).toContain(String(identity.role_code || identity.resolved_role).toUpperCase());
  expect(identity.on_behalf).toBe(false);
  await page.context().storageState({ path: authFile });
});
