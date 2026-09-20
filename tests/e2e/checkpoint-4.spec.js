const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

async function actor(page, name) {
  const directory = await rpc(page, 'rr_real_chat_directory_v85');
  expect(directory.error).toBeNull();
  const row = directory.data.people.find((x) => String(x.worker_name).toLowerCase() === name.toLowerCase());
  expect(row, name).toBeTruthy();
  return row;
}

async function lot2624(page) {
  return page.evaluate(async () => {
    const lot = await window.supabaseClient.from('rr_upm_lot_registry')
      .select('canonical_lot_id,lot_no,print_no').eq('lot_no', '2624').single();
    if (lot.error) throw new Error(lot.error.message);
    const assignment = await window.supabaseClient.from('rr_upm_work_assignments_v8')
      .select('id,worker_id,assigned_qty').eq('canonical_lot_id', lot.data.canonical_lot_id)
      .in('department_code', ['PRINTING', 'PRINT']).limit(1).single();
    if (assignment.error) throw new Error(assignment.error.message);
    const receipt = await window.supabaseClient.from('rr_upm_assignment_receipts_v9112')
      .select('confirmed_qty').eq('assignment_id', assignment.data.id).maybeSingle();
    if (receipt.error) throw new Error(receipt.error.message);
    return { ...lot.data, assignment: assignment.data, confirmed_qty: receipt.data?.confirmed_qty || assignment.data.assigned_qty };
  });
}

test.beforeEach(async ({ page }) => { await ensureSession(page); });
test.afterEach(async ({ page }) => {
  if (!page.isClosed()) await rpc(page, 'rr_test_clear_on_behalf_context_v176').catch(() => null);
});

test('Super Admin gets private costing while raw salary sources remain inaccessible', async ({ page }) => {
  const lot = await lot2624(page);
  const costing = await rpc(page, 'rr_upm_final_costing_v308', { p_canonical_lot_id: lot.canonical_lot_id, p_data_mode: 'TEST' });
  expect(costing.error).toBeNull();
  expect(costing.data.security).toBe('SUPER_ADMIN_PRIVATE');
  expect(costing.data).toHaveProperty('base_cost_per_pc');
  expect(costing.data).toHaveProperty('owner_margin_per_pc');
  expect(costing.data.salary.rules).toContain('ACCEPT_TO_SUBMIT');
  const raw = await page.evaluate(async () => {
    const r = await window.supabaseClient.from('rr_upm_department_labor_cost_v9160').select('*').limit(1);
    return r.error && { message: r.error.message, code: r.error.code };
  });
  expect(raw?.message).toMatch(/permission denied/i);
});

test('worker Act As receives no private cost and cannot edit rate', async ({ page }) => {
  const lot = await lot2624(page);
  const imamul = await actor(page, 'imamul');
  expect((await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: imamul.worker_id })).error).toBeNull();
  const costing = await rpc(page, 'rr_upm_final_costing_v308', { p_canonical_lot_id: lot.canonical_lot_id, p_data_mode: 'TEST' });
  expect(costing.error).toBeNull();
  expect(costing.data.security).toBe('PRIVATE_COST_OMITTED');
  for (const key of ['base_cost_per_pc', 'owner_margin_per_pc', 'salary', 'printing', 'materials_resolved']) {
    expect(costing.data).not.toHaveProperty(key);
  }
  const denied = await rpc(page, 'rr_upm_set_department_rate_v760', {
    p_canonical_lot_id: lot.canonical_lot_id, p_department_code: 'PRINTING', p_actual_rate: 1, p_request_id: null
  });
  expect(denied.error?.message).toMatch(/Only eligible Manager\/Admin\/Owner/i);
});

test('Manager can resolve canonical rate event but still receives no private cost', async ({ page }) => {
  const lot = await lot2624(page);
  const nasim = await actor(page, 'nasim');
  expect((await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: nasim.worker_id })).error).toBeNull();
  const scope = await rpc(page, 'rr_costing_user_scope_v760', { p_department_code: 'PRINTING' });
  expect(scope.error).toBeNull();
  expect(scope.data.effective_role).toBe('MANAGER');
  expect(scope.data.can_edit_rate).toBe(true);
  expect(scope.data.can_view_private_cost).toBe(false);
  const costing = await rpc(page, 'rr_upm_final_costing_v308', { p_canonical_lot_id: lot.canonical_lot_id, p_data_mode: 'TEST' });
  expect(costing.data).not.toHaveProperty('base_cost_per_pc');
  expect(costing.data).not.toHaveProperty('owner_margin_per_pc');
});

test('Printing worker gets multi-design operational context without money payload', async ({ page }) => {
  const lot = await lot2624(page);
  const sanju = await actor(page, 'sanju');
  expect(String(lot.assignment.worker_id)).toBe(String(sanju.worker_id));
  expect((await rpc(page, 'rr_test_set_on_behalf_context_v176', { p_worker_id: sanju.worker_id })).error).toBeNull();
  const context = await rpc(page, 'rr_printing_submit_costing_context_v307', {
    p_canonical_lot_id: lot.canonical_lot_id, p_assignment_id: lot.assignment.id,
    p_completed_qty: Number(lot.confirmed_qty), p_data_mode: 'TEST'
  });
  expect(context.error).toBeNull();
  expect(context.data.private_cost).toBe(false);
  expect(context.data.print_designs).toHaveLength(2);
  expect(context.data.print_designs.map((x) => x.print_no).sort()).toEqual(['PTST1', 'PTST2']);
  expect(context.data.heads.team_salary).not.toHaveProperty('cost_per_pc');
  expect(context.data.heads.team_salary).not.toHaveProperty('team_salary_per_min');
  expect(context.data.heads.chemical).not.toHaveProperty('printing_material_pool');
});

test('Checkpoint 4 live surfaces remain mobile-width safe', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/test70-cb-purchase-real-chat-pilot.html?mode=TEST');
  await expect(page.locator('#messages')).toBeVisible();
  const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
  expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
  expect(await page.locator('body').evaluate((el) => el.textContent.includes('undefined'))).toBe(false);
});

