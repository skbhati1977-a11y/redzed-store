const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

const cb=()=>read('real-cb-new-v9130-fix2.html');
const cut=()=>read('real-cutting-master-pm.V719.3.js');
const planSql=()=>read('supabase/migrations/20261003103000_test71_cb_art_material_planning_yield_whatsapp.sql');

test('Art & Material Decision is the first canonical planning surface',()=>{
  const s=cb();
  assert.ok(s.includes('Art &amp; Material Decision'));
  for(const token of [
    'PENDING · NO DECISION',
    'DUE · DECIDE LATER',
    'SINGLE LOT · ALL SETS',
    'MULTI LOT / MIXED SETS',
    'id="artMaterialPlanState"'
  ]) assert.ok(s.includes(token),token);
  assert.ok(s.indexOf('Art &amp; Material Decision') < s.indexOf('Cloth Purchase & Bill Details'));
});

test('Single Multi planning uses real CB profile identities and is reversible before Cutting final',()=>{
  const s=cb(),sql=planSql();
  assert.ok(s.includes('rr_cb_set_lot_plan_v1'));
  assert.ok(s.includes('rootPlanMode'));
  assert.ok(s.includes('CHILD PROFILES'));
  assert.ok(s.includes('profileShare'));
  assert.ok(s.includes('profile-card'));
  assert.ok(sql.includes('rr_cb_set_lot_plan_v1'));
  assert.ok(sql.includes('parent_unit_id'));
  assert.ok(sql.includes('planning_share_pct'));
  assert.ok(sql.includes("mode not in('SINGLE','MULTI')"));
  assert.ok(sql.includes("first child Combo parent"));
});

test('Multi children have their own Art Combo but share downstream CB-unit authority',()=>{
  const s=cb(),sql=planSql();
  assert.ok(s.includes('Each child has its own Art Combo and downstream identity.'));
  assert.ok(s.includes('cb_unit_id:r.unitId||null'));
  assert.ok(s.includes('rr_cb_set_requirement_sync_v6'));
  assert.ok(sql.includes('rr_cb_copy_combo_v1'));
  assert.ok(sql.includes('rr_cb_set_requirement_sync_v6'));
  assert.ok(sql.includes('Active Set profile not found.'));
});

test('Art is directly editable until exact Cutting Lot No plus PCS save',()=>{
  const s=cb(),sql=planSql();
  assert.ok(s.includes('class="canonicalSetArt"'));
  assert.ok(!s.includes('CHANGE CATEGORY / ART'));
  assert.ok(s.includes('rr_cb_select_art_v1'));
  assert.ok(sql.includes('rr_cb_unit_has_final_cutting_v1'));
  assert.ok(sql.includes("nullif(trim(coalesce(lot_no,'')),'') is not null"));
  assert.ok(sql.includes('coalesce(nullif(actual_pcs,0),planned_pcs,0)>0'));
  assert.ok(sql.includes('frozen after Cutting Lot No + Pieces save.'));
});

test('Art drives Category automatically and category defaults are configurable',()=>{
  const s=cb(),sql=planSql();
  assert.ok(s.includes('CATEGORY · AUTO MAPPED'));
  assert.ok(s.includes('applyCategoryDefaults'));
  assert.ok(s.includes('MAKE CURRENT VALUES DEFAULT'));
  assert.ok(s.includes('rr_cb_category_defaults_set_v1'));
  assert.ok(sql.includes('rr_cb_category_construction_defaults_v1'));
  assert.ok(sql.includes("default_sleeve_type text not null default 'HALF'"));
  assert.ok(sql.includes("default_sleeve_finish text not null default 'CUFF'"));
  assert.ok(sql.includes("default_border_pounchi text not null default 'WITHOUT_BORDER_POUNCHI'"));
  assert.ok(sql.includes("lower(category_code) in('crew-neck','drop-shoulder') then 'PLAIN'"));
});

test('Print Sticker Metal pickers collapse after Done and show selected thumbnails',()=>{
  const s=cb();
  for(const token of ['comboOpen','comboDone','combo-preview-grid','combo-preview-tile','frame-detail']) assert.ok(s.includes(token),token);
  assert.ok(s.includes("if(!open)"));
  assert.ok(s.includes("s[kind+'Done']"));
  assert.ok(s.includes('comboPrintPreview'));
  assert.ok(s.includes('comboFrames'));
  assert.ok(s.includes('FRAME'));
});

test('Existing Add New masters are reused inside CB Combo',()=>{
  const s=cb();
  for(const token of [
    'art-v9148/?v=9233&from=cb-combo',
    'real-print-master.html?v=9233&from=cb-combo',
    'real-sticker-master-v804.html?v=9233&from=cb-combo',
    'real-metal-id-master-v804.html?v=9233&from=cb-combo'
  ]) assert.ok(s.includes(token),token);
  assert.ok(s.includes('comboAddArt'));
  assert.ok(s.includes('comboAddNew'));
});

test('Manual Additional Material decision surface is operationally retired',()=>{
  const s=cb();
  assert.ok(s.includes('id="extraMaterialCard" hidden'));
  assert.ok(s.includes('Yield · Consolidated Requirement'));
  assert.ok(!s.includes('SET CONSTRUCTION · PRE-ART SPEC'));
  assert.ok(!s.includes('CHANGE CATEGORY / ART'));
});

test('Yield drives Collar Rib Sticker and Metal ID initial requirement',()=>{
  const s=cb(),sql=planSql();
  assert.ok(s.includes('rr_cb_refresh_derived_requirements_v1'));
  assert.ok(s.includes('rr_cb_requirement_context_v1'));
  assert.ok(s.includes('rr_cb_material_estimate_v3'));
  assert.ok(s.includes('rr_cb_material_mapping_sync_v6'));
  assert.ok(sql.includes('rr_cb_profile_yield_v1'));
  assert.ok(sql.includes('rr_cb_material_estimate_v3'));
  assert.ok(sql.includes("requirement_type in('MATERIAL','STICKER','METAL_ID')"));
  assert.ok(sql.includes("when 'STICKER' then 'STICKER_MASTER_V803'"));
  assert.ok(sql.includes("when 'METAL_ID' then 'METAL_ID_MASTER_V803'"));
  assert.ok(sql.includes('qty_per_piece'));
  assert.ok(sql.includes("basis text not null default 'YIELD'"));
});

test('Cutting actual revises the same derived requirement only after final lot save',()=>{
  const sql=planSql();
  assert.ok(sql.includes('rr_cb_cutting_actual_requirement_refresh_trg_v1'));
  assert.ok(sql.includes('rr_cb_cutting_actual_requirement_refresh_v1'));
  assert.ok(sql.includes('rr_cb_multi_actual_requirement_refresh_v1'));
  assert.ok(sql.includes("or update of cb_unit_id,lot_no,planned_pcs,actual_pcs,status"));
  assert.ok(sql.includes("basis='CUTTING_ACTUAL'"));
  assert.ok(sql.includes('revision_no'));
  assert.ok(sql.includes('drop trigger if exists rr_cb_derived_after_single_cutting_v1'));
  assert.ok(sql.includes('drop trigger if exists rr_cb_derived_after_multi_cutting_v1'));
});

test('Supplier mapping and WhatsApp first resend revised history are canonical',()=>{
  const s=cb(),sql=planSql();
  assert.ok(s.includes('rr_cb_requirement_supplier_set_v1'));
  assert.ok(s.includes('rr_cb_requirement_send_v1'));
  assert.ok(s.includes('RESEND #'));
  assert.ok(s.includes('SEND REVISED'));
  assert.ok(sql.includes('rr_cb_requirement_send_log_v1'));
  assert.ok(sql.includes("template_kind in('FIRST','RESEND','REVISED')"));
  assert.ok(sql.includes('rr_cb_requirement_whatsapp_send_v1'));
  assert.ok(sql.includes('REQUIREMENT STILL PENDING'));
  assert.ok(sql.includes('REVISED PURCHASE ORDER / REQUIREMENT'));
  assert.ok(sql.includes('rr_material_source_supplier_map_v805_31'));
});

test('One CB-level Purchase Order uses profile-aware Yield v3',()=>{
  const s=cb();
  assert.ok(s.includes('GENERATE PURCHASE ORDER · ALL SETS'));
  assert.ok(s.includes('generateAllSetPurchaseOrder'));
  assert.ok(s.includes('rr_cb_material_estimate_v3'));
  assert.ok(s.includes('rr_cb_supplier_po_generate_v1'));
  assert.ok(!s.includes('rr_cb_material_estimate_v2'));
  assert.ok(!s.includes('rr_cb_material_mapping_sync_v5'));
  for(const token of ['Set</th>','Material</th>','Colour</th>','Thumbnail</th>','Yield PCS</th>','Approx Qty</th>']) assert.ok(s.includes(token),token);
});

test('Cutting cannot redefine parent profile construction identity',()=>{
  const s=cut();
  assert.ok(s.includes('Sleeve · Parent Set'));
  assert.ok(s.includes('Border Pounchi · Parent Set'));
  assert.ok(!s.includes('<select class="cm-dev-sleeve"'));
  assert.ok(!s.includes('<select class="cm-dev-border"'));
  const lot=read('supabase/migrations/20261003075100_test71_lot_parent_combo_inheritance.sql');
  for(const token of ['new.art_no:=v_art_no','new.print_no:=v_print_no','new.sleeve_type:=lower','new.border_type:=case']) assert.ok(lot.includes(token),token);
});

test('Standalone Art Decision UI stays retired and routes back to CB',()=>{
  const retired=read('real-art-decide-master-v9231.js');
  const chat=read('test70-real-chat-live-v70.js');
  const pm=read('real-product-master-art-decision-module-v9226.js');
  assert.ok(retired.includes('ART_DECISION_RETIRED#setDecisionCard'));
  assert.ok(chat.includes('EDIT ART COMBO'));
  assert.ok(chat.includes('CB_ART_COMBO'));
  assert.ok(!chat.includes('>ART DECISION EDIT</a>'));
  assert.ok(!pm.includes('>ART DECISION MASTER</button>'));
});

test('Planning Yield WhatsApp migration retires duplicate intermediate engines',()=>{
  const sql=planSql();
  assert.ok(sql.includes('drop function if exists public.rr_cb_requirement_prepare_send_v1'));
  assert.ok(sql.includes('drop function if exists public.rr_cb_requirement_supplier_set_v1(uuid,uuid,text,text)'));
  assert.ok(sql.includes('drop function if exists public.rr_cb_refresh_derived_after_cutting_v1()'));
});
