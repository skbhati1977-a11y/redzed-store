const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const r = await window.supabaseClient.rpc(name, args);
    return { data: r.data, error: r.error && { message: r.error.message, code: r.error.code } };
  }, { name, args });
}

test('deployed Unit dropdown, creation, Material persistence, CB mirror and Worker denial', async ({ page }) => {
  await ensureSession(page);
  await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);

  // Do not race the Git push against the immutable preview rollout.
  await expect.poll(async () => {
    const response = await page.request.get(`/real-material-master-v805.js?v=607-${Date.now()}`);
    return response.ok() && (await response.text()).includes('rr_unit_master_list_v606');
  }, { timeout: 240_000, intervals: [5_000, 10_000, 15_000] }).toBe(true);

  const nonce = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
  const unitName = `TEST71 Bundle ${nonce}`;
  const unitCode = `TEST71_BUNDLE_${nonce}`;
  const materialName = `TEST71 Rope Unit ${nonce}`;

  try {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/real-material-master-v805.html?mode=TEST&v=607');
    await expect(page.locator('#who')).toContainText(/Super Admin|OWNER/i, { timeout: 30_000 });
    await page.locator('#type').selectOption('OTHER_MATERIAL');
    await page.locator('#addMaterial').click();
    await expect(page.locator('#materialModal')).toBeVisible();
    await expect(page.locator('#newPurchaseUnit')).toHaveValue('PCS');

    await page.locator('#newPurchaseUnit').selectOption('__NEW_UNIT__');
    await expect(page.locator('#unitModal')).toBeVisible();
    await page.locator('#newUnitName').fill(unitName);
    // Unit Code is canonically normalized from Unit Name. Re-entering it here
    // races the app-wide mobile fill helper and does not model the user flow.
    await expect(page.locator('#newUnitCode')).toHaveValue(unitCode);
    await page.locator('#saveNewUnit').click();
    await expect(page.locator('#unitModal')).toBeHidden({ timeout: 15_000 });
    await expect(page.locator('#newPurchaseUnit')).toHaveValue(unitCode);
    await page.locator('#newStockUnit').selectOption(unitCode);
    await page.locator('#newConsumptionUnit').selectOption(unitCode);
    await page.locator('#newMaterialName').fill(materialName);
    await page.locator('#saveNewMaterial').click();
    await expect(page.locator('#materialModal')).toBeHidden({ timeout: 20_000 });

    // Retry/double-tap and close spelling both resolve safely to existing Units.
    const retry = await rpc(page, 'rr_unit_master_create_v606', { p_unit_name: unitName, p_unit_code: unitCode });
    expect(retry.error).toBeNull();
    expect(retry.data).toMatchObject({ created: false, existing_match: true });
    expect(retry.data.unit.unit_code).toBe(unitCode);
    const alias = await rpc(page, 'rr_unit_master_create_v606', { p_unit_name: 'Metres', p_unit_code: 'METRE' });
    expect(alias.error).toBeNull();
    expect(alias.data).toMatchObject({ created: false, existing_match: true });
    expect(alias.data.unit.unit_code).toBe('MTR');

    // Reload proves exact canonical persistence, not transient select state.
    await page.reload();
    await page.locator('#type').selectOption('OTHER_MATERIAL');
    await page.locator('#name').fill(materialName);
    await expect(page.locator('#suggestions .suggestion')).toHaveCount(1, { timeout: 15_000 });
    await page.locator('#suggestions .suggestion').first().click();
    await expect(page.locator('#purchaseUnit')).toHaveValue(unitCode);

    // CB reads the linked category projection and keeps Unit read-only while Qty changes.
    await page.goto('/real-cb-new-v9130-fix2.html?mode=TEST&v=607');
    await page.locator('#addMaterial').click();
    const material = page.locator('#materialList [data-m="1"]');
    await material.locator('.cat').selectOption({ label: materialName });
    await expect(material.locator('.unit-readonly')).toHaveValue(unitCode);
    await material.locator('.reqState').selectOption('CONFIRMED');
    await material.locator('.materialQty').fill('250');
    await expect(material.locator('.materialQty')).toHaveValue('250');
    await expect(material.locator('.unit-readonly')).toHaveValue(unitCode);

    // Real Chat renderer uses the same unit field without a second selector.
    await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST&v=607');
    const rendered = await page.evaluate(({ materialName, unitCode }) => cbDepartmentCard({
      source_status: 'WORKING', cb_no: 'TEST71-UNIT', quantity: 1, materials: [
        { name: materialName, state: 'CONFIRMED', qty: 250, unit: unitCode }
      ]
    }), { materialName, unitCode });
    expect(rendered).toContain(`250 ${unitCode}`);

    const directory = await rpc(page, 'rr_real_chat_directory_v600');
    const worker = directory.data.people.find((x) => String(x.role_code).toUpperCase() === 'WORKER');
    expect(worker).toBeTruthy();
    expect((await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: worker.worker_id })).error).toBeNull();
    const denied = await rpc(page, 'rr_unit_master_create_v606', {
      p_unit_name: `TEST71 Denied ${nonce}`, p_unit_code: `TEST71_DENIED_${nonce}`
    });
    expect(denied.error).not.toBeNull();
    expect(denied.error.message).toMatch(/Super Admin Unit Master authority required/i);
  } finally {
    if (!page.isClosed()) {
      await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
      const clean = await rpc(page, 'rr_test_material_unit_cleanup_v606', {
        p_material_name: materialName, p_unit_code: unitCode
      }).catch(() => null);
      if (clean?.error) console.warn(`Fixture cleanup failed: ${clean.error.message}`);
    }
  }
});
