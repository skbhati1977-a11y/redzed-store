const {test}=require('node:test');const assert=require('node:assert/strict');const {JSDOM}=require('jsdom');const fs=require('node:fs');const path=require('node:path');
const src=fs.readFileSync(path.join(__dirname,'../../real-chat-cross-party-notifications-test67.js'),'utf8');
const msg=(id,time,kind='STAFF')=>({id,created_at:new Date(time).toISOString(),sender_kind:kind,sender_name:'Sales',body:'Collection updated'});
async function run(staff){
 let rows=[],notices=0;const d=new JSDOM(staff?'<div id="inboxRows"></div>':'<b id="chatTitle">REDZED</b>',{url:'https://example.test/chat',runScripts:'outside-only'});
 d.window.RF853={rpc:async n=>n.includes('actor_profile')?{}:rows};
 d.window.Notification=class{static permission='granted';constructor(){notices++}};
 d.window.eval(src);const call=async r=>{rows=r;await d.window.RF853.rpc(staff?'rr_chat_staff_messages_v9434':'rr_chat_customer_messages_v9434',{p_chat_id:'party',p_token:'token'});await new Promise(r=>setTimeout(r,5))};
 return {d,call,count:()=>notices};
}
test('Sales history, reopening and even new rows never trigger this party alert path',async()=>{const x=await run(true);try{await x.call([msg('old',Date.now()-86400000)]);await x.call([msg('new',Date.now()+1000)]);assert.equal(x.count(),0);assert.equal(x.d.window.document.getElementById('rrCrossPartyNotice67'),null)}finally{x.d.window.close()}});
test('party baseline and older history silent; new Sales activity alerts once; own activity silent',async()=>{const x=await run(false);try{const now=Date.now();await x.call([]);await x.call([msg('old',now-86400000)]);assert.equal(x.count(),0);await x.call([msg('fresh',now+1000)]);assert.equal(x.count(),1);await x.call([msg('fresh',now+1000)]);assert.equal(x.count(),1);await x.call([msg('own',now+2000,'CUSTOMER')]);assert.equal(x.count(),1)}finally{x.d.window.close()}});
test('new collection notification carries its exact token and cycle',async()=>{
 const x=await run(false);try{
  const message={...msg('new',Date.now()+1000),payload:{url:'https://example.test/s.html?t=new-party-token&r=req-a',direct_collection_cycle_id:'cycle-a'}};
  const target=new URL(x.d.window.RRChatActivityTarget71(message));assert.equal(target.searchParams.get('t'),'new-party-token');assert.equal(target.searchParams.get('collection_cycle_id'),'cycle-a');assert.equal(target.searchParams.get('open'),'collection');
  assert.equal(x.d.window.RRChatActivityTarget71({...message,payload:{url:'https://evil.test/s.html?t=bad'}}),x.d.window.location.href);
 }finally{x.d.window.close()}
});
test('notification tap navigates the matching collection tab and never another party surface',async()=>{
 const vm=require('node:vm'),listeners={},actions=[];
 const target='https://example.test/s.html?t=party-new&open=collection';
 const windows=[{url:'https://example.test/other.html',navigate:async()=>actions.push('wrong')},{url:'https://example.test/s.html?t=party-old',navigate:async url=>{actions.push(url);return {focus:async()=>actions.push('focus')}}}];
 const self={location:{href:'https://example.test/redzed-sw-test67.js',origin:'https://example.test'},addEventListener:(n,f)=>listeners[n]=f,clients:{matchAll:async()=>windows,openWindow:async u=>actions.push(u)}};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../redzed-sw-test67.js'),'utf8'),{self,URL});
 let task;listeners.notificationclick({notification:{data:{url:target},close:()=>{}},waitUntil:p=>task=p});await task;assert.deepEqual(actions,[target,'focus']);
 actions.length=0;windows.length=0;listeners.notificationclick({notification:{data:{url:target},close:()=>{}},waitUntil:p=>task=p});await task;assert.deepEqual(actions,[target]);
});
