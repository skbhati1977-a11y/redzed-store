const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const r = await window.supabaseClient.rpc(name, args);
    return { data: r.data, error: r.error && { message: r.error.message, code: r.error.code } };
  }, { name, args });
}

test.beforeEach(async ({ page }) => {
  await ensureSession(page);
  await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test.afterEach(async ({ page }) => {
  if (!page.isClosed()) await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test('canonical CB draft, confirm, DUE completion and retry proof roll back', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_cb_department_flow_v600');
  expect(proof.error).toBeNull();
  expect(proof.data).toMatchObject({
    open_to_working: true,
    due_survived_confirm: true,
    rolled_back: true,
    persisted: false
  });
  expect(proof.data.retry.duplicate_blocked).toBe(true);
  expect(proof.data.confirm.state).toBe('WORKING');
  expect(proof.data.working_card.pending_material_count).toBe(2);
  expect(proof.data.counts).toMatchObject({
    cb_rows: 1,
    regular_rows: 1,
    material_rows: 2,
    roll_rows: 1,
    due_rows: 1,
    zip_confirmed: true
  });
});

test('CB Department is the visible mobile directory while PURCHASE stays canonical', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await expect(page.locator('#state')).toContainText(/departments · .* people/, { timeout: 30_000 });
  const department = page.locator('[data-department="PURCHASE"]');
  await expect(department).toContainText('CB Department');
  await department.click();
  await expect(page.locator('[data-dept-group="PURCHASE"]')).toContainText('CB Department');
  await page.locator('[data-dept-group="PURCHASE"]').click();
  await expect(page.locator('#chatName')).toContainText('CB Department');
  await expect(page.locator('#contextAction')).toContainText(/NEW CB/i);
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
});

test('Act As Worker cannot mutate CB purchase or material state', async ({ page }) => {
  const directory = await rpc(page, 'rr_real_chat_directory_v600');
  expect(directory.error).toBeNull();
  const worker = directory.data.people.find((x) => String(x.role_code).toUpperCase() === 'WORKER');
  expect(worker).toBeTruthy();
  const acting = await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: worker.worker_id });
  expect(acting.error).toBeNull();
  const denied = await rpc(page, 'rr_cb_department_save_v600', {
    p_cb_id: null,
    p_action_id: crypto.randomUUID(),
    p_confirm: false,
    p_payload: { cb_no: 'TEST71-UNAUTHORIZED', division_count: 1, colour_count: 1 }
  });
  expect(denied.error).not.toBeNull();
  expect(denied.error.message).toMatch(/Owner\/Admin authority/i);
});
