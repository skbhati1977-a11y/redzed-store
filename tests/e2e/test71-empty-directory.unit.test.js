const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require('node:path').join(__dirname, '../../test70-real-chat-live-v70.js'), 'utf8');
const fn = source.slice(source.indexOf('function ensureEmptyStateV708('), source.indexOf('function installEmptyStateObserverV707('));
for (const kind of ['department', 'division']) {
  test(`Empty-card observer preserves ${kind} navigation`, () => {
    const box = { innerHTML: 'Group Chat / workers', querySelector: () => null };
    vm.runInNewContext(fn + ';ensureEmptyStateV708();', { S: { active: { kind }, status: 'WORKING' }, $: () => box, emptyStateV705: () => 'empty' });
    assert.equal(box.innerHTML, 'Group Chat / workers');
  });
}
test('Empty operational group still receives its empty-state message', () => {
  const box = { innerHTML: '', querySelector: () => null };
  vm.runInNewContext(fn + ';ensureEmptyStateV708();', { S: { active: { kind: 'group' }, status: 'WORKING' }, $: () => box, emptyStateV705: () => 'empty' });
  assert.equal(box.innerHTML, 'empty');
});
