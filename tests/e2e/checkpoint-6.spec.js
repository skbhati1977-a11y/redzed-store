const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

async function people(page) {
  const result = await rpc(page, 'rr_real_chat_directory_v85');
  expect(result.error).toBeNull();
  return result.data.people;
}

function named(rows, name) {
  const row = rows.find((x) => String(x.worker_name).trim().toLowerCase() === name.toLowerCase());
  expect(row, name).toBeTruthy();
  return row;
}

async function setActAs(page, worker) {
  const result = await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: worker.worker_id });
  expect(result.error).toBeNull();
}

async function actAsUi(page, name) {
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await page.locator('#rrGlobalViewAs172 .rr-view-handle').click();
  await page.locator('#rrGlobalViewAs172 [data-search]').fill(name);
  const actor = page.locator('#rrGlobalViewAs172 [data-worker]').filter({ hasText: name }).first();
  await expect(actor).toBeVisible();
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
    actor.click({ noWaitAfter: true })
  ]);
  await expect.poll(() => page.evaluate(() => Boolean(window.RR_ON_BEHALF_ACTIVE))).toBe(true);
}

async function openPacking2614(page) {
  await expect(page.locator('[data-department="PACKING"]')).toBeVisible();
  await page.locator('[data-department="PACKING"]').click();
  await expect(page.locator('#chat')).toBeVisible();
  const group = page.locator('[data-dept-group="PACKING"]');
  await expect(group).toBeVisible();
  await group.click();
  await page.locator('[data-chat-status="WORKING"]').click();
  const open = page.locator('[data-fg-open][data-lot="2614"]').first();
  await expect(open).toBeVisible();
  await open.click();
  await expect(page.locator('.rrfg-sheet')).toBeVisible();
}

test.beforeEach(async ({ page }) => { await ensureSession(page); });
test.afterEach(async ({ page }) => {
  if (!page.isClosed()) await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test('Final Rate 75 maps RRQ once and rolls the live fixture back', async ({ page }) => {
  const result = await rpc(page, 'rr_test_checkpoint6_rate_approval_v333');
  expect(result.error).toBeNull();
  expect(result.data.lot_no).toBe('2614');
  expect(result.data.final_rate).toBe(75);
  expect(result.data.first.ok).toBe(true);
  expect(result.data.first.duplicate_blocked).toBe(false);
  expect(result.data.second.duplicate_blocked).toBe(true);
  expect(result.data.lot_row_delta_during).toBe(1);
  expect(result.data.ledger_delta_during).toBe(1);
  expect(Number(result.data.balance_delta_during)).not.toBe(0);
  expect(result.data.rolled_back).toBe(true);
  expect(result.data.persisted).toBe(false);
});

test('backend rate payload and approval authority follow effective role', async ({ page }) => {
  const directory = await people(page);
  const ownerStatus = await rpc(page, 'rr_pack_rate_status_v9340', { p_lot_no: '2614', p_data_mode: 'TEST' });
  expect(ownerStatus.error).toBeNull();
  expect(ownerStatus.data.visibility).toBe('SUPER_ADMIN_PRIVATE');
  expect(ownerStatus.data).toHaveProperty('source_rate');
  const ownerContext = await rpc(page, 'rr_pack_rate_context_public_v333', { p_lot_no: '2614', p_data_mode: 'TEST' });
  expect(ownerContext.error).toBeNull();
  expect(ownerContext.data.visibility).toBe('SUPER_ADMIN_PRIVATE');
  expect(ownerContext.data).toHaveProperty('base_cost_per_pc');

  const raw = await page.evaluate(async () => {
    const r = await window.supabaseClient.from('rrq_rate_ledger_v9300').select('*').limit(1);
    return r.error && { message: r.error.message, code: r.error.code };
  });
  expect(raw?.message).toMatch(/permission denied/i);

  await setActAs(page, named(directory, 'singh ji'));
  const workerStatus = await rpc(page, 'rr_pack_rate_status_v9340', { p_lot_no: '2614', p_data_mode: 'TEST' });
  expect(workerStatus.error).toBeNull();
  expect(workerStatus.data.visibility).toBe('PACKING_STATUS_ONLY');
  for (const key of ['source_rate','sale_rate','final_rate','qty','reserve_delta_per_pc','reserve_quota_impact','art_code']) {
    expect(workerStatus.data).not.toHaveProperty(key);
  }
  const workerContext = await rpc(page, 'rr_pack_rate_context_public_v333', { p_lot_no: '2614', p_data_mode: 'TEST' });
  expect(workerContext.data.visibility).toBe('PACKING_STATUS_ONLY');
  expect(workerContext.data).not.toHaveProperty('source_rate');
  expect(workerContext.data).not.toHaveProperty('base_cost_per_pc');
  const denied = await rpc(page, 'rr_pack_rate_approve_v9340', { p_lot_no: '2614', p_final_rate: 75, p_data_mode: 'TEST' });
  expect(denied.error?.message).toMatch(/Effective Super Admin approval required/i);

  await rpc(page, 'rr_test_clear_on_behalf_context_v176');
  await setActAs(page, named(directory, 'kishan'));
  const sales = await rpc(page, 'rr_pack_rate_status_v9340', { p_lot_no: '2614', p_data_mode: 'TEST' });
  expect(sales.error).toBeNull();
  expect(sales.data.visibility).toBe('SALES_RATE');
  expect(sales.data).toHaveProperty('sale_rate');
  expect(sales.data).not.toHaveProperty('reserve_quota_impact');
  expect(sales.data).not.toHaveProperty('qty');
});

test('mobile Packing table is aligned and Final Rate UI is single-tap safe', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await openPacking2614(page);
  const sheet = page.locator('.rrfg-sheet');
  await expect(sheet.locator('th')).toHaveText(['Box No.','Consignment','Box PCS','Colour / Size Composition']);
  await expect(sheet).toContainText('1–18');
  await expect(sheet).toContainText('FRESH');
  await expect(sheet).toContainText('12 × 18 = 216');
  await expect(sheet).toContainText('C1');
  await expect(sheet).toContainText('2XL');
  await expect(sheet).toContainText('4 PCS');
  await expect(sheet.locator('[data-role-surface="SUPER_ADMIN"]')).toBeVisible();
  await expect(sheet).toContainText('Owner Margin / PCS');
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);

  await page.evaluate(() => {
    const client = window.supabaseClient;
    const original = client.rpc.bind(client);
    window.__cp6ApprovalCalls = 0;
    client.rpc = (name, args, options) => {
      if (name === 'rr_pack_rate_approve_v9340') {
        window.__cp6ApprovalCalls += 1;
        return original('rr_test_checkpoint6_rate_approval_v333', {}, options);
      }
      return original(name, args, options);
    };
  });
  await sheet.locator('[data-final-rate]').fill('75');
  await sheet.locator('[data-approve]').evaluate((button) => { button.click(); button.click(); });
  await expect.poll(() => page.evaluate(() => window.__cp6ApprovalCalls)).toBe(1);
  await expect(sheet.locator('.rrfg-msg')).not.toContainText('TypeError');
});

test('Packing worker sees only the pending current action', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await actAsUi(page, 'singh ji');
  await openPacking2614(page);
  const sheet = page.locator('.rrfg-sheet');
  await expect(sheet.locator('[data-role-surface="PACKING_WORKER"]')).toBeVisible();
  await expect(sheet.locator('[data-current-action]')).toContainText('FINAL RATE APPROVAL PENDING');
  for (const forbidden of [
    'RUN / RESET PACKING ALGORITHM','UPLOAD 3 FINAL PHOTOS','Final Rate / PCS',
    'SUPER ADMIN APPROVE & MAP TO RRQ','FINALIZE PACKING','Owner Margin','Total Cost / PCS'
  ]) await expect(sheet).not.toContainText(forbidden);
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
});
