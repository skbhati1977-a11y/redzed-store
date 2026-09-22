const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../../test70-action-return-v110.js'), 'utf8');

function loadBridge(search, embedded) {
  const posted = [];
  let historyBacks = 0;
  let replaced = null;
  const location = {
    href: `https://preview.example/action.html${search}`,
    origin: 'https://preview.example',
    pathname: '/action.html',
    search,
    hash: '',
    replace(url) { replaced = url; }
  };
  const parent = { postMessage(message, origin) { posted.push({ message, origin }); } };
  const window = { location };
  window.parent = embedded ? parent : window;
  vm.runInNewContext(source, {
    window,
    location,
    history: { back() { historyBacks += 1; } },
    URL,
    URLSearchParams
  });
  return {
    bridge: window.RRActionReturn,
    location,
    posted,
    get historyBacks() { return historyBacks; },
    get replaced() { return replaced; }
  };
}

test('embedded success keeps its captured parent contract after replaceState-style URL rewrite', () => {
  const target = encodeURIComponent('/chat.html?rc_status=OPEN&rc_id=PURCHASE');
  const runtime = loadBridge(`?embed=1&rr_action=CREATE_CB&return=${target}&success_return=${target}`, true);
  runtime.location.search = '?cb_id=permanent-id&from=CB_DEPARTMENT';
  runtime.location.href = 'https://preview.example/action.html?cb_id=permanent-id&from=CB_DEPARTMENT';

  assert.equal(runtime.bridge.hasReturn(), true);
  runtime.bridge.success({ status: 'OPEN', focus: 'TEST71F-A-260922' });

  assert.equal(runtime.historyBacks, 0);
  assert.equal(runtime.replaced, null);
  assert.deepEqual(JSON.parse(JSON.stringify(runtime.posted)), [{
    message: {
      type: 'RR_REAL_CHAT_ACTION_SUCCESS',
      action: 'CREATE_CB',
      status: 'OPEN',
      focus: 'TEST71F-A-260922'
    },
    origin: 'https://preview.example'
  }]);
});

test('non-embedded success keeps the captured same-origin return URL', () => {
  const target = encodeURIComponent('/chat.html?rc_status=OPEN&rc_id=PURCHASE');
  const runtime = loadBridge(`?return=${target}`, false);
  runtime.location.search = '?cb_id=permanent-id';
  runtime.bridge.success({ status: 'WORKING', focus: 'TEST71F-B-260922' });

  assert.equal(runtime.historyBacks, 0);
  assert.equal(runtime.replaced, '/chat.html?rc_status=WORKING&rc_id=PURCHASE&rc_focus_cb=TEST71F-B-260922');
});
