const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('real-customer-chat-collection-card-v9605.js','utf8');
test('red cross is available only for zero required quantity',()=>{
 const render=source.slice(source.indexOf('function card(r)'),source.indexOf('async function loadRows()'));
 const context={media:()=>[],esc:String,money:String,stockLimit:()=>null,savedQty:new Map(),Number};vm.runInNewContext(render,context);
 const row={lot_no:'STYLE1',available_qty:30};assert.match(context.card(row),/data-fc-hide="STYLE1"[^>]*>×/);assert.doesNotMatch(context.card(row),/data-fc-hide="STYLE1"[^>]*hidden/);
 context.savedQty.set('STYLE1',7);assert.match(context.card(row),/data-fc-hide="STYLE1"[^>]*hidden/);
});
test('cross automatically hides when customer enters qty and reappears at zero',()=>{
 const listeners={};const context={document:{addEventListener:(name,callback)=>listeners[name]=callback},clampQuantity:el=>Number(el.value),Number};
 vm.runInNewContext(source.slice(source.indexOf('function bindQuantity()'),source.indexOf('function card(r)'))+';bindQuantity();',context);
 const cross={hidden:false},input={value:'9',dataset:{},matches:()=>true,closest:()=>({querySelector:()=>cross})};listeners.input({target:input});assert.equal(cross.hidden,true);input.value='0';listeners.input({target:input});assert.equal(cross.hidden,false);
});
test('closed collection opens the read-only viewer instead of quantity editor',async()=>{
 const handler=source.slice(source.indexOf('async function openPanel()'),source.indexOf('function closePanel()'));
 let readonly=0,editor=0;const context={rpc:async()=>({collection_status:'CLOSED',collection_cycle_id:'old'}),terminal:s=>s.collection_status==='CLOSED',closePanel(){},openReadOnly:()=>readonly++,setMode:()=>editor++,activeState:null,token:"approved"};vm.runInNewContext(handler,context);await context.openPanel();assert.equal(readonly,1);assert.equal(editor,0);
});
