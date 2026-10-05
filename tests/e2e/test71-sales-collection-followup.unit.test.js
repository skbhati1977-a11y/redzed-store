'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM,VirtualConsole}=require('jsdom');
const root=path.resolve(__dirname,'../..');
const source=name=>fs.readFileSync(path.join(root,name),'utf8');
const tick=()=>new Promise(resolve=>setTimeout(resolve,20));
function dom(html,url,rpc){
 const errors=[];const vc=new VirtualConsole();
 vc.on('jsdomError',e=>{if(!/navigation/.test(e.message))errors.push(e.message)});
 const d=new JSDOM(html,{url,runScripts:'outside-only',virtualConsole:vc});
 d.window.RF853={rpc,mode:()=> 'TEST'};d.window.CSS={escape:s=>String(s)};
 d.window.alert=()=>{};d.window.confirm=()=>true;
 d.errors=errors;return d;
}
test('Sales list uses server eligibility, preserves identity and locks TEST scope',async()=>{
 const calls=[];const context={chat_id:'chat-a',customer_id:'party-a',customer_name:'Party A',collection_cycle_id:'cycle-a',
 requirement_id:'req-a',collection_display_no:'COLLECTION 01',categories:['Round Neck'],sent_lots:['OLD'],can_send:true};
 const d=dom(source('real-web-window-v9329.html'),'https://example.test/real-web-window-v9329.html?from_chat=1&chat_id=chat-a&collection_cycle_id=cycle-a&append_requirement_id=req-a',
 async(name,args)=>{calls.push({name,args});if(name==='rr_sales_collection_cards_test71')return {context,rows:[{lot_no:'NEW',category:'Round Neck',available_qty:24,media:[]}]};if(name==='rr_market_window_colours_v1')return {};throw Error('Unexpected RPC '+name)});
 try{
  d.window.eval(source('real-sales-collection-contract-test71.js'));
  d.window.eval(source('real-web-window-v9329.js'));await tick();
  assert.equal(d.window.document.querySelectorAll('[data-card]').length,1);
  assert.equal(d.window.document.querySelector('[data-card]').dataset.card,'NEW');
  assert.equal(calls[0].name,'rr_sales_collection_cards_test71');
  assert.equal(calls[0].args.p_collection_cycle_id,'cycle-a');
  assert.equal(calls[0].args.p_requirement_id,'req-a');
  assert.equal(d.window.document.getElementById('dataMode').disabled,true);
  assert.match(d.window.document.getElementById('rrCollectionContext71').textContent,/Round Neck/);
  assert.ok(!calls.some(x=>x.name==='rr_web_window_cards_v9329'));
  assert.deepEqual(d.errors,[]);
 }finally{d.window.close()}
});
test('Select & Send is one call on double tap and returns to the same collection',async()=>{
 const calls=[];let resolveSend;
 const context={chat_id:'chat-a',customer_id:'party-a',customer_name:'Party A',collection_cycle_id:'cycle-a',
 requirement_id:'req-a',collection_display_no:'COLLECTION 01',categories:['Round Neck'],sent_lots:[],can_send:true};
 const d=dom(source('real-web-window-v9329.html'),'https://example.test/real-web-window-v9329.html?from_chat=1&chat_id=chat-a&collection_cycle_id=cycle-a&append_requirement_id=req-a',
 async(name,args)=>{calls.push({name,args});if(name==='rr_sales_collection_cards_test71')return {context,rows:[{lot_no:'NEW',available_qty:24,media:[]}]};if(name==='rr_sales_collection_context_test71')return context;if(name==='rr_market_window_colours_v1')return {};if(name==='rr_sales_collection_send_test71')return new Promise(ok=>resolveSend=ok);throw Error(name)});
 try{
  d.window.eval(source('real-sales-collection-contract-test71.js'));d.window.eval(source('real-web-window-v9329.js'));
  d.window.eval(source('real-web-window-chat-share-v9507.js'));await tick();
  const checkbox=d.window.document.querySelector('[data-select]');checkbox.checked=true;
  checkbox.dispatchEvent(new d.window.Event('change',{bubbles:true}));
  const button=d.window.document.getElementById('sendChatBtn');
  button.click();button.dispatchEvent(new d.window.MouseEvent('click',{bubbles:true}));await tick();
  const sent=calls.filter(x=>x.name==='rr_sales_collection_send_test71');assert.equal(sent.length,1);
  assert.deepEqual(Array.from(sent[0].args.p_lots),['NEW']);
  assert.equal(sent[0].args.p_customer_id,'party-a');assert.equal(sent[0].args.p_collection_cycle_id,'cycle-a');assert.equal(sent[0].args.p_requirement_id,'req-a');
  resolveSend({token:'t',collection_cycle_id:'cycle-a',collection_display_no:'COLLECTION 01'});await tick();
  const returned=JSON.parse(d.window.sessionStorage.getItem('rr_real_chat_return_v9507'));
  assert.equal(returned.chat_id,'chat-a');assert.equal(returned.collection_cycle_id,'cycle-a');
  assert.match(d.window.document.getElementById('flash').textContent,/UPDATED/);
  assert.deepEqual(d.errors,[]);
 }finally{d.window.close()}
});
test('Detail follow-up keeps explicit cycle, switching parties cannot reuse it',async()=>{
 const context={chat_id:'chat-a',customer_id:'party-a',customer_name:'Party A',collection_cycle_id:'cycle-a',requirement_id:'req-a',categories:[],can_send:true};
 const calls=[];const d=dom('<div id="inboxRows"><div class="chatrow on" data-chat="chat-a"></div></div><div id="flash"></div>',
 'https://example.test/real-sales-live-chat-v9434.html?chat_id=chat-a&collection_cycle_id=cycle-a&followup=1',
 async(name,args)=>{calls.push({name,args});return {...context,chat_id:args.p_chat_id,collection_cycle_id:args.p_collection_cycle_id||'cycle-b'}});
 try{
  d.window.eval(source('real-chat-list-default-v9690.js'));assert.equal(new URL(d.window.location.href).searchParams.get('chat_id'),'chat-a');
  d.window.eval(source('real-sales-collection-contract-test71.js'));
  const url=new URL(await d.window.RRSalesCollection.open());
  assert.equal(url.searchParams.get('collection_cycle_id'),'cycle-a');assert.equal(url.searchParams.get('append_requirement_id'),'req-a');
  d.window.document.querySelector('.chatrow').dataset.chat='chat-b';
  await d.window.RRSalesCollection.open();
  assert.equal(calls.at(-1).args.p_chat_id,'chat-b');assert.equal(calls.at(-1).args.p_collection_cycle_id,null);
 }finally{d.window.close()}
});
test('Customer reload shows saved requirement and submits changed, zero and excess quantities unchanged',async()=>{
 const calls=[];const rows=[{lot_no:'NEW',available_qty:100,sale_rate:100,media:[]},{lot_no:'OLD',available_qty:2,sale_rate:100,media:[]}];
 const d=dom('<div id="rrFSChat"><div class="fstabs"></div><div class="fsmsgs"></div><div class="fscomp"></div></div>',
 'https://example.test/s.html?t=token',
 async(name,args)=>{calls.push({name,args});if(name==='rr_market_share_view_v9420')return {rows};
 if(name==='rr_collection_customer_requirement_summary_v9637')return {lines:[{lot_no:'OLD',requested_qty:12}]};
 if(name==='rr_collection_submit_requirement_v9588')return {requirement_no:'REQ 01'};throw Error(name)});
 try{
  d.window.localStorage.setItem('rr_market_customer_identity_v9423',JSON.stringify({name:'Party A',mobile:'9999999999'}));
  d.window.eval(source('real-customer-chat-collection-card-v9605.js'));
  await new Promise(r=>setTimeout(r,230));
  d.window.document.getElementById('fcOpen').click();await tick();
  assert.equal(d.window.document.querySelector('[data-fcq="OLD"]').value,'12');
  d.window.document.querySelector('[data-fcq="OLD"]').value='0';
  d.window.document.querySelector('[data-fcq="NEW"]').value='120';
  d.window.document.getElementById('fcSubmit').click();await tick();
  const call=calls.find(x=>x.name==='rr_collection_submit_requirement_v9588');
  assert.equal(call.args.p_lines.find(x=>x.lot_no==='OLD').qty,0);
  assert.equal(call.args.p_lines.find(x=>x.lot_no==='NEW').qty,120);
  assert.deepEqual(d.errors,[]);
 }finally{d.window.close()}
});
test('Root follow-up links carry the exact collection and old hide script is retired',()=>{
 const js=source('test70-real-chat-live-v70.js');
 assert.match(js,/collection_cycle_id='\+encodeURIComponent\(c.id\|\|''\)/);
 assert.match(js,/followup=1/);
 assert.ok(!source('real-web-window-v9329.html').includes('real-web-window-exclude-used-v9512.js'));
 assert.match(source('real-web-window-v9329.html'),/real-sales-collection-contract-test71/);
});
test('Bulk internal collection send targets each party with its own eligible designs',async()=>{
 const calls=[];const d=dom(source('real-web-window-v9329.html')+'<article data-card="OLD"><input class="ww-select" data-select="OLD" type="checkbox" checked></article><article data-card="NEW"><input class="ww-select" data-select="NEW" type="checkbox" checked></article>',
 'https://example.test/real-web-window-v9329.html?share_mode=chooser',
 async(name,args)=>{calls.push({name,args});
 if(name==='rr_chat_staff_inbox_v9434')return [{chat_id:'a',customer_name:'Party A'},{chat_id:'b',customer_name:'Party B'}];
 if(name==='rr_market_create_share_v9420')return {token:'outside-only'};
 if(name==='rr_sales_collection_cards_test71')return {context:{customer_id:'party-'+args.p_chat_id,collection_cycle_id:'cycle-'+args.p_chat_id,requirement_id:'req-'+args.p_chat_id},
 rows:args.p_chat_id==='a'?[{lot_no:'NEW'}]:[{lot_no:'OLD'}]};
 if(name==='rr_sales_collection_send_test71')return {token:'own-token',collection_cycle_id:args.p_collection_cycle_id};
 throw Error('Unexpected RPC '+name)});
 try{
  d.window.eval(source('real-web-window-share-chooser-v9510.js'));await tick();
  d.window.document.getElementById('rrMwTopBtn9510').click();await tick();
  d.window.document.querySelectorAll('#rrMwCustomers9510 input').forEach(el=>el.checked=true);
  d.window.document.getElementById('rrMwInternal9510').click();await tick();
  const sends=calls.filter(x=>x.name==='rr_sales_collection_send_test71');assert.equal(sends.length,2);
  assert.deepEqual(Array.from(sends[0].args.p_lots),['NEW']);assert.deepEqual(Array.from(sends[1].args.p_lots),['OLD']);
  assert.equal(sends[0].args.p_collection_cycle_id,'cycle-a');assert.equal(sends[1].args.p_collection_cycle_id,'cycle-b');
  assert.ok(!calls.some(x=>/^rr_chat_(send_staff|staff_upload)/.test(x.name)));
  assert.match(d.window.document.getElementById('rrMwPrep9511').textContent,/1 sent/);
  assert.deepEqual(d.errors,[]);
 }finally{d.window.close()}
});
