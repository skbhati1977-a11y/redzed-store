const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const chat = fs.readFileSync('test70-fg-direct-chat-v140.js', 'utf8');
const migrationPath = 'supabase/migrations/20260920224530_test71_checkpoint7_chat_native_despatch_receive_v335.sql';

test('Despatch partial and full actions stay inside the canonical Real Chat sheet', () => {
  assert.match(chat, /rr_fg_create_despatch_chat_v335/);
  assert.match(chat, /data-partial-box/);
  assert.match(chat, /data-send-qty/);
  assert.doesNotMatch(
    chat,
    /\[data-full\]\)\.onclick=\(\)=>openFull\(`real-finished-goods-v787\.html\?view=despatch/
  );
});

test('Store Receive posts canonical group ids and never opens the legacy App flow', () => {
  assert.match(chat, /\{id:g\.id,received_box_count:/);
  assert.match(chat, /p_accept_as:acceptAs/);
  assert.doesNotMatch(
    chat,
    /\[data-full\]\)\.onclick=\(\)=>openFull\(`real-finished-goods-v787\.html\?view=receive/
  );
});

test('Checkpoint 7 backend reuses canonical FG tables with effective identity and idempotency', () => {
  assert.equal(fs.existsSync(migrationPath), true, `${migrationPath} is required`);
  const sql = fs.readFileSync(migrationPath, 'utf8');
  for (const token of [
    'rr_upm_effective_identity_v200()',
    'rr_fg_create_despatch_v7981',
    'rr_fg_create_despatch_lot_v9356',
    'rr_fg_despatch_v787',
    'rr_fg_despatch_receive_groups_v9356',
    'rr_fg_receive_accept_v9361',
    'client_action_id',
    'pg_advisory_xact_lock',
    'rr_test_checkpoint7_despatch_receive_v335'
  ]) assert.ok(sql.includes(token), `missing canonical contract: ${token}`);
  assert.match(sql, /revoke all on function public\.rr_fg_create_despatch_chat_v335[\s\S]*from public,anon/);
  assert.match(sql, /grant execute on function public\.rr_fg_create_despatch_chat_v335[\s\S]*to authenticated,service_role/);
});
