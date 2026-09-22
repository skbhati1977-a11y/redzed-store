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
  await ensureSession(page, { quiet: true });

  const beforeRows = await rpc(page, 'rr_get_mc1_purchase_account_v9076');
  const retainedBefore = beforeRows.filter((x) => String(x.bill_no || '').startsWith('MC1-E2E-')).length;

  // Exercise the real canonical writers twice in a database exception
  // subtransaction. The exact-run fixture is projected through Real Chat and
  // then fully rolled back.
  const proof = await rpc(page, 'rr_test_mc1_e2e_invariants_v613');
  expect(proof.rolled_back).toBe(true);
  expect(proof.fixture_residue).toBe(0);
  expect(proof.purchase.purchase_rows).toBe(1);
  expect(proof.purchase.purchase_in_rows).toBe(1);
  expect(proof.purchase.first.duplicate_blocked).toBe(false);
  expect(proof.purchase.retry.duplicate_blocked).toBe(true);
  expect(proof.purchase.first.supplier_ledger_id).toBe(proof.fixture.supplier_ledger_id);
  expect(proof.consumption.reservation_rows).toBe(1);
  expect(proof.consumption.consumption_rows).toBe(1);
  expect(proof.consumption.reserve_first.reservation_id).toBe(proof.consumption.reserve_retry.reservation_id);
  expect(proof.consumption.confirm_first.duplicate_blocked).toBe(false);
  expect(proof.consumption.confirm_retry.duplicate_blocked).toBe(true);
  expect(proof.projection.open.cards).toHaveLength(1);
  expect(proof.projection.open.cards[0].bill_no).toBe(proof.fixture.bill_no);
  expect(proof.projection.working.cards).toHaveLength(1);
  expect(proof.projection.working.cards[0].lot_no).toBe(proof.fixture.lot_no);
  expect(proof.projection.close.cards).toHaveLength(1);
  expect(Number(proof.costing.matching_qty_kg)).toBe(0.001);

  const afterProofRows = await rpc(page, 'rr_get_mc1_purchase_account_v9076');
  expect(afterProofRows.filter((x) => String(x.bill_no || '').startsWith('MC1-E2E-'))).toHaveLength(retainedBefore);
  expect(afterProofRows.filter((x) => x.bill_no === proof.fixture.bill_no)).toHaveLength(0);

  // Browser Draft remains non-posting. Do not confirm another immutable stock
  // transaction merely to prove the already-covered backend contract.
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
  const draftBill = `TEST71-DRAFT-${proof.fixture.idempotency_key.slice(0, 8)}`;
  await page.locator('[data-mc-fabric]').selectOption(String(seed.fabric.id || seed.fabric.matching_item_id));
  await page.locator('[data-mc-vendor]').selectOption(String(seed.vendor.supplier_ledger_id));
  await page.locator('[data-mc-bill]').fill(draftBill);
  await page.locator('[data-mc-qty]').fill('0.001');
  await page.locator('[data-mc-rate]').fill('250');
  await page.locator('[data-mc-value]').fill('0.25');
  await page.locator('[data-mc-save-draft]').click();
  await expect(page.locator('[data-mc-draft]')).toContainText('NOT POSTED');
  expect((await rpc(page, 'rr_get_mc1_purchase_account_v9076')).filter((x) => x.bill_no === draftBill)).toHaveLength(0);
  await page.evaluate(() => localStorage.removeItem('RR_MC1_PURCHASE_DRAFT_V504'));

  // Select one exact canonical history record by its backend identity. This
  // avoids coupling navigation to a named/historical fixture or visual order.
  const workingBefore = await rpc(page, 'rr_mc1_real_chat_queue_v504', { p_status: 'WORKING', p_search: null });
  const consumption = workingBefore.cards.find((x) =>
    x.lot_no && x.fabric_id && Number(x.qty) > 0 && Number(x.value) >= 0
  );
  expect(consumption).toBeTruthy();
  const lotLabel = `LOT ${consumption.lot_no}`;
  const qtyLabel = `${Number(consumption.qty).toFixed(3)} KG`;

  // Start WORKING while the OPEN request can still be in flight. A stale OPEN
  // response must never overwrite the selected Lot Consumption projection.
  await openMc1(page, 'OPEN');
  await page.locator('[data-chat-status="WORKING"]').click();
  await expect(page.locator('#kind')).toContainText('Lot Consumption');
  await expect(page.locator('#messages')).toContainText(lotLabel);
  await expect(page.locator('#messages')).toContainText(qtyLabel);

  const working = await rpc(page, 'rr_mc1_real_chat_queue_v504', {
    p_status: 'WORKING',
    p_search: String(consumption.lot_no)
  });
  const exactConsumption = working.cards.filter((x) =>
    String(x.lot_no) === String(consumption.lot_no) && String(x.fabric_id) === String(consumption.fabric_id)
  );
  expect(exactConsumption).toHaveLength(1);
  expect(Number(exactConsumption[0].qty)).toBe(Number(consumption.qty));
  expect(Number(exactConsumption[0].value)).toBe(Number(consumption.value));

  await page.locator('[data-chat-status="CLOSE"]').click();
  await expect(page.locator('#kind')).toContainText('Closing Stock');
  await expect(page.locator('#messages')).toContainText(seed.fabric.fabric_name);
  const close = await rpc(page, 'rr_mc1_real_chat_queue_v504', { p_status: 'CLOSE', p_search: seed.fabric.fabric_name });
  expect(close.cards).toHaveLength(1);

  await page.reload();
  await expect(page.locator('#state')).not.toContainText('Secure mapping loading', { timeout: 30_000 });
  await page.locator('#menu').evaluate((button) => button.click());
  await page.locator('[data-workflow="1:1"]').evaluate((button) => button.click());
  await expect(page.locator('#kind')).toContainText('Closing Stock');
  await expect(page.locator('#messages')).toContainText(seed.fabric.fabric_name);
});
