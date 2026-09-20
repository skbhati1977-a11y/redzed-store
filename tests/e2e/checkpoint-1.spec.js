const { test, expect } = require("@playwright/test");
const { ensureSession } = require("./session");

const FIXTURE = "TEST71 E2E Worker Fixture";

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

async function actAs(page, name) {
  await ensureSession(page);
  await page.locator("#rrGlobalViewAs172 .rr-view-handle").click();
  await page.locator("#rrGlobalViewAs172 [data-search]").fill(name);
  const actor = page.locator("#rrGlobalViewAs172 [data-worker]").filter({ hasText: name }).first();
  await expect(actor).toBeVisible();
  const workerId = await actor.getAttribute("data-worker");
  await Promise.all([
    page.waitForNavigation({ waitUntil: "domcontentloaded" }),
    actor.click({ noWaitAfter: true })
  ]);
  await expect.poll(() => page.evaluate((id) =>
    window.RR_ON_BEHALF_ACTIVE && String(window.RR_VIEW_AS_ACTOR_ID) === String(id), workerId
  )).toBe(true);
  const result = await rpc(page, "rr_upm_effective_identity_v200");
  expect(result.error).toBeNull();
  return result.data;
}

async function restoreActual(page) {
  await page.locator("#rrGlobalViewAs172 .rr-view-handle").click();
  await Promise.all([
    page.waitForNavigation({ waitUntil: "domcontentloaded" }),
    page.locator("#rrGlobalViewAs172 [data-actual]").click({ noWaitAfter: true })
  ]);
  await expect.poll(() => page.evaluate(() => !window.RR_ON_BEHALF_ACTIVE)).toBe(true);
}

test.afterEach(async ({ page }) => {
  if (!page.isClosed()) {
    const active = await page.evaluate(() => Boolean(window.RR_ON_BEHALF_ACTIVE)).catch(() => false);
    if (active) await restoreActual(page);
  }
});

test("canonical Act As mappings expose only configured departments", async ({ page }) => {
  const cases = [
    ["imamul", "KR KARIGER", ["STITCHING"], ["STICKER"]],
    ["akhtar", "FLD KARIGER", ["FOLDING", "OVERLOCK"], []],
    ["yashpal", "KAJ/BTN KARIGAR", ["KAJ_BUTTON"], []],
    ["baldev", "KAJ/BTN KARIGAR", ["KAJ_BUTTON"], []],
    ["balli", "ID KARIGER", ["METAL_ID"], []],
    ["javed", "OV KARIGER", ["OVERLOCK"], []],
    ["sanju", "PRINTER", ["PRINTING"], []],
    ["chotu", "PRINT WORKER", ["PRINTING"], []],
    ["sharwan", "PRESSMAN", ["PRESS"], ["PACKING"]],
    ["ali", "LINE MAN", ["FABRICATION"], []],
    ["dhiraj", "LINE MAN", ["FABRICATION"], []],
    ["nasim", "MANAGER", ["FABRICATION"], []],
    ["shailender", "ACCOUNT", ["ADMIN"], []]
  ];
  for (const [name, role, required, forbidden] of cases) {
    const identity = await actAs(page, name);
    expect(String(identity.role_code || identity.resolved_role).toUpperCase()).toBe(role);
    const departments = (identity.departments || identity.department_codes || []).map((x) => String(x).toUpperCase());
    for (const department of required) expect(departments).toContain(department);
    for (const department of forbidden) expect(departments).not.toContain(department);
    const allowed = await rpc(page, "rr_upm_assignment_allowed_v200");
    expect(allowed.error).toBeNull();
    expect(allowed.data).toBe(["LINE MAN", "MANAGER"].includes(role));
    await restoreActual(page);
  }
});

test("worker Act As is rejected by backend staff mutations", async ({ page }) => {
  await actAs(page, "imamul");
  const add = await rpc(page, "rr_owner_add_worker_v8_4", {
    p_worker_name: FIXTURE, p_department_code: "STITCHING", p_role_code: "test worker", p_mobile: null
  });
  expect(add.error?.message).toMatch(/permission denied|Owner \/ Super Admin \/ Admin/i);
  const remove = await rpc(page, "rr_real_chat_membership_admin_v136", {
    p_worker_id: "00000000-0000-0000-0000-000000000071", p_action: "REMOVE", p_scope: "DEPARTMENT",
    p_department_codes: ["STITCHING"], p_reason: "TEST71 unauthorized mutation proof"
  });
  expect(remove.error?.message).toMatch(/effective Owner|permission/i);
});

test("Staff Manage add is real, idempotent, persistent, and removable", async ({ page }) => {
  await ensureSession(page);
  const first = await rpc(page, "rr_owner_add_worker_v8_4", {
    p_worker_name: FIXTURE, p_department_code: "STITCHING", p_role_code: "test worker", p_mobile: null
  });
  expect(first.error).toBeNull();
  const row = Array.isArray(first.data) ? first.data[0] : first.data;
  expect(row.worker_id).toBeTruthy();

  const second = await rpc(page, "rr_owner_add_worker_v8_4", {
    p_worker_name: FIXTURE, p_department_code: "STITCHING", p_role_code: "test worker", p_mobile: null
  });
  expect(second.error).toBeNull();
  expect((Array.isArray(second.data) ? second.data[0] : second.data).worker_id).toBe(row.worker_id);

  await page.reload({ waitUntil: "domcontentloaded" });
  const roster = await rpc(page, "rr_real_chat_membership_roster_v136");
  expect(roster.error).toBeNull();
  expect((roster.data?.workers || []).filter((x) => x.worker_name === FIXTURE)).toHaveLength(1);

  const removed = await rpc(page, "rr_real_chat_membership_admin_v136", {
    p_worker_id: row.worker_id, p_action: "REMOVE", p_scope: "DEPARTMENT",
    p_department_codes: ["STITCHING"], p_reason: "TEST71 reversible fixture cleanup"
  });
  expect(removed.error).toBeNull();

  const restored = await rpc(page, "rr_owner_add_worker_v8_4", {
    p_worker_name: FIXTURE, p_department_code: "STITCHING", p_role_code: "test worker", p_mobile: null
  });
  expect(restored.error).toBeNull();
  expect((Array.isArray(restored.data) ? restored.data[0] : restored.data).worker_id).toBe(row.worker_id);
  const restoredRoster = await rpc(page, "rr_real_chat_membership_roster_v136");
  const restoredWorker = restoredRoster.data.workers.find((x) => x.worker_id === row.worker_id);
  expect(restoredWorker.manual_global_inactive).toBe(false);
  expect(restoredWorker.memberships.some((x) => x.department_code === "STITCHING" && x.is_active)).toBe(true);
});
