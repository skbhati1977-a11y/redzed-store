'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');const fs=require('node:fs');const path=require('node:path');
const source=n=>fs.readFileSync(path.join(__dirname,'../..',n),'utf8');
const req='e053b33c-d5b0-402b-9435-848b35fead13';
const data={id:req,requirement_display_no:'RZ REQUIREMENT 21',collection_display_no:'RZ COLLECTION 01',status:'READY_FOR_PI',can_prepare_pi:true,can_add_update:true,lines:[{lot_no:'N2777',requested_qty:12,accepted_qty:8}]};
const tick=ms=>new Promise(r=>setTimeout(r,ms||25));
async function setup(rpc){
 const d=new JSDOM('<div id="inboxRows"><div class="chatrow on" data-chat="chat-a"></div></div><b id="chatTitle">LUKMAN SALES</b><div id="msgs"><div class="msg"><div>[REQ:'+req+']</div><time>now</time></div></div><div id="flash"></div>',{url:'https://example.test/real-sales-live-chat-v9434.html',runScripts:'outside-only'});
 d.window.RF853={rpc};d.window.CSS={escape:s=>s};
 // Exercise the production timeout without making regression tests wait 8s.
 const native=d.window.setTimeout.bind(d.window);d.window.setTimeout=(fn,ms,...args)=>native(fn,ms===8000?60:ms,...args);
 for(const f of ['real-chat-requirement-flow-v9508.js','real-chat-requirement-identity-v9682.js'])d.window.eval(source(f));
 await tick();return d;
}
test('fresh sessions open immediately and metadata/click share one detail request',async()=>{
 for(let session=0;session<3;session++){
  let calls=0,resolve;const d=await setup(()=>{calls++;return new Promise(r=>resolve=r)});
  try{
   d.window.document.querySelector('.rrReqOpen9508').click();
   assert.ok(d.window.document.getElementById('rrReqBack9508').classList.contains('on'));
   d.window.document.querySelector('.rrReqOpen9508').click();assert.equal(calls,1);
   resolve(data);await tick();assert.match(d.window.document.getElementById('rrReqBody9508').textContent,/N2777/);assert.equal(calls,1);
   await tick(100);assert.equal(calls,1);
  }finally{d.window.close()}
 }
});
test('failed cold prefetch is evicted and next tap succeeds',async()=>{
 let calls=0;const d=await setup(()=>++calls===1?Promise.reject(Error('offline')):Promise.resolve(data));
 try{d.window.document.querySelector('.rrReqOpen9508').click();await tick();assert.match(d.window.document.getElementById('rrReqBody9508').textContent,/N2777/);assert.equal(calls,2)}finally{d.window.close()}
});
test('hung connection shows Retry; late response cannot replace the retry result',async()=>{
 let calls=0,oldResolve;const d=await setup(()=>++calls===1?new Promise(r=>oldResolve=r):Promise.resolve(data));
 try{
  d.window.document.querySelector('.rrReqOpen9508').click();await tick(80);
  d.window.document.getElementById('rrReqRetry71').click();await tick();
  assert.match(d.window.document.getElementById('rrReqBody9508').textContent,/N2777/);
  oldResolve({...data,lines:[{lot_no:'STALE'}]});await tick();assert.doesNotMatch(d.window.document.getElementById('rrReqBody9508').textContent,/STALE/);
 }finally{d.window.close()}
});
test('switching party or closing sheet prevents late render and stale PI actions',async()=>{
 let resolve;const d=await setup(()=>new Promise(r=>resolve=r));
 try{
  d.window.document.querySelector('.rrReqOpen9508').click();
  d.window.document.querySelector('.chatrow').dataset.chat='chat-b';resolve(data);await tick();
  assert.doesNotMatch(d.window.document.getElementById('rrReqBody9508').textContent,/N2777/);
  assert.equal(d.window.document.getElementById('rrReqPi9508').disabled,true);
 }finally{d.window.close()}
});
test('one-row refresh poll does not evict prefetched detail; actual update does',async()=>{
 let details=0;const d=await setup((name,args)=>name==='rr_chat_requirement_detail_v9508'?(details++,Promise.resolve(data)):Promise.resolve([{id:'message',payload:{requirement_update_no:args.rev||1}}]));
 try{
  await d.window.RF853.rpc('rr_chat_staff_messages_v9434',{p_chat_id:'chat-a',p_limit:1});await tick();
  d.window.document.querySelector('.rrReqOpen9508').click();await tick();assert.equal(details,1);
  await d.window.RF853.rpc('rr_chat_staff_messages_v9434',{p_chat_id:'chat-a',p_limit:200,rev:2});await tick();assert.equal(details,2);
 }finally{d.window.close()}
});
test('PDF decoration never refetches inbox/messages after unrelated DOM changes',async()=>{const d=new JSDOM('<div id="msgs"></div><div id="flash"></div>',{url:'https://example.test/real-sales-live-chat-v9434.html',runScripts:'outside-only'}),calls=[];try{d.window.RF853={rpc:async(n,a)=>{calls.push(n);return []}};d.window.eval(source('real-chat-pdf-attachment-render-v9573.js'));for(let i=0;i<10;i++){d.window.document.getElementById('msgs').appendChild(d.window.document.createElement('div'));await tick(5)}await tick(150);assert.equal(calls.length,0);await d.window.RF853.rpc('rr_chat_staff_messages_v9479',{p_chat_id:'chat-a'});await tick();assert.deepEqual(calls,['rr_chat_staff_messages_v9479'])}finally{d.window.close()}});
test('fresh requirement context survives an inbox rerender without selected row',async()=>{const d=await setup(()=>Promise.resolve(data));try{d.window.RRActiveSalesChat71=()=> 'chat-a';d.window.document.getElementById('inboxRows').innerHTML='';d.window.document.querySelector('.rrReqOpen9508').click();await tick();assert.ok(d.window.document.getElementById('rrReqBack9508').classList.contains('on'));assert.match(d.window.document.getElementById('rrReqBody9508').textContent,/N2777/)}finally{d.window.close()}});

test('saved requirement exposes Open PI, Resend and Outside JPG actions',async()=>{const d=await setup(()=>Promise.resolve({...data,can_prepare_pi:false,pi:{id:'saved-pi',pi_no:'10/002'}}));try{d.window.document.querySelector('.rrReqOpen9508').click();await tick();assert.equal(d.window.document.getElementById('rrReqPi9508').disabled,false);assert.equal(d.window.document.querySelectorAll('[data-req-invoice-action]').length,2);assert.match(d.window.document.getElementById('rrReqBack9508').textContent,/SHARE JPG OUTSIDE/);}finally{d.window.close()}});

test('requirement resend sends its exact saved PI and party chat once on double tap',async()=>{const d=await setup(()=>Promise.resolve({...data,can_prepare_pi:false,pi:{id:'saved-pi',pi_no:'10/002'}}));const calls=[];let finish;try{d.window.RRPIReceipt71={send:(...args)=>{calls.push(args);return new Promise(r=>finish=r)}};d.window.document.querySelector('.rrReqOpen9508').click();await tick();const b=d.window.document.querySelector('[data-req-invoice-action="resend"]');b.click();b.click();assert.equal(calls.length,1);assert.equal(calls[0][0],'saved-pi');assert.equal(calls[0][1],'chat-a');assert.equal(calls[0][3].resend,true);finish({sent:true});await tick();assert.match(b.textContent,/RESENT/);}finally{d.window.close()}});
