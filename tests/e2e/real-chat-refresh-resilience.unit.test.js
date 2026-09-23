const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const shell = fs.readFileSync('test70-cb-purchase-real-chat-pilot.html', 'utf8');

test('Real Chat requests the canonical bounded history window', () => {
  const bridge = chat.match(/async function loadBridge\(\)\{[\s\S]*?\nasync function load\(/)?.[0] || '';
  assert.match(bridge, /rr_real_chat_conversation_history_v83',\{p_limit:2000\}/);
  assert.doesNotMatch(bridge, /p_limit:5000/);
  assert.match(shell, /test70-real-chat-live-v70\.js\?v=628/);
});

test('auxiliary projection timeouts cannot discard canonical CB cards', () => {
  assert.match(chat, /\.then\(cb=>projectCanonicalCbCards\(cb,status,seq\)\)/);
  assert.match(chat, /const \[d,workResult,cb\]=await Promise\.all\(\[directory,workJob,cbJob\]\)/);
  assert.match(chat, /workRequest\.then\(data=>\(\{data\}\)\)\.catch\(error=>\(\{error\}\)\)/);
  assert.match(chat, /bridgeResult=\{data:await loadBridge\(\)\}/);
  assert.match(chat, /if\(bridgeResult\.error\).*clearBridgeProjection\(\)/);
  assert.match(chat, /S\.cbCards=arr\(cb\?\.cards\)/);
  assert.match(chat, /history temporarily unavailable/);
});

test('CB projection renders before slow history and skips unrelated production supplements', () => {
  const progressive = chat.indexOf(".then(cb=>projectCanonicalCbCards(cb,status,seq))");
  const bridge = chat.indexOf('bridgeResult={data:await loadBridge()}');
  assert.ok(progressive >= 0 && bridge > progressive, 'CB cards must project before history fetch');
  assert.match(chat, /function projectCanonicalCbCards\(cb,status,seq\)/);
  assert.equal((chat.match(/!\['COSTING','PURCHASE'\]\.includes\(String\(id\)\.toUpperCase\(\)\)/g) || []).length, 2);
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
