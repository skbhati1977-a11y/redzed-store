const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {JSDOM}=require('jsdom');
const code=fs.readFileSync(path.resolve(__dirname,'../../test71-readymade-real-chat.js'),'utf8');
const wait=()=>new Promise(r=>setTimeout(r,25));
async function setup(role='OWNER',status='WORKING'){
 const dom=new JSDOM('<div id="messages"></div>',{url:'https://example.com/chat',runScripts:'outside-only'}),w=dom.window;
 w.CSS={escape:x=>x};w.URL.createObjectURL=()=> 'blob:test';w.eval(code);
 const calls=[],c={stock_id:'s1',lot_no:'RM1',item_name:'Shirt',category:'Polo',size_text:'L / XL',available_qty:20,received_qty:24,approved_rate:150,approval_ready:true,market_ready:true,mapping_ready:true,missing_fields:[],image_url:'https://example.com/shirt.jpg',costing:role==='OWNER'?{purchase_cost_per_pc:100,salary_per_pc:10,overhead_per_pc:18,source_rate:150,costing_complete:true}:{costing_complete:true}};
 const s={actor:{role},status,search:'',db:{from:table=>({select(){return this},eq(){return this},order:async()=>({data:table==='rr_art_categories'?[{id:'cat1',category_name:'Polo'}]:[{id:'supplier1',supplier_name:'Supplier'},{id:'supplier2',supplier_name:'RDN'}],error:null})})},departmentCountCache:new Map(),departments:[{department_code:'PURCHASE'},{department_code:'CUTTING'}]};
 const rpc=async(n,p)=>{calls.push({n,p});if(n==='rr_rm_chat_fast_queue_test71')return{can_complete_mapping:['OWNER','ADMIN','MANAGER','ACCOUNTS'].includes(role),can_purchase:['OWNER','ADMIN','ACCOUNTS'].includes(role),can_approve:['OWNER','ADMIN'].includes(role),cards:[c],drafts:[],categories:['Polo'],counts:{OPEN:1,WORKING:1}};
 if(n==='rr_cb_category_defaults_get_v1')return{rows:[{art_category_id:'cat1',default_size_family:'L,XL,XXL'}]};if(n==='rr_rm_chat_save_test71')return{purchase_id:'p1',rate_notes:[]};if(n==='rr_chat_staff_inbox_v9434')return[{chat_id:'chat1',customer_name:'Buyer <One>'}];if(n==='rr_sales_collection_cards_test71')return{context:{customer_id:'buyer1',collection_cycle_id:'cycle1',requirement_id:null},rows:[{lot_no:'RM1'}]};return{quota_delta:40,rrq_balance:500};};
 const navigations=[];const ctx={navigate:url=>navigations.push(url),s,rpc,box:w.document.getElementById('messages'),owned:()=>true,changed:()=>{},notice:()=>{},refresh:()=>w.RRReadymadeChat.render(ctx)};
 await ctx.refresh();return{w,s,calls,ctx,navigations,close:()=>w.close()};
}
test('Readymade is first before CB and excluded for worker scope',async()=>{
 const x=await setup();try{x.w.RRReadymadeChat.directory(x.s);assert.deepEqual(Array.from(x.s.departments,d=>d.department_code),['READYMADE','PURCHASE','CUTTING']);x.s.actor.role='WORKER';x.w.RRReadymadeChat.directory(x.s);assert.equal(x.s.departments[0].department_code,'PURCHASE')}finally{x.close()}
});
test('OPEN purchase form posts canonical payload and moves to WORKING once',async()=>{
 const x=await setup('OWNER','OPEN');try{const d=x.w.document;d.querySelector('[data-new]').click();await wait();assert.equal(d.querySelector('[data-supplier]').tagName,'SELECT');assert.ok([...d.querySelector('[data-supplier]').options].some(x=>x.value==='RDN'));assert.equal(d.querySelector('[data-field="category"]').tagName,'SELECT');assert.equal(d.querySelector('[data-field="size_text"]').tagName,'SELECT');d.querySelector('[data-field="category"]').value='Polo';d.querySelector('[data-field="category"]').dispatchEvent(new x.w.Event('change'));assert.equal(d.querySelector('[data-field="size_text"]').value,'L, XL, XXL');const values={'data-supplier':'Supplier','data-bill':'B1','data-date':'2030-01-15'};for(const[k,v]of Object.entries(values))d.querySelector('['+k+']').value=v;
 const fields={lot_no:'RM2',item_name:'Polo garment',category:'Polo',size_text:'L, XL, XXL',qty:'24',purchase_rate:'100',final_rate:'150',final_image_url:'https://example.com/a.jpg'};for(const[k,v]of Object.entries(fields))d.querySelector('[data-field="'+k+'"]').value=v;
 const b=d.querySelector('[data-post]');b.click();b.click();await wait();assert.equal(x.calls.filter(c=>c.n==='rr_rm_chat_save_test71').length,1);const p=x.calls.find(c=>c.n==='rr_rm_chat_save_test71').p;assert.equal(p.p_lines[0].markup_mode,'DEFAULT_22');assert.equal(p.p_lines[0].category,'Polo');assert.equal(p.p_lines[0].size_text,'L, XL, XXL');assert.equal(p.p_post,true);assert.equal(x.s.status,'WORKING');assert.ok(!d.querySelector('.rm-chat-modal'));
 }finally{x.close()}
});
test('Sales sees stock balance, caption and multi-select but no costing or return controls',async()=>{
 const x=await setup('SALES');try{const d=x.w.document;assert.match(d.body.textContent,/Available balance: 20 PCS/);assert.ok(!d.querySelector('[data-approve]'));assert.ok(!d.querySelector('[data-return]'));assert.ok(!d.body.textContent.includes('Purchase ₹'));d.querySelector('[data-select]').click();assert.equal(d.querySelector('[data-count]').textContent,'1');d.querySelector('[data-send-selected]').click();const u=new URL(x.navigations.at(-1));assert.equal(u.searchParams.get('share_mode'),'chooser');assert.deepEqual(u.searchParams.getAll('selected_lot'),['RM1']);assert.ok(!x.calls.some(c=>c.n==='rr_sales_collection_send_test71'));}finally{x.close()}
});
test('Working approval updates RRQ and purchase return uses stable duplicate protection',async()=>{
 const x=await setup();try{const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71'&&!x.calls.some(c=>c.n==='rr_rm_approve_rate_test71'))j.cards[0].approval_ready=false;return j};await x.ctx.refresh();const d=x.w.document;d.querySelector('[data-rate]').value='152';const b=d.querySelector('[data-approve]');b.click();b.click();await wait();assert.equal(x.calls.filter(c=>c.n==='rr_rm_approve_rate_test71').length,1);assert.equal(x.calls.find(c=>c.n==='rr_rm_approve_rate_test71').p.p_final_rate,152);
 d.querySelector('[data-return-qty]').value='2';d.querySelector('[data-return-reason]').value='Damage';const r=d.querySelector('[data-return]');r.click();r.click();await wait();assert.equal(x.calls.filter(c=>c.n==='rr_rm_purchase_return_test71').length,1);assert.equal(x.calls.find(c=>c.n==='rr_rm_purchase_return_test71').p.p_qty,2);assert.ok(x.calls.find(c=>c.n==='rr_rm_purchase_return_test71').p.p_idempotency_key);
 }finally{x.close()}
});
test('Pending-rate garment stays in Working and cannot enter Market flow',async()=>{
 const x=await setup();try{const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71'){j.cards[0].approval_ready=false;j.cards[0].market_ready=false;j.cards[0].missing_fields=['Final sale-rate approval'];j.cards[0].costing.costing_complete=false;}return j};await x.ctx.refresh();assert.ok(x.w.document.querySelector('[data-select]').disabled);assert.ok(x.w.document.querySelector('[data-complete]'));assert.equal(x.navigations.length,0);assert.ok(!x.calls.some(c=>c.n==='rr_sales_collection_send_test71'));assert.ok(x.w.document.querySelector('[data-approve]').disabled);assert.match(x.w.document.body.textContent,/Approval pending/)}finally{x.close()}
});
test('Real Chat shell opens Readymade first, switches OPEN/WORKING, and Back returns to directory',async()=>{
 const root=path.resolve(__dirname,'../..'),html=fs.readFileSync(path.join(root,'test70-cb-purchase-real-chat-pilot.html'),'utf8').replace(/<script\b[\s\S]*?<\/script>/g,'');
 const dom=new JSDOM(html,{url:'https://example.com/chat',runScripts:'outside-only',pretendToBeVisual:true}),w=dom.window;
 try{
 w.CSS={escape:x=>x};
 w.supabaseClient={auth:{getSession:async()=>({data:{session:{user:{id:'owner1'}}}}),getUser:async()=>({data:{user:{id:'owner1'}}})},channel:()=>({on(){return this},subscribe(){return this}}),rpc:async(n)=>{
 let data={cards:[]};if(n==='rr_real_chat_directory_v85')data={actor:{role:'OWNER',name:'Owner'},departments:[{department_code:'PURCHASE',department_name:'CB',workers:[],staff:[]},{department_code:'CUTTING',department_name:'Cutting',workers:[],staff:[]}],people:[]};
 if(n==='rr_rm_chat_fast_queue_test71')data={can_purchase:true,can_approve:true,cards:[],drafts:[],categories:[],counts:{OPEN:1,WORKING:0}};
 return {data,error:null};}};
 w.eval(code);w.eval(fs.readFileSync(path.join(root,'test70-real-chat-live-v70.js'),'utf8'));await wait();await wait();
 assert.equal(w.document.querySelector('[data-department]').dataset.department,'READYMADE');
 w.document.querySelector('[data-department="READYMADE"]').click();await wait();assert.ok(w.document.querySelector('[data-new]'));assert.equal(w.document.getElementById('chatName').textContent,'Readymade Garments');
 w.document.querySelector('[data-chat-status="WORKING"]').click();await wait();assert.ok(w.document.querySelector('[data-category]'));assert.equal(w.__rrRealChatView.status,'WORKING');
 w.document.querySelector('[data-chat-status="OPEN"]').click();await wait();assert.ok(w.document.querySelector('[data-new]'));
 w.document.getElementById('back').click();await wait();assert.ok(!w.document.getElementById('inbox').hidden);assert.equal(w.document.querySelector('[data-department]').dataset.department,'READYMADE');
 }finally{w.close()}
});
test('OPEN New Purchase is usable while a delayed draft request is still pending',async()=>{
 const x=await setup('OWNER','OPEN');try{
 let resolve;const pending=new Promise(r=>resolve=r),old=x.ctx.rpc;
 x.ctx.rpc=(n,p)=>n==='rr_rm_chat_fast_queue_test71'?pending:old(n,p);
 const rendering=x.ctx.refresh();assert.ok(x.w.document.querySelector('[data-new]'));
 x.w.document.querySelector('[data-new]').click();assert.ok(x.w.document.querySelector('[data-supplier]'));
 resolve({cards:[],drafts:[],categories:[],counts:{OPEN:1,WORKING:0},can_purchase:true});await rendering;
 assert.ok(!x.calls.some(c=>c.n==='rr_rm_costing_test71'));
 }finally{x.close()}
});
test('WORKING lists stock first and loads costing only when rate details open',async()=>{
 const x=await setup();try{
 const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{
  if(n==='rr_rm_costing_test71'){x.calls.push({n,p});return{costing_complete:true,source_rate:150,purchase_cost_per_pc:100,salary_per_pc:10,overhead_per_pc:18}}
  const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71'){j.can_view_cost=true;j.cards[0].approval_ready=false;j.cards[0].costing={costing_complete:false,frozen:false};}return j;
 };
 await x.ctx.refresh();assert.equal(x.calls.filter(c=>c.n==='rr_rm_costing_test71').length,0);
 const details=x.w.document.querySelector('[data-cost-load]');details.open=true;details.dispatchEvent(new x.w.Event('toggle'));await wait();
 assert.equal(x.calls.filter(c=>c.n==='rr_rm_costing_test71').length,1);assert.ok(!x.w.document.querySelector('[data-approve]').disabled);assert.match(x.w.document.querySelector('[data-cost-body]').textContent,/Purchase ₹100/);
 }finally{x.close()}
});

test('Private Working heads respect effective Super Admin scope even when RPC permits Admin approval',async()=>{
 for(const role of ['OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS','SALES','MANAGER']){
  const x=await setup(role);try{
   const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71'){j.can_view_cost=true;j.can_approve=true;}return j};
   await x.ctx.refresh();const privateRole=['OWNER','SUPER_ADMIN'].includes(role),d=x.w.document;
   assert.equal(!!d.querySelector('[data-cost-body]'),privateRole,role);
   assert.equal(!!d.querySelector('[data-approved-rate]'),privateRole,role);assert.ok(!d.querySelector('[data-approve]'));
   assert.match(d.body.textContent,/Available balance: 20 PCS/);
   if(privateRole){x.w.RR_EFFECTIVE_ROLE=()=> 'ADMIN';await x.ctx.refresh();assert.equal(d.querySelectorAll('[data-cost-load]').length,0);assert.ok(!x.calls.some(c=>c.n==='rr_rm_costing_test71'));}
  }finally{x.close()}
 }
});

test('Select all includes every available garment and carries selection into existing Market share chooser',async()=>{
 const x=await setup();try{
 const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71')j.cards.push({...j.cards[0],stock_id:'s2',lot_no:'RM2',approval_ready:true},{...j.cards[0],stock_id:'s3',lot_no:'RM3',available_qty:0});return j};
 await x.ctx.refresh();const d=x.w.document,checks=d.querySelectorAll('[data-select]');checks[1].click();assert.equal(d.querySelector('[data-count]').textContent,'1');checks[1].click();d.querySelector('[data-all]').click();assert.equal(d.querySelector('[data-count]').textContent,'2');assert.ok(checks[0].checked&&checks[1].checked);assert.ok(checks[2].disabled);
 const u=new URL(d.querySelector('[data-market]').href);assert.equal(u.searchParams.get('share_mode'),'chooser');assert.deepEqual(u.searchParams.getAll('selected_lot'),['RM1','RM2']);
 d.querySelector('[data-all]').click();assert.equal(d.querySelector('[data-count]').textContent,'0');checks[0].click();d.querySelector('[data-send-selected]').click();const outside=new URL(x.navigations.at(-1));assert.deepEqual(outside.searchParams.getAll('selected_lot'),['RM1']);
 }finally{x.close()}
});

test('Approved reduced or increased rates stay read only across reloads',async()=>{
 for(const rate of [125,175]){
 const x=await setup();try{const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71'){j.cards[0].approved_rate=rate;j.cards[0].approval_ready=true;}return j};
 await x.ctx.refresh();await x.ctx.refresh();const d=x.w.document;assert.ok(d.querySelector('[data-approved-rate]'));assert.match(d.querySelector('[data-approved-rate]').textContent,new RegExp('₹'+rate));assert.ok(!d.querySelector('[data-rate]'));assert.ok(!d.querySelector('[data-approve]'));assert.equal(x.calls.filter(c=>c.n==='rr_rm_approve_rate_test71').length,0);
 }finally{x.close()}
 }
});

test('Send on any Working card sends the full selection and all count badges stay in sync',async()=>{
 const x=await setup('SALES');try{
 const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71')j.cards.push({...j.cards[0],stock_id:'s2',lot_no:'RM2'});if(n==='rr_sales_collection_cards_test71')j.rows.push({lot_no:'RM2'});return j};await x.ctx.refresh();const d=x.w.document;
 assert.equal(d.querySelectorAll('.rm-chat-card [data-send-selected]').length,2);d.querySelector('[data-all]').click();assert.ok([...d.querySelectorAll('[data-count]')].every(n=>n.textContent==='2'));
 d.querySelectorAll('.rm-chat-card [data-send-selected]')[1].click();const u=new URL(x.navigations.at(-1));assert.deepEqual(u.searchParams.getAll('selected_lot'),['RM1','RM2']);assert.equal(u.searchParams.get('share_mode'),'chooser');assert.ok(!x.calls.some(c=>c.n==='rr_sales_collection_send_test71'));
 }finally{x.close()}
});

test('Working captions keep identical fields and order when garment mappings are missing',async()=>{
 const x=await setup('SALES');try{const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71'){j.cards[0].art_no='RA40';j.cards[0].cloth_name='Cotton';j.cards[0].colours_text='Blue';j.cards[0].caption_note='Full sleeve';j.cards.push({...j.cards[0],stock_id:'s2',lot_no:'RM2',art_no:null,size_text:' ',cloth_name:undefined,colours_text:'',caption_note:null});}return j};await x.ctx.refresh();
 const captions=[...x.w.document.querySelectorAll('.rm-caption')];assert.equal(captions.length,2);
 const labels=caption=>[...caption.querySelectorAll('dt')].map(e=>e.textContent);assert.deepEqual(labels(captions[0]),['Art No.','Sizes','Fabric','Colours']);assert.deepEqual(labels(captions[1]),labels(captions[0]));assert.deepEqual([...captions[1].querySelectorAll('dd')].map(e=>e.textContent),['—','—','—','—']);assert.match(captions[1].querySelector('.rm-caption-note').textContent,/Caption note—/);
 assert.deepEqual([...captions[0].children].map(e=>e.tagName),[...captions[1].children].map(e=>e.tagName));
 }finally{x.close()}
});

test('Pending filter keeps incomplete cards in repair queue and excludes them from Select all',async()=>{
 const x=await setup('MANAGER');try{const old=x.ctx.rpc;x.ctx.rpc=async(n,p)=>{const j=await old(n,p);if(n==='rr_rm_chat_fast_queue_test71')j.cards.push({...j.cards[0],lot_no:'RM2',stock_id:'s2',approval_ready:false,market_ready:false,mapping_ready:false,missing_fields:['Category','Final sale-rate approval']});return j};await x.ctx.refresh();const d=x.w.document;d.querySelector('[data-all]').click();assert.equal(d.querySelector('[data-count]').textContent,'1');const filter=d.querySelector('[data-mapping]');filter.value='PENDING';filter.dispatchEvent(new x.w.Event('change'));await wait();assert.equal(d.querySelectorAll('[data-lot]').length,1);assert.equal(d.querySelector('[data-lot]').dataset.lot,'RM2');assert.ok(d.querySelector('[data-select]').disabled);assert.equal(d.querySelector('[data-count]').textContent,'0');d.querySelector('[data-complete]').click();await wait();assert.ok(d.querySelector('[data-field="category"]'));assert.ok(d.querySelector('[data-field="size_text"]'));assert.ok(!d.querySelector('[data-field="purchase_rate"]'));assert.ok(!d.querySelector('[data-field="qty"]'));assert.ok(!d.querySelector('[data-field="final_rate"]'));assert.ok(d.querySelector('[data-request-approval]'));assert.ok(!d.querySelector('[data-open-approval]'));d.querySelector('[data-field="category"]').value='Polo';d.querySelector('[data-field="size_text"]').value='L, XL, XXL';d.querySelector('[data-save-mapping]').click();await wait();const call=x.calls.find(c=>c.n==='rr_rm_complete_mapping_test71');assert.equal(call.p.p_lot_no,'RM2');assert.equal(call.p.p_fields.category,'Polo');assert.ok(!('purchase_rate' in call.p.p_fields));assert.ok(!('qty' in call.p.p_fields));d.querySelector('[data-request-approval]').click();await wait();assert.equal(x.calls.filter(c=>c.n==='rr_rm_request_approval_test71').length,1);
 }finally{x.close()}
});
