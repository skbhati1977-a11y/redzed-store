const { test, expect } = require('@playwright/test');

const baseURL = (process.env.TEST69_BASE_URL || '').replace(/\/$/, '');
const target = 'real-accounts-v805.html?v=9766';
const loginURL = `${baseURL}/real-login.html?next=${encodeURIComponent(target)}`;

async function login(page, username, password) {
  await page.goto(loginURL, { waitUntil: 'domcontentloaded' });
  await page.locator('#identifier').fill(username);
  await page.locator('#password').fill(password);
  await page.locator('#loginBtn').click();
  await page.waitForURL(url => url.pathname.endsWith('/real-accounts-v805.html'), { timeout: 30_000 });
  await expect(page.locator('[data-tab="creditors"]')).toBeVisible({ timeout: 30_000 });
  await expect(page.locator('#accountsHome')).toBeVisible();
}

async function creditorBalance(page) {
  await page.locator('[data-tab="creditors"]').click();
  await page.locator('#creditorSearch').fill('TEST SUPPLIER E2E');
  await page.locator('#loadCreditors').click();
  const row = page.locator('#creditorResult tbody tr').filter({ hasText: 'TEST SUPPLIER E2E' }).first();
  await expect(row).toBeVisible({ timeout: 20_000 });
  expect((await row.locator('td').nth(0).innerText()).trim()).toMatch(/^[0-9a-f-]{36}$/i);
  return Number((await row.locator('td').nth(6).innerText()).replace(/[^0-9.-]/g, ''));
}

async function selectLedger(page, selectId, text) {
  const option = page.locator(`${selectId} option`).filter({ hasText: text }).first();
  const value = await option.getAttribute('value');
  expect(value, `${text} ledger option must exist`).toBeTruthy();
  await page.locator(selectId).selectOption(value);
}

test('Admin journal changes canonical creditor; second session sees it; reversal restores it', async ({ browser }) => {
  test.setTimeout(150_000);
  expect(baseURL, 'TEST69_BASE_URL must be configured').toBeTruthy();
  const adminContext = await browser.newContext();
  const secondContext = await browser.newContext();
  const admin = await adminContext.newPage();
  const second = await secondContext.newPage();
  let voucher = '';
  try {
    await login(admin, process.env.TEST69_ADMIN_USERNAME, process.env.TEST69_ADMIN_PASSWORD);
    await login(second, process.env.TEST69_SECOND_USERNAME, process.env.TEST69_SECOND_PASSWORD);
    await expect(admin.locator('#openAccountsMenu')).toHaveText(/Accounts Menu/);
    await admin.locator('#openAccountsMenu').click();
    await expect(admin.locator('#accountsDrawer')).toBeVisible();
    await expect(admin.locator('#accountsDrawer')).toContainText('Complete Chart of Accounts');
    await admin.locator('#closeAccountsMenu').click();
    await admin.locator('[data-tab="accountsMap"]').click();
    await admin.locator('#loadAccountsMap').click();
    await expect(admin.locator('#accountsMapResult')).toContainText('Loans & Advances (Asset)', { timeout: 20_000 });
    await expect(admin.locator('#accountsMapResult')).toContainText('Piece Rate Wages');
    await expect(admin.locator('#accountsMapResult')).toContainText('Customer Receivable');
    await expect(admin.locator('#accountsMapResult')).toContainText('Supplier Payable');
    await expect(admin.locator('#accountsMapResult').getByRole('button', { name: '+ Create Account' }).first()).toBeVisible();
    const before = await creditorBalance(second);
    await admin.locator('[data-tab="money"]').click();
    await selectLedger(admin, '#journalDebit', 'TEST SUPPLIER E2E');
    await selectLedger(admin, '#journalCredit', 'Cash');
    await admin.locator('#journalAmount').fill('7.77');
    await admin.locator('#journalRef').fill(`E2E-${Date.now()}`);
    await admin.locator('#journalNote').fill('TEST69 two-session creditor gate; must be reversed');
    await admin.locator('#postJournal').click();
    await expect(admin.locator('#journalMsg')).toContainText(/Journal TJV\d+ posted/, { timeout: 20_000 });
    voucher = ((await admin.locator('#journalMsg').innerText()).match(/TJV\d+/) || [])[0] || '';
    expect(voucher).toBeTruthy();
    await expect.poll(async () => Math.abs((await creditorBalance(second)) - before), { timeout: 20_000 }).toBeCloseTo(7.77, 2);
    await admin.locator('[data-tab="creditors"]').click();
    await admin.locator('#reverseVoucher').fill(voucher);
    await admin.locator('#reverseReason').fill('Automated two-session cleanup');
    await admin.locator('#reverseVoucherBtn').click();
    await expect(admin.locator('#reverseMsg')).toContainText('reversed with audit trail', { timeout: 20_000 });
    voucher = '';
    await expect.poll(async () => await creditorBalance(second), { timeout: 20_000 }).toBeCloseTo(before, 2);
  } finally {
    if (voucher && !admin.isClosed()) {
      await admin.locator('[data-tab="creditors"]').click().catch(() => {});
      await admin.locator('#reverseVoucher').fill(voucher).catch(() => {});
      await admin.locator('#reverseReason').fill('Emergency automated cleanup').catch(() => {});
      await admin.locator('#reverseVoucherBtn').click().catch(() => {});
      await admin.locator('#reverseMsg').filter({ hasText: 'reversed with audit trail' }).waitFor({ timeout: 20_000 }).catch(() => {});
    }
    await adminContext.close(); await secondContext.close();
  }
});
