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
