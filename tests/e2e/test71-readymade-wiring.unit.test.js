const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('jsdom');
const root = path.resolve(__dirname, '../..');
const code = fs.readFileSync(path.join(root, 'real-readymade-test71.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'real-commerce-v853.html'), 'utf8');
const wait = () => new Promise(resolve => setTimeout(resolve, 20));
async function setup(role = 'owner') {
  const dom = new JSDOM(html.replace(/<script[\s\S]*?<\/script>/g, ''), {runScripts:'outside-only',url:'https://example.com/real-commerce-v853.html'});
  const w = dom.window, calls = [];
  const card = {stock_id:'stock1',lot_no:'RM1',item_name:'Ready garment',received_qty:100,available_qty:80,approved_rate:130,costing:role==='owner'?{costing_complete:true,source_rate:127,purchase_cost_per_pc:100,salary_per_pc:3,overhead_per_pc:2,overhead_heads:[]}:{costing_complete:true,source_rate:127}};
  w.RR = {requireRoles:async()=>({profile:{role_code:role}})};
  w.RF853 = {esc:x=>String(x??''),mode:()=>w.document.getElementById('dataMode').value,rpc:async(name,args)=>{
    calls.push({name,args});
    if(name==='rr_rm_cards_test71') return [card];
    if(name==='rr_rm_purchase_drafts_test71') return [{purchase_id:'draft1',purchase_no:'RMP1',supplier_name:'Supplier',bill_no:'B1',purchase_date:'2026-10-01',lines:[{lot_no:'RM2',item_name:'Draft garment',qty:20,purchase_rate:110,final_image_url:'https://example.com/img.jpg'}]}];
    if(name==='rr_rm_purchase_save_test71') return {purchase_id:'draft1'};
    if(name==='rr_rm_approve_rate_test71') return {quota_delta:400,rrq_balance:500};
    return {ok:true};
  }};
  w.eval(code);await wait();return {w,calls,close:()=>w.close()};
}
test('Readymade saved draft reloads and posts through the canonical purchase RPC with fixed margin',async()=>{
  const {w,calls,close}=await setup();try{
    const d=w.document;d.getElementById('rmDraft').value='draft1';d.getElementById('rmDraft').dispatchEvent(new w.Event('change'));
    assert.equal(d.getElementById('rmBill').value,'B1');
    assert.equal(d.querySelector('[data-field="purchase_rate"]').value,'110');
    d.getElementById('rmPostPurchase').click();await wait();
    const c=calls.find(x=>x.name==='rr_rm_purchase_save_test71');
    assert.equal(c.args.p_purchase_id,'draft1');assert.equal(c.args.p_post,true);assert.equal(c.args.p_lines[0].markup_mode,'DEFAULT_22');
  }finally{close();}
});
test('Rate approval and repeat tap produce one approval request; Purchase Return uses one stable request reference',async()=>{
 const {w,calls,close}=await setup();try{
  const d=w.document;d.querySelector('[data-rate]').value='135';const b=d.querySelector('[data-approve]');b.click();b.click();await wait();
  assert.equal(calls.filter(x=>x.name==='rr_rm_approve_rate_test71').length,1);
  assert.equal(calls.find(x=>x.name==='rr_rm_approve_rate_test71').args.p_final_rate,135);
  d.querySelector('[data-return-qty]').value='2';d.querySelector('[data-return-reason]').value='Supplier damage';d.querySelector('[data-return]').click();await wait();
  const c=calls.find(x=>x.name==='rr_rm_purchase_return_test71');assert.equal(c.args.p_stock_id,'stock1');assert.equal(c.args.p_qty,2);assert.ok(c.args.p_idempotency_key);
 }finally{close();}
});
test('Sales UI has no purchase, overhead or approval actions and no owner costing details',async()=>{
 const {w,calls,close}=await setup('sales');try{
  assert.ok([...w.document.querySelectorAll('[data-rm-purchase-role]')].every(x=>x.hidden));
  assert.ok([...w.document.querySelectorAll('[data-rm-approval]')].every(x=>x.hidden));
  assert.ok(!w.document.getElementById('rmCards').textContent.includes('Owner margin'));
  assert.ok(!calls.some(x=>x.name==='rr_rm_purchase_drafts_test71'));
 }finally{close();}
});
