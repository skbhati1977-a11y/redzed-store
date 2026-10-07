const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=name=>fs.readFileSync(path.join(fs.existsSync('dist/'+name)?'dist':'.',name),'utf8');
const part=(s,a,b)=>s.slice(s.indexOf(a),s.indexOf(b,s.indexOf(a)));
const esc=x=>String(x??'');

test('same display names still render customer on right and staff on left',()=>{
 const s=source('real-customer-fullscreen-secure-chat-v9648.js');
 const ctx={esc,ident:{name:'Sudesh Bhati'},Date,locationHtml:()=>'',attachmentHtml:()=>''};
 vm.runInNewContext(part(s,'function mh(m)','function paint(a)'),ctx);
 const msg={id:'1',sender_name:'Sudesh Bhati',body:'hi',created_at:'2026-10-07T00:39:00Z'};
 assert.match(ctx.mh({...msg,payload:{rr_customer_is_own:true}}),/class="fsm me"/);
 assert.match(ctx.mh({...msg,sender_kind:'CUSTOMER',payload:{rr_customer_is_own:false}}),/class="fsm "/);
 assert.match(ctx.mh(msg),/class="fsm "/);
 assert.notEqual(ctx.sig([{...msg,payload:{rr_customer_is_own:true}}]),ctx.sig([{...msg,payload:{rr_customer_is_own:false}}]));
 assert.match(s,/#fsMsgs>\.fsm\{align-self:flex-start!important/);
 assert.match(s,/\.fsm\.me\{align-self:flex-end!important/);
});

test('button uses collection U4 instead of unrelated activity 01',()=>{
 const s=source('real-customer-chat-commercial-actions-v9630.js'),card={dataset:{}},button={};
 const ctx={$:id=>id==='fsCollectionCard'?card:id==='fcOpen'?button:null,esc,setClosedMetrics(){},closedState(){},token:'old',actionToken:'old'};
 vm.runInNewContext(part(s,'function paintState(d)','async function refreshState'),ctx);
 ctx.paintState({collection_display_no:'RZ COLLECTION 12',collection_update_no:4,update_no:1,latest_collection_token:'latest'});
 assert.equal(button.textContent,'UPDATE RZ COLLECTION 12 · U4');
 assert.equal(card.dataset.rrUpdateNo,'4');assert.equal(ctx.actionToken,'latest');
 assert.doesNotMatch(s,/rrCustomerRequirementClosed58 #rrReqAvg9641/);
});

test('customer and staff live cards use one latest collection button without dropdowns',()=>{
 const s=source('real-direct-cycle-history-test71.js');let removed=0,panelCalls=0;
 const ctx={staff:false,state:{collection_cycle_id:'cycle'},document:{getElementById:()=>({remove:()=>removed++}),querySelectorAll:sel=>sel==='.rrCycleHistory71'?[{remove:()=>removed++}]:[]},panel:()=>{panelCalls++;return{};}};
 vm.runInNewContext(part(s,' function paint(){',' async function refresh'),ctx);ctx.paint();
 assert.equal(panelCalls,0);assert.equal(removed,2);
 assert.doesNotMatch(s,/#rrFSChat #fsCollectionCard\{display:none/);
 const htmlctx={staff:true,esc,date:()=>'',Number};
 vm.runInNewContext(part(s,' function markup(data){',' function beltMarkup'),htmlctx);
 const d={collection_display_no:'RZ COLLECTION 12',update_history:[{kind:'COLLECTION',update_no:4}]};
 assert.doesNotMatch(htmlctx.markup(d),/<details|<summary/);
 htmlctx.staff=false;assert.doesNotMatch(htmlctx.markup(d),/<details>/);
});

test('latest collection, summary and pricing reads use the same authorized token',async()=>{
 const calls=[],RF853={rpc:async(name,args)=>{calls.push([name,args]);return name==='rr_collection_current_state_v9633'?{latest_collection_token:'latest'}:{rows:[]};}};
 vm.runInNewContext(source('real-collection-cycle-share-adapter-v9686.js'),{window:{RF853},setTimeout(){}});
 for(const name of ['rr_market_share_view_v9420','rr_collection_customer_requirement_summary_v9637','rr_collection_customer_pricing_v9637'])await RF853.rpc(name,{p_token:'old'});
 assert.deepEqual(calls.filter(([n])=>n!=='rr_collection_current_state_v9633').map(([n,a])=>[n,a.p_token]),[
  ['rr_collection_cycle_share_view_v9686','latest'],['rr_collection_customer_requirement_summary_v9637','latest'],['rr_collection_customer_pricing_v9637','latest']]);
 await RF853.rpc('rr_chat_customer_messages_session_test71',{p_session_token:'session'});
 assert.equal(calls.at(-1)[1].p_session_token,'session');
});

test('quantity input is a bottom full-width child and preserves saved quantity',()=>{
 const s=source('real-customer-chat-collection-card-v9605.js');
 const ctx={esc,media:()=>[],savedQty:new Map([['RM006',58]]),stockLimit:r=>r.available_qty,money:String};
 vm.runInNewContext(part(s,'function card(r)','async function loadRows'),ctx);
 const html=ctx.card({lot_no:'RM006',available_qty:70,sale_rate:110});
 // Parse ancestry so an input nested in the narrow specification column fails.
 const stack=[];let ancestors;
 for(const tag of html.matchAll(/<\/?(?:article|div|label|input)\b[^>]*>/g)){
  const t=tag[0];if(t.startsWith('</')){stack.pop();continue;}
  if(t.startsWith('<input')){ancestors=[...stack];assert.match(t,/value="58"/);continue;}
  stack.push(t);
 }
 assert(ancestors.some(t=>/class="fc-qty"/.test(t)));
 assert(!ancestors.some(t=>/class="fc-body"/.test(t)));
 const css=source('real-customer-chat-collection-layout-v9623.js');
 assert.match(css,/'qty qty'/);assert.match(css,/\.fc-lot>\.fc-qty\{grid-area:qty!important/);
 assert.match(css,/min-height:58px!important/);assert.match(css,/width:100%!important/);
 assert.match(s,/p_token:activeCollectionToken,p_customer_name/);
});

test('all four metrics remain visible on completed collections; values retain rate math',()=>{
 const s=source('real-customer-requirement-state-v9641.js');
 const boxes=Object.fromEntries(['rrReqAvg9641','rrReqQty9641','rrReqAmt9641','rrAllAvg9641'].map(id=>[id,{style:{display:'none'},b:{}}]));
 let closed=false;
 const ctx={saved:new Map([['A',2],['B',3]]),pricing:new Map([['A',{net_rate:100,pricing_status:'RESOLVED'}],['B',{net_rate:200,pricing_status:'RESOLVED'}]]),history:{status:'RESOLVED',history_qty:10,history_net_value:1000,history_avg_per_pc:100},draftReady:false,panelOpen:()=>false,terminal:()=>closed,ensureReqStats(){},ensureAvgStats(){},money:n=>Number(n).toFixed(2),document:{getElementById:id=>boxes[id],querySelector:sel=>boxes[sel.split(' ')[0].slice(1)]?.b}};
 vm.runInNewContext(part(s,'  function metricsFromMap','  function paintCards'),ctx);
 ctx.paintMetrics();assert.equal(boxes.rrReqQty9641.b.textContent,'5 PCS');assert.equal(boxes.rrReqAmt9641.b.textContent,'₹800.00');assert.equal(boxes.rrReqAvg9641.b.textContent,'₹160.00');assert.equal(boxes.rrAllAvg9641.b.textContent,'₹120.00');
 closed=true;ctx.paintMetrics();assert.equal(boxes.rrAllAvg9641.b.textContent,'₹100.00');
 for(const box of Object.values(boxes))assert.equal(box.style.display,'flex');
 ctx.history={status:'NO_CI_HISTORY'};ctx.paintMetrics();assert.equal(boxes.rrAllAvg9641.b.textContent,'—');
});

test('four-column row survives component reparenting without duplicate summaries',()=>{
 const s=source('real-customer-requirement-layout-v9645.js');
 const nodes={};function node(id){const n={id,children:[],label:{textContent:'old'},querySelector:()=>n.label,insertBefore(child,before){if(child.parent){child.parent.children.splice(child.parent.children.indexOf(child),1);}const i=before?this.children.indexOf(before):this.children.length;this.children.splice(i,0,child);child.parent=this;}};nodes[id]=n;return n;}
 const chat=node('rrFSChat'),tabs=node('tabs');chat.querySelector=()=>tabs;tabs.insertAdjacentElement=(_,row)=>{tabs.nextElementSibling=row;nodes[row.id]=row;};
 for(const id of ['rrReqAvg9641','rrReqQty9641','rrReqAmt9641','rrAllAvg9641'])node(id);
 const ctx={ids:['rrReqAvg9641','rrReqQty9641','rrReqAmt9641','rrAllAvg9641'],labels:['AVG RATE','TOTAL PCS','AMOUNT','ALL TIME AVG'],document:{getElementById:id=>nodes[id],createElement:()=>node('temp')}};
 vm.runInNewContext(part(s,'  function align()','  function boot()'),ctx);
 assert.equal(ctx.align(),true);const row=nodes.rrCustomerSummary71;
 assert.deepEqual(row.children.map(n=>n.id),ctx.ids);const other=node('other');other.insertBefore(nodes.rrReqAmt9641,null);ctx.align();ctx.align();
 assert.equal(nodes.rrCustomerSummary71,row);assert.deepEqual(row.children.map(n=>n.id),ctx.ids);
 assert.match(s,/grid-template-columns:repeat\(4,minmax\(0,1fr\)\)/);assert.doesNotMatch(s,/display:contents/);
 assert.match(s,/height:calc\(100vh - 46px\)/);assert.match(s,/@supports\(height:100dvh\)/);
});
