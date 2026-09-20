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

test('Add New persists, is immediately searchable, and prevents normalized duplicates', async ({ page }) => {
  const fixture = 'TEST71-CP3-E2E';
  const result = await page.evaluate(async (fixture) => {
    const db = window.supabaseClient;
    const out = {};

    // Art/Print fixtures are removed in finally. Accessory masters use their canonical
    // upsert RPC and are returned to inactive state because those masters are archived,
    // not hard-deleted, by design.
    await db.from('rr_art_master').delete().eq('art_no', fixture + '-ART');
    await db.from('rr_print_master').delete().eq('print_no', fixture + '-PRINT');
    try {
      const art = await db.from('rr_art_master').insert({
        art_no: fixture + '-ART', item_name: 'TEST E2E Art', category: 'TEST E2E',
        description: 'Reversible TEST71 Checkpoint 3 fixture', is_active: true
      }).select('id,art_no,category').single();
      if (art.error) throw art.error;
      out.art = (await db.from('rr_art_master').select('id').eq('art_no', fixture + '-ART').single()).data;
      out.artDuplicate = (await db.from('rr_art_master').insert({ art_no: '  ' + fixture.toLowerCase() + '-art  ' })).error?.code || null;

      const print = await db.from('rr_print_master').insert({
        print_no: fixture + '-PRINT', print_name: 'TEST E2E Print', design_colours: 2,
        short_note: 'Reversible TEST71 Checkpoint 3 fixture', is_active: true
      }).select('id,print_no,design_colours').single();
      if (print.error) throw print.error;
      out.print = (await db.from('rr_print_master').select('id').eq('print_no', fixture + '-PRINT').single()).data;
      out.printDuplicate = (await db.from('rr_print_master').insert({ print_no: fixture.toLowerCase() + '-print', print_name: 'duplicate' })).error?.code || null;

      for (const x of [
        { key: 'sticker', rpc: 'rr_upsert_sticker_master_v804', type: 'STICKER', no: fixture + '-STICKER', args: { p_sticker_no: fixture + '-STICKER', p_sticker_name: 'TEST E2E Sticker', p_sticker_quality: 'HD' } },
        { key: 'metal', rpc: 'rr_upsert_metal_id_master_v804', type: 'METAL_ID', no: fixture + '-METAL', args: { p_metal_id_no: fixture + '-METAL', p_metal_id_name: 'TEST E2E Metal ID', p_id_size: 'SMALL' } }
      ]) {
        const before = await db.rpc('rr_accessory_master_list_v804', { p_item_type: x.type, p_data_mode: 'TEST' });
        const existing = (before.data || []).find((row) => row.item_no === x.no);
        const saved = await db.rpc(x.rpc, { p_id: existing?.id || null, ...x.args, p_is_active: true });
        if (saved.error) throw saved.error;
        const after = await db.rpc('rr_accessory_master_list_v804', { p_item_type: x.type, p_data_mode: 'TEST' });
        out[x.key] = (after.data || []).find((row) => row.item_no === x.no) || null;
        const archived = await db.rpc(x.rpc, { p_id: saved.data, ...x.args, p_is_active: false });
        if (archived.error) throw archived.error;
      }
      return out;
    } finally {
      await db.from('rr_art_master').delete().eq('art_no', fixture + '-ART');
      await db.from('rr_print_master').delete().eq('print_no', fixture + '-PRINT');
    }
  }, fixture);

  expect(result.art).toBeTruthy();
  expect(result.print).toBeTruthy();
  expect(result.sticker?.is_active).toBe(true);
  expect(result.metal?.is_active).toBe(true);
  expect(result.artDuplicate).toBe('23505');
  expect(result.printDuplicate).toBe('23505');
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
  const list = await rpc(page, 'rr_accessory_master_list_v804', { p_item_type: 'STICKER', p_data_mode: 'TEST' });
  const marker = (list.data || []).find((row) => row.item_no === 'TEST71-CP3-E2E-STICKER');
  expect(marker).toBeTruthy();
  const marked = await rpc(page, 'rr_upsert_sticker_master_v804', {
    p_id: marker.id, p_sticker_no: marker.item_no,
    p_sticker_name: 'TEST E2E Sticker · MOBILE LIVE PASS', p_sticker_quality: marker.item_attr,
    p_is_active: false
  });
  expect(marked.error).toBeNull();
});
