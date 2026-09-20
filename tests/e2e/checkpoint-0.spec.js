const { test, expect } = require("@playwright/test");
const { bootstrap, ensureSession } = require("./session");

async function selectActAs(page, name) {
  await ensureSession(page);
  await expect(page.locator("#rrGlobalViewAs172")).toBeAttached();
  await page.locator("#rrGlobalViewAs172 .rr-view-handle").click();
  await page.locator("#rrGlobalViewAs172 [data-search]").fill(name);
  const button = page.locator("#rrGlobalViewAs172 [data-worker]").filter({ hasText: name }).first();
  await expect(button).toBeVisible();
  await button.click();
  await page.waitForLoadState("domcontentloaded");
  return page.evaluate(async () => {
    const identity = await window.supabaseClient.rpc("rr_upm_effective_identity_v200");
    const canAssign = await window.supabaseClient.rpc("rr_upm_assignment_allowed_v200");
    if (identity.error) throw new Error(identity.error.message);
    if (canAssign.error) throw new Error(canAssign.error.message);
    return { identity: identity.data, canAssign: canAssign.data };
  });
}

async function restoreActual(page) {
  await page.locator("#rrGlobalViewAs172 .rr-view-handle").click();
  await page.locator("#rrGlobalViewAs172 [data-actual]").click();
  await page.waitForLoadState("domcontentloaded");
}

test("reuses the stored Super Admin session", async ({ page }) => {
  await ensureSession(page);
  await expect(page).not.toHaveURL(/real-login\.html/);
  await expect(page.locator("#rrGlobalViewAs172")).toBeAttached();
});

test("expired or cleared session automatically re-bootstraps", async ({ page }) => {
  await page.goto("/real-login.html");
  await page.evaluate(async () => window.supabaseClient.auth.signOut({ scope: "local" }));
  await bootstrap(page);
  const active = await page.evaluate(async () => Boolean((await window.supabaseClient.auth.getSession()).data?.session));
  expect(active).toBe(true);
});

for (const actor of [
  { name: "ali", roles: ["LINE_MANAGER", "LINE_MAN"], canAssign: true },
  { name: "imamul", roles: ["WORKER"], canAssign: false },
  { name: "nasim", roles: ["MANAGER"], canAssign: true },
  { name: "shailender", roles: ["ADMIN"], canAssign: true }
]) {
  test(`Act As ${actor.name} propagates backend identity and authority`, async ({ page }) => {
    const result = await selectActAs(page, actor.name);
    expect(result.identity.on_behalf).toBe(true);
    expect(String(result.identity.display_name || result.identity.name).toLowerCase()).toContain(actor.name);
    expect(actor.roles).toContain(String(result.identity.role_code || result.identity.resolved_role).toUpperCase());
    expect(result.canAssign).toBe(actor.canAssign);
    await restoreActual(page);
  });
}
