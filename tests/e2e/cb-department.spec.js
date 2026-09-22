const { test, expect } = require('@playwright/test');
const { randomUUID } = require('node:crypto');
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

test('DUE allows Art, partial decisions stay actionable, retry is single, and completion projects immediately', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_cb_working_art_v611');
  expect(proof.error).toBeNull();
  expect(proof.data).toMatchObject({
    exact_invariant: true,
    rolled_back: true,
    fixture_residue: 0,
    partial_art_status: 'DUE',
    partial_action_count: 1,
    complete_art_status: 'COMPLETE',
    complete_action_count: 0,
    complete_message: 'CB COMPLETE · CUTTING HOLD · 1 MATERIAL DUE',
    assignment_rows: 1,
    due_rows: 1
  });
  expect(proof.data.confirm.state).toBe('WORKING');
  expect(proof.data.partial.assignment_id).toBe(proof.data.retry.assignment_id);
});

test('CB parent closes after Art while Cutting HOLD/READY remains separate and reversible proof leaves zero residue', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_cb_working_projection_v618');
  expect(proof.error).toBeNull();
  expect(proof.data).toMatchObject({
    exact_invariant: true,
    rolled_back: true,
    fixture_residue: 0,
    open_state: 'OPEN',
    initial_art_status: 'DUE',
    initial_art_actions: 2,
    mid_art_status: '1/2 COMPLETE',
    mid_art_actions: 1,
    ready_art_status: 'COMPLETE',
    ready_count: 2,
    ready_actions: 2,
    ready_message: 'CB COMPLETE · READY FOR CUTTING · 2 D CARDS',
    bridge_state: 'CLOSE',
    bridge_actions: 2,
    assignment_rows: 2
  });
  expect(proof.data.draft_retry.duplicate_blocked).toBe(true);
  expect(proof.data.open_cb_id).toBe(proof.data.draft.cb_id);
});

test('the seven read-only evidence CBs no longer remain in CB WORKING and mobile cards show both status dimensions', async ({ page }) => {
  const evidence = ['CB111TST', 'CBTST11', 'CB4TST', 'CB1TSTY', 'CB1MTC', '1002', 'TST1'];
  const states = await page.evaluate(async (names) => {
    const working = await window.supabaseClient.rpc('rr_cb_department_cards_v600', { p_state: 'WORKING', p_search: null });
    const close = await window.supabaseClient.rpc('rr_cb_department_cards_v600', { p_state: 'CLOSE', p_search: null });
    return {
      error: working.error?.message || close.error?.message || null,
      working: (working.data?.cards || []).filter((x) => names.includes(x.cb_no)),
      close: (close.data?.cards || []).filter((x) => names.includes(x.cb_no))
    };
  }, evidence);
  expect(states.error).toBeNull();
  expect(states.working).toHaveLength(0);
  expect(states.close.map((x) => x.cb_no).sort()).toEqual([...evidence].sort());
  for (const card of states.close) {
    expect(card.source_status).toBe('CLOSE');
    if (['CB111TST', 'CBTST11', 'CB1TSTY', 'CB1MTC'].includes(card.cb_no)) {
      expect(card.history_reason).toBe('INCOMPLETE_LEGACY_HISTORY');
      expect(card.message).toBe('INCOMPLETE LEGACY CB · READ-ONLY HISTORY');
      expect(card.available_child_count).toBe(0);
    } else {
      expect(card.art_status).toBe('COMPLETE');
      expect(card.cutting_ready_count + card.released_child_count).toBeGreaterThan(0);
    }
  }

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST&rc_status=CLOSE&rc_view=chat&rc_kind=group&rc_id=PURCHASE&rc_focus_cb=1002');
  await expect(page.locator('#chatName')).toContainText('CB Department', { timeout: 30_000 });
  const card = page.locator('[data-cb-no="1002"]');
  await expect(card).toBeVisible();
  await expect(card).toContainText('CB Status CLOSE');
  await expect(card).toContainText('Cutting Status READY FOR CUTTING');
  await expect(page.locator('#workFilters')).toBeHidden();
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
});

test('deployed mobile Art picker retains image/no-name records without mutating evidence', async ({ page }) => {
  const key = randomUUID();
  const fixture = await rpc(page, 'rr_test_cb_ui_fixture_v619', { p_action: 'SETUP', p_fixture_key: key });
  expect(fixture.error).toBeNull();
  const retry = await rpc(page, 'rr_test_cb_ui_fixture_v619', { p_action: 'SETUP', p_fixture_key: key });
  expect(retry.error).toBeNull();
  expect(retry.data.art_due_unit_id).toBe(fixture.data.art_due_unit_id);
  expect(retry.data.fixture_rows).toBe(1);
  try {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`/real-art-decide-master.html?mode=TEST&cb_unit_id=${encodeURIComponent(fixture.data.art_due_unit_id)}&v=619`);
    await expect(page.locator('#decisionSheet')).not.toHaveClass(/hidden/, { timeout: 30_000 });
    await expect(page.locator('#picker .pick').first()).toBeVisible();
    await expect(page.locator('#picker .pick-media').first()).toBeVisible();
    const layout = await page.evaluate(() => ({
      body: document.body.scrollWidth,
      viewport: document.documentElement.clientWidth,
      namedFallbacks: [...document.querySelectorAll('#picker .pick small')]
        .filter((node) => node.textContent.trim() === 'No Name').length,
      rows: document.querySelectorAll('#picker .pick').length
    }));
    expect(layout.rows).toBeGreaterThan(0);
    expect(layout.body).toBeLessThanOrEqual(layout.viewport + 2);
  } finally {
    const clean = await rpc(page, 'rr_test_cb_ui_fixture_v619', { p_action: 'CLEANUP', p_fixture_key: key });
    expect(clean.error).toBeNull();
    expect(clean.data.fixture_residue).toBe(0);
  }
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

test('Cutting lifecycle proof is canonical, retry-safe and rollback-only', async ({ page }) => {
  const proof = await rpc(page, 'rr_test_cutting_department_lifecycle_v615');
  expect(proof.error).toBeNull();
  expect(proof.data).toMatchObject({
    exact_invariant: true,
    rolled_back: true,
    fixture_residue: 0,
    due_release_blocked: true,
    release_retry_blocked: true,
    multi_request_final_status: 'CONSUMED',
    actionable_ready_count: 0,
    release_history_count: 1
  });
  expect(proof.data.art_due).toMatchObject({ state: 'ART_DUE', canonical_state: 'OPEN' });
  expect(proof.data.cutting_hold).toMatchObject({ state: 'CUTTING_HOLD', canonical_state: 'OPEN', material_due_count: 1 });
  expect(proof.data.ready).toMatchObject({ state: 'READY_FOR_CUTTING', canonical_state: 'WORKING', material_due_count: 0 });
  expect(proof.data.close).toMatchObject({ state: 'RELEASED', canonical_state: 'CLOSE' });
  expect(proof.data.request_retry.request_id).toBe(proof.data.request_first.request_id);
  expect(proof.data.request_retry.duplicate_blocked).toBe(true);
  expect(proof.data.decision_retry.duplicate_blocked).toBe(true);
});

test('TTT1-S2 read-only evidence is CLOSE and cannot resurrect a multi-art action', async ({ page }) => {
  const lookup = await page.evaluate(async () => {
    const unit = await window.supabaseClient.from('rr_cb_units').select('id,cb_code').eq('cb_code', 'TTT1-S2').maybeSingle();
    if (unit.error) return { error: unit.error.message };
    if (!unit.data) return { skipped: true };
    const lifecycle = await window.supabaseClient.rpc('rr_cutting_child_lifecycle_v615', { p_cb_unit_id: unit.data.id });
    const multi = await window.supabaseClient.rpc('rr_cutting_get_multi_art_decision_v1', { p_cb_unit_id: unit.data.id });
    const bridge = await window.supabaseClient.from('rr_real_chat_message_bridge_v70')
      .select('canonical_key,archived_at,archive_reason')
      .eq('source_event_type', 'MULTI_ART_DECISION_REQUIRED')
      .contains('personal_payload', { cb_unit_id: unit.data.id });
    return { unit: unit.data, lifecycle: lifecycle.data, multi: multi.data, bridge: bridge.data || [], error: lifecycle.error?.message || multi.error?.message || bridge.error?.message || null };
  });
  expect(lookup.error).toBeNull();
  test.skip(lookup.skipped, 'TTT1-S2 evidence is not present on this TEST database');
  expect(lookup.lifecycle).toMatchObject({ state: 'RELEASED', canonical_state: 'CLOSE' });
  expect(lookup.multi).toMatchObject({ status: 'RELEASED', ineligible: true });
  expect(lookup.bridge.filter((row) => row.archived_at === null)).toHaveLength(0);
});

test('mobile Cutting App opens exact Art child and Ready child remains WORKING after reload', async ({ page }) => {
  const key = randomUUID();
  const fixture = await rpc(page, 'rr_test_cb_ui_fixture_v619', { p_action: 'SETUP', p_fixture_key: key });
  expect(fixture.error).toBeNull();
  expect(fixture.data.art_due_lifecycle.state).toBe('ART_DUE');
  expect(fixture.data.ready_lifecycle.state).toBe('READY_FOR_CUTTING');
  try {
    const rows = { artDue: fixture.data.art_due_unit_id, ready: fixture.data.ready_unit_id };
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`/real-cutting-master.html?mode=TEST&cb_unit_id=${encodeURIComponent(rows.artDue)}&v=619`);
    const artAction = page.locator(`[data-art-decision="${rows.artDue}"]`);
    await expect(artAction).toBeVisible({ timeout: 30_000 });
    await artAction.click();
    await expect(page).toHaveURL(new RegExp(`real-art-decide-master\\.html.*cb_unit_id=${rows.artDue}`));
    await expect(page.locator('#decisionSheet')).not.toHaveClass(/hidden/, { timeout: 30_000 });

    await page.goto(`/real-cutting-master.html?mode=TEST&cb_unit_id=${encodeURIComponent(rows.ready)}&v=619`);
    await expect(page.locator('#lotSheet')).not.toHaveClass(/cm-hidden/, { timeout: 30_000 });
    await page.locator('#lotSheet [data-close-lot]').last().click();
    await expect(page.locator('.chip-ready')).toBeVisible({ timeout: 30_000 });
    await expect(page.locator(`[data-single="${rows.ready}"]`)).toBeEnabled();
    await page.reload();
    await expect(page.locator('#lotSheet')).not.toHaveClass(/cm-hidden/, { timeout: 30_000 });
    await page.locator('#lotSheet [data-close-lot]').last().click();
    await expect(page.locator('.chip-ready')).toBeVisible({ timeout: 30_000 });
    await expect(page.locator(`[data-single="${rows.ready}"]`)).toBeEnabled();
    const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
    expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
  } finally {
    const clean = await rpc(page, 'rr_test_cb_ui_fixture_v619', { p_action: 'CLEANUP', p_fixture_key: key });
    expect(clean.error).toBeNull();
    expect(clean.data.fixture_residue).toBe(0);
  }
});

test('Act As Worker is rejected by the shared Cutting backend authority gate', async ({ page }) => {
  const directory = await rpc(page, 'rr_real_chat_directory_v600');
  expect(directory.error).toBeNull();
  const worker = directory.data.people.find((x) => String(x.role_code).toUpperCase() === 'WORKER');
  expect(worker).toBeTruthy();
  const ready = await page.evaluate(async () => {
    const all = await window.supabaseClient.rpc('rr_pm_decision_filter_v802', { p_filter: 'ALL' });
    for (const row of all.data || []) {
      const state = await window.supabaseClient.rpc('rr_cutting_child_lifecycle_v615', { p_cb_unit_id: row.cb_unit_id });
      if (state.data?.state === 'READY_FOR_CUTTING') return row.cb_unit_id;
    }
    return null;
  });
  expect(ready).toBeTruthy();
  expect((await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: worker.worker_id })).error).toBeNull();
  const denied = await rpc(page, 'rr_cutting_request_multi_art_decision_v1', { p_cb_unit_id: ready });
  expect(denied.error).not.toBeNull();
  expect(denied.error.message).toMatch(/Cutting release authority required/i);
});
