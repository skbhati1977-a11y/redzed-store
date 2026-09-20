const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

const RECOVERY_2622 = '1f3cedd1-d5f3-42e3-b1f1-608eb806a72d';

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

async function people(page) {
  await ensureSession(page);
  const result = await rpc(page, 'rr_real_chat_directory_v85');
  expect(result.error).toBeNull();
  return result.data.people;
}

function named(rows, name) {
  const row = rows.find((x) => String(x.worker_name).trim().toLowerCase() === name.toLowerCase());
  expect(row, name).toBeTruthy();
  return row;
}

async function actAs(page, worker) {
  const result = await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: worker.worker_id });
  expect(result.error).toBeNull();
  return result.data;
}

test.beforeEach(async ({ page }) => { await ensureSession(page); });
test.afterEach(async ({ page }) => {
  if (page.isClosed()) return;
  await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
  await rpc(page, 'rr_test_checkpoint5_purchase_fixture_v330', { p_action: 'CLEANUP', p_worker_id: null }).catch(() => null);
});

test('Purchase staff Personal Chat mirrors one canonical OPEN/WORKING/CLOSE event', async ({ page }) => {
  const shailender = named(await people(page), 'shailender');
  const fixture = await rpc(page, 'rr_test_checkpoint5_purchase_fixture_v330', {
    p_action: 'SETUP', p_worker_id: shailender.worker_id
  });
  expect(fixture.error).toBeNull();

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await expect(page.locator('#inbox')).toBeVisible();
  await page.locator('[data-department="PURCHASE"]').click();
  await expect(page.locator(`[data-person="${shailender.worker_id}"]`)).toBeVisible();
  await page.locator(`[data-person="${shailender.worker_id}"]`).click();
  await expect(page.locator('#chat')).toBeVisible();

  const expected = { OPEN: 'TEST71-CP5-O', WORKING: 'TEST71-CP5-W', CLOSE: 'TEST71-CP5-C' };
  for (const [status, child] of Object.entries(expected)) {
    await page.locator(`[data-chat-status="${status}"]`).click();
    await expect(page.locator('#messages')).toContainText(child);
    await expect(page.locator('#messages')).toContainText('TEST71 E2E FIXTURE');
  }
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
});

test('Purchase history backend uses effective Act As identity', async ({ page }) => {
  const shailender = named(await people(page), 'shailender');
  expect((await rpc(page, 'rr_test_checkpoint5_purchase_fixture_v330', {
    p_action: 'SETUP', p_worker_id: shailender.worker_id
  })).error).toBeNull();
  await actAs(page, shailender);
  const identity = await rpc(page, 'rr_upm_effective_identity_v200');
  expect(identity.error).toBeNull();
  expect(identity.data.on_behalf).toBe(true);
  expect(identity.data.role_code).toBe('ACCOUNT');
  const history = await rpc(page, 'rr_real_chat_conversation_history_v83', { p_limit: 5000 });
  expect(history.error).toBeNull();
  const row = history.data.find((x) => x.canonical_key === 'TEST71_CP5_PURCHASE_PERSONAL');
  expect(row).toBeTruthy();
  expect(row.personal_payload.fixture_label).toContain('TEST71 CHECKPOINT 5');
  expect(new Set(row.personal_payload.cb_children.map((x) => x.state))).toEqual(
    new Set(['ART_DUE', 'READY_FOR_CUTTING', 'RELEASED'])
  );
});

test('Fabrication lot 2624 distinguishes genuine pending handover from confirmed receipt', async ({ page }) => {
  const directory = await people(page);
  const ali = named(directory, 'ali');
  const nasim = named(directory, 'nasim');
  await actAs(page, ali);

  const open = await rpc(page, 'rr_real_chat_work_search_v317', {
    p_status: 'OPEN', p_search: '2624', p_department_code: null, p_limit: 500
  });
  expect(open.error).toBeNull();
  const handover = open.data.cards.find((x) => x.event_key === 'UPM_FABRICATION_SUBMIT:af63ba12-ddf6-4832-a40d-21887c56d751');
  expect(handover).toBeTruthy();
  expect(handover.source_status).toBe('WAITING_LM');
  expect(handover.actions.map((x) => x.code)).toContain('LM_ACCEPT_COUNT');

  const close = await rpc(page, 'rr_real_chat_work_search_v317', {
    p_status: 'CLOSE', p_search: '2624', p_department_code: null, p_limit: 500
  });
  expect(close.error).toBeNull();
  const closedReceipt = close.data.cards.find((x) => String(x.event_key).startsWith('UPM_FABRICATION_RECEIPT:'));
  expect(closedReceipt).toBeTruthy();
  expect(closedReceipt.resolved_work_state).toBe('CLOSE');
  expect(['CONFIRMED', 'CONFIRMED_SHORT', 'RESOLVED']).toContain(closedReceipt.source_status);
  expect(closedReceipt.actions).toEqual([]);

  const retry = await rpc(page, 'rr_test_checkpoint5_accept_retry_v330');
  expect(retry.error).toBeNull();
  expect(retry.data.first.duplicate_blocked).toBe(false);
  expect(retry.data.second.duplicate_blocked).toBe(true);
  expect(retry.data.audit_count).toBe(1);
  expect(retry.data.rolled_back).toBe(true);

  await actAs(page, nasim);
  const manager = await rpc(page, 'rr_real_chat_work_search_v317', {
    p_status: 'OPEN', p_search: '2624', p_department_code: null, p_limit: 500
  });
  expect(manager.error).toBeNull();
  const waiting = manager.data.cards.find((x) => x.event_key === handover.event_key);
  expect(waiting).toBeTruthy();
  expect(waiting.actions).toEqual([]);
  expect(waiting.action_waiting).toMatch(/WAITING FOR ALI RECEIPT/i);
});

test('Lot 2622 separates performer, assigner, receiver and responsible identities', async ({ page }) => {
  const recoveryRetry = await rpc(page, 'rr_test_checkpoint5_recovery_retry_v330');
  expect(recoveryRetry.error).toBeNull();
  expect(recoveryRetry.data.first.event_id).toBe(recoveryRetry.data.second.event_id);
  expect(recoveryRetry.data.second.duplicate_blocked).toBe(true);
  expect(recoveryRetry.data.event_count).toBe(1);
  expect(recoveryRetry.data.outbox_count).toBe(2);
  expect(recoveryRetry.data.rolled_back).toBe(true);

  const imamul = named(await people(page), 'imamul');
  await actAs(page, imamul);
  const journey = await rpc(page, 'rr_upm_missing_recovery_journey_v215', { p_missing_id: RECOVERY_2622 });
  expect(journey.error).toBeNull();
  expect(journey.data.identity.performer_name).toBe('Sudesh Bhati');
  expect(journey.data.identity.assigner_name.toLowerCase()).toBe('shailender');
  expect(journey.data.identity.receiver_name.toLowerCase()).toBe('imamul');
  expect(journey.data.identity.responsible_name.toLowerCase()).toBe('shailender');
  expect(journey.data.identity.performer_name).not.toBe(journey.data.identity.responsible_name);
  expect(journey.data.identity.act_as_recorded).toBe(false);
  expect(journey.data.canonical_event_count).toBe(1);
  expect(journey.data.audit_event_count).toBeGreaterThan(journey.data.canonical_event_count);
  expect(journey.data.quantity_journey).toMatchObject({
    source_expected_qty: 24, accepted_qty: 22, difference_qty: 2,
    found_qty: 1, confirmed_short_qty: 1, recovery_pending_qty: 1,
    current_downstream_good_qty: 22, downstream_after_pending_accept_qty: 23,
    colour_code: 'C1'
  });

  const mirror = await rpc(page, 'rr_real_chat_work_search_v317', {
    p_status: 'WORKING', p_search: '2622', p_department_code: null, p_limit: 500
  });
  expect(mirror.error).toBeNull();
  const card = mirror.data.cards.find((x) => x.event_key === `UPM_MISSING:${RECOVERY_2622}`);
  expect(card).toBeTruthy();
  expect(card.performed_by_name).toBe('Sudesh Bhati');
  expect(card.responsible_name.toLowerCase()).toBe('shailender');
  expect(card.receiver_name.toLowerCase()).toBe('imamul');
  expect(card.difference_qty).toBe(2);
  expect(card.pending_downstream_good_qty).toBe(23);

  const akhtar = named(await people(page), 'akhtar');
  await actAs(page, akhtar);
  const unauthorized = await rpc(page, 'rr_upm_missing_recovery_journey_v215', {
    p_missing_id: RECOVERY_2622
  });
  expect(unauthorized.data).toBeNull();
  expect(unauthorized.error && unauthorized.error.message).toMatch(/not authorized/i);
});
