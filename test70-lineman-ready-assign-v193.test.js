const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/20260916090000_test70_lineman_ready_assign_projection_v193.sql','utf8')+fs.readFileSync('supabase/migrations/20260916091500_test70_lineman_ready_assign_projection_v194.sql','utf8')+fs.readFileSync('supabase/migrations/20260916093000_test70_fabrication_filter_projection_v195.sql','utf8')+fs.readFileSync('supabase/migrations/20260916094500_test70_lineman_consolidated_open_v197.sql','utf8');
const live=fs.readFileSync('test70-real-chat-live-v70.js','utf8');
const waitingSql=fs.readFileSync('supabase/migrations/20260916100000_test70_working_waiting_action_v198.sql','utf8');
test('canonical Ready-to-Assign is consolidated to one card per lot',()=>{
 assert.match(sql,/distinct on\(coalesce\(x\.card->>'canonical_lot_id',x\.card->>'lot_no'\)\)x\.card/);
 assert.match(sql,/UPM_FABRICATION_ASSIGN:/);
 assert.match(sql,/'work_category','READY_TO_ASSIGN'/);
 assert.match(sql,/'canonical_source','rr_upm_ready_to_assign_v9107'/);
});
test('shared queue is visible and actionable for all mapped Linemen',()=>{
 assert.match(sql,/LINE_MANAGER','LINE_MAN/);
 assert.match(sql,/visible_worker_ids',v_lineman_ids/);
 assert.match(sql,/ASSIGN_WORKER/);
});
test('Ready-to-Submit keeps the existing selected-Lineman handoff',()=>{
 assert.match(sql,/rr_real_chat_work_inbox_v81/);
 assert.match(sql,/rr_real_chat_work_inbox_v82/);
});
test('live client consumes V10 and recognises Ready-to-Assign',()=>{
 assert.match(live,/rr_real_chat_work_search_v10/);
 assert.match(live,/READY_TO_ASSIGN/);
});
test('Fabrication group filtering happens after virtual projection',()=>{
 assert.match(sql,/case when v_fabrication then null else p_department_code end/);
 assert.match(sql,/not v_fabrication or upper\(coalesce\(card->>'department_code',''\)\)='FABRICATION'/);
});
test('Fabrication Ready-to-Assign opens the embedded canonical assignment form',()=>{
 assert.match(live,/function openFabricationAssignForm/);
 assert.match(live,/closest\('\.work-card'\).*querySelector\('h2'\)/);
 assert.match(live,/real-department-lite-v9127\.html\?mode=TEST/);
 assert.match(live,/rrOpenAssign=/);
 assert.match(live,/ASSIGN \/ REASSIGN/);
 assert.match(live,/stopImmediatePropagation\(\);openFabricationAssignForm/);
});
test('consolidated Lot opens department chooser before colours and worker form',()=>{
 assert.match(sql,/'label','ASSIGN WORK'/);
 assert.match(sql,/rrMode=ASSIGN&lot=/);
 assert.match(sql,/Pending departments choose/);
 assert.match(live,/ASSIGN_DEPARTMENTS\.map/);
 assert.match(live,/rr_upm_department_colour_due_card_v9109/);
});
test('Lineman custody waiting card shows truthful non-duplicate status action',()=>{
 assert.match(waitingSql,/CUSTODY_HANDOVER/);
 assert.match(waitingSql,/WAITING FOR WORKER RECEIPT/);
 assert.match(waitingSql,/jsonb_array_length\(coalesce\(card->'actions','\[\]'::jsonb\)\)=0/);
 assert.match(live,/rr_real_chat_work_search_v11/);
});
