const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const session = fs.readFileSync(path.join(__dirname, 'session.js'), 'utf8');
const checkpoint8 = fs.readFileSync(path.join(__dirname, 'checkpoint-8-commercial.spec.js'), 'utf8');
const endpoint = fs.readFileSync(path.join(__dirname, '..', '..', 'api', 'e2e-session.js'), 'utf8');

test('backend proof suites can retain auth without dashboard polling', () => {
  assert.match(session, /options\.quiet === true/);
  assert.match(session, /real-login\.html\?e2e=quiet/);
  assert.match(session, /real-dashboard-v9182\.html\?mode=TEST/);
  assert.match(checkpoint8, /ensureSession\(page, \{ quiet: true \}\)/);
});

test('runner refuses a branch alias that is not the exact workflow SHA', () => {
  assert.match(endpoint, /VERCEL_GIT_COMMIT_SHA/);
  assert.match(endpoint, /VERCEL_URL/);
  assert.match(session, /process\.env\.GITHUB_SHA/);
  assert.match(session, /deployment SHA mismatch/);
});

test('explicit upstream outage stops bootstrap after one call without loading a session or starting work', async () => {
  const { bootstrap } = require('./session');
  const previous = process.env.E2E_TEST_BOOTSTRAP_SECRET;
  process.env.E2E_TEST_BOOTSTRAP_SECRET = 'fixture-bootstrap-only';
  let requests = 0;
  try {
    await assert.rejects(bootstrap({ request: { post: async () => {
      requests += 1;
      return { status: () => 503, headers: () => ({ 'x-test71-upstream-unavailable': '1' }) };
    } } }), /authentication unavailable.*verification has not started/);
    assert.equal(requests, 1);
  } finally {
    if (previous === undefined) delete process.env.E2E_TEST_BOOTSTRAP_SECRET;
    else process.env.E2E_TEST_BOOTSTRAP_SECRET = previous;
  }
});
