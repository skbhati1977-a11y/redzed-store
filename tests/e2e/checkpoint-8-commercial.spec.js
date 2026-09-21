const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

async function person(page, name) {
  const d = await rpc(page, 'rr_real_chat_directory_v85');
  expect(d.error).toBeNull();
  const row = d.data.people.find((x) => String(x.worker_name).trim().toLowerCase() === name.toLowerCase());
  expect(row, name).toBeTruthy();
  return row;
}

async function e2eDcardSnapshot(page) {
  return page.evaluate(async () => {
    const unitId = 'a2000000-0000-4000-8000-000000000013';
    const [gallery, lot, history] = await Promise.all([
      window.supabaseClient
        .from('rr_product_gallery_production_v719')
        .select('division_id,division_code,division_status,lot_no')
        .eq('division_id', unitId)
        .maybeSingle(),
      window.supabaseClient
        .from('rr_cutting_lots_v3')
        .select('id,lot_no,status,cb_unit_id')
        .eq('cb_unit_id', unitId)
        .maybeSingle(),
      window.supabaseClient.rpc('rr_real_chat_conversation_history_v83', { p_limit: 5000 })
    ]);
    return {
      gallery: gallery.data,
      lot: lot.data,
      history: history.data,
      errors: [gallery.error, lot.error, history.error]
        .filter(Boolean)
        .map((x) => ({ message: x.message, code: x.code }))
    };
  });
}

test.beforeEach(async ({ page }) => { await ensureSession(page); });
test.afterEach(async ({ page }) => {
  if (!page.isClosed()) await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test('Sales canonical OPEN WORKING CLOSE queues and CI-linked RCI context agree', async ({ page }) => {
  for (const status of ['OPEN', 'WORKING', 'CLOSE']) {
    const q = await rpc(page, 'rr_sales_real_chat_queue_v500', { p_status: status, p_search: null, p_data_mode: 'TEST' });
    expect(q.error).toBeNull();
    expect(q.data.status).toBe(status);
    expect(Array.isArray(q.data.cards)).toBe(true);
  }
  const close = await rpc(page, 'rr_sales_real_chat_queue_v500', { p_status: 'CLOSE', p_search: null, p_data_mode: 'TEST' });
  expect(close.data.cards.length).toBeGreaterThan(0);
  const ci = close.data.cards[0];
  const rci = await rpc(page, 'rr_rci_context_v9740', { p_pi_id: ci.id });
  expect(rci.error).toBeNull();
  expect(rci.data.pi_id).toBe(ci.id);
});

test('Costing queues are consolidated and never contain private cost keys', async ({ page }) => {
  for (const status of ['OPEN', 'WORKING', 'CLOSE']) {
    const q = await rpc(page, 'rr_costing_real_chat_queue_v500', { p_status: status, p_search: null });
    expect(q.error).toBeNull();
    expect(q.data.status).toBe(status);
    expect(q.data.private_cost_included).toBe(false);
    expect(JSON.stringify(q.data)).not.toMatch(/owner_margin|base_cost_per_pc|team_salary|material_breakdown/i);
    const ids = q.data.cards.map((x) => x.canonical_lot_id);
    expect(new Set(ids).size).toBe(ids.length);
  }
});

test('Accounts summary, bill status, FIFO allocation and aging are internally consistent', async ({ page }) => {
  const home = await rpc(page, 'rr_accounts_real_chat_home_v500', { p_status: 'CLOSE', p_data_mode: 'TEST' });
  expect(home.error).toBeNull();
  expect(home.data.categories.map((x) => x.code)).toEqual(expect.arrayContaining(['DEBTORS','CREDITORS','SALES','PURCHASE','RECEIPTS','PAYMENTS','EXPENSES','JOURNALS']));
  const parties = await rpc(page, 'rr_accounts_party_summary_v500', { p_kind: null, p_data_mode: 'TEST', p_search: null });
  expect(parties.error).toBeNull();
  expect(parties.data.parties.length).toBeGreaterThan(0);
  const withBills = parties.data.parties.find((x) => Number(x.unpaid_count) + Number(x.part_paid_count) > 0) || parties.data.parties[0];
  const detail = await rpc(page, 'rr_accounts_bill_detail_v500', { p_party_ledger_id: withBills.party_ledger_id, p_data_mode: 'TEST' });
  expect(detail.error).toBeNull();
  for (const bill of detail.data.bills) {
    expect(Number(bill.allocated) + Number(bill.outstanding)).toBeCloseTo(Number(bill.original_amount), 2);
    expect(['PAID','PART_PAID','UNPAID','REVERSED']).toContain(bill.status);
  }
});

test('worker cannot open commercial authority RPCs and receives no cost data', async ({ page }) => {
  const imamul = await person(page, 'imamul');
  expect((await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: imamul.worker_id })).error).toBeNull();
  for (const [name,args] of [
    ['rr_sales_real_chat_queue_v500',{p_status:'OPEN',p_search:null,p_data_mode:'TEST'}],
    ['rr_costing_real_chat_queue_v500',{p_status:'OPEN',p_search:null}],
    ['rr_accounts_real_chat_home_v500',{p_status:'OPEN',p_data_mode:'TEST'}]
  ]) {
    const denied = await rpc(page, name, args);
    expect(denied.error?.message).toMatch(/permission|required|eligible|sales actor/i);
  }
});

test('mobile Sales, Costing and Accounts group projections stay inside viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await expect(page.locator('#state')).toContainText(/departments · .* people/, { timeout: 30_000 });
  for (const department of ['SALES','COSTING','ACCOUNTS']) {
    const row = page.locator(`[data-department="${department}"]`);
    await expect(row).toBeVisible();
    await row.click();
    await page.locator(`[data-dept-group="${department}"]`).click();
    await expect(page.locator('#messages')).toBeVisible();
    await expect(page.locator('#messages')).not.toContainText(/undefined|parallel engine/i);
    const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
    expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
    await page.locator('#back').click();
    await page.locator('#back').click();
  }
});

test('released D-card succeeds once, closes action state and rolls its fixture back', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_released_dcard_regression_v502');
  expect(proof.error).toBeNull();
  expect(proof.data.first_release_count).toBe(1);
  expect(proof.data.retry_blocked).toBe(true);
  expect(proof.data.cross_mode_retry_blocked).toBe(true);
  expect(proof.data.gallery_state).toBe('released');
  expect(proof.data.actionable_ready_count).toBe(0);
  expect(proof.data.history_count).toBe(1);
  expect(proof.data.real_chat_state).toBe('CLOSE');
  expect(proof.data.real_chat_action).toBeNull();
  expect(proof.data.real_chat_next_actions).toEqual([]);
  expect(proof.data.rolled_back).toBe(true);
  expect(proof.data.fixture_residue).toBe(0);
});

test('E2E-CB-3 is retained RELEASED history across backend, App and Real Chat', async ({ page }) => {
  const snapshot = await e2eDcardSnapshot(page);
  expect(snapshot.errors).toEqual([]);
  expect(snapshot.gallery).toMatchObject({
    division_code: 'E2E-CB-3',
    division_status: 'released'
  });
  expect(snapshot.gallery.lot_no).toContain('E2E-FRESH-03');
  expect(snapshot.lot).toMatchObject({ lot_no: 'E2E-FRESH-03', status: 'released' });

  const release = snapshot.history.find((row) =>
    row.source_event_type === 'CUTTING_RELEASE_SUCCEEDED' &&
    String(row.personal_payload?.lot_no || row.group_payload?.lot_no || '').toUpperCase() === 'E2E-FRESH-03'
  );
  expect(release).toBeTruthy();
  expect(release.canonical_state).toBe('CLOSE');
  expect(release.personal_payload.canonical_state).toBe('CLOSE');
  expect(release.action_code).toBeNull();
  expect(release.personal_payload.next_actions).toEqual([]);

  const purchase = snapshot.history.find((row) =>
    row.source_module === 'CB_PURCHASE' &&
    (row.personal_payload?.cb_children || []).some((child) => child.cb_unit_id === snapshot.lot.cb_unit_id)
  );
  expect(purchase).toBeTruthy();
  const child = purchase.personal_payload.cb_children.find((row) => row.cb_unit_id === snapshot.lot.cb_unit_id);
  expect(child.state).toBe('RELEASED');
  expect(purchase.personal_payload.canonical_state).toBe('CLOSE');

  await page.setViewportSize({ width: 390, height: 844 });
  const dialogMessages = [];
  page.on('dialog', async (dialog) => {
    dialogMessages.push(dialog.message());
    await dialog.dismiss();
  });
  const url = '/real-cutting-master.html?mode=TEST&embed=1&cb_unit_id=a2000000-0000-4000-8000-000000000013&lot_mode=single';
  await page.goto(url);
  const card = page.locator('[data-division-id="a2000000-0000-4000-8000-000000000013"]');
  await expect(card).toBeVisible({ timeout: 30_000 });
  await expect(page.locator('#divisionGallery .cm-card')).toHaveCount(1);
  await expect(card).toContainText('E2E-CB-3');
  await expect(card).toContainText(/released/i);
  await expect(card.locator('[data-single]')).toBeDisabled();
  await expect(card.locator('[data-multi]')).toBeDisabled();
  await expect(page.locator('#cmMessage')).toContainText(/history/i);
  expect(dialogMessages).toEqual([]);

  await page.reload();
  await expect(card).toBeVisible({ timeout: 30_000 });
  await expect(page.locator('#divisionGallery .cm-card')).toHaveCount(1);
  await expect(card.locator('[data-single]')).toBeDisabled();
  await expect(card.locator('[data-multi]')).toBeDisabled();
  expect(dialogMessages).toEqual([]);

  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST&rc_status=CLOSE');
  await expect(page.locator('#state')).toContainText(/departments · .* people/, { timeout: 30_000 });
  await page.locator('[data-department="CUTTING"]').click();
  await page.locator('[data-dept-group="CUTTING"]').click();
  await page.locator('[data-chat-status="CLOSE"]').click();
  await page.locator('#chatFind').fill('E2E-FRESH-03');
  await page.locator('#chatFind').press('Enter');
  await expect(page.locator('#messages')).toContainText('E2E-FRESH-03', { timeout: 30_000 });
  await expect(page.locator('#messages')).not.toContainText(/SINGLE LOT|MULTI LOT/);
});
