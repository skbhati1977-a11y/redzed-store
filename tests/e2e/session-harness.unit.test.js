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
