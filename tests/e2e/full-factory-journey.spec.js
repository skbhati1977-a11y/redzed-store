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

async function waitForForm(page, { allowReadOnlyHistory = false } = {}) {
  await expect(page.locator('#actionSheet')).toBeVisible();
  const form = page.frameLocator('#actionFrame');
  await expect(form.locator('#cbForm')).toBeVisible({ timeout: 30_000 });
  if (allowReadOnlyHistory) {
    await expect(form.locator('#bootMsg')).toContainText(/SENT TO CUTTING.*Read-only history/i, { timeout: 30_000 });
  } else {
    await expect(form.locator('#bootMsg')).toBeHidden({ timeout: 30_000 });
  }
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

async function completeArtDecisions(page, fixture) {
  for (let completed = 0; completed < fixture.divisions; completed += 1) {
    const current = await lookupCb(page, fixture.cbNo);
    if (current.detail.state === 'CLOSE') break;
    await openCbGroup(page, 'WORKING');
    const card = page.locator(`[data-cb-no="${fixture.cbNo}"]`);
    await expect(card).toBeVisible({ timeout: 30_000 });
    const action = card.locator('[data-action="ART_DECISION"]').first();
    await expect(action).toBeVisible();
    await action.click();
    await expect(page.locator('#actionSheet')).toBeVisible();
    const art = page.frameLocator('#actionFrame');
    await expect(art.locator('#decisionSheet')).not.toHaveClass(/hidden/, { timeout: 30_000 });
    await art.locator('#picker .pick').first().click();
    await art.locator('#decisionNext').click();
    await expect(art.locator('[data-step="print"]')).toHaveClass(/active/);
    await art.locator('#decisionNext').click();
    await expect(art.locator('[data-step="sticker"]')).toHaveClass(/active/);
    await art.locator('#decisionNext').click();
    await expect(art.locator('[data-step="metal"]')).toHaveClass(/active/);
    await art.locator('#decisionNext').click();
    await expect(page.locator('#actionSheet')).toBeHidden({ timeout: 60_000 });
  }

  const snapshot = await lookupCb(page, fixture.cbNo);
  expect(snapshot.detail.state).toBe('CLOSE');
  await openCbGroup(page, 'WORKING');
  await expect(page.locator(`[data-cb-no="${fixture.cbNo}"]`)).toHaveCount(0);
  await page.locator('[data-chat-status="CLOSE"]').click();
  const closed = page.locator(`[data-cb-no="${fixture.cbNo}"]`);
  await expect(closed).toBeVisible();
  await expect(closed).toContainText('CB Status CLOSE');
  if (fixture.material === 'due-rope') await expect(closed).toContainText(/Cutting Status HOLD · 1 MATERIAL DUE/i);
  else await expect(closed).toContainText(/Cutting Status READY FOR CUTTING/i);
}

async function confirmRetainedDueMaterial(page, fixture) {
  const before = await lookupCb(page, fixture.cbNo);
  expect(before.detail.state).toBe('CLOSE');
  const dueBefore = before.detail.entries.filter((row) => row.state === 'DUE');
  if (!dueBefore.length) return { resumed: true, materialId: null };
  expect(dueBefore).toHaveLength(1);

  await openCbGroup(page, 'CLOSE');
  const closed = page.locator(`[data-cb-no="${fixture.cbNo}"]`);
  await expect(closed).toBeVisible();
  await closed.locator('summary').click();
  const edit = closed.locator('[data-action="CB_EDIT"]');
  await expect(edit).toContainText(/UPDATE DUE MATERIAL/i);
  await edit.click();
  const form = await waitForForm(page, { allowReadOnlyHistory: true });
  const material = form.locator('#materialList [data-m="1"]');
  await expect(material.locator('.reqState')).toHaveValue('DUE');
  await material.locator('.reqState').selectOption('CONFIRMED');
  await material.locator('.materialQty').fill('250');
  await material.locator('.vendor').fill(SUPPLIER);
  await material.locator('.fabric').fill(ROPE);
  await material.locator('.bill').fill('TEST71-C-DUE-260922');
  await material.locator('.date').fill(new Date().toISOString().slice(0, 10));
  await material.locator('.rate').fill('5');
  const saveBody = await saveForm(page, form, false);
  const after = await lookupCb(page, fixture.cbNo);
  expect(after.row.id).toBe(before.row.id);
  expect(after.detail.state).toBe('CLOSE');
  expect(after.detail.entries.filter((row) => row.state === 'DUE')).toHaveLength(0);
  expect(after.detail.entries.find((row) => row.id === dueBefore[0].id)?.state).toBe('CONFIRMED');
  await retrySave(page, saveBody, before.row.id);
  const card = await assertSameCardFocus(page, fixture.cbNo);
  await expect(card).toContainText('CB Status CLOSE');
  await expect(card).toContainText(/Cutting Status READY FOR CUTTING/i);
  return { resumed: false, materialId: dueBefore[0].id };
}


async function cuttingChildren(page) {
  return page.evaluate(async (cbNos) => {
    const purchases = await window.supabaseClient.from('rr_fabric_purchases').select('id,cb_no').in('cb_no', cbNos);
    if (purchases.error) throw new Error(purchases.error.message);
    const out = [];
    for (const purchase of purchases.data || []) {
      const units = await window.supabaseClient.from('rr_cb_units').select('id,cb_code').eq('purchase_id', purchase.id).eq('is_final', true).eq('is_cutting_enabled', true).order('created_at');
      if (units.error) throw new Error(units.error.message);
      for (const unit of units.data || []) {
        const life = await window.supabaseClient.rpc('rr_cutting_child_lifecycle_v615', { p_cb_unit_id: unit.id });
        if (life.error) throw new Error(life.error.message);
        out.push({ fixture: purchase.cb_no, unit, lifecycle: life.data });
      }
    }
    return out;
  }, FIXTURES.map((x) => x.cbNo));
}

async function releaseRetainedCuttingChildren(page) {
  const before = await cuttingChildren(page);
  expect(before).toHaveLength(5);
  for (const child of before) {
    if (child.lifecycle.state === 'RELEASED') continue;
    expect(child.lifecycle.state).toBe('READY_FOR_CUTTING');
    await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST&rc_status=WORKING&rc_view=workflow&rc_id=2%3A0');
    await expect(page.locator('#chatName')).toContainText(/Ready \/ Release \/ All Lot/i, { timeout: 30_000 });
    let card = page.locator('#messages .work-card').filter({ hasText: child.unit.cb_code }).first();
    if (!await card.isVisible().catch(() => false)) {
      // Existing V113 Cutting projection places unassigned release cards in OPEN.
      await page.locator('[data-chat-status="OPEN"]').click();
      card = page.locator('#messages .work-card').filter({ hasText: child.unit.cb_code }).first();
    }
    await expect(card).toBeVisible({ timeout: 30_000 });
    const single = card.locator('a[data-action="CUTTING_SINGLE_LOT"], a:has-text("SINGLE LOT")').first();
    const multi = card.locator('a[data-action="CUTTING_MULTI_LOT"], a:has-text("MULTI LOT")').first();
    const action = await single.isVisible().catch(() => false) ? single : multi;
    await expect(action).toBeVisible();
    await action.click();
    await expect(page.locator('#actionSheet')).toBeVisible();
    await expect(page.locator('#actionFrame')).toHaveAttribute('src', /real-cutting-master\.html/);
    const form = page.frameLocator('#actionFrame');
    // The canonical cb_unit_id deep link opens the requested Single/Multi form.
    await expect(form.locator('#lotSheet')).not.toHaveClass(/cm-hidden/, { timeout: 60_000 });
    // Normal Cutting Master requires a manual permanent Lot identity.
    const lotNo = `TEST71-${Date.now().toString(36).toUpperCase()}-${Math.random().toString(36).slice(2, 7).toUpperCase()}`;
    const existing = await page.evaluate(async (lot) => {
      for (const table of ['rr_cutting_lots_v3', 'rr_production_lots', 'rr_upm_lot_registry']) {
        const result = await window.supabaseClient.from(table).select('lot_no').eq('lot_no', lot).limit(1);
        if (result.error) throw new Error(result.error.message);
        if (result.data.length) return true;
      }
      return false;
    }, lotNo);
    expect(existing, `Lot ${lotNo} must be unique`).toBe(false);
    const manualLot = form.locator('#cmManualLotNo');
    if (await manualLot.isVisible()) await manualLot.fill(lotNo);
    else throw new Error('Multi Lot needs separate manually entered Lot numbers and quantities');
    // Colour total must equal its existing size quantities.
    const colours = form.locator('#cuttingMatrix .cm-colour-cut-card');
    for (let n = 0; n < await colours.count(); n += 1) {
      const colour = colours.nth(n);
      const sizes = colour.locator('.cm-size-qty');
      let total = 0;
      for (let i = 0; i < await sizes.count(); i += 1) {
        const size = sizes.nth(i);
        if (!Number(await size.inputValue() || 0)) await size.fill('1');
        total += Number(await size.inputValue());
      }
      expect(total, 'Fixture size quantities must be positive').toBeGreaterThan(0);
      await colour.locator('.cm-colour-total').fill(String(total));
    }
    expect(Number(await form.locator('#cmPieceBalance').innerText())).toBe(0);
    expect(Number(await form.locator('#baseCost').inputValue())).toBeGreaterThan(0);
    await form.locator('#releaseLotBtn').click();
    await expect.poll(async () => (await cuttingChildren(page)).find(x => x.unit.id === child.unit.id)?.lifecycle.state, { timeout: 60_000 }).toBe('RELEASED');
  }
  return cuttingChildren(page);
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

  // Resume retained canonical children without replaying completed CB actions.
  const before = [];
  for (const fixture of FIXTURES) {
    const found = await lookupCb(page, fixture.cbNo);
    expect(found, `Retained CB ${fixture.cbNo} is required`).toBeTruthy();
    expect(found.detail.entries.filter((row) => row.state === 'DUE')).toHaveLength(0);
    before.push({ cbNo: fixture.cbNo, cb_id: found.row.id, state: found.detail.state });
  }
  const ready = await cuttingChildren(page);
  expect(ready).toHaveLength(5);
  for (const child of ready) {
    expect(child.lifecycle.material_due_count).toBe(0);
    expect(['READY_FOR_CUTTING', 'RELEASED']).toContain(child.lifecycle.state);
  }
  const cutting = await releaseRetainedCuttingChildren(page);
  expect(cutting.every((x) => x.lifecycle.state === 'RELEASED')).toBe(true);
  // Inspect the next real production card for the same released Lot.
  const firstLot = cutting.flatMap(x => x.lifecycle.lots || [])[0]?.lot_no;
  expect(firstLot).toBeTruthy();
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST&rc_status=OPEN&rc_view=chat&rc_kind=group&rc_id=STITCHING');
  await expect(page.locator('#chatName')).toContainText(/STITCHING/i, { timeout: 30_000 });
  await page.locator('#chatFind').fill(firstLot);
  await page.locator('#chatFind').press('Enter');
  const productionCard = await page.locator('#messages').innerText();
  await testInfo.attach('first-production-real-chat-card.json', {
    body: Buffer.from(JSON.stringify({ firstLot, productionCard }, null, 2)),
    contentType: 'application/json'
  });
  expect(productionCard).toContain(firstLot);
  const assignCard = page.locator('#messages .work-card').filter({ hasText: firstLot }).first();
  await expect(assignCard).toBeVisible();
  const assignAction = assignCard.locator('[data-assign-action]').first();
  await expect(assignAction).toBeVisible();
  await assignAction.click();
  await expect(page.locator('#actionSheet')).toBeVisible();
  const department = page.frameLocator('#actionFrame');
  await expect(department.locator('#rfAssignModal')).toBeVisible({ timeout: 60_000 });
  const workerOptions = await department.locator('#rfWorker option').allTextContents();
  await testInfo.attach('first-production-worker-options.json', {
    body: Buffer.from(JSON.stringify({ firstLot, workerOptions }, null, 2)),
    contentType: 'application/json'
  });
  await department.locator('#rfAll').check();
  const worker = department.locator('#rfWorker option[value]:not([value=""])').first();
  const workerId = await worker.getAttribute('value');
  expect(workerId, 'Canonical department worker required').toBeTruthy();
  await department.locator('#rfWorker').selectOption(workerId);
  await department.locator('#rfDoAssign').click();
  await expect(page.locator('#actionSheet')).toBeHidden({ timeout: 60_000 });
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
  expect(runtimeErrors).toEqual([]);

  await testInfo.attach('checkpoint-1-three-cb-evidence.json', {
    body: Buffer.from(JSON.stringify({ exact_preview_origin: new URL(page.url()).origin, before, cutting }, null, 2)),
    contentType: 'application/json'
  });
  await testInfo.attach('checkpoint-1-three-cb-working-mobile.png', {
    body: await page.screenshot({ fullPage: true }),
    contentType: 'image/png'
  });
});
