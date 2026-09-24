const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const app = fs.readFileSync('real-cutting-master-pm.V719.3.js', 'utf8');
const sql = fs.readFileSync('supabase/migrations/20260924063001_test71_cutting_canonical_handoff_v632.sql', 'utf8');
function chatFunction(name, context = {}) {
  const line = chat.split('\n').find(line => line.startsWith(`function ${name}(`));
  return vm.runInNewContext(`(${line})`, context);
}
const matches = chatFunction('currentMatchesStatus');
for (const [event, state, assigned] of [
  ['READY_FOR_CUTTING', 'OPEN', false],
  ['CUTTING_RELEASE_SUCCEEDED', 'WORKING', false],
  ['CUTTING_RELEASED_PENDING_ASSIGNMENT', 'WORKING', false],
  ['CUTTING_RELEASE_SUCCEEDED', 'CLOSE', true],
]) {
  test(`${event}/${state} appears in exactly one Cutting tab`, () => {
    const card = {source_event_type: event, canonical_state: state, production_assigned: assigned};
    assert.deepEqual(['OPEN', 'WORKING', 'CLOSE'].filter(tab => matches(card, tab)), [state]);
  });
}
test('explicit WORKING release is not overridden by the old terminal event rule', () => {
  assert.equal(matches({source_event_type:'CUTTING_RELEASE_SUCCEEDED', chat_status:'WORKING', source_status:'RELEASED'}, 'WORKING'), true);
});
test('Cutting CLOSE hides even stale actions', () => {
  const render = chatFunction('actionButtons');
  assert.equal(render({department_code:'CUTTING', canonical_state:'CLOSE', actions:[{code:'ASSIGN_WORKER'}]}), '');
});
test('release action returns to WORKING', () => {
  assert.equal(chatFunction('successStatus')({code:'CUTTING_SINGLE_LOT'}), 'WORKING');
});
test('App reads the backend state, including mixed multi-Lot handoff', () => {
  const state = app.slice(app.indexOf('function cardState(card)'), app.indexOf('\nasync function loadCuttingLifecycle'));
  const cuttingLifecycle = new Map();
  const classify = vm.runInNewContext(`(${state})`, {cuttingLifecycle});
  for (const [life, expected] of [
    [{state:'READY_FOR_CUTTING',canonical_state:'OPEN'}, 'ready'],
    [{state:'RELEASED',canonical_state:'WORKING',production_assigned:false}, 'released'],
    [{state:'RELEASED',canonical_state:'CLOSE',production_assigned:true}, 'completed'],
    [{state:'CUTTING_HOLD',canonical_state:'OPEN'}, 'cutting_hold'],
  ]) {
    cuttingLifecycle.set('child', life);
    assert.equal(classify({division:{division_id:'child'}}), expected);
  }
  assert.equal(classify({division:{division_id:'missing'}}), 'unavailable');
});
test('assignment retry serializes before computing due quantities', () => {
  const start = sql.indexOf('CREATE OR REPLACE FUNCTION public.rr_upm_ready_to_assign_v9107');
  const body = sql.slice(start, sql.indexOf('create or replace function public.rr_real_chat_work_search_v317', start));
  assert.ok(body.indexOf('for update') < body.indexOf('v_due:='));
  assert.match(body, /Duplicate colour in assignment request/);
  assert.match(body, /already running/);
});
test('Fabrication uses the existing projection and synthetic proof checks same identity', () => {
  assert.match(sql, /rr_real_chat_work_search_v317_core_v401\(p_status,p_search,p_department_code,p_limit\)/);
  assert.match(sql, /Released fixture missing from Fabrication OPEN/);
  assert.match(sql, /Assigned fixture missing read-only Cutting CLOSE/);
  assert.match(sql, /Duplicate assignment guard failed/);
  assert.doesNotMatch(sql, /\b(2640|1007|1008|1009|1010)\b/);
});
