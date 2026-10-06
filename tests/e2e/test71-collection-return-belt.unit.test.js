const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {JSDOM}=require('jsdom');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-direct-cycle-history-test71.js'),'utf8');
async function run(cycle='cycle-new',chat='chat-buyer',existing=false){
 const dom=new JSDOM('<section class="chat"><div id="msgs" data-chat-id="chat-buyer"><div class="msg" data-rr-cycle71="cycle-new" data-rr-workflow71="1">Hidden collection message</div></div><div class="compose"></div></section><div id="flash"></div>',{url:'https://example.com/real-sales-live-chat-v9434.html?chat_id=chat-buyer&collection_cycle_id=cycle-new&'+(existing?'focus_collection=1&collection_notice=existing':'focus_message_id=msg-new')}),w=dom.window;
 w.RRActiveSalesChat71=()=>chat;w.RRSalesChatActions71={context:()=>({channel:'GROUP'})};w.RF853={rpc:async()=>({collection_cycle_id:cycle,collection_display_no:'COL1',collection_update_no:2,live_status:'NEW COLLECTION'})};
 const context={window:w,document:w.document,location:w.location,URLSearchParams,URL,CSS:{escape:x=>x},RF853:w.RF853,MutationObserver:w.MutationObserver,innerHeight:800,requestAnimationFrame:cb=>setImmediate(()=>{if(!w.closed)cb()}),setTimeout:()=>1,setInterval:()=>1,console};
 vm.runInNewContext(source,context);for(let i=0;i<6;i++)await new Promise(setImmediate);return {dom,w};
}
test('Return focus highlights and focuses the visible live belt even when workflow message is hidden',async()=>{
 const x=await run();try{const d=x.w.document,host=d.getElementById('rrSalesCycleLive71');assert.equal(host.hidden,false);assert.ok(host.classList.contains('rrCollectionReturnFocus71'));assert.equal(d.activeElement,host.querySelector('.rrLiveBelt71'));assert.match(d.getElementById('flash').textContent,/Collection sent ✓ · COL1 · UPDATE 2/);assert.equal(d.querySelector('.msg').style.display,'none');}finally{x.dom.window.close()}
});
test('Return focus never highlights another customer or collection cycle',async()=>{
 for(const [cycle,chat] of [['other-cycle','chat-buyer'],['cycle-new','other-chat']]){const x=await run(cycle,chat);try{assert.ok(!x.w.document.querySelector('.rrCollectionReturnFocus71'));assert.equal(x.w.document.getElementById('flash').textContent,'');}finally{x.dom.window.close()}}
});

test('No-new-design return focuses existing collection belt and shows honest status',async()=>{
 const x=await run('cycle-new','chat-buyer',true);try{assert.ok(x.w.document.querySelector('.rrCollectionReturnFocus71'));assert.match(x.w.document.getElementById('flash').textContent,/Existing collection/);assert.ok(!x.w.document.getElementById('flash').textContent.includes('Collection sent'));}finally{x.dom.window.close()}
});
