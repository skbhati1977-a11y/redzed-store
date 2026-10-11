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
  assert.match(shell,/test70-real-chat-live-v70\.js\?v=(?:TEST71_[A-Z0-9_]+|\d{3,})"/);
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
  assert.match(chat,/!\['COSTING','PURCHASE'\]\.includes\(String\(id\)\.toUpperCase\(\)\)/);
  assert.match(chat,/!RR_PRODUCTION_DEPARTMENTS_V763\.has\(String\(id\)\.toUpperCase\(\)\)&&!\['FABRICATION','COSTING','PURCHASE'\]\.includes/);
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
  assert.match(chat,/kind==='group'&&!S\.search&&\(S\.status==='CLOSE'\|\|S\.status==='WORKING'&&!RR_PRODUCTION_DEPARTMENTS_V763\.has/);
  assert.match(chat,/kind==='group'&&!S\.search&&\['WORKING','CLOSE'\]\.includes\(S\.status\)&&!RR_PRODUCTION_DEPARTMENTS_V763\.has/);
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


test('empty-state observer preserves MC1 purchase form and stock cards', () => {
  const { JSDOM } = require('jsdom');
  for (const html of [
    '<article class="mcv504-card" data-mc-draft><select data-mc-fabric><option>Fabric</option></select></article>',
    '<article class="mcv504-card">LOT CONSUMPTION</article>',
    '<article class="mcv504-card">CLOSING STOCK</article>',
    '<section class="mcv504-stock-section">No Matching Cloth stock.</section>'
  ]) {
    const dom = new JSDOM('<div id="messages">'+html+'</div>');
    const box = dom.window.document.getElementById('messages');
    const scope = { $: id => dom.window.document.getElementById(id), S:{status:'OPEN'}, emptyStateV705:()=>'<div class="rr-empty-v705">No cards</div>' };
    installFunctions(chat, scope, ['ensureEmptyStateV708']);
    const before = box.innerHTML;
    scope.ensureEmptyStateV708();
    assert.equal(box.innerHTML, before);
    dom.window.close();
  }
});
test('empty-state observer still repairs a genuinely empty feed', () => {
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM('<div id="messages"></div>');
  const scope = { $:id=>dom.window.document.getElementById(id), S:{status:'OPEN'}, emptyStateV705:()=>'<div class="rr-empty-v705">No cards</div>' };
  installFunctions(chat, scope, ['ensureEmptyStateV708']);
  scope.ensureEmptyStateV708();
  assert.equal(dom.window.document.querySelector('.rr-empty-v705').textContent, 'No cards');
  dom.window.close();
});

test('late initial directory preserves an MC1 workflow chosen while loading', async () => {
  let finish, rootRenders=0;
  const scope={S:{loadSeq:0,navigationSeq:0,status:'OPEN',search:'',active:null,history:[],departments:[],actor:{}},window:{},
    $:()=>({textContent:''}),console,arr:x=>Array.isArray(x)?x:[],
    rpc:()=>new Promise(resolve=>{finish=resolve}),
    actAsScope:d=>d,updateProjectionState(){},saveCache(){},inbox:async()=>{rootRenders++;}};
  installFunctions(chat,scope,['load']);
  const pending=scope.load(false);
  scope.S.navigationSeq++;
  scope.S.active={kind:'workflow',id:'1:1'};
  finish({departments:[],people:[],actor:{role:'SUPER_ADMIN'}});
  await pending;
  assert.equal(rootRenders,0);
  assert.deepEqual(scope.S.active,{kind:'workflow',id:'1:1'});
  assert.equal(scope.S.actor.role,'SUPER_ADMIN');
});
test('initial view restoration cannot replace a newer user navigation', async () => {
  let rootRenders=0;
  const active={kind:'workflow',id:'1:1'};
  const scope={S:{navigationSeq:1,active},inbox:async()=>{rootRenders++;},restoreView(){throw Error('Stale restore');},openChat(){throw Error('Stale open');}};
  installFunctions(chat,scope,['restoreInitialView71']);
  await scope.restoreInitialView71({view:'inbox'},new URLSearchParams(),0);
  assert.equal(rootRenders,0);assert.equal(scope.S.active,active);
  await scope.restoreInitialView71({view:'inbox'},new URLSearchParams(),1);
  assert.equal(rootRenders,1);assert.equal(scope.S.active,null);
});

test('initial conversation renders before history hydration and is not reopened afterward', async () => {
  const boot=functionSource(chat,'boot');
  const renderAt=boot.indexOf("if(resumeState.view!=='inbox')restoreView(resumeState)"), loadAt=boot.indexOf('await load(false)');
  assert.ok(renderAt>=0 && loadAt>renderAt);
  const active={kind:'group',id:'STITCHING'};
  const scope={S:{navigationSeq:1,active},restoreView(){throw Error('Conversation reopened');},inbox(){throw Error('Conversation replaced');}};
  installFunctions(chat,scope,['restoreInitialView71']);
  await scope.restoreInitialView71({view:'chat',kind:'group',id:'STITCHING'},new URLSearchParams(),1);
  assert.equal(scope.S.active,active);
});

function mc1WorkingFixture(rpc) {
  const {JSDOM}=require('jsdom');
  const dom=new JSDOM('<div id="drawer"></div><div id="chatName"></div><div id="kind"></div><div id="manageStaffAction"></div><div id="contextAction"></div><div id="searchNotice"></div><div id="messages"></div><div id="inbox"></div><div id="chat"></div>');
  const scope={S:{mc1LoadSeq:0,status:'WORKING',search:''},$:id=>dom.window.document.getElementById(id),mc1Css(){},syncStatusButtons(){},syncWorkFilters(){},arr:x=>x||[],safe:x=>x,rpc,
    mc1ConsumptionCard:c=>'<article class="mcv504-card">'+c.lot_no+'</article>',mc1ClosingCard:c=>'<article class="mcv504-card">'+c.fabric_name+' '+c.closing_qty+'</article>',bindMc1History(){},err:e=>e.message};
  installFunctions(chat,scope,['openMc1Chat']);return {dom,scope};
}
test('MC1 WORKING exposes canonical closing stock without a retired CLOSE tab', async () => {
  const calls=[];
  const {dom,scope}=mc1WorkingFixture(async(name,p)=>{calls.push(p.p_status);return {cards:p.p_status==='WORKING'?[{lot_no:'TEST-LOT'}]:[{fabric_name:'TEST CLOTH',closing_qty:3}]};});
  await scope.openMc1Chat(1,1,false);
  assert.deepEqual(calls,['WORKING','CLOSE']);
  assert.match(scope.$('messages').textContent,/TEST-LOT/);
  assert.match(dom.window.document.querySelector('.mcv504-stock-section').textContent,/TEST CLOTH 3/);
  assert.equal(scope.S.status,'WORKING');dom.window.close();
});
test('MC1 stock failure preserves the available consumption records', async () => {
  const {dom,scope}=mc1WorkingFixture(async(name,p)=>{if(p.p_status==='CLOSE')throw Error('Stock temporarily unavailable');return {cards:[{lot_no:'TEST-LOT'}]};});
  await scope.openMc1Chat(1,1,false);
  assert.match(scope.$('messages').textContent,/TEST-LOT/);
  assert.match(scope.$('messages').textContent,/Stock temporarily unavailable/);dom.window.close();
});
test('a late MC1 stock reply cannot overwrite a newly selected conversation', async () => {
  let finish;
  const {dom,scope}=mc1WorkingFixture(async(name,p)=>{if(p.p_status==='CLOSE')return new Promise(resolve=>{finish=resolve});return {cards:[{lot_no:'TEST-LOT'}]};});
  const pending=scope.openMc1Chat(1,1,false);
  await new Promise(resolve=>setImmediate(resolve));
  assert.match(scope.$('messages').textContent,/TEST-LOT/);
  scope.S.active={kind:'group',id:'STITCHING'};scope.$('messages').textContent='New conversation';
  finish({cards:[{fabric_name:'STALE CLOTH',closing_qty:3}]});await pending;
  assert.equal(scope.$('messages').textContent,'New conversation');dom.window.close();
});
