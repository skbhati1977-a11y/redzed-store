const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{JSDOM}=require('jsdom');
const root=path.resolve(__dirname,'../..');
const wait=(ms=35)=>new Promise(r=>setTimeout(r,ms));
async function setup(saved=false){
 const html=fs.readFileSync(path.join(root,'real-pi-specimen-v9514.html'),'utf8').replace(/<script[\s\S]*?<\/script>/g,'');
 const dom=new JSDOM(html,{url:'https://example.com/pi'+(saved?'?pi_id=pi1':''),runScripts:'outside-only'}),w=dom.window,calls=[];
 w.sessionStorage.setItem('rr_pi_requirement_v9514',JSON.stringify({customer_name:'Buyer',lines:[]}));w.RR={requireRoles:async()=>{}};w.confirm=()=>true;
 const context={approved_rate:200,effective_rate:200,allowed_discount:0,available_qty:1080,category:'Shirt',size_text:'L',pack_pcs_per_box:100};
 w.RF853={rpc:async(n,p)=>{calls.push({n,p});
 if(n==='rr_pi_actor_context_v9526')return{superadmin:true};
 if(n==='rr_rm_sale_search_test71')return[{lot_no:'ART:DC1100',art_no:'DC1100',category:'Shirt',available_qty:1080}];
 if(n==='rr_ws_stock_search_v9411')return[{lot_no:'RM004',category:'Shirt',available_qty:540}];
 if(n==='rr_rm_sale_context_test71'||n==='rr_pi_lot_context_v9517')return context;
 if(n==='rr_trade_effective_rate_v849')return{target_sale_rate:200};
 if(n==='rr_sales_pi_detail_v500')return{pi_id:'pi1',pi_no:'TPI1',customer_name:'Buyer',status:'DRAFT',lines:[{lot_no:'RM004',art_no:'DC1100',art_sale_key:'one',stock_type:'TRADED',qty:530,rate:200},{lot_no:'RM005',art_no:'DC1100',art_sale_key:'one',stock_type:'TRADED',qty:70,rate:200}]};
 if(n==='rr_fg_save_pi_value_adjustment_test71')return{pi_id:'pi1',pi_no:'TPI1',party_discount_per_piece:0};
 return{};
 }};
 w.eval(fs.readFileSync(path.join(root,'real-pi-specimen-v9514.js'),'utf8'));await wait();return{w,calls,close:()=>w.close()};
}
test('PI dropdown offers Art and physical Lot; Art selection saves one logical item',async()=>{const x=await setup();try{const d=x.w.document;d.getElementById('itemLot').value='DC1100';d.getElementById('itemLot').dispatchEvent(new x.w.Event('input'));await wait(260);assert.match(d.getElementById('itemLotSuggestions').textContent,/Art DC1100/);d.querySelector('#pi-lot-option-0').click();assert.equal(d.getElementById('itemStockType').value,'TRADED');d.getElementById('itemQty').value='600';d.getElementById('addItem').click();await wait();const save=x.calls.find(c=>c.n==='rr_fg_save_pi_value_adjustment_test71');assert.equal(save.p.p_lines.length,1);assert.equal(save.p.p_lines[0].art_no,'DC1100');assert.equal(save.p.p_lines[0].qty,600);assert.equal(d.querySelectorAll('#rows tr').length,1);}finally{x.close()}});
test('Typing an Art without a prefix resolves to the same Art sale item',async()=>{const x=await setup();try{const d=x.w.document;d.getElementById('itemLot').value='dc1100';d.getElementById('itemQty').value='7';d.getElementById('addItem').click();await wait();const save=x.calls.find(c=>c.n==='rr_fg_save_pi_value_adjustment_test71');assert.equal(save.p.p_lines[0].art_no,'DC1100');assert.equal(save.p.p_lines[0].stock_type,'TRADED');}finally{x.close()}});
test('Saved physical Lot allocations reopen as one Art row with combined PCS',async()=>{const x=await setup(true);try{assert.equal(x.w.document.querySelectorAll('#rows tr').length,1);assert.match(x.w.document.getElementById('rows').textContent,/ART:DC1100/);assert.equal(x.w.document.querySelector('#rows input.qty').value,'600');assert.ok(x.calls.some(c=>c.n==='rr_rm_sale_context_test71'&&c.p.p_pi_id==='pi1'));}finally{x.close()}});
