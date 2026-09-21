const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, params = {}) {
  return page.evaluate(async ({ name, params }) => {
    const result = await window.supabaseClient.rpc(name, params);
    if (result.error) throw new Error(`${name}: ${result.error.message}`);
    return result.data;
  }, { name, params });
}

async function openMc1(page, status = 'OPEN') {
  await page.goto(`/test70-cb-purchase-real-chat-pilot.html?rc_status=${status}`);
  await expect(page.locator('#state')).not.toContainText('Secure mapping loading', { timeout: 30_000 });
  await page.locator('#menu').click();
  await page.locator('[data-workflow="1:1"]').click();
  await expect(page.locator('#chatName')).toHaveText('MC1 / Matching Cloth');
  await expect(page.locator('#kind')).toContainText(status === 'OPEN' ? 'Purchase / Stock IN' : status === 'WORKING' ? 'Lot Consumption' : 'Closing Stock');
}

test('MC1 purchase, consumption, costing, close and idempotency stay canonical', async ({ page }) => {
  await ensureSession(page);
  await openMc1(page, 'OPEN');

  const seed = await page.evaluate(async () => {
    const [fabrics, vendors] = await Promise.all([
      window.supabaseClient.rpc('rr_get_mc1_fabric_options_v9134'),
      window.supabaseClient.rpc('rr_get_mc_vendor_options_v9135')
    ]);
    if (fabrics.error) throw new Error(fabrics.error.message);
    if (vendors.error) throw new Error(vendors.error.message);
    const fabric = fabrics.data.find((x) => x.fabric_name === 'TEST E2E CLOTH 20260814');
    const vendor = vendors.data.find((x) => x.vendor_name === 'TEST SUPPLIER E2E');
    if (!fabric || !vendor) throw new Error('Safe MC1 E2E fabric/vendor fixture missing');
    return { fabric, vendor };
  });

  const bill = `MC1-E2E-${Date.now()}`;
  const beforeQty = Number(seed.fabric.current_qty || seed.fabric.available_qty || 0);
  await page.locator('[data-mc-fabric]').selectOption(String(seed.fabric.id || seed.fabric.matching_item_id));
  await page.locator('[data-mc-vendor]').selectOption(String(seed.vendor.supplier_ledger_id));
  await page.locator('[data-mc-bill]').fill(`${bill}-DRAFT`);
  await page.locator('[data-mc-qty]').fill('0.001');
  await page.locator('[data-mc-rate]').fill('250');
  await page.locator('[data-mc-value]').fill('0.25');
  await page.locator('[data-mc-save-draft]').click();
  await expect(page.locator('[data-mc-draft]')).toContainText('NOT POSTED');

  const prePost = await rpc(page, 'rr_get_mc1_purchase_account_v9076');
  expect(prePost.filter((x) => x.bill_no === `${bill}-DRAFT`)).toHaveLength(0);

  await page.locator('[data-mc-edit]').click();
  await page.locator('[data-mc-bill]').fill(bill);
  await page.locator('[data-mc-save-draft]').click();
  const idempotencyKey = await page.evaluate(() => JSON.parse(localStorage.getItem('RR_MC1_PURCHASE_DRAFT_V504')).idempotency_key);
  await page.locator('[data-mc-confirm]').click();
  await expect(page.locator('#messages')).toContainText(bill, { timeout: 20_000 });

  const duplicate = await rpc(page, 'rr_confirm_mc_purchase_v504', {
    p_idempotency_key: idempotencyKey,
    p_fabric_id: seed.fabric.id || seed.fabric.matching_item_id,
    p_fabric_name: seed.fabric.fabric_name,
    p_supplier_ledger_id: seed.vendor.supplier_ledger_id,
    p_vendor_name: seed.vendor.vendor_name,
    p_bill_no: bill,
    p_bill_qty: 0.001,
    p_bill_value: 0.25,
    p_bill_date: new Date().toISOString().slice(0, 10),
    p_remarks: 'TEST71 MC1 LIVE E2E'
  });
  expect(duplicate.duplicate_blocked).toBe(true);

  const [postRows, fabricsAfter] = await Promise.all([
    rpc(page, 'rr_get_mc1_purchase_account_v9076'),
    rpc(page, 'rr_get_mc1_fabric_options_v9134')
  ]);
  expect(postRows.filter((x) => x.bill_no === bill)).toHaveLength(1);
  const fabricAfter = fabricsAfter.find((x) => String(x.id || x.matching_item_id) === String(seed.fabric.id || seed.fabric.matching_item_id));
  expect(Number(fabricAfter.current_qty || fabricAfter.available_qty)).toBeCloseTo(beforeQty + 0.001, 3);

  await page.locator('[data-chat-status="WORKING"]').click();
  await expect(page.locator('#kind')).toContainText('Lot Consumption');
  await expect(page.locator('#messages')).toContainText('LOT 2622');
  await expect(page.locator('#messages')).toContainText('10.000 KG');

  const working = await rpc(page, 'rr_mc1_real_chat_queue_v504', { p_status: 'WORKING', p_search: '2622' });
  const consumption = working.cards.find((x) => x.lot_no === '2622');
  expect(consumption).toBeTruthy();
  expect(Number(consumption.qty)).toBe(10);
  expect(Number(consumption.value)).toBe(3250);

  const costing = await rpc(page, 'rr_upm_final_costing_v308', {
    p_canonical_lot_id: 'rr_cutting_lots_v3:2f9001de-ff41-4ceb-ae5d-8f6b6054151c',
    p_data_mode: 'TEST'
  });
  expect(costing.security).toBe('SUPER_ADMIN_PRIVATE');
  expect(Number(costing.cloth.matching_qty_kg)).toBe(10);
  expect(Number(costing.cloth.matching_rate_per_kg)).toBe(325);
  expect(Number(costing.cloth.matching_total)).toBe(3250);
  expect(costing.cloth.components.find((x) => x.category === 'MATCHING_CLOTH').source).toBe('LOT_MATCHING_ACTUAL');

  const beforeRetry = await rpc(page, 'rr_get_mc1_fabric_options_v9134');
  const retryResult = await rpc(page, 'rr_confirm_lot_matching_v2', { p_lot_no: '2622', p_source_id: null });
  const afterRetry = await rpc(page, 'rr_get_mc1_fabric_options_v9134');
  expect(retryResult.duplicate_blocked).toBe(true);
  const retryFabricId = consumption.fabric_id;
  expect(Number(afterRetry.find((x) => String(x.id || x.matching_item_id) === String(retryFabricId)).current_qty))
    .toBe(Number(beforeRetry.find((x) => String(x.id || x.matching_item_id) === String(retryFabricId)).current_qty));

  await page.locator('[data-chat-status="CLOSE"]').click();
  await expect(page.locator('#kind')).toContainText('Closing Stock');
  await expect(page.locator('#messages')).toContainText(seed.fabric.fabric_name);
  const close = await rpc(page, 'rr_mc1_real_chat_queue_v504', { p_status: 'CLOSE', p_search: seed.fabric.fabric_name });
  expect(close.cards).toHaveLength(1);
  expect(Number(close.cards[0].closing_qty)).toBeCloseTo(beforeQty + 0.001, 3);

  await page.reload();
  await page.locator('#menu').click();
  await page.locator('[data-workflow="1:1"]').click();
  await expect(page.locator('#kind')).toContainText('Closing Stock');
  await expect(page.locator('#messages')).toContainText(seed.fabric.fabric_name);
});
