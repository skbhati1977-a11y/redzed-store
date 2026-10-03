const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');
const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

test('CB owns the complete Art Combo and reuses existing backend assignment engine',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  for(const token of ['ART COMBO','PRINT','STICKER','METAL ID','comboModeBtn','comboChoice','comboAddNew','comboAddArt','SAVE SET COMBO']) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes("rr_pm_save_decision_bundle_v804"));
  assert.ok(cb.includes("rr_sync_cb_mapping_from_art_v3"));
  assert.ok(cb.includes("p_sticker_master_ids:s.stickerIds"));
  assert.ok(cb.includes("p_metal_id_master_ids:s.metalIds"));
});

test('CB Combo Add New reuses original Art Print Sticker and Metal masters',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  for(const url of ['art-v9148/?v=9233&from=cb-combo','real-print-master.html?v=9233&from=cb-combo','real-sticker-master-v804.html?v=9233&from=cb-combo','real-metal-id-master-v804.html?v=9233&from=cb-combo']) assert.ok(cb.includes(url),url);
  assert.ok(cb.includes('RR_PRINT_MASTER_CAN_CLOSE'));
  assert.ok(cb.includes('New '+"'+CB_COMBO_MASTER_META[ctx.kind].label+'"+' created and selected in CB Combo.'));
});

test('one CB-level button generates all-Set Yield PO table and supplier drafts behind it',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes('id="generateAllSetPo"'));
  assert.ok(cb.includes('GENERATE PURCHASE ORDER · ALL SETS'));
  assert.ok(cb.includes('generateAllSetPurchaseOrder'));
  assert.ok(cb.includes('ensureAllMaterialEstimates'));
  assert.ok(cb.includes("rr_cb_supplier_po_generate_v1"));
  assert.ok(cb.includes('<th style="text-align:left;padding:7px">Set</th>'));
  assert.ok(cb.includes('colour_image_url'));
  assert.ok(!cb.includes('class="primary supplierPo"'));
});

test('standalone Art Decision is operationally retired into CB and Real Chat routes there',()=>{
  const art=read('real-art-decide-master-v9231.js');
  const chat=read('test70-real-chat-live-v70.js');
  assert.ok(art.includes('retiredCbTarget'));
  assert.ok(art.includes('ART_DECISION_RETIRED#setDecisionCard'));
  assert.ok(chat.includes('EDIT ART COMBO'));
  assert.ok(chat.includes('data-action="CB_ART_COMBO"'));
  assert.ok(!chat.includes('ART DECISION EDIT'));
  assert.ok(!chat.includes('Art Decide ·'));
  assert.ok(chat.includes('CB Art Combo ·'));
  assert.ok(!chat.includes("real-art-decide-master.html?cb_no="));
});

test('Single and Multi Lot inherit parent Set Art Print Sleeve and Border while Size remains split-able',()=>{
  const cut=read('real-cutting-master-pm.V719.3.js');
  const sql=read('supabase/migrations/20261003075100_test71_lot_parent_combo_inheritance.sql');
  assert.ok(cut.includes('Sleeve · Parent Set'));
  assert.ok(cut.includes('Border Pounchi · Parent Set'));
  assert.ok(cut.includes('class="cm-dev-size"'));
  assert.ok(cut.includes('class="cm-dev-sleeve" data-dev-index="${index}" type="text" readonly'));
  assert.ok(cut.includes('class="cm-dev-border" data-dev-index="${index}" type="text" readonly'));
  assert.ok(sql.includes('new.art_no:=v_art_no'));
  assert.ok(sql.includes("new.sleeve_type:=lower"));
  assert.ok(sql.includes("new.border_type:=case"));
  assert.ok(sql.includes("new.print_no:='N/A'"));
  assert.ok(sql.includes('rr_cutting_lot_inherit_cb_set_combo_trg'));
  assert.ok(sql.includes('rr_production_lot_inherit_cb_set_combo_trg'));
});

test('Art Combo backend is locked after any Cutting Lot release',()=>{
  const sql=read('supabase/migrations/20261003075600_test71_cb_combo_lock_after_lot.sql');
  assert.ok(sql.includes('rr_cutting_lots_v3 where cb_unit_id=p_cb_unit_id'));
  assert.ok(sql.includes('rr_production_lots where cb_unit_id=p_cb_unit_id'));
  assert.ok(sql.includes('CB Set Art Combo is locked after Cutting Lot release.'));
  assert.ok(sql.includes("'combo_authority','CB_SET'"));
});


test('CB Combo libraries hydrate after the initial new-CB render',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes("await Promise.all([loadCanonicalMasters(),loadCategories(),loadOptions()]);"));
  assert.ok(cb.includes("loadComboLibraries().then(renderSetDecisions)"));
});
