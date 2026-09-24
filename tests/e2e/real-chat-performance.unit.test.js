const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const extract = (name, next) => source.slice(source.indexOf(`function ${name}(`), source.indexOf(next, source.indexOf(`function ${name}(`)));

test('craft identity is fetched once per visible Lot and preserves every existing field', async () => {
  const S = { userId: 'one', actor: { role: 'ADMIN' }, craftIdentityCache: new Map() };
  const calls = [];
  const scope = { S, window: {}, arr: x => Array.isArray(x) ? x : [], rpc: async (name, args) => {
    calls.push([name, args]);
    return { art_no: 'A1', print_no: 'P1', frame_no: 'F1', sticker_no: 'S1', sticker_name: 'Sticker', metal_id_no: 'M1', metal_id_name: 'Metal', print_images: ['print.png'] };
  } };
  vm.createContext(scope);
  vm.runInContext('async ' + extract('mergeCraftIdentityV634', '\nasync function operationalWorkV283'), scope);
  const cards = [{ canonical_lot_id: 'lot-1', lot_no: '101', print_images: ['existing.png'] }, { canonical_lot_id: 'lot-1', lot_no: '101', print_images: [] }];
  const first = await scope.mergeCraftIdentityV634(cards);
  const second = await scope.mergeCraftIdentityV634(cards);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], 'rr_upm_lot_craft_identity_v634');
  assert.deepEqual(JSON.parse(JSON.stringify(first[0].print_images)), ['existing.png', 'print.png']);
  for (const field of ['art_no', 'print_no', 'frame_no', 'sticker_no', 'sticker_name', 'metal_id_no', 'metal_id_name']) assert.equal(first[0][field], second[1][field]);
  scope.window.RR_VIEW_AS_ACTOR_ID = 'other';
  await scope.mergeCraftIdentityV634(cards);
  assert.equal(calls.length, 2, 'Act As cannot reuse another identity projection');
});

test('status switch clears previous cards before canonical request and scopes the cache', () => {
  const elements = { chat: { hidden: false }, messages: { innerHTML: '<article>Old WORKING card</article>' }, rows: { innerHTML: '' } };
  let requested = 0, rendered = 0;
  const S = { userId: 'one', actor: { id: 'admin', role: 'ADMIN' }, status: 'WORKING', search: '', searchFocusIndex: 0, active: { kind: 'group', id: 'CUTTING' }, statusCache: new Map(), chatSeq: 0 };
  const scope = { S, window: {}, arr: x => Array.isArray(x) ? x : [], $: id => elements[id], history: { state: {}, replaceState() {}, pushState() {} }, viewUrl: () => '/', syncStatusButtons() {}, safe: x => x, renderActive() { rendered++; }, load() { requested++; } };
  vm.createContext(scope);
  vm.runInContext(extract('statusProjectionKey', '\nfunction inbox()'), scope);
  scope.changeStatus('OPEN');
  assert.equal(requested, 1);
  assert.equal(rendered, 0);
  assert.equal(elements.messages.innerHTML.includes('Old WORKING card'), false);
  const key = scope.statusProjectionKey('OPEN');
  scope.window.RR_VIEW_AS_ACTOR_ID = 'other';
  assert.notEqual(scope.statusProjectionKey('OPEN'), key);
  scope.window.RR_VIEW_AS_ACTOR_ID = undefined;
  S.active = { kind: 'group', id: 'STITCHING' };
  assert.notEqual(scope.statusProjectionKey('OPEN'), key);
  S.active = { kind: 'group', id: 'CUTTING' };
  assert.notEqual(scope.statusProjectionKey('CLOSE'), key);
});
