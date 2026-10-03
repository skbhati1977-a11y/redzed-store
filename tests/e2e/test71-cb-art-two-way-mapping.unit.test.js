const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

test('CB uses one canonical S1-S4 Set decision UI with no duplicate material construction fields',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  for(const token of ['id="setDecisionCard"','class="canonicalSetCategory"','class="canonicalSetArt"','class="canonicalSetSleeve"','class="canonicalSetFinish"','class="canonicalSetBorder"','class="canonicalSetSizes"']) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes('DIRECT · MATERIAL N/A'));
  assert.ok(cb.includes('CB Set Art authority · downstream linked'));
  assert.ok(!cb.includes('SET CONSTRUCTION · PRE-ART SPEC'));
  assert.ok(!cb.includes('details class="allowedArtCats"'));
  assert.ok(!cb.includes('class="setArt"'));
  assert.ok(!cb.includes('class="directArt"'));
});

test('CB Set Art Combo owns the shared Art assignment authority',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const art=read('real-art-decide-master-v9231.js');
  assert.ok(cb.includes("rr_cb_select_art_v1"));
  assert.ok(cb.includes('saveCbArtSelection(di,id)'));
  assert.ok(cb.includes('Art decides Category'));
  assert.ok(cb.includes('CHANGE CATEGORY / ART'));
  assert.ok(art.includes('rr_pm_save_decision_bundle_v804'));
  assert.ok(art.includes('rr_sync_cb_mapping_from_art_v3'));
  assert.ok(!art.includes('rr_sync_cb_mapping_from_art_v2'));
  assert.ok(!art.includes('rr_art_canonical_mapping_status_v1'));
});

test('Border Pounchi is canonical end-to-end with WITHOUT as default',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const art=read('real-art-decide-master-v9231.js');
  const cut=read('real-cutting-master-pm.V719.3.js');
  const sql=read('supabase/migrations/20261003064331_test71_cb_art_two_way_border_authority.sql');
  assert.ok(cb.includes('WITHOUT BORDER POUNCHI'));
  assert.ok(cb.includes('WITH BORDER POUNCHI'));
  assert.ok(cb.includes('border_pounchi:normalizeBorderPounchi'));
  assert.ok(art.includes("border_pounchi,art_id"));
  assert.ok(cut.includes('defaultBorderForActiveSet'));
  assert.ok(cut.includes('Without Border Pounchi'));
  assert.ok(cut.includes('With Border Pounchi'));
  assert.ok(sql.includes("default 'WITHOUT_BORDER_POUNCHI'"));
  assert.ok(sql.includes('border_pounchi=excluded.border_pounchi'));
});

test('New Set defaults are configurable without rewriting existing Sets',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003065207_test71_cb_configurable_set_defaults.sql');
  for(const token of ['DEFAULT SLEEVE','DEFAULT FINISH','DEFAULT BORDER POUNCHI','DEFAULT SIZE FAMILY']) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes('rr_cb_construction_defaults_get_v2'));
  assert.ok(cb.includes('rr_cb_construction_defaults_set_v2'));
  assert.ok(cb.includes('Existing Sets unchanged.'));
  assert.ok(sql.includes("default_border_pounchi text not null default 'WITHOUT_BORDER_POUNCHI'"));
});

test('Self Collar is direct and guarded from Additional Material mapping',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003071031_test71_cb_material_set_guard_v5.sql');
  assert.ok(cb.includes('DIRECT · MATERIAL N/A'));
  assert.ok(cb.includes('rr_cb_material_mapping_sync_v5'));
  assert.ok(sql.includes("set_code='self-collar'"));
  assert.ok(sql.includes('Additional Material cannot be linked'));
});

test('Cutting reads shared Set size sleeve and Border Pounchi',()=>{
  const cut=read('real-cutting-master-pm.V719.3.js');
  assert.ok(cut.includes('setRequirementRows'));
  assert.ok(cut.includes('setRequirementForUnit'));
  assert.ok(cut.includes('defaultSizeForActiveSet'));
  assert.ok(cut.includes('defaultSleeveForActiveSet'));
  assert.ok(cut.includes('defaultBorderForActiveSet'));
  for(const x of ['"L.XL.XXL"','"2XL.3XL.4XL"','"3XL.4XL.5XL"','"M.L.XL.XXL"','"M.L.XL"','"L.XL"','"L.XXL"','"FREE SIZE"']) assert.ok(cut.includes(x),x);
});


test('S1-S4 structural Art families are enforced in CB Art Decision and backend',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const art=read('real-art-decide-master-v9231.js');
  const sql=read('supabase/migrations/20261003071702_test71_cb_set_category_family_guard.sql');
  assert.ok(cb.includes("di)===1?['self-collar']:Number(di)===4?['flat-polo']:['crew-neck','drop-shoulder']"));
  assert.ok(cb.includes('artOptionsForSet'));
  assert.ok(art.includes('structuralArtCategoryIds'));
  assert.ok(art.includes("['self-collar']"));
  assert.ok(art.includes("['flat-polo']"));
  assert.ok(art.includes("['crew-neck','drop-shoulder']"));
  assert.ok(sql.includes("when u.division_index=1 then lower(c.category_code)='self-collar'"));
  assert.ok(sql.includes("when u.division_index=4 then lower(c.category_code)='flat-polo'"));
  assert.ok(sql.includes("when u.division_index in(2,3) then lower(c.category_code) in('crew-neck','drop-shoulder')"));
});


test('CB embeds the existing Print Sticker Metal combo engine and Add New masters',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  for(const token of ['ART COMBO','PRINT','STICKER','METAL ID','comboModeBtn','comboChoice','comboAddNew','comboAddArt']) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes('rr_pm_save_decision_bundle_v804'));
  assert.ok(cb.includes("p_print_mode:s.printMode"));
  assert.ok(cb.includes("p_sticker_mode:s.stickerMode"));
  assert.ok(cb.includes("p_metal_id_mode:s.metalMode"));
  assert.ok(cb.includes('art-v9148/?v=9233&from=cb-combo'));
  assert.ok(cb.includes('real-print-master.html?v=9233&from=cb-combo'));
  assert.ok(cb.includes('real-sticker-master-v804.html?v=9233&from=cb-combo'));
  assert.ok(cb.includes('real-metal-id-master-v804.html?v=9233&from=cb-combo'));
});

test('All Sets create one CB-level Purchase Order table from Yield',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes('GENERATE PURCHASE ORDER · ALL SETS'));
  assert.ok(cb.includes('generateAllSetPurchaseOrder'));
  assert.ok(cb.includes('ensureAllMaterialEstimates'));
  assert.ok(cb.includes('rr_cb_material_estimate_v2'));
  assert.ok(cb.includes('rr_cb_supplier_po_generate_v1'));
  for(const token of ['Set</th>','Material</th>','Colour</th>','Thumbnail</th>','Yield PCS</th>','Approx Qty</th>']) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes("code||'').toLowerCase()!=='self-collar'"));
  assert.ok(!cb.includes('class="primary supplierPo"'));
});

test('Standalone Art Decision editing is retired into CB without retiring backend engine',()=>{
  const retired=read('real-art-decide-master-v9231.js');
  const chat=read('test70-real-chat-live-v70.js');
  const pm=read('real-product-master-art-decision-module-v9226.js');
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(retired.includes('ART_DECISION_RETIRED#setDecisionCard'));
  assert.ok(chat.includes('EDIT ART COMBO'));
  assert.ok(chat.includes('CB_ART_COMBO'));
  assert.ok(!chat.includes('>ART DECISION EDIT</a>'));
  assert.ok(!pm.includes('>ART DECISION MASTER</button>'));
  assert.ok(pm.includes('Art / Print / Sticker / Metal ID decisions are managed only inside the CB Set · Art Combo screen.'));
  assert.ok(cb.includes('rr_pm_save_decision_bundle_v804'));
});

test('Single and Multi Lots inherit parent Set Combo and cannot redefine construction identity',()=>{
  const cut=read('real-cutting-master-pm.V719.3.js');
  const sql=read('supabase/migrations/20261003075100_test71_lot_parent_combo_inheritance.sql');
  const lock=read('supabase/migrations/20261003075600_test71_cb_combo_lock_after_lot.sql');
  assert.ok(cut.includes('Sleeve · Parent Set'));
  assert.ok(cut.includes('Border Pounchi · Parent Set'));
  assert.ok(!cut.includes('<select class="cm-dev-sleeve"'));
  assert.ok(!cut.includes('<select class="cm-dev-border"'));
  for(const token of ['new.art_no:=v_art_no','new.print_no:=v_print_no','new.sleeve_type:=lower','new.border_type:=case']) assert.ok(sql.includes(token),token);
  assert.ok(sql.includes('rr_cutting_lot_inherit_cb_set_combo_trg'));
  assert.ok(sql.includes('rr_production_lot_inherit_cb_set_combo_trg'));
  assert.ok(lock.includes('CB Set Art Combo is locked after Cutting Lot release.'));
});
