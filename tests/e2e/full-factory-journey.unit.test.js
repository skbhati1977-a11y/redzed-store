const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, 'full-factory-journey.spec.js'), 'utf8');
const snapshotMigration = fs.readFileSync(
  path.join(__dirname, '../../supabase/migrations/20260922233000_test71_action_return_snapshot_v626.sql'),
  'utf8'
);

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
  assert.match(source, /rr_test_cb_snapshot_v608/);
  assert.doesNotMatch(source, /from\('rr_cb_department_audit_v600'\)/);
  assert.match(source, /new Set\(snapshot\.audit\.map/);
  assert.match(source, /DRAFT_SAVE/);
  assert.match(source, /SAVE_CONFIRM/);
});

test('purchase total weight follows all confirmed canonical entries, excluding DUE quantity', () => {
  assert.match(source, /filter\(\(row\) => row\.state !== 'DUE'\)/);
  assert.match(source, /reduce\(\(total, row\) => total \+ Number\(row\.qty \|\| 0\), 0\)/);
  assert.doesNotMatch(source, /total_weight\)\)\.toBe\(365\)/);
});

test('the retained journeys use canonical Art UI and separate CB close from Cutting readiness', () => {
  assert.match(source, /\[data-action="ART_DECISION"\]/);
  assert.match(source, /#decisionSheet/);
  assert.match(source, /#picker \.pick/);
  assert.match(source, /CB Status CLOSE/);
  assert.match(source, /Cutting Status HOLD · 1 MATERIAL DUE/);
  assert.match(source, /Cutting Status READY FOR CUTTING/);
  assert.doesNotMatch(source, /rr_pm_save_decision_bundle_v804/);
});

test('deployed proof uses the existing parameterized read-only snapshot', () => {
  const definition = snapshotMigration.match(
    /create or replace function public\.rr_test_cb_snapshot_v608\(p_cb_no text\)[\s\S]*?\$function\$;/
  )?.[0] || '';
  assert.match(definition, /language plpgsql\s+stable\s+security definer/);
  assert.match(definition, /rr_cb_department_audit_v600/);
  assert.match(definition, /rr_cb_units/);
  assert.match(definition, /auth_user_id=auth\.uid\(\)/);
  assert.doesNotMatch(definition, /\b(insert|update|delete)\b/i);
});
