const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const r = await window.supabaseClient.rpc(name, args);
    return { data: r.data, error: r.error && { message: r.error.message, code: r.error.code } };
  }, { name, args });
}

test.beforeEach(async ({ page }) => {
  await ensureSession(page);
  await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test.afterEach(async ({ page }) => {
  if (!page.isClosed()) await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test('canonical CB draft, confirm, DUE completion and retry proof roll back', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_cb_department_flow_v600');
  expect(proof.error).toBeNull();
  expect(proof.data).toMatchObject({
    open_to_working: true,
    due_survived_confirm: true,
    rolled_back: true,
    persisted: false
  });
  expect(proof.data.retry.duplicate_blocked).toBe(true);
  expect(proof.data.confirm.state).toBe('WORKING');
  expect(proof.data.working_card.pending_material_count).toBe(2);
  expect(proof.data.counts).toMatchObject({
    cb_rows: 1,
    regular_rows: 1,
    material_rows: 2,
    roll_rows: 1,
    due_rows: 1,
    zip_confirmed: true
  });
});

test('CB 1004 remains read-only while backend and frontend projections agree', async ({ page }) => {
  const snapshot = await rpc(page, 'rr_test_cb_snapshot_v608', { p_cb_no: '1004' });
  expect(snapshot.error).toBeNull();
  expect(snapshot.data.read_only).toBe(true);
  expect(snapshot.data.found_count).toBeGreaterThan(0);

  const evidence = [];
  for (const row of snapshot.data.rows) {
    expect(row.frontend_detail.cb_id).toBe(row.cb_id);
    expect(row.frontend_detail.cb_no).toBe(row.cb_no);
    const projectedById = new Map(row.frontend_detail.entries.map((entry) => [entry.id, entry]));
    for (const raw of row.entries) {
      const projected = projectedById.get(raw.id);
      expect(projected, `missing projected purchase entry ${raw.id}`).toBeTruthy();
      expect(Number(projected.qty)).toBe(Number(raw.quantity));
      expect(Number(projected.rate)).toBe(Number(raw.rate));
      expect(Number(projected.amount)).toBe(Number(raw.amount));
      expect(projected.rolls.map((roll) => ({
        colour: Number(roll.colour_index),
        roll: Number(roll.roll_no),
        qty: Number(roll.qty)
      }))).toEqual(raw.rolls.map((roll) => ({
        colour: Number(roll.colour_no),
        roll: Number(roll.roll_no),
        qty: Number(roll.quantity)
      })));
    }
    evidence.push({
      cb_id: row.cb_id,
      cb_no: row.cb_no,
      state: row.department_state,
      division_count: row.division_count,
      colour_count: row.colour_count,
      entries: row.entries.map((entry) => ({
        id: entry.id,
        quantity: entry.quantity,
        rate: entry.rate,
        amount: entry.amount,
        rolls: entry.rolls.map((roll) => ({
          id: roll.id,
          colour_no: roll.colour_no,
          roll_no: roll.roll_no,
          quantity: roll.quantity
        }))
      }))
    });
  }
  console.log('CB1004_READ_ONLY_EVIDENCE', JSON.stringify(evidence));
});

test('Roll 1 Qty 120, Rate 365 and Value 43800 survive repeated Draft Save without residue', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_cb_open_draft_invariants_v608');
  expect(proof.error).toBeNull();
  expect(proof.data).toMatchObject({
    exact_invariant: true,
    natural_duplicate_blocked: true,
    rolled_back: true,
    fixture_residue: 0
  });
  expect(proof.data.retry.duplicate_blocked).toBe(true);
  expect(proof.data.counts).toMatchObject({
    cb_rows: 1,
    regular_rows: 1,
    roll_rows: 1,
    roll1_rows: 1,
    roll2_rows: 0,
    quantity: 120,
    rate: 365,
    amount: 43800,
    same_action_audits: 1
  });
});

test('deployed mobile hydration and sticky-footer invariants are exact', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/real-cb-new-v9130-fix2.html?mode=TEST&v=608');
  await page.waitForFunction(() => Boolean(window.__CB_DEPARTMENT_TEST__));
  await expect(page.locator('#bootMsg')).toBeHidden({ timeout: 30_000 });
  const preview = await page.evaluate(() => window.__CB_DEPARTMENT_TEST__.draftInvariantPreview({
    division_count: 2,
    colour_count: 1,
    entries: [{
      entry_notes: 'Regular Cloth',
      qty: 120,
      rate: 365,
      amount: 43800,
      rolls: [{ colour_index: 1, roll_no: 1, qty: 120 }]
    }]
  }));
  expect(preview).toMatchObject({
    qty: 120,
    rate: 365,
    value: 43800,
    storedValue: 43800,
    roll1: 120,
    roll2: ''
  });
  expect(preview.rolls[0]).toHaveLength(2);

  await page.evaluate(() => {
    window.__CB_DEPARTMENT_TEST__.showMessage('Draft saved · remains OPEN', true);
  });
  await expect.poll(async () => page.evaluate(() => {
    const message = document.querySelector('#msg').getBoundingClientRect();
    const footer = document.querySelector('.actions').getBoundingClientRect();
    return message.bottom < footer.top - 4;
  }), { timeout: 5_000 }).toBe(true);
  const layout = await page.evaluate(() => {
    const message = document.querySelector('#msg').getBoundingClientRect();
    const footer = document.querySelector('.actions').getBoundingClientRect();
    const main = getComputedStyle(document.querySelector('main'));
    return {
      messageBottom: message.bottom,
      footerTop: footer.top,
      mainPaddingBottom: parseFloat(main.paddingBottom),
      bodyWidth: document.body.scrollWidth,
      viewportWidth: document.documentElement.clientWidth
    };
  });
  expect(layout.messageBottom).toBeLessThan(layout.footerTop - 4);
  expect(layout.mainPaddingBottom).toBeGreaterThan(120);
  expect(layout.bodyWidth).toBeLessThanOrEqual(layout.viewportWidth + 2);
});

test('CB Department is the visible mobile directory while PURCHASE stays canonical', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await expect(page.locator('#state')).toContainText(/departments · .* people/, { timeout: 30_000 });
  const department = page.locator('[data-department="PURCHASE"]');
  await expect(department).toContainText('CB Department');
  await department.click();
  await expect(page.locator('[data-dept-group="PURCHASE"]')).toContainText('CB Department');
  await page.locator('[data-dept-group="PURCHASE"]').click();
  await expect(page.locator('#chatName')).toContainText('CB Department');
  await expect(page.locator('#contextAction')).toContainText(/NEW CB/i);
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
});

test('Act As Worker cannot mutate CB purchase or material state', async ({ page }) => {
  const directory = await rpc(page, 'rr_real_chat_directory_v600');
  expect(directory.error).toBeNull();
  const worker = directory.data.people.find((x) => String(x.role_code).toUpperCase() === 'WORKER');
  expect(worker).toBeTruthy();
  const acting = await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: worker.worker_id });
  expect(acting.error).toBeNull();
  const denied = await rpc(page, 'rr_cb_department_save_v600', {
    p_cb_id: null,
    p_action_id: crypto.randomUUID(),
    p_confirm: false,
    p_payload: { cb_no: 'TEST71-UNAUTHORIZED', division_count: 1, colour_count: 1 }
  });
  expect(denied.error).not.toBeNull();
  expect(denied.error.message).toMatch(/Owner\/Admin authority/i);
});
