const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {JSDOM}=require('jsdom');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-web-window-share-chooser-v9510.js'),'utf8');
async function run(fail=false,auto=true){
 const dom=new JSDOM('<div id="flash"></div><button id="shareBtn"></button><input class="ww-select" data-select="1101" type="checkbox" checked>',{url:'https://example.com/real-web-window-v9329.html?share_mode=chooser'}),w=dom.window;
 const location={search:'?share_mode=chooser',href:w.location.href},timers=[],calls=[];
 vm.runInNewContext(source,{window:w,document:w.document,location,URL,URLSearchParams,CSS:{escape:x=>x},Event:w.Event,console,setTimeout:(f,ms)=>{timers.push({f,ms});return timers.length},clearTimeout(){},RF853:{mode:()=> 'TEST',rpc:async(name,args)=>{calls.push(name);if(name==='rr_sales_collection_cards_test71')return {context:{customer_id:'buyer',collection_cycle_id:'cycle'},rows:fail==='skip'?[]:[{lot_no:'1101'}]};if(name==='rr_sales_collection_send_test71'){if(fail)throw Error('Send failed');return {chat_message_id:'message-new',collection_cycle_id:'cycle-new',token:'token'}};return []}}});
 w.document.dispatchEvent(new w.Event('DOMContentLoaded'));
 w.document.getElementById('rrMwCustomers9510').innerHTML='<label><input type="checkbox" data-chat="chat-buyer" data-name="Buyer" checked></label>';
 if(auto)w.document.getElementById('rrMwInternal9510').click();await new Promise(setImmediate);return {dom,w,location,timers,calls};
}
test('Confirmed internal collection send returns to exact customer and new collection message',async()=>{
 const x=await run();try{assert.match(x.w.document.getElementById('rrMwPrep9511').textContent,/Buyer: 1 sent/);const nav=x.timers.find(t=>t.ms===450);assert.ok(nav);nav.f();const u=new URL(x.location.href);assert.equal(u.pathname,'/real-sales-live-chat-v9434.html');assert.equal(u.searchParams.get('chat_id'),'chat-buyer');assert.equal(u.searchParams.get('focus_message_id'),'message-new');assert.equal(u.searchParams.get('collection_cycle_id'),'cycle-new');assert.equal(u.searchParams.get('followup'),'1');}finally{x.dom.window.close()}
});
test('Failed internal collection send reports failure and stays in chooser',async()=>{
 const x=await run(true);try{assert.match(x.w.document.getElementById('rrMwPrep9511').textContent,/Buyer: Send failed/);assert.ok(!x.timers.some(t=>t.ms===450));assert.equal(x.w.document.getElementById('rrMwInternal9510').disabled,false);}finally{x.dom.window.close()}
});

test('No eligible new designs still opens selected customer existing collection without pretending send succeeded',async()=>{
 const x=await run('skip');try{assert.ok(!x.calls.includes('rr_sales_collection_send_test71'));assert.match(x.w.document.getElementById('rrMwPrep9511').textContent,/Opening existing collection/);const nav=x.timers.find(t=>t.ms===450);assert.ok(nav);nav.f();const u=new URL(x.location.href);assert.equal(u.searchParams.get('chat_id'),'chat-buyer');assert.equal(u.searchParams.get('collection_cycle_id'),'cycle');assert.equal(u.searchParams.get('focus_collection'),'1');assert.equal(u.searchParams.get('collection_notice'),'existing');assert.equal(u.searchParams.get('focus_message_id'),null);}finally{x.dom.window.close()}
});

test('Selecting a customer hides previously sent cards and opens a customer scoped new-design list',async()=>{
 const x=await run(false,false);try{const d=x.w.document;d.body.insertAdjacentHTML('beforeend','<article class="ww-card" data-card="1101"><input class="ww-select" data-select="1101" checked type="checkbox"></article><article class="ww-card" data-card="SENT"><input class="ww-select" data-select="SENT" checked type="checkbox"></article>');d.querySelector('#rrMwCustomers9510 input').dispatchEvent(new x.w.Event('change',{bubbles:true}));await new Promise(setImmediate);assert.equal(d.querySelector('[data-card="SENT"]').hidden,true);assert.equal(d.querySelector('[data-card="SENT"] input').checked,false);assert.equal(d.querySelector('[data-card="1101"]').hidden,false);const u=new URL(d.querySelector('#rrMwPrep9511 a').href);assert.equal(u.searchParams.get('chat_id'),'chat-buyer');assert.equal(u.searchParams.get('from_chat'),'1');assert.equal(u.searchParams.get('collection_cycle_id'),'cycle');assert.ok(!x.calls.includes('rr_sales_collection_send_test71'));}finally{x.dom.window.close()}
});
