'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root, 'real-print-master.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'real-print-master.html'), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
function section(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a, `Missing source boundary: ${start}`);
  return source.slice(a, b);
}
// Run the real collector and submit handler; only DOM, media and database I/O are mocked.
const collector = section('function getFrameRows(){', '\nasync function loadData');
const submit = section('form.onsubmit=async e=>{', '\nlet viewer=');
function harness(options = {}) {
  const rows = options.frames || ['F1', 'F2', 'F3', 'F4'];
  const calls = {writes: [], rpc: [], messages: [], saved: [], resets: 0};
  const elements = {
    printNo: {value: options.no === undefined ? 'UNIT-PRINT' : options.no},
    printName: {value: 'Unit print'}, designColours: {value: String(options.colours || 2)},
    shortNote: {value: ''}, savePrintBtn: {disabled: false, textContent: 'Save Print'},
    frameRows: {querySelectorAll: () => rows.map(no => ({querySelector: selector => ({value:
      selector === '.frame-no' ? no : selector === '.frame-status' ? 'active' : ''
    })}))}
  };
  const context = {
    form: {}, $: id => elements[id], printId: () => options.id || '',
    prints: options.prints || [], allImages: () => options.hasImage === false ? [] : [{}],
    queued: [], selectedIcon: null, rrPrintDirty: true, rrPrintSaved: false,
    say: (message, type) => calls.messages.push({message, type}),
    console: {error() {}}, loadData: async () => {},
    resetForm: () => {calls.resets++;},
    window: {parent: {postMessage: message => calls.saved.push(message)}},
    confirmFrameReassignments: async () => {
      if (options.cancelReassign) throw new Error('Frame reassignment cancelled');
    },
    supabaseClient: {
      from(table) {
        const chain = {
          insert(payload) {calls.writes.push({table, operation: 'insert', payload}); return this;},
          update(payload) {calls.writes.push({table, operation: 'update', payload}); return this;},
          eq() {return this;}, select() {return this;},
          async single() {return {data: {id: options.id || 'unit-print-id', print_no: 'UNIT-PRINT'}, error: null};}
        };
        return chain;
      },
      async rpc(name, args) {
        calls.rpc.push({name, args});
        return {error: options.rpcError ? {message: options.rpcError} : null};
      }
    }
  };
  vm.runInNewContext(collector + '\n' + submit, context, {filename: 'real-print-master-submit.js'});
  return {context, calls, elements, run: () => context.form.onsubmit({preventDefault() {}})};
}
for (const [colours, count] of [[2,4], [4,2], [1,6], [2,2]]) {
  test(`${colours} design colours save ${count} actual frames without cloning either count`, async () => {
    const h = harness({colours, frames: Array.from({length: count}, (_, i) => ` f${i + 1} `)});
    await h.run();
    assert.equal(h.calls.writes.length, 1);
    assert.equal(h.calls.writes[0].payload.design_colours, colours);
    assert.equal(h.calls.rpc.length, 1);
    assert.equal(h.calls.rpc[0].name, 'rr_save_print_frames');
    const saved = plain(h.calls.rpc[0].args.p_rows);
    assert.equal(saved.length, count);
    assert.deepEqual(saved.map(x => x.frame_no), Array.from({length: count}, (_, i) => `F${i + 1}`));
    assert.deepEqual(saved.map(x => x.colour_order), Array.from({length: count}, (_, i) => i + 1));
    assert.equal(h.calls.saved.length, 1);
    assert.equal(h.elements.savePrintBtn.disabled, false);
    assert.equal(h.elements.designColours.value, String(colours));
  });
}
test('blank optional frame rows are excluded from the actual entered list', async () => {
  const h = harness({frames: ['F1', 'F2', '', '  ', 'F3', 'F4']}); await h.run();
  assert.equal(h.calls.rpc[0].args.p_rows.length, 4);
});
for (const [name, options, message] of [
  ['empty frame list', {frames: []}, 'Enter at least one Frame No'],
  ['case-insensitive duplicate frames', {frames: ['f1', ' F1 ']}, 'Duplicate Frame No: F1'],
  ['missing new print image', {hasImage: false}, 'Select at least one Print image'],
  ['missing print number', {no: ''}, 'Enter Print No'],
  ['duplicate print number', {prints: [{id: 'other', print_no: 'unit-print'}]}, 'already exists'],
  ['cancelled frame reassignment', {cancelReassign: true}, 'Frame reassignment cancelled']
]) {
  test(`${name} stays blocked and unlocks SAVE for correction`, async () => {
    const h = harness(options); await h.run();
    assert.equal(h.calls.writes.length, 0); assert.equal(h.calls.rpc.length, 0);
    assert.ok(h.calls.messages.some(x => x.type === 'error' && x.message.includes(message)));
    assert.equal(h.elements.savePrintBtn.disabled, false);
  });
}
test('editing an existing print retains four frames with two colours', async () => {
  const h = harness({id: 'existing-id', hasImage: false}); await h.run();
  assert.equal(h.calls.writes[0].operation, 'update');
  assert.equal(h.calls.rpc[0].args.p_print_id, 'existing-id');
  assert.equal(h.calls.rpc[0].args.p_rows.length, 4);
});
test('double submit cannot duplicate an in-flight save', async () => {
  const h = harness(); await Promise.all([h.run(), h.run()]);
  assert.equal(h.calls.writes.length, 1); assert.equal(h.calls.rpc.length, 1);
});
test('frame RPC failure never reports success or closes the form', async () => {
  const h = harness({rpcError: 'test frame failure'}); await h.run();
  assert.equal(h.calls.saved.length, 0); assert.equal(h.calls.resets, 0);
  assert.equal(h.context.rrPrintSaved, false);
  assert.equal(h.elements.savePrintBtn.disabled, false);
  assert.ok(h.calls.messages.some(x => x.type === 'error' && x.message === 'test frame failure'));
});
test('all Print Master help text separates colour count from frame count', () => {
  assert.doesNotMatch(html, /one frame per design colour|frame rows must equal/i);
  assert.match(html, /2 colours can use 4 frames/);
  assert.match(html, /Frame count is independent from design colour count/);
  assert.match(html, /real-print-master\.js\?v=[^"\s]*frames-independent-20260929/);
  assert.doesNotMatch(source, /frames\.length\s*!==?\s*colours|so enter exactly.*Frame No/);
});
