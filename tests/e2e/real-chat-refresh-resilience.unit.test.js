const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const shell = fs.readFileSync('test70-cb-purchase-real-chat-pilot.html', 'utf8');

test('Real Chat requests the canonical bounded history window', () => {
  const bridge = chat.match(/async function loadBridge\(\)\{[\s\S]*?\nasync function load\(/)?.[0] || '';
  assert.match(bridge, /rr_real_chat_conversation_history_v83',\{p_limit:2000\}/);
  assert.doesNotMatch(bridge, /p_limit:5000/);
  assert.match(shell, /test70-real-chat-live-v70\.js\?v=627/);
});

test('an auxiliary history timeout cannot discard canonical CB cards', () => {
  assert.match(chat, /loadBridge\(\)\.then\(\(\)=>null\)\.catch\(error=>\(\{error\}\)\)/);
  assert.match(chat, /\[d,w,historyResult,cb\]=await Promise\.all/);
  assert.match(chat, /if\(historyResult\?\.error\)\{console\.error\(historyResult\.error\);clearBridgeProjection\(\)\}/);
  assert.match(chat, /S\.cbCards=arr\(cb\?\.cards\)/);
  assert.match(chat, /history temporarily unavailable/);
});

test('embedded action close is single-flight and restores same-card focus around refresh', () => {
  const close = chat.match(/function restoreActionOrigin\(origin\)[\s\S]*?\nasync function openChatSubmit/)?.[0] || '';
  assert.match(close, /if\(S\.actionClosing\|\|\(refresh&&!S\.actionOrigin\)\)return/);
  const before = close.indexOf('restoreActionOrigin(origin);await load(false)');
  assert.ok(before >= 0, 'focus/scroll must restore before the network refresh');
  assert.match(close, /await load\(false\);restoreActionOrigin\(origin\)/);
  assert.match(chat, /getAttribute\('src'\)===\'about:blank\'/);
  assert.match(chat, /S\.actionClosing\)return/);
});
