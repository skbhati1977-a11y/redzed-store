const { test, expect } = require('@playwright/test');
const { ensureSession } = require('./session');

async function rpc(page, name, args = {}) {
  return page.evaluate(async ({ name, args }) => {
    const result = await window.supabaseClient.rpc(name, args);
    return { data: result.data, error: result.error && { message: result.error.message, code: result.error.code } };
  }, { name, args });
}

test.beforeEach(async ({ page }) => {
  await ensureSession(page);
});

test('canonical media map supplies grouped and colour-aware card media', async ({ page }) => {
  const result = await rpc(page, 'rr_real_chat_media_map_v1');
  expect(result.error).toBeNull();
  expect(Array.isArray(result.data)).toBe(true);
  expect(result.data.length).toBeGreaterThan(0);
  for (const row of result.data) {
    for (const key of ['art_images', 'print_images', 'sticker_images', 'metal_id_images', 'colour_images']) {
      expect(Array.isArray(row[key]), `${key} must be grouped`).toBe(true);
    }
    for (const image of row.colour_images) {
      expect(image.colour_code).toBeTruthy();
      expect(image.url).toMatch(/^https?:\/\//);
    }
  }
});

test('all four canonical backend master catalogs return searchable identity and preview media', async ({ page }) => {
  const catalog = await rpc(page, 'rr_real_chat_decision_catalog_v1');
  expect(catalog.error).toBeNull();
  for (const key of ['art', 'print', 'sticker', 'metal']) {
    expect(Array.isArray(catalog.data[key]), key).toBe(true);
    for (const row of catalog.data[key]) {
      expect(row.id).toBeTruthy();
      expect(row.value).toBeTruthy();
      expect(row.label).toContain(row.value);
      if (row.image_url) expect(row.image_url).toMatch(/^https?:\/\//);
    }
  }

  for (const itemType of ['STICKER', 'METAL_ID']) {
    const list = await rpc(page, 'rr_accessory_master_list_v804', { p_item_type: itemType, p_data_mode: 'TEST' });
    expect(list.error, itemType).toBeNull();
    expect(Array.isArray(list.data)).toBe(true);
    for (const row of list.data) {
      expect(row.item_no).toBeTruthy();
      expect(row.item_attr).toBeTruthy();
    }
  }
});

test('master search and selected-preview surfaces remain usable on mobile', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const pages = [
    ['/real-product-master-v804.html', '#artSearch'],
    ['/real-print-master.html', '#printSearch'],
    ['/real-sticker-master-v804.html', '#search'],
    ['/real-metal-id-master-v804.html', '#search']
  ];
  for (const [url, search] of pages) {
    await page.goto(url);
    await expect(page.locator(search)).toBeVisible();
    await page.locator(search).fill('TEST71-NO-MATCH');
    await expect(page.locator(search)).toHaveValue('TEST71-NO-MATCH');
    const width = await page.evaluate(() => ({ body: document.body.scrollWidth, viewport: document.documentElement.clientWidth }));
    expect(width.body).toBeLessThanOrEqual(width.viewport + 2);
  }
});
