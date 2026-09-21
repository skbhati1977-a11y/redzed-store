const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

const PARTIAL_PENDING = '63e2a15f-1239-4786-ba39-aa72d49a5f2c';

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

async function openDespatch(page, status) {
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await expect(page.locator('#state')).toContainText(/departments · .* people/, { timeout: 30_000 });
  await expect(page.locator('[data-department="DISPATCH"]')).toBeVisible({ timeout: 30_000 });
  await page.locator('[data-department="DISPATCH"]').click();
  await expect(page.locator('#chat')).toBeVisible();
  const group = page.locator('[data-dept-group="DISPATCH"]');
  await expect(group).toBeVisible();
  await group.click();
  await page.locator(`[data-chat-status="${status}"]`).click();
}

test.beforeEach(async ({ page }) => { await ensureSession(page); });
test.afterEach(async ({ page }) => {
  if (!page.isClosed()) await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test('canonical partial/full Despatch and both Store Receive acknowledgements roll back', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_checkpoint7_despatch_receive_v335');
  expect(proof.error).toBeNull();
  expect(proof.data.partial).toMatchObject({
    kind: 'PARTIAL', boxes: 1, duplicate_blocked: true,
    app_mirror: true, receiver_finalized: false, depositor_finalized: true
  });
  expect(proof.data.partial.remaining_ready_during).toBeGreaterThan(0);
  expect(proof.data.full).toMatchObject({
    kind: 'FULL_LOT', duplicate_blocked: true, remaining_ready_during: 0,
    app_mirror: true, receiver_finalized: false, depositor_finalized: true
  });
  expect(proof.data.full.boxes).toBe(proof.data.full.expected_boxes);
  expect(proof.data.rolled_back).toBe(true);
  expect(proof.data.persisted).toBe(false);
});

test('full and partial challans use one chat-native modal and first tap is pending', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openDespatch(page, 'OPEN');
  const card = page.locator('[data-kind="despatch"][data-lot="E2E-FRESH-03"]').first();
  await expect(card).toBeVisible();
  await card.click();
  const sheet = page.locator('.rrfg-sheet');
  await expect(sheet).toBeVisible();
  await expect(sheet).toContainText('CREATE & LOCK FULL-LOT CHALLAN');
  await expect(sheet.locator('[data-line]')).toBeVisible();
  await expect(sheet.locator('[data-dest]')).toBeVisible();
  await expect(sheet.locator('[data-remarks]')).toBeVisible();

  await sheet.locator('[data-toggle]').click();
  await expect(sheet).toContainText('CREATE & LOCK PARTIAL CHALLAN');
  await expect(sheet.locator('[data-partial-box]').first()).toBeVisible();
  await expect(sheet.locator('[data-send-qty]').first()).toBeVisible();
  await expect(page).toHaveURL(/test70-cb-purchase-real-chat-pilot\.html/);
  await expect(page.locator('#actionSheet')).toBeHidden();

  await sheet.locator('[data-line]').selectOption({ index: 1 });
  await sheet.locator('[data-dest]').selectOption('G1');
  await sheet.locator('[data-remarks]').fill('TEST71 browser rollback-backed UI proof');
  const first = sheet.locator('tr[data-box]').first();
  const packed = Number(await first.locator('[data-packed]').textContent());
  await first.locator('[data-partial-box]').check();
  await first.locator('[data-send-qty]').fill(String(packed));

  await page.evaluate(() => {
    const client = window.supabaseClient;
    const original = client.rpc.bind(client);
    window.__cp7CreateCalls = 0;
    client.rpc = (name, args, options) => {
      if (name === 'rr_fg_create_despatch_chat_v335') {
        window.__cp7CreateCalls += 1;
        return Promise.resolve({ data: {
          challan_no: 'TEST71-ROLLBACK-UI', total_boxes: 1,
          total_qty: args.p_boxes[0].qty, kind: 'PARTIAL', already_locked: false
        }, error: null });
      }
      return original(name, args, options);
    };
  });
  await sheet.locator('[data-create]').evaluate((button) => { button.click(); button.click(); });
  await expect.poll(() => page.evaluate(() => window.__cp7CreateCalls)).toBe(1);
  await expect(sheet.locator('[data-create]')).toBeDisabled();
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
});

test('Store Receive is chat-native and effective Ali identity is the mapped depositor', async ({ page }) => {
  const directory = await people(page);
  const ownerContext = await rpc(page, 'rr_fg_despatch_action_context_v335', { p_despatch_id: PARTIAL_PENDING });
  expect(ownerContext.error).toBeNull();
  expect(ownerContext.data.can_receive).toBe(true);
  expect(ownerContext.data.can_deposit).toBe(true);

  await setActAs(page, named(directory, 'ali'));
  const ali = await rpc(page, 'rr_fg_despatch_action_context_v335', { p_despatch_id: PARTIAL_PENDING });
  expect(ali.error).toBeNull();
  expect(ali.data.on_behalf).toBe(true);
  expect(ali.data.is_delivery_line_man).toBe(true);
  expect(ali.data.can_deposit).toBe(true);
  expect(ali.data.can_receive).toBe(false);

  await rpc(page, 'rr_test_clear_on_behalf_context_v176');
  await setActAs(page, named(directory, 'dhiraj'));
  const wrongLineMan = await rpc(page, 'rr_fg_despatch_action_context_v335', { p_despatch_id: PARTIAL_PENDING });
  expect(wrongLineMan.error).toBeNull();
  expect(wrongLineMan.data.is_delivery_line_man).toBe(false);
  expect(wrongLineMan.data.can_deposit).toBe(false);

  await rpc(page, 'rr_test_clear_on_behalf_context_v176');
  await page.setViewportSize({ width: 390, height: 844 });
  await openDespatch(page, 'WORKING');
  const card = page.locator(`[data-kind="receive"][data-id="${PARTIAL_PENDING}"]`).first();
  await expect(card).toBeVisible();
  await card.click();
  const sheet = page.locator('.rrfg-sheet');
  await expect(sheet).toBeVisible();
  await expect(sheet).toContainText('VERIFY & RECEIVE');
  await expect(sheet).toContainText('TDC12');
  await expect(sheet.locator('[data-box]').first()).toBeVisible();
  await expect(sheet.locator('[data-pcs]').first()).toBeVisible();
  await expect(sheet).not.toContainText('OPEN FULL RECEIVE DETAILS');
  await expect(page).toHaveURL(/test70-cb-purchase-real-chat-pilot\.html/);
  await expect(page.locator('#actionSheet')).toBeHidden();
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
});
