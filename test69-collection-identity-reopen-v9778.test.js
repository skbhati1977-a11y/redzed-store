const fs=require('fs'),assert=require('assert');
const js=fs.readFileSync('real-customer-collection-identity-v9778.js','utf8');
const page=fs.readFileSync('s.html','utf8');
const sql=fs.readFileSync('supabase/migrations/20260911123000_test69_collection_canonical_identity_reopen_v9778.sql','utf8');
for(const token of ['rr_collection_submit_requirement_v9778','CANONICAL_COLLECTION','origin_chat_id','rr_customer_chat_v9433','rr_collection_customer_requirement_summary_v9778','rr_collection_send_v9586','from public','to anon,authenticated,service_role'])assert.ok(sql.includes(token),`missing SQL ${token}`);
assert.ok(!/p_customer_name|p_mobile/.test(js),'frontend must not supply mutable local customer identity');
for(const token of ['#fcSubmit','[data-fcq]','rr_collection_submit_requirement_v9778','rr_collection_customer_requirement_summary_v9778','location.reload()'])assert.ok(js.includes(token),`missing frontend repair ${token}`);
assert.ok(page.includes('real-customer-collection-identity-v9778.js?v=9778'),'customer collection page must load repair');
console.log('V9778 canonical collection identity and exact-cycle reopen: PASS');
