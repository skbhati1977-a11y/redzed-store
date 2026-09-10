const { test, expect } = require('@playwright/test');

const baseURL = (process.env.TEST69_BASE_URL || '').replace(/\/$/, '');
const target = 'real-rci-v9740.html?v=9756';
const loginURL = `${baseURL}/real-login.html?next=${encodeURIComponent(target)}`;

async function login(page, username, password) {
  await page.goto(loginURL, { waitUntil: 'domcontentloaded' });
  await page.locator('#identifier').fill(username);
  await page.locator('#password').fill(password);
  await page.locator('#loginBtn').click();
  await page.waitForURL(/real-rci-v9740\.html/, { timeout: 30_000 });
  await expect(page.locator('#flowLabel')).toContainText('Standalone RCI');
  await expect(page.locator('#msg')).not.toContainText(/not allowed|denied|unauthorized/i);
}

async function selectKnownSale(page) {
  await page.locator('#ciSearch').fill('TCI11');
  await expect(page.locator('#ciSelect')).toContainText('Avnimycutie', { timeout: 20_000 });
  await page.locator('#ciSelect').selectOption({ label: /Avnimycutie.*TCI11/i });
  await expect(page.locator('#ciNo')).toContainText('TCI11', { timeout: 20_000 });
  await page.locator('#sourceSearch').fill('1RR1');
  await expect(page.locator('#sourceLine')).toContainText('1RR1');
  const available = Number(await page.locator('#returnableNow').inputValue());
  expect(available).toBeGreaterThan(0);
  return available;
}

async function reverseIfNeeded(page, rciId, reason) {
  if (!rciId || page.isClosed()) return;
  await page.evaluate(async ({ id, why }) => {
    const result = await window.RF853.rpc('rr_rci_reverse_v9740', {
      p_rci_id: id,
      p_reason: why
    });
    return result;
  }, { id: rciId, why: reason });
}

test('Admin create, second-session visibility/reversal, Admin restoration', async ({ browser }) => {
  test.setTimeout(120_000);
  expect(baseURL, 'TEST69_BASE_URL must be configured').toBeTruthy();

  const adminContext = await browser.newContext();
  const secondContext = await browser.newContext();
  const admin = await adminContext.newPage();
  const second = await secondContext.newPage();
  let rciId = null;
  let reversed = false;

  try {
    await login(admin, process.env.TEST69_ADMIN_USERNAME, process.env.TEST69_ADMIN_PASSWORD);
    const before = await selectKnownSale(admin);

    await admin.evaluate(() => {
      const original = window.RF853.rpc.bind(window.RF853);
      window.RF853.rpc = async (...args) => {
        const value = await original(...args);
        if (args[0] === 'rr_rci_post_standalone_v9740') window.__test69PostedRci = value;
        return value;
      };
    });
    await admin.locator('#rciQty').fill('1');
    await admin.locator('#reason').fill(`TEST69 automated two-session gate ${Date.now()}`);
    await admin.locator('#add').click();
    await expect(admin.locator('#qty')).toHaveText('1');
    await admin.locator('#post').click();
    await expect(admin.locator('#msg')).toContainText('Separate RCI posted', { timeout: 20_000 });
    const posted = await admin.evaluate(() => window.__test69PostedRci);
    rciId = posted && posted.rci_id;
    expect(rciId, 'Posted RCI id must be captured').toBeTruthy();

    await login(second, process.env.TEST69_SECOND_USERNAME, process.env.TEST69_SECOND_PASSWORD);
    const afterCreate = await selectKnownSale(second);
    expect(afterCreate).toBe(before - 1);

    await reverseIfNeeded(second, rciId, 'TEST69 automated cross-session reversal cleanup');
    reversed = true;

    await admin.reload({ waitUntil: 'domcontentloaded' });
    const afterReverse = await selectKnownSale(admin);
    expect(afterReverse).toBe(before);
  } finally {
    if (rciId && !reversed) {
      try { await reverseIfNeeded(admin, rciId, 'TEST69 automatic failure cleanup'); } catch (_) {}
      try { await reverseIfNeeded(second, rciId, 'TEST69 automatic failure cleanup'); } catch (_) {}
    }
    await adminContext.close();
    await secondContext.close();
  }
});
