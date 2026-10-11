const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{JSDOM}=require('jsdom');
test('chat shell does not reinsert a global notification setup popup on every page',()=>{
 const html=fs.readFileSync('test70-cb-purchase-real-chat-pilot.html','utf8');
 assert.doesNotMatch(html,/showPushSetup|rzPushSetupCurrent/);
 assert.match(html,/real-notification-permission-guard-v69\.js/);
});
test('Alter save success refreshes only its queue and never treats history-sync timeout as save failure',async()=>{
 const src=fs.readFileSync('test70-real-chat-live-v70.js','utf8'),start=src.indexOf('async function executeAlterInline('),end=src.indexOf('\nasync function openVendorPopup',start),calls=[],alerts=[];const c={confirm:()=>true,prompt:()=>'',rpc:async n=>{calls.push(n);if(n.includes('sync_e2e'))throw Error('timeout');return {ok:true}},S:Object.fromEntries(['statusCache','queueProjectionCache','alterCustodyCache','chatRenderCache','departmentCountCache'].map(k=>[k,new Map()])),renderActive:async()=>calls.push('refresh'),alert:v=>alerts.push(v),console,err:e=>e.message};vm.createContext(c);vm.runInContext(src.slice(start,end),c);const button={dataset:{alterAction:'KARIGAR_SUBMIT_GOOD',journeyId:'j',alterQty:'1'},textContent:'SUBMIT'};await c.executeAlterInline(button);assert.deepEqual(calls,['rr_chat_alter_action_test71','refresh']);assert.deepEqual(alerts,[]);assert.equal(button.textContent,'SAVED');assert.equal(button.disabled,true);
});
test('periodic active manufacturing refresh avoids global work-search before rendering its queue',async()=>{
 const src=fs.readFileSync('test70-real-chat-live-v70.js','utf8'),start=src.indexOf('async function load(fast=false){'),end=src.indexOf('\nfunction ',start);const c={S:{search:'',departments:[{}],active:{kind:'group',id:'FABRICATION'}},actAsActive:x=>x,renderActive:async a=>a.id};vm.createContext(c);vm.runInContext(src.slice(start,end),c);assert.equal(await c.load(true),'FABRICATION');
});
