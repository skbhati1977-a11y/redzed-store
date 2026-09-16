const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');

const sql=fs.readFileSync('supabase/migrations/20260916142546_test70_global_lot_department_open_consolidation_v202.sql','utf8');
const mirrorSql=fs.readFileSync('supabase/migrations/20260916143454_test70_lineman_personal_open_mirror_v203.sql','utf8');
const chat=fs.readFileSync('test70-real-chat-live-v70.js','utf8');
const html=fs.readFileSync('test70-cb-purchase-real-chat-pilot.html','utf8');

test('OPEN projection consolidates by canonical Lot plus Department',()=>{
  assert.match(sql,/create or replace function public\.rr_real_chat_work_search_v13/);
  assert.match(sql,/group by lot_key,department_key/);
  assert.match(sql,/distinct on\(lot_key,department_key,colour_key\)/);
  assert.match(sql,/'consolidated_scope','LOT_DEPARTMENT'/);
});

test('consolidated card keeps every unique colour and totals its PCS',()=>{
  assert.match(sql,/sum\(coalesce\(nullif\(card->>'qty',''\),'0'\)::numeric\)/);
  assert.match(sql,/'colour_rows',g\.colour_rows/);
  assert.match(sql,/'colour_count',g\.colour_count/);
  assert.match(sql,/'qty',g\.total_qty/);
});

test('search runs after consolidation so a colour query returns the full Lot card',()=>{
  assert.match(sql,/rr_real_chat_work_search_v12\([\s\S]*p_status,[\s\S]*null,[\s\S]*p_department_code/);
  assert.match(sql,/if v_find<>'' then[\s\S]*jsonb_array_elements\(v_cards\)/);
});

test('group and personal chat share a client-side consolidation guard',()=>{
  assert.match(chat,/function consolidateReadyAssignRowsV202\(rows,status\)/);
  assert.match(chat,/consolidateReadyAssignRowsV202\(current\.concat\(old\)/);
  assert.match(chat,/g\.consolidated=c/);
  assert.match(chat,/consolidated_scope:'LOT_DEPARTMENT'/);
});

test('client guard turns six 24 PCS colour cards into one 144 PCS Lot card',()=>{
  const source=chat.match(/function consolidateReadyAssignRowsV202\(rows,status\)\{[\s\S]*?\n(?=function chatRows)/)?.[0];
  assert.ok(source);
  const context={
    arr:value=>Array.isArray(value)?value:[],
    workType:card=>card.work_category,
    guard:null
  };
  vm.runInNewContext(`${source};guard=consolidateReadyAssignRowsV202;`,context);
  const cards=Array.from({length:6},(_,index)=>({
    canonical_lot_id:'canonical:2622',lot_no:'2622',department_code:'STITCHING',
    event_key:`UPM_OPEN:canonical:2622:STITCHING:C${index+1}`,
    colour_code:`C${index+1}`,colour_name:`C${index+1}`,qty:24,
    work_category:'READY_TO_ASSIGN',event_at:'2026-09-14T06:42:15Z',
    actions:[{code:'ASSIGN_WORKER'}],art_images:[`https://example.test/c${index+1}.jpg`]
  }));
  const result=context.guard(cards,'OPEN');
  assert.equal(result.length,1);
  assert.equal(result[0].qty,144);
  assert.equal(result[0].colour_count,6);
  assert.equal(result[0].colour_rows.length,6);
  assert.equal(result[0].actions.filter(x=>x.code==='ASSIGN_WORKER').length,1);
});

test('Lineman personal projection mirrors the consolidated source Lot payload',()=>{
  assert.match(mirrorSql,/create or replace function public\.rr_real_chat_work_search_v14/);
  assert.match(mirrorSql,/public\.rr_real_chat_work_search_v13\([\s\S]*p_status,[\s\S]*null/);
  assert.match(mirrorSql,/'qty',peer\.card->'qty'/);
  assert.match(mirrorSql,/'colour_rows',peer\.card->'colour_rows'/);
  assert.match(mirrorSql,/'consolidated_scope','LOT'/);
});

test('live chat calls V14 and cache-busts the V203 asset',()=>{
  assert.match(chat,/rr_real_chat_work_search_v13'\]\.includes\(n\)\)n='rr_real_chat_work_search_v14'/);
  assert.match(html,/test70-real-chat-live-v70\.js\?v=203/);
});
