const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

const FIXTURES = [
  { key: 'A', cbNo: 'TEST71F-A-260922', divisions: 1, colours: 1, material: 'rope' },
  { key: 'B', cbNo: 'TEST71F-B-260922', divisions: 3, colours: 2, material: 'strap' },
  { key: 'C', cbNo: 'TEST71F-C-260922', divisions: 1, colours: 1, material: 'due-rope' }
];
const ROPE = 'TEST71 Rope 260922';
const STRAP = 'TEST71 Strap 260922';
const UNIT_NAME = 'TEST71 Coil 260922';
const UNIT_CODE = 'TEST71_COIL_260922';
const SUPPLIER = 'TEST71 Supplier 260922';
const FABRIC = 'TEST71 Regular Cloth 260922';

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

async function installDeterministicCamera(page) {
  await page.addInitScript(() => {
    const getUserMedia = async () => {
      const canvas = document.createElement('canvas');
      canvas.width = 640;
      canvas.height = 640;
      const context = canvas.getContext('2d');
      context.fillStyle = '#8f2942';
      context.fillRect(0, 0, canvas.width, canvas.height);
      context.fillStyle = '#f7e6c4';
      context.font = 'bold 56px sans-serif';
      context.fillText('TEST71', 205, 330);
      return canvas.captureStream(5);
    };
    const mediaDevices = navigator.mediaDevices || {};
    Object.defineProperty(mediaDevices, 'getUserMedia', { configurable: true, value: getUserMedia });
    if (!navigator.mediaDevices) Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: mediaDevices });
  });
}

async function lookupCb(page, cbNo) {
  return page.evaluate(async (name) => {
    const rows = await window.supabaseClient.from('rr_fabric_purchases')
      .select('id,cb_no,operation_status,status,created_at')
      .eq('cb_no', name)
      .order('created_at', { ascending: true });
    if (rows.error) throw new Error(rows.error.message);
    if ((rows.data || []).length > 1) throw new Error(`Duplicate CB identity: ${name}`);
    if (!rows.data?.[0]) return null;
    const detail = await window.supabaseClient.rpc('rr_cb_department_detail_v600', { p_cb_id: rows.data[0].id });
    if (detail.error) throw new Error(detail.error.message);
    return { row: rows.data[0], detail: detail.data };
  }, cbNo);
}

async function openCbGroup(page, status = 'OPEN') {
  await page.goto(`/test70-cb-purchase-real-chat-pilot.html?mode=TEST&rc_status=${status}&rc_view=chat&rc_kind=group&rc_id=PURCHASE`);
  await expect(page.locator('#chatName')).toContainText('CB Department', { timeout: 30_000 });
  await expect(page.locator(`[data-chat-status="${status}"]`)).toHaveClass(/on/);
  await expect(page).toHaveURL(/rc_view=chat/);
  await expect(page).toHaveURL(/rc_id=PURCHASE/);
}

async function waitForForm(page) {
  await expect(page.locator('#actionSheet')).toBeVisible();
  const form = page.frameLocator('#actionFrame');
  await expect(form.locator('#cbForm')).toBeVisible({ timeout: 30_000 });
  await expect(form.locator('#bootMsg')).toBeHidden({ timeout: 30_000 });
  return form;
}

async function openNewCb(page) {
  await openCbGroup(page, 'OPEN');
  await expect(page.locator('#contextAction')).toContainText(/NEW CB/i);
  await page.locator('#contextAction').click();
  return waitForForm(page);
}

async function openCbEdit(page, cbNo, status = 'OPEN') {
  await openCbGroup(page, status);
  const card = page.locator(`[data-cb-no="${cbNo}"]`);
  await expect(card).toBeVisible({ timeout: 30_000 });
  await card.locator('[data-action="CB_EDIT"]').click();
  return waitForForm(page);
}

async function fillRegular(form, fixture) {
  await form.locator('#cbNo').fill(fixture.cbNo);
  await form.locator('#divisionCount').fill(String(fixture.divisions));
  await form.locator('#colourCount').fill(String(fixture.colours));
  const regular = form.locator('#materialList [data-m="0"]');
  await regular.locator('.vendor').fill(SUPPLIER);
  await regular.locator('.fabric').fill(FABRIC);
  await regular.locator('.materialQty').fill('365');
  await regular.locator('.bill').fill(`${fixture.cbNo}-BILL`);
  await regular.locator('.date').fill(new Date().toISOString().slice(0, 10));
  await regular.locator('.rate').fill('120');
  await form.locator('#colourList [data-c="0"] [data-ri="0"] .qty').fill('120');
  await form.locator('#remarks').fill(`TEST71 FULL FACTORY ${fixture.key} · isolated retained canonical history`);
}

async function createRopeMaterial(form) {
  await form.locator('#addMaterial').click();
  let row = form.locator('#materialList [data-m="1"]');
  await row.locator('.newMaterial').click();
  await expect(form.locator('#cbMaterialModal')).toBeVisible();
  await expect(form.locator('#cbNewPurchaseUnit')).toHaveValue('PCS');
  await form.locator('#cbNewMaterialName').fill(ROPE);
  await form.locator('#saveCbMaterial').click();
  await expect(form.locator('#cbMaterialModal')).toBeHidden({ timeout: 30_000 });
  row = form.locator('#materialList [data-m="1"]');
  await expect(row.locator('.unitSelect')).toHaveValue('PCS');
  await row.locator('.unitSelect').selectOption('MTR');
  await row.locator('.reqState').selectOption('CONFIRMED');
  row = form.locator('#materialList [data-m="1"]');
  await row.locator('.materialQty').fill('250');
  await row.locator('.vendor').fill(SUPPLIER);
  await row.locator('.fabric').fill(ROPE);
  await row.locator('.bill').fill('TEST71-ROPE-260922');
  await row.locator('.date').fill(new Date().toISOString().slice(0, 10));
  await row.locator('.rate').fill('5');
}

async function createStrapWithUnit(form) {
  await form.locator('#addMaterial').click();
  let row = form.locator('#materialList [data-m="1"]');
  await row.locator('.newMaterial').click();
  await expect(form.locator('#cbMaterialModal')).toBeVisible();
  await expect(form.locator('#cbNewPurchaseUnit')).toHaveValue('PCS');
  await form.locator('#cbNewPurchaseUnit').selectOption('__NEW_UNIT__');
  await expect(form.locator('#cbUnitModal')).toBeVisible();
  await form.locator('#cbNewUnitName').fill(UNIT_NAME);
  await expect(form.locator('#cbNewUnitCode')).toHaveValue(UNIT_CODE);
  await form.locator('#saveCbUnit').click();
  await expect(form.locator('#cbUnitModal')).toBeHidden({ timeout: 30_000 });
  await expect(form.locator('#cbNewPurchaseUnit')).toHaveValue(UNIT_CODE);
  await form.locator('#cbNewStockUnit').selectOption(UNIT_CODE);
  await form.locator('#cbNewConsumptionUnit').selectOption(UNIT_CODE);
  await form.locator('#cbNewMaterialName').fill(STRAP);
  await form.locator('#saveCbMaterial').click();
  await expect(form.locator('#cbMaterialModal')).toBeHidden({ timeout: 30_000 });
  row = form.locator('#materialList [data-m="1"]');
  await expect(row.locator('.unitSelect')).toHaveValue(UNIT_CODE);
  await row.locator('.reqState').selectOption('CONFIRMED');
  row = form.locator('#materialList [data-m="1"]');
  await row.locator('.materialQty').fill('50');
  await row.locator('.vendor').fill(SUPPLIER);
  await row.locator('.fabric').fill(STRAP);
  await row.locator('.bill').fill('TEST71-STRAP-260922');
  await row.locator('.date').fill(new Date().toISOString().slice(0, 10));
  await row.locator('.rate').fill('8');
}

async function addDueRope(form) {
  await form.locator('#addMaterial').click();
  let row = form.locator('#materialList [data-m="1"]');
  await row.locator('.cat').selectOption({ label: ROPE });
  await row.locator('.unitSelect').selectOption('MTR');
  await row.locator('.reqState').selectOption('DUE');
  row = form.locator('#materialList [data-m="1"]');
  await expect(row.locator('.materialQty')).toHaveValue('');
  await expect(row.locator('.unitSelect')).toHaveValue('MTR');
}

async function configureNewForm(form, fixture) {
  await fillRegular(form, fixture);
  if (fixture.material === 'rope') await createRopeMaterial(form);
  if (fixture.material === 'strap') await createStrapWithUnit(form);
  if (fixture.material === 'due-rope') await addDueRope(form);
}

async function saveForm(page, form, confirming) {
  const requestPromise = page.waitForRequest((request) =>
    request.method() === 'POST' && request.url().includes('/rest/v1/rpc/rr_cb_department_save_v600')
  );
  await (confirming ? form.locator('#saveBtn') : form.locator('#draftBtn')).click();
  const request = await requestPromise;
  const body = request.postDataJSON();
  await expect(page.locator('#actionSheet')).toBeHidden({ timeout: 90_000 });
  return body;
}

async function assertSameCardFocus(page, cbNo) {
  const card = page.locator(`[data-cb-no="${cbNo}"]`);
  await expect(card).toBeVisible({ timeout: 30_000 });
  await expect.poll(() => card.evaluate((node) =>
    document.activeElement === node || node.classList.contains('search-card-focus')
  ), { timeout: 8_000 }).toBe(true);
  return card;
}

async function assertDraftInvariants(form, fixture) {
  const regular = form.locator('#materialList [data-m="0"]');
  await expect(form.locator('#cbNo')).toHaveValue(fixture.cbNo);
  await expect(regular.locator('.materialQty')).toHaveValue('365');
  await expect(regular.locator('.rate')).toHaveValue('120');
  await expect(regular.locator('.value')).toHaveValue('43800.00');
  await expect(form.locator('#colourList [data-c="0"] [data-ri="0"] .qty')).toHaveValue('120');
  const roll2 = form.locator('#colourList [data-c="0"] [data-ri="1"] .qty');
  if (fixture.divisions > 1) await expect(roll2).toHaveValue('');
  else await expect(roll2).toHaveCount(0);
  if (fixture.material === 'rope') {
    const material = form.locator('#materialList [data-m="1"]');
    await expect(material.locator('.unitSelect')).toHaveValue('MTR');
    await expect(material.locator('.materialQty')).toHaveValue('250');
  }
  if (fixture.material === 'due-rope') {
    const material = form.locator('#materialList [data-m="1"]');
    await expect(material.locator('.reqState')).toHaveValue('DUE');
    await expect(material.locator('.materialQty')).toHaveValue('');
  }
}

async function captureColourPhotos(form, count) {
  for (let index = 0; index < count; index += 1) {
    const colour = form.locator(`#colourList [data-c="${index}"]`);
    await colour.locator('.liveCam').click();
    await expect(form.locator('#cameraModal')).toBeVisible();
    await expect.poll(() => form.locator('#cameraVideo').evaluate((video) => video.videoWidth), { timeout: 15_000 })
      .toBeGreaterThan(0);
    await form.locator('#capturePhoto').click();
    await expect(form.locator('#savePhoto')).toBeVisible({ timeout: 15_000 });
    await form.locator('#savePhoto').click();
    await expect(form.locator('#cameraModal')).toBeHidden({ timeout: 15_000 });
    await expect(colour.locator('.photo-ok')).toContainText('Photo Saved');
  }
}

async function retrySave(page, body, expectedId) {
  const retry = await rpc(page, 'rr_cb_department_save_v600', body);
  expect(retry.error).toBeNull();
  expect(retry.data.cb_id).toBe(expectedId);
  expect(retry.data.duplicate_blocked).toBe(true);
}

async function proofSnapshot(page, cbNo) {
  const result = await rpc(page, 'rr_test_cb_snapshot_v608', { p_cb_no: cbNo });
  if (result.error) throw new Error(result.error.message);
  if (result.data?.found_count !== 1) throw new Error(`Expected one canonical CB proof row for ${cbNo}`);
  return result.data.rows[0];
}

async function draftAuditCount(page, cbNo) {
  const snapshot = await proofSnapshot(page, cbNo);
  return (snapshot.audit || []).filter((row) => row.action_code === 'DRAFT_SAVE').length;
}

async function createAndConfirm(page, fixture) {
  const existing = await lookupCb(page, fixture.cbNo);
  if (existing && existing.detail.state !== 'OPEN') return { resumed: true, cbId: existing.row.id };

  let form;
  let cbId = existing?.row.id || null;
  if (!existing) {
    form = await openNewCb(page);
    await configureNewForm(form, fixture);
  } else {
    form = await openCbEdit(page, fixture.cbNo, 'OPEN');
    await assertDraftInvariants(form, fixture);
  }

  let draftCount = cbId ? await draftAuditCount(page, fixture.cbNo) : 0;
  while (draftCount < 2) {
    const draftBody = await saveForm(page, form, false);
    const snapshot = await lookupCb(page, fixture.cbNo);
    expect(snapshot).toBeTruthy();
    expect(snapshot.detail.state).toBe('OPEN');
    cbId = snapshot.row.id;
    const card = await assertSameCardFocus(page, fixture.cbNo);
    await expect(card).toContainText('CB Status OPEN');
    await retrySave(page, draftBody, cbId);
    draftCount = await draftAuditCount(page, fixture.cbNo);
    if (draftCount < 2) {
      form = await openCbEdit(page, fixture.cbNo, 'OPEN');
      await assertDraftInvariants(form, fixture);
    }
  }

  form = await openCbEdit(page, fixture.cbNo, 'OPEN');
  await assertDraftInvariants(form, fixture);
  await captureColourPhotos(form, fixture.colours);
  const confirmBody = await saveForm(page, form, true);
  const card = await assertSameCardFocus(page, fixture.cbNo);
  await expect(card).toContainText('CB Status WORKING');
  await expect(card).toContainText(/ART DECISION|ART \/ COMBO DECISION/i);
  if (fixture.material === 'due-rope') await expect(card).toContainText(/DUE · Qty — MTR/i);
  await retrySave(page, confirmBody, cbId);

  await page.locator('[data-chat-status="OPEN"]').click();
  await expect(page.locator(`[data-cb-no="${fixture.cbNo}"]`)).toHaveCount(0);
  await page.locator('[data-chat-status="WORKING"]').click();
  await expect(page.locator(`[data-cb-no="${fixture.cbNo}"]`)).toBeVisible();
  return { resumed: Boolean(existing), cbId };
}

async function canonicalSnapshot(page, cbNo) {
  const row = await proofSnapshot(page, cbNo);
  return {
    purchase: {
      id: row.cb_id,
      cb_no: row.cb_no,
      cb_department_state: row.department_state,
      operation_status: row.operation_status,
      status: row.status,
      total_weight: row.total_weight,
      total_amount: row.total_amount
    },
    detail: row.frontend_detail,
    units: row.units || [],
    audit: row.audit || []
  };
}

test('three new TEST71 CBs complete deployed New/Open/Draft/Confirm invariants', async ({ page }, testInfo) => {
  test.setTimeout(12 * 60_000);
  const runtimeErrors = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  await installDeterministicCamera(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await ensureSession(page, { quiet: true });
  expect((await rpc(page, 'rr_test_clear_on_behalf_context_v176')).error).toBeNull();

  const before = [];
  for (const fixture of FIXTURES) {
    const found = await lookupCb(page, fixture.cbNo);
    if (found) {
      expect(found.detail.remarks).toBe(`TEST71 FULL FACTORY ${fixture.key} · isolated retained canonical history`);
      expect(String(found.row.operation_status || 'ACTIVE').toUpperCase()).toBe('ACTIVE');
    }
    before.push({ cbNo: fixture.cbNo, existing: Boolean(found), cb_id: found?.row.id || null, state: found?.detail.state || 'ABSENT' });
  }

  const results = [];
  for (const fixture of FIXTURES) results.push({ fixture, ...(await createAndConfirm(page, fixture)) });

  const unitRetry = await rpc(page, 'rr_unit_master_create_v606', { p_unit_name: UNIT_NAME, p_unit_code: UNIT_CODE });
  expect(unitRetry.error).toBeNull();
  expect(unitRetry.data).toMatchObject({ created: false, existing_match: true });
  const materialRetry = await rpc(page, 'rr_material_create_v805_31', {
    p_type_code: 'OTHER_MATERIAL', p_material_name: ROPE, p_material_no: null,
    p_purchase_unit: 'PCS', p_stock_unit: 'PCS', p_purchase_to_stock: 1,
    p_consumption_unit: 'PCS', p_consumption_to_stock: 1,
    p_consumption_basis: 'MANUAL', p_consumption_per_good_piece: null,
    p_auto_consumption_event: null, p_preferred_supplier_ledger_id: null,
    p_applicable_to: { source: 'CB_DEPARTMENT' }
  });
  expect(materialRetry.error).toBeNull();

  const evidence = [];
  for (const fixture of FIXTURES) {
    const snapshot = await canonicalSnapshot(page, fixture.cbNo);
    expect(snapshot.purchase.cb_department_state).toBe('WORKING');
    expect(Number(snapshot.purchase.total_weight)).toBe(365);
    expect(Number(snapshot.purchase.total_amount)).toBeGreaterThanOrEqual(43800);
    expect(snapshot.units).toHaveLength(fixture.divisions);
    expect(new Set(snapshot.audit.map((row) => row.action_id)).size).toBe(snapshot.audit.length);
    expect(snapshot.audit.filter((row) => row.action_code === 'DRAFT_SAVE')).toHaveLength(2);
    expect(snapshot.audit.filter((row) => row.action_code === 'SAVE_CONFIRM')).toHaveLength(1);
    const regular = snapshot.detail.entries.find((row) => String(row.entry_notes).toLowerCase() === 'regular cloth');
    expect(Number(regular.qty)).toBe(365);
    expect(Number(regular.rate)).toBe(120);
    expect(Number(regular.amount)).toBe(43800);
    expect(regular.rolls.filter((row) => Number(row.qty) > 0)).toHaveLength(1);
    expect(Number(regular.rolls.find((row) => Number(row.roll_no) === 1).qty)).toBe(120);
    if (fixture.material === 'due-rope') {
      const due = snapshot.detail.entries.find((row) => row.state === 'DUE');
      expect(due).toBeTruthy();
      expect(due.qty).toBeNull();
      expect(due.unit).toBe('MTR');
    }
    evidence.push({
      fixture: fixture.key,
      cb_no: fixture.cbNo,
      cb_id: snapshot.purchase.id,
      starting_state: 'NEW',
      expected_state: 'WORKING',
      actual_backend_state: snapshot.purchase.cb_department_state,
      divisions: snapshot.units.map((row) => ({ id: row.id, code: row.cb_code })),
      materials: snapshot.detail.entries.map((row) => ({ id: row.id, name: row.fabric_name, state: row.state, qty: row.qty, unit: row.unit })),
      actor: snapshot.audit[0] && { actual: snapshot.audit[0].actual_actor_id, effective: snapshot.audit[0].effective_actor_id, name: snapshot.audit[0].effective_name, role: snapshot.audit[0].effective_role },
      audit_actions: snapshot.audit.map((row) => ({ action_id: row.action_id, code: row.action_code, from: row.previous_state, to: row.new_state })),
      idempotency: 'same action payload retried; duplicate_blocked=true; one audit per action'
    });
  }

  await openCbGroup(page, 'WORKING');
  for (const fixture of FIXTURES) await expect(page.locator(`[data-cb-no="${fixture.cbNo}"]`)).toBeVisible();
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
  expect(runtimeErrors).toEqual([]);

  await testInfo.attach('checkpoint-1-three-cb-evidence.json', {
    body: Buffer.from(JSON.stringify({ exact_preview_origin: new URL(page.url()).origin, before, results, evidence }, null, 2)),
    contentType: 'application/json'
  });
  await testInfo.attach('checkpoint-1-three-cb-working-mobile.png', {
    body: await page.screenshot({ fullPage: true }),
    contentType: 'image/png'
  });
});
