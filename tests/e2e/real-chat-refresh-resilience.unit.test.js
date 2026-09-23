const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const shell = fs.readFileSync('test70-cb-purchase-real-chat-pilot.html', 'utf8');

test('Real Chat requests the canonical bounded history window', () => {
  const bridge = chat.match(/async function loadBridge\(\)\{[\s\S]*?\nasync function load\(/)?.[0] || '';
  assert.match(bridge, /rr_real_chat_conversation_history_v83',\{p_limit:2000\}/);
  assert.doesNotMatch(bridge, /p_limit:5000/);
  assert.match(shell, /test70-real-chat-live-v70\.js\?v=630/);
});

test('auxiliary projection timeouts cannot discard canonical CB cards', () => {
  assert.match(chat, /\.then\(cb=>projectCanonicalCbCards\(cb,status,seq\)\)/);
  assert.match(chat, /const \[d,workResult,cb\]=await Promise\.all\(\[directory,workJob,cbJob\]\)/);
  assert.match(chat, /workRequest\.then\(data=>\(\{data\}\)\)\.catch\(error=>\(\{error\}\)\)/);
  assert.match(chat, /try\{const eligible=await rpc\('rr_real_chat_assignable_lots_v125'\);projection\.eligible=eligible\}catch\(error\)\{errors\.push\(error\)\}/);
  assert.match(chat, /try\{const mediaMap=await rpc\('rr_real_chat_media_map_v1'\);projection\.mediaMap=mediaMap\}catch\(error\)\{errors\.push\(error\)\}/);
  assert.match(chat, /Object\.prototype\.hasOwnProperty\.call\(projection\|\|\{\},'history'\)/);
  assert.doesNotMatch(chat, /clearBridgeProjection/);
  assert.match(chat, /S\.cbCards=arr\(cb\?\.cards\)/);
  assert.match(chat, /history temporarily unavailable/);
});

test('CB projection renders before slow history and skips unrelated production supplements', () => {
  const progressive = chat.indexOf(".then(cb=>projectCanonicalCbCards(cb,status,seq))");
  const bridge = chat.indexOf('await refreshBridgeProjection()');
  assert.ok(progressive >= 0 && bridge > progressive, 'CB cards must project before history fetch');
  assert.match(chat, /function projectCanonicalCbCards\(cb,status,seq\)/);
  assert.equal((chat.match(/!\['COSTING','PURCHASE'\]\.includes\(String\(id\)\.toUpperCase\(\)\)/g) || []).length, 2);
});

test('history refresh is global, single-flight and survives a fast search sequence change', () => {
  assert.match(chat, /bridgeRefresh:null/);
  assert.match(chat, /function refreshBridgeProjection\(force=false\)\{if\(S\.bridgeRefresh\)return S\.bridgeRefresh/);
  assert.match(chat, /applyBridgeProjection\(projection\);S\.bridgeLoadedAt=Date\.now\(\);S\.bridgeWarning='';renderBridgeProjection\(\)/);
  assert.match(chat, /const bridgeNeeded=fast&&\(!!search\|\|!S\.history\.length\),bridgeBarrier=bridgeNeeded\?refreshBridgeProjection\(!!search\)/);
  const bridgeRefresh = chat.match(/function refreshBridgeProjection\(force=false\)[\s\S]*?\nasync function loadSearchWork/)?.[0] || '';
  assert.doesNotMatch(bridgeRefresh, /loadSeq|seq!==|status!==/);
});

test('search waits for canonical history and avoids three competing history-time queries', () => {
  assert.match(chat, /const workRequest=search\?bridgeBarrier\.then\(\(\)=>loadSearchWork\(search,status\)\)/);
  assert.match(chat, /for\(const searchStatus of states\)\{try\{const data=await rpc\('rr_real_chat_work_search_v10'/);
  assert.doesNotMatch(chat, /Promise\.all\(\["OPEN","WORKING","CLOSE"\]\.map/);
  assert.equal((chat.match(/kind==='group'&&!S\.search&&\['WORKING','CLOSE'\]/g) || []).length, 2);
});

test('embedded action close is single-flight and restores same-card focus around refresh', () => {
  const close = chat.match(/function restoreActionOrigin\(origin\)[\s\S]*?\nasync function openChatSubmit/)?.[0] || '';
  assert.match(close, /if\(S\.actionClosing\|\|\(refresh&&!S\.actionOrigin\)\)return/);
  const before = close.indexOf('restoreActionOrigin(origin);await load(false)');
  assert.ok(before >= 0, 'focus/scroll must restore before the network refresh');
  assert.match(close, /await load\(false\);restoreActionOrigin\(origin\)/);
  assert.match(chat, /getAttribute\('src'\)===\'about:blank\'/);
  assert.match(chat, /S\.actionClosing\)return/);
  assert.match(chat, /S\.returnFocusCb=event\.data\.focus/);
  assert.match(chat, /const focusedCb=S\.returnFocusCb\|\|document\.activeElement\?\.closest\?\.\('\[data-cb-no\]'\)/);
  assert.match(chat, /if\(focusedCb\)focusCbCard\(focusedCb,focusedCb===S\.returnFocusCb\)/);
});
