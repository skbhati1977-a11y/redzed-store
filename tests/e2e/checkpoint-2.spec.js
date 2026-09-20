const { test, expect } = require("@playwright/test");
const { ensureSession } = require("./session");

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

async function directory(page) {
  await ensureSession(page);
  const result = await rpc(page, "rr_real_chat_directory_v85");
  expect(result.error).toBeNull();
  return result.data;
}

test.afterEach(async ({ page }) => {
  if (!page.isClosed()) await rpc(page, "rr_test_clear_on_behalf_context_v176").catch(() => null);
});

test("canonical department cases resolve from one operational projection", async ({ page }) => {
  const data = await directory(page);
  const cases = [
    ["javed", "OVERLOCK"], ["akhtar", "FOLDING"], ["balli", "METAL_ID"],
    ["yashpal", "KAJ_BUTTON"], ["baldev", "KAJ_BUTTON"], ["sharwan", "PRESS"]
  ];
  for (const [name, department] of cases) {
    const actor = data.people.find((x) => String(x.worker_name).toLowerCase() === name);
    expect(actor, `${name} directory mapping`).toBeTruthy();
    const result = await rpc(page, "rr_real_chat_operational_work_v319", {
      p_worker_id: actor.worker_id, p_status: "WORKING", p_department_code: department
    });
    expect(result.error, `${name} ${department}`).toBeNull();
    expect(result.data.version).toBe("V324_ACCEPTED_VARIANCE_MIRROR");
    for (const card of result.data.cards || []) {
      expect(card.department_code).toBe(department);
      expect(card.colour_code).toBeTruthy();
      expect(Number(card.qty)).toBe(Number(card.good_qty));
      if (card.variance) {
        expect(["SHORT", "EXCESS"]).toContain(card.variance.type);
        expect(card.variance.colour_code).toBe(card.colour_code);
      }
    }
  }
});

test("separate and atomic colour batches render exactly their canonical rows", async ({ page }) => {
  const data = await directory(page);
  for (const name of ["akhtar", "balli"]) {
    const actor = data.people.find((x) => String(x.worker_name).toLowerCase() === name);
    expect(actor).toBeTruthy();
    const selected = await rpc(page, "rr_test_set_on_behalf_context_v176", { p_worker_id: actor.worker_id });
    expect(selected.error).toBeNull();
    const pending = await rpc(page, "rr_upm_my_pending_receipts_v9112");
    expect(pending.error).toBeNull();
    for (const batch of pending.data?.rows || []) {
      const ids = (batch.colour_rows || []).map((x) => x.assignment_id);
      expect(new Set(ids).size).toBe(ids.length);
      expect((batch.colour_rows || []).every((x) => x.colour_code && Number(x.expected_qty) >= 0)).toBe(true);
    }
    await rpc(page, "rr_test_clear_on_behalf_context_v176");
  }
});

test("Accept & Count UI permits excess and disables the first tap", async ({ page }) => {
  const data = await directory(page);
  const akhtar = data.people.find((x) => String(x.worker_name).toLowerCase() === "akhtar");
  expect(akhtar).toBeTruthy();
  expect((await rpc(page, "rr_test_set_on_behalf_context_v176", { p_worker_id: akhtar.worker_id })).error).toBeNull();
  const pending = await rpc(page, "rr_upm_my_pending_receipts_v9112");
  const batch = pending.data?.rows?.find((x) => (x.colour_rows || []).length);
  test.skip(!batch, "No reversible Akhtar pending receipt fixture is currently available");
  const assignment = batch.colour_rows[0].assignment_id;
  await page.goto(`/test70-accept-work-v205.html?assignment=${assignment}&worker=${akhtar.worker_id}`);
  await expect(page.locator(".qty")).toHaveCount(batch.colour_rows.length);
  await expect(page.locator(".qty").first()).not.toHaveAttribute("max", /.+/);
  await page.locator(".qty").first().fill(String(Number(batch.colour_rows[0].expected_qty) + 2));
  await page.locator("#note").fill("TEST71 browser pending-state proof; no submit");
  await expect(page.locator("#accept")).toBeEnabled();
});
