'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { buildOperationalImportPlan, runOperationalImport, verifyImportedRows } = require('../scripts/redzed-operational-import-core.test71.cjs');

function adapter(overrides = {}) {
  return {
    targetTable: 'public.test_master', sideEffectFree: true, testModeOnly: true, writeMode: 'insert-only',
    findIdentityConflict: async () => null,
    insert: async (_tx, canonical) => ({ id: canonical.id }),
    verify: async () => true,
    ...overrides,
  };
}

function dataset(records = []) {
  return { format: 'redzed-ci-operational-import/v1',
    source: { application: 'Redzed Clothing', reference: 'fixture.csv', sha256: 'a'.repeat(64) }, records };
}

function row(module, source_id, extras = {}) {
  return { module, source_id, raw: { id: source_id }, canonical: { id: `target-${source_id}` },
    classification: 'READY_TO_IMPORT', dependencies: [], ...extras };
}

test('planner preserves source ids as strings and orders dependencies before children', () => {
  const records = [row('ART', 12, { dependencies: [{ module: 'ITEM', source_id: 7 }] }), row('ITEM', 7)];
  const plan = buildOperationalImportPlan({ dataset: dataset(records), adapters: { ART: adapter(), ITEM: adapter() } });
  assert.deepEqual(plan.records.map((x) => x.module), ['ITEM', 'ART']);
  assert.equal(plan.records[0].source_id, '7');
  assert.match(plan.records[0].payload_sha256, /^[a-f0-9]{64}$/);
});

test('planner rejects duplicate identities, missing dependencies, and unregistered or side-effecting writers', () => {
  assert.throws(() => buildOperationalImportPlan({ dataset: dataset([row('ART', '1'), row('ART', '1')]), adapters: { ART: adapter() } }), /Duplicate source identity/);
  assert.throws(() => buildOperationalImportPlan({ dataset: dataset([row('ART', '1', { dependencies: [{ module: 'CB', source_id: '9' }] })]), adapters: { ART: adapter() } }), /Missing dependency/);
  assert.throws(() => buildOperationalImportPlan({ dataset: dataset([row('ART', '1')]), adapters: {} }), /No operational adapter/);
  assert.throws(() => buildOperationalImportPlan({ dataset: dataset([row('ART', '1')]), adapters: { ART: adapter({ sideEffectFree: false }) } }), /side effects/);
  assert.throws(() => buildOperationalImportPlan({ dataset: dataset([row('ART', '1')]), adapters: { ART: adapter({ targetTable: 'rr_art_master_core_v402' }) } }), /explicit public target table/);
});

test('dry run is read-only and apply is gated by TEST plus a backup reference', async () => {
  const plan = buildOperationalImportPlan({ dataset: dataset([row('ITEM', '1')]), adapters: { ITEM: adapter() } });
  let writes = 0;
  const repo = {
    transaction: (fn, opts) => { assert.equal(opts.readOnly, true); return fn({}); },
    findSourceIdentity: async () => null,
    recordSourceIdentity: async () => { writes++; },
    writeRowLog: async () => { writes++; },
  };
  const dry = await runOperationalImport({ plan, adapters: { ITEM: adapter() }, repository: repo });
  assert.equal(dry.summary.READY_TO_IMPORT, 1);
  assert.equal(writes, 0);
  await assert.rejects(runOperationalImport({ plan, adapters: { ITEM: adapter() }, repository: repo, mode: 'APPLY' }), /TEST environment and a recorded target backup/);
});

test('identical source replay is skipped; changed payload and existing target collisions are never overwritten', async () => {
  const p = buildOperationalImportPlan({ dataset: dataset([row('ITEM', '1')]), adapters: { ITEM: adapter() } });
  const same = { transaction: (fn) => fn({}), findSourceIdentity: async () => ({ target_id: 'old', payload_sha256: p.records[0].payload_sha256 }) };
  let result = await runOperationalImport({ plan: p, adapters: { ITEM: adapter() }, repository: same });
  assert.equal(result.results[0].status, 'SKIPPED_DUPLICATE');
  const changed = { ...same, findSourceIdentity: async () => ({ target_id: 'old', payload_sha256: 'b'.repeat(64) }) };
  result = await runOperationalImport({ plan: p, adapters: { ITEM: adapter() }, repository: changed });
  assert.equal(result.results[0].status, 'REVIEW_REQUIRED');
  const conflictAdapter = adapter({ findIdentityConflict: async () => ({ id: 'existing' }) });
  result = await runOperationalImport({ plan: p, adapters: { ITEM: conflictAdapter }, repository: { ...same, findSourceIdentity: async () => null } });
  assert.equal(result.results[0].status, 'REVIEW_REQUIRED');
});

test('apply imports within one rollback-capable transaction and verifies separately', async () => {
  const p = buildOperationalImportPlan({ dataset: dataset([row('ITEM', '1')]), adapters: { ITEM: adapter() } });
  let writes = 0;
  const repo = {
    transaction: async (fn, opts) => { assert.equal(opts.rollbackOnError, true); return fn({}); },
    findSourceIdentity: async () => null,
    recordSourceIdentity: async () => { writes++; },
    writeRowLog: async () => { writes++; },
  };
  let result = await runOperationalImport({ plan: p, adapters: { ITEM: adapter() }, repository: repo, mode: 'APPLY', environment: 'TEST', backupReference: 'test-backup-2026-10-12' });
  assert.equal(result.results[0].status, 'IMPORTED_PENDING_VERIFY');
  assert.equal(writes, 2);
  repo.findSourceIdentity = async () => ({ target_id: 'target-1', payload_sha256: p.records[0].payload_sha256 });
  result = await verifyImportedRows({ plan: p, adapters: { ITEM: adapter() }, repository: repo });
  assert.equal(result.results[0].status, 'IMPORTED_VERIFIED');
});

test('foreign-key references without an imported or prior target identity stay blocked', async () => {
  const p = buildOperationalImportPlan({ dataset: dataset([
    row('ART', '2', { dependencies: [{ module: 'ITEM', source_id: '1', alias: 'item_id' }] }),
    row('ITEM', '1', { classification: 'ARCHIVE_ONLY' }),
  ]), adapters: { ART: adapter() } });
  const repo = { transaction: (fn) => fn({}), findSourceIdentity: async () => null };
  const result = await runOperationalImport({ plan: p, adapters: { ART: adapter() }, repository: repo });
  assert.equal(result.results.find((x) => x.module === 'ART').status, 'BLOCKED');
  assert.equal(result.results.find((x) => x.module === 'ART').reason, 'UNRESOLVED_FOREIGN_KEY');
});
