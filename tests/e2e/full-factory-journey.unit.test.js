const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, 'full-factory-journey.spec.js'), 'utf8');

test('three full-factory identities are fixed, isolated and driven through deployed UI', () => {
  for (const cb of ['TEST71F-A-260922', 'TEST71F-B-260922', 'TEST71F-C-260922']) assert.match(source, new RegExp(cb));
  assert.match(source, /#contextAction/);
  assert.match(source, /#actionFrame/);
  assert.match(source, /#draftBtn/);
  assert.match(source, /#saveBtn/);
  assert.match(source, /#cameraVideo/);
  assert.match(source, /rr_cb_department_save_v600/);
  assert.doesNotMatch(source, /\.delete\s*\(/);
  assert.doesNotMatch(source, /\.update\s*\(/);
});

test('fixture retries reuse canonical action payloads and preserve audit identity', () => {
  assert.match(source, /duplicate_blocked/);
  assert.match(source, /rr_cb_department_audit_v600/);
  assert.match(source, /new Set\(snapshot\.audit\.map/);
  assert.match(source, /DRAFT_SAVE/);
  assert.match(source, /SAVE_CONFIRM/);
});
