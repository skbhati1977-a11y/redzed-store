const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const { expect } = require('@playwright/test');

function harness(results) {
  const calls = [];
  const attachments = [];
  const browserTest = () => {};
  browserTest.beforeEach = browserTest.afterEach = () => {};
  const source = fs.readFileSync(path.join(__dirname, 'cb-department.spec.js'), 'utf8');
  const context = {
    require(name) {
      if (name === '@playwright/test') return { test: browserTest, expect };
      if (name === './session') return { ensureSession: async () => {} };
      return require(name);
    },
    process, Buffer, module: { exports: {} }
  };
  vm.runInNewContext(source + '\nmodule.exports = setupCbUiFixture;', context);
  const page = { evaluate: async (_, args) => {
    calls.push(args);
    const next = results.shift();
    if (next instanceof Error) throw next;
    assert.ok(next, 'unexpected RPC');
    return next;
  } };
  const info = {
    project: { name: 'cb-department' }, workerIndex: 0, repeatEachIndex: 0, retry: 0,
    attach: async (name, data) => attachments.push({ name, data })
  };
  return { run: () => context.module.exports(page, 'cleanup-proof', info, true), calls, attachments };
}

const first = { error: null, data: { ok: true, fixture_rows: 1, cb_id: 'fixture-cb' } };
const retry = { error: null, data: { ...first.data, setup_duplicate_blocked: true } };
const retired = { error: null, data: { ok: true, active_fixture_rows: 0 } };

test('READY transport failure retires only the same marker-guarded fixture and preserves the error', async () => {
  const original = new Error('READY connection reset');
  const h = harness([first, retry, original, retired]);
  await assert.rejects(h.run(), error => error === original);
  assert.deepEqual(h.calls.map(x => x.args.p_action), ['SETUP', 'SETUP', 'READY', 'RETIRE']);
  assert.equal(new Set(h.calls.map(x => x.args.p_fixture_key)).size, 1);
  assert.equal(h.attachments.length, 0);
});

test('failed retirement leaves explicit fixture evidence without replacing the READY error', async () => {
  const original = new Error('READY failed');
  const h = harness([first, retry, original, new Error('retirement offline')]);
  await assert.rejects(h.run(), error => error === original);
  assert.equal(h.attachments[0].name, 'cb-fixture-cleanup-failure');
  const evidence = JSON.parse(h.attachments[0].data.body);
  assert.equal(evidence.fixture_key, h.calls[0].args.p_fixture_key);
  assert.equal(evidence.error, 'retirement offline');
});

test('successful READY setup remains active for the browser test', async () => {
  const ready = { error: null, data: { ready_lifecycle: { state: 'READY_FOR_CUTTING', canonical_state: 'OPEN' } } };
  const readyRetry = { error: null, data: {
    ...first.data, ready_duplicate_blocked: true,
    ready_lifecycle: ready.data.ready_lifecycle,
    art_due_lifecycle: { state: 'ART_DUE', canonical_state: 'OPEN' }
  } };
  const h = harness([first, retry, ready, readyRetry]);
  const result = await h.run();
  assert.equal(result.data.cb_id, 'fixture-cb');
  assert.deepEqual(h.calls.map(x => x.args.p_action), ['SETUP', 'SETUP', 'READY', 'READY']);
  assert.equal(h.attachments.length, 0);
});
