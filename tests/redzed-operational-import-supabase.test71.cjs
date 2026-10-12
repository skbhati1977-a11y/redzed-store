'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildOperationalImportPlan, runOperationalImport } = require('../scripts/redzed-operational-import-core.test71.cjs');
const { ART_ADAPTER, SupabaseOperationalRepository, mapArtMasterRow } = require('../scripts/redzed-operational-import-supabase.test71.cjs');

const sourceSha = 'a'.repeat(64);
const exactArt = {
  ID: 393, 'Item Name': '393.self clr fs', art_no: 393,
  art_status: 'NAME_CODE_MASTER_ID_AGREES',
  image_source: 'http://redzedclothing.in/uploads/1791538808_977704132bbe23bcfb4e.jpg',
  'KR/PC': null, 'YARN/PC': 2,
};
const dataset = (raw = exactArt) => ({
  format: 'redzed-ci-operational-import/v1',
  source: { application: 'Redzed Clothing', reference: 'historic.xlsx#Art Master', sha256: sourceSha },
  records: [mapArtMasterRow(raw)],
});

test('Art adapter preserves source ID and raw rates while retaining CI current defaults', () => {
  const row = mapArtMasterRow(exactArt);
  assert.equal(row.source_id, '393');
  assert.equal(row.classification, 'READY_TO_IMPORT');
  assert.equal(row.canonical.art_no, '393');
  assert.equal(row.canonical.item_name, '393.self clr fs');
  assert.equal(row.canonical.source_image_url, 'https://redzedclothing.in/uploads/1791538808_977704132bbe23bcfb4e.jpg');
  assert.equal(row.canonical.category, null);
  assert.equal(row.canonical.default_margin, undefined);
  assert.equal(row.raw['YARN/PC'], 2);
});

test('Art adapter holds uncertain identity and malformed image references', () => {
  assert.equal(mapArtMasterRow({ ...exactArt, art_status: 'ART_NUMBER_REVIEW' }).classification, 'REVIEW_REQUIRED');
  assert.equal(mapArtMasterRow({ ...exactArt, image_source: 'https://images.example.invalid/a.jpg' }).classification, 'BLOCKED');
});

test('atomic Supabase batch writer is the only allowed writer route', async () => {
  let called = 0;
  const repo = { runOperationalBatch: async (input) => { called++; return { mode: input.mode, results: [] }; } };
  const plan = buildOperationalImportPlan({ dataset: dataset(), adapters: { ART: ART_ADAPTER } });
  const result = await runOperationalImport({ plan, adapters: { ART: ART_ADAPTER }, repository: repo, mode: 'DRY_RUN' });
  assert.equal(called, 1);
  assert.equal(result.mode, 'DRY_RUN');
});

test('apply is blocked before batch writer unless TEST backup is recorded', async () => {
  let called = false;
  const repo = { runOperationalBatch: async () => { called = true; } };
  const plan = buildOperationalImportPlan({ dataset: dataset(), adapters: { ART: ART_ADAPTER } });
  await assert.rejects(() => runOperationalImport({ plan, adapters: { ART: ART_ADAPTER }, repository: repo, mode: 'APPLY' }), /backup reference/);
  assert.equal(called, false);
});

test('Supabase writer refuses a non-TEST Supabase project URL', () => {
  assert.throws(() => new SupabaseOperationalRepository({ url: 'https://another-project.supabase.co', serviceRoleKey: 'unused' }), /approved CI TEST/);
});

test('Art verification reads application view, core margin, and linked media separately', async () => {
  const requested = [];
  const repository = new SupabaseOperationalRepository({
    url: 'https://hruartsemierwhtzonei.supabase.co', serviceRoleKey: 'test-only',
    fetchImpl: async (url) => {
      requested.push(url);
      const route = new URL(url).pathname.split('/').pop();
      const records = route === 'rr_art_master'
        ? [{ id: 'target-1', art_no: '393', item_name: '393.self clr fs', product_name: '393.self clr fs', category: null }]
        : route === 'rr_art_master_core_v402'
          ? [{ id: 'target-1', default_margin: '22.00' }]
          : [{ id: 'media-1', entity_type: 'art', entity_id: 'target-1', file_url: 'https://redzedclothing.in/uploads/1791538808_977704132bbe23bcfb4e.jpg', is_cover: true, storage_path: null }];
      return { ok: true, text: async () => JSON.stringify(records) };
    },
  });
  const source = mapArtMasterRow(exactArt);
  const verified = await repository.verifyArt({ target_id: 'target-1', media_id: 'media-1' }, source);
  assert.equal(verified, true);
  assert.deepEqual(requested.map((url) => new URL(url).pathname.split('/').pop()), [
    'rr_art_master', 'rr_art_master_core_v402', 'rr_media',
  ]);
});
