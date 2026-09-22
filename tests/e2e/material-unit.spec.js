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
    await page.goto('/real-cb-new-v9130-fix2.html?mode=TEST&v=610');
    await expect(page.locator('#bootMsg')).toBeHidden({ timeout: 30_000 });
    await page.locator('#addMaterial').click();
    const material = page.locator('#materialList [data-m="1"]');
    await expect(material.locator('.unitSelect')).toHaveValue('PCS');
    await material.locator('.newMaterial').click();
    await expect(page.locator('#cbMaterialModal')).toBeVisible();
    await expect(page.locator('#cbNewPurchaseUnit')).toHaveValue('PCS');

    await page.locator('#cbNewPurchaseUnit').selectOption('__NEW_UNIT__');
    await expect(page.locator('#cbUnitModal')).toBeVisible();
    await page.locator('#cbNewUnitName').fill(unitName);
    // Unit Code is canonically normalized from Unit Name. Re-entering it here
    // races the app-wide mobile fill helper and does not model the user flow.
    await expect(page.locator('#cbNewUnitCode')).toHaveValue(unitCode);
    await page.locator('#saveCbUnit').click();
    await expect(page.locator('#cbUnitModal')).toBeHidden({ timeout: 15_000 });
    await expect(page.locator('#cbNewPurchaseUnit')).toHaveValue(unitCode);
    await page.locator('#cbNewStockUnit').selectOption(unitCode);
    await page.locator('#cbNewConsumptionUnit').selectOption(unitCode);
    await page.locator('#cbNewMaterialName').fill(materialName);
    await page.locator('#saveCbMaterial').click();
    await expect(page.locator('#cbMaterialModal')).toBeHidden({ timeout: 20_000 });
    await expect(material.locator('.cat')).toHaveValue(/.+/);
    await expect(material.locator('.unitSelect')).toHaveValue(unitCode);

    const materialArgs = {
      p_type_code: 'OTHER_MATERIAL', p_material_name: materialName, p_material_no: null,
      p_purchase_unit: unitCode, p_stock_unit: unitCode, p_purchase_to_stock: 1,
      p_consumption_unit: unitCode, p_consumption_to_stock: 1,
      p_consumption_basis: 'MANUAL', p_consumption_per_good_piece: null,
      p_auto_consumption_event: null, p_preferred_supplier_ledger_id: null,
      p_applicable_to: { source: 'CB_DEPARTMENT_E2E' }
    };
    const materialRetry1 = await rpc(page, 'rr_material_create_v805_31', materialArgs);
    const materialRetry2 = await rpc(page, 'rr_material_create_v805_31', materialArgs);
    expect(materialRetry1.error).toBeNull();
    expect(materialRetry2.error).toBeNull();
    expect(materialRetry2.data).toBe(materialRetry1.data);

    // Retry/double-tap and close spelling both resolve safely to existing Units.
    const retry = await rpc(page, 'rr_unit_master_create_v606', { p_unit_name: unitName, p_unit_code: unitCode });
    expect(retry.error).toBeNull();
    expect(retry.data).toMatchObject({ created: false, existing_match: true });
    expect(retry.data.unit.unit_code).toBe(unitCode);
    const alias = await rpc(page, 'rr_unit_master_create_v606', { p_unit_name: 'Metres', p_unit_code: 'METRE' });
    expect(alias.error).toBeNull();
    expect(alias.data).toMatchObject({ created: false, existing_match: true });
    expect(alias.data.unit.unit_code).toBe('MTR');

    // The existing Material Master reads the same canonical identity after reload.
    await page.goto('/real-material-master-v805.html?mode=TEST&v=610');
    await expect(page.locator('#who')).toContainText(/Super Admin|OWNER/i, { timeout: 30_000 });
    await page.locator('#type').selectOption('OTHER_MATERIAL');
    await page.locator('#name').fill(materialName);
    await expect(page.locator('#suggestions .suggestion')).toHaveCount(1, { timeout: 15_000 });
    await page.locator('#suggestions .suggestion').first().click();
    await expect(page.locator('#purchaseUnit')).toHaveValue(unitCode);

    // A fresh CB projection reads the linked category and allows an authorized Unit override.
    await page.goto('/real-cb-new-v9130-fix2.html?mode=TEST&v=610');
    await expect(page.locator('#bootMsg')).toBeHidden({ timeout: 30_000 });
    await page.locator('#addMaterial').click();
    const freshMaterial = page.locator('#materialList [data-m="1"]');
    await freshMaterial.locator('.cat').selectOption({ label: materialName });
    await expect(freshMaterial.locator('.unitSelect')).toHaveValue(unitCode);
    await freshMaterial.locator('.reqState').selectOption('DUE');
    await expect(freshMaterial.locator('.materialQty')).toHaveValue('');

    const backendProof = await rpc(page, 'rr_test_cb_material_unit_v610');
    expect(backendProof.error).toBeNull();
    expect(backendProof.data).toMatchObject({
      exact_invariant: true, rolled_back: true, fixture_residue: 0,
      additional_unit: 'MTR', additional_state: 'DUE', same_action_audits: 1
    });

    // Real Chat renderer uses the same unit field without a second selector.
    await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST&v=610');
    await page.waitForFunction(() => typeof window.__TEST70_REAL_CHAT__?.renderCbDepartmentCard === 'function');
    const rendered = await page.evaluate(({ materialName, unitCode }) => window.__TEST70_REAL_CHAT__.renderCbDepartmentCard({
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
