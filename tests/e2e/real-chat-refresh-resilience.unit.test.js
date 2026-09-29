const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { functionSource, installFunctions } = require('./helpers/source-functions');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const shell = fs.readFileSync('test70-cb-purchase-real-chat-pilot.html', 'utf8');
test('Real Chat requests the canonical bounded history window', () => {
  const bridge = functionSource(chat, 'loadBridge');
  assert.match(bridge, /rr_real_chat_conversation_history_v83',\{p_limit:2000\}/);
  assert.doesNotMatch(bridge, /p_limit:5000/);
  assert.ok(Number.parseInt(shell.match(/test70-real-chat-live-v70\.js\?v=([^"\s]+)/)?.[1],10) >= 633);
});
test('auxiliary projection timeouts cannot discard canonical CB cards', () => {
  assert.match(chat, /\.then\(cb=>projectCanonicalCbCards\(cb,status,seq\)\)/);
  assert.match(chat, /const \[workResult,cbResult\]=await Promise\.all\(\[workJob,cbJob\]\)/);
  assert.match(chat, /workRequest\.then\(data=>\(\{data\}\)\)\.catch\(error=>\(\{error\}\)\)/);
  assert.match(chat, /try\{const eligible=await rpc\('rr_real_chat_assignable_lots_v125'\);projection\.eligible=eligible\}catch\(error\)\{errors\.push\(error\)\}/);
  assert.match(chat, /try\{const mediaMap=await rpc\('rr_real_chat_media_map_v1'\);projection\.mediaMap=mediaMap\}catch\(error\)\{errors\.push\(error\)\}/);
  assert.match(chat, /Object\.prototype\.hasOwnProperty\.call\(projection\|\|\{\},'history'\)/);
  assert.doesNotMatch(chat, /clearBridgeProjection/);
  assert.match(chat, /S\.cbCards=arr\(cb\?\.cards\)/);
  assert.match(chat, /history temporarily unavailable/);
});
test('CB projection renders before slow history and skips unrelated production supplements', () => {
  const progressive = chat.indexOf('.then(cb=>projectCanonicalCbCards(cb,status,seq))');
  const bridge = chat.indexOf('await refreshBridgeProjection()');
  assert.ok(progressive >= 0 && bridge > progressive);
  assert.equal((chat.match(/!\['COSTING','PURCHASE'\]\.includes\(String\(id\)\.toUpperCase\(\)\)/g) || []).length, 2);
});
test('history refresh is global and single-flight despite a navigation change', async () => {
  let finish, calls=0, applied=0;
  const scope = { S:{bridgeRefresh:null,bridgeLoadedAt:0}, console,
    loadBridge:()=>{calls++;return new Promise(resolve=>{finish=resolve;});},
    applyBridgeProjection:()=>{applied++;},renderBridgeProjection(){},refreshBridgeAuxiliary(){} };
  installFunctions(chat,scope,['refreshBridgeProjection']);
  const first=scope.refreshBridgeProjection(), second=scope.refreshBridgeProjection();
  assert.equal(first,second); assert.equal(calls,1);
  scope.S.loadSeq=200; scope.S.status='OPEN'; finish({history:[]}); await first;
  assert.equal(applied,1); assert.equal(scope.S.bridgeRefresh,null);
});
test('instant frontend search does not wait on history or launch three competing searches', () => {
  const load=functionSource(chat,'load');
  assert.match(load,/const workRequest=search\?Promise\.resolve\(\{cards:S\.cards,related_terms:S\.searchTerms,actor:S\.actor,frontend_search:true\}\)/);
  assert.match(load,/bridgeNeeded=fast&&!search&&!S\.history\.length/);
  assert.doesNotMatch(load,/bridgeBarrier\.then\(\(\)=>loadSearchWork/);
  assert.doesNotMatch(load,/Promise\.all\(\["OPEN","WORKING","CLOSE"\]\.map/);
  assert.equal((chat.match(/kind==='group'&&!S\.search&&\['WORKING','CLOSE'\]/g)||[]).length,2);
});
test('embedded action close restores same-card focus before and after refresh', async () => {
  const events=[], origin={active:{kind:'group',id:'PURCHASE'},status:'WORKING',scroll:50};
  const scope={S:{actionOrigin:origin,actionClosing:false}, $:()=>({}),
    restoreActionOrigin:()=>events.push('focus'),load:async()=>events.push('load'),
    installEmptyStateObserverV707(){},syncStatusButtons(){},renderActive(){}};
  installFunctions(chat,scope,['closeActionForm']);
  await Promise.all([scope.closeActionForm(true),scope.closeActionForm(true)]);
  assert.deepEqual(events,['focus','load','focus']);
  assert.equal(scope.S.actionClosing,false);
  assert.equal(scope.S.active,origin.active);
  assert.match(chat,/getAttribute\('src'\)===\'about:blank\'/);
  assert.match(chat,/S\.returnFocusCb=event\.data\.focus/);
});
test('CLOSE card expansion survives canonical and auxiliary refresh rerenders', () => {
  assert.match(chat,/data-closed-key=/);
  assert.match(chat,/function expandedClosedCardKeys\(\)/);
  assert.match(chat,/function restoreExpandedClosedCards\(keys\)/);
  assert.match(chat,/const expandedClosed=expandedClosedCardKeys\(\);[\s\S]*?restoreExpandedClosedCards\(expandedClosed\)/);
});
