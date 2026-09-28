const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20260928111500_test71_compensation_aware_submit_rate_gate_v777.sql', 'utf8');

test('piece-rate receipt failure never blindly claims a salaried team assignment', () => {
  const fn = chat.match(/async function openReceiptCountTableV736\(button\)\{[\s\S]*?\nfunction bindMedia/)?.[0] || '';
  assert.match(fn, /rr_upm_assignment_action_route_v769/);
  assert.match(fn, /route\?\.mode==='TEAM'/);
  assert.match(fn, /rr_upm_claim_team_assignment_v694/);
  assert.doesNotMatch(fn, /catch\([^)]*\)\{await rpc\('rr_upm_claim_team_assignment_v694'/);
});

test('submit Actual Rate gate is compensation-aware and remains backend enforced', () => {
  assert.match(migration, /rr_department_compensation_choices_v667/);
  assert.match(migration, /auto_mode/);
  assert.match(migration, /SALARIED_TEAM/);
  assert.match(migration, /not is_team and coalesce\(a\.actual_rate,0\)<=0/);
  assert.match(migration, /Submit blocked: Assignment Actual Rate required/);
});
