const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

test('CB Art Material Decision owns Single Multi planning before Cutting',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003102000_test71_cb_art_material_planning_profiles.sql');
  for(const token of [
    'Art &amp; Material Decision',
    'PENDING · NO DECISION',
    'DUE · DECIDE LATER',
    'SINGLE LOT · ALL SETS',
    'MULTI LOT / MIXED SETS',
    'rootPlanMode','rootChildCount','profileShare','rr_cb_set_lot_plan_v1'
  ]) assert.ok(cb.includes(token),token);
  assert.ok(sql.includes("art_material_plan_state in ('PENDING','DUE','SINGLE','MULTI')"));
  assert.ok(sql.includes('rr_cb_set_lot_plan_v1'));
  assert.ok(sql.includes("raise exception 'Set Lot structure is frozen after Cutting Lot save.'"));
});

test('Multi planning creates real child CB profiles with independent Art Combo identity',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003102000_test71_cb_art_material_planning_profiles.sql');
  assert.ok(cb.includes('Each child has its own Art Combo and downstream identity.'));
  assert.ok(cb.includes('profileCardHtml(String(ch.division_index))'));
  assert.ok(cb.includes('activeProfileKeys'));
  assert.ok(sql.includes('parent_unit_id'));
  assert.ok(sql.includes('batch_index'));
  assert.ok(sql.includes('parent.cb_code||chr(64+i)'));
  assert.ok(sql.includes('rr_cb_copy_combo_v1'));
  assert.ok(sql.includes("combo_mode='multi',is_final=false,is_cutting_enabled=false"));
});

test('Art remains directly editable until exact Cutting Lot save and Category auto maps',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const plan=read('supabase/migrations/20261003102000_test71_cb_art_material_planning_profiles.sql');
  const derived=read('supabase/migrations/20261003102500_test71_cb_derived_requirement_whatsapp.sql');
  assert.ok(cb.includes('class="canonicalSetArt"'));
  assert.ok(cb.includes('CATEGORY · AUTO MAPPED'));
  assert.ok(!cb.includes('CHANGE CATEGORY / ART'));
  assert.ok(cb.includes('rr_cb_unit_has_final_cutting_v1'));
  assert.ok(cb.includes('Lot No + Cutting Pieces save हो चुके हैं.'));
  assert.ok(plan.includes("nullif(trim(coalesce(lot_no,'')),'') is not null"));
  assert.ok(plan.includes('coalesce(nullif(actual_pcs,0),planned_pcs,0)>0'));
  assert.ok(derived.includes('CB Set Art Combo is frozen after Cutting Lot No + Pieces save.'));
});

test('Category defaults are configurable and do not rewrite saved profiles',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003102000_test71_cb_art_material_planning_profiles.sql');
  assert.ok(cb.includes('MAKE CURRENT VALUES DEFAULT'));
  assert.ok(cb.includes('rr_cb_category_defaults_get_v1'));
  assert.ok(cb.includes('rr_cb_category_defaults_set_v1'));
  assert.ok(cb.includes('Future/new decisions only; saved profiles नहीं बदलेंगे.'));
  assert.ok(sql.includes("default_sleeve_type text not null default 'HALF'"));
  assert.ok(sql.includes("default_sleeve_finish text not null default 'CUFF'"));
  assert.ok(sql.includes("lower(category_code) in('crew-neck','drop-shoulder') then 'PLAIN'"));
  assert.ok(sql.includes("default_border_pounchi text not null default 'WITHOUT_BORDER_POUNCHI'"));
});

test('Print Sticker Metal pickers collapse after Done and show selected thumbnails and Frames',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  for(const token of ['comboOpen','comboDone','comboCancel','combo-preview-grid','combo-preview-tile','frame-detail','rr_print_frames']) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes("done&&mode==='SELECTED'?comboPreviewHtml(kind,ids):''"));
  assert.ok(cb.includes("kind==='print'?comboFrames(id):[]"));
  assert.ok(cb.includes('comboPrintPreview'));
  assert.ok(cb.includes("btn.classList.toggle('open')"));
});

test('Additional Material manual decision UI is retired and requirement is derived from Art Combo',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const plan=read('supabase/migrations/20261003102000_test71_cb_art_material_planning_profiles.sql');
  const derived=read('supabase/migrations/20261003102500_test71_cb_derived_requirement_whatsapp.sql');
  assert.ok(cb.includes('id="extraMaterialCard" hidden'));
  assert.ok(cb.includes('Yield · Consolidated Requirement'));
  assert.ok(cb.includes('rr_cb_material_mapping_sync_v6'));
  assert.ok(cb.includes('rr_cb_material_estimate_v3'));
  assert.ok(plan.includes('rr_cb_material_mapping_sync_v6'));
  assert.ok(plan.includes('rr_cb_profile_yield_v1'));
  assert.ok(plan.includes('rr_cb_material_estimate_v3'));
  assert.ok(derived.includes("lower(mc.category_code) in('collar-cuff','rib')"));
  assert.ok(derived.includes("entry_notes='AUTO ART COMBO MATERIAL'"));
});

test('Sticker and Metal ID initial purchase or making quantity uses Yield PCS',()=>{
  const derived=read('supabase/migrations/20261003102500_test71_cb_derived_requirement_whatsapp.sql');
  assert.ok(derived.includes("basis:='YIELD'"));
  assert.ok(derived.includes("'STICKER'"));
  assert.ok(derived.includes("'METAL_ID'"));
  assert.ok(derived.includes("case when upper(fulfil)='OUTSOURCE' then 'PURCHASE' else 'MAKING' end"));
  assert.ok(derived.includes("case when upper(fulfil)='IN_HOUSE' then 'MAKING' else 'PURCHASE' end"));
  assert.ok(derived.includes('basis_pcs*coalesce(gpp,1)'));
});

test('Cutting actual revises Yield requirements only after Lot No and PCS are saved',()=>{
  const derived=read('supabase/migrations/20261003102500_test71_cb_derived_requirement_whatsapp.sql');
  assert.ok(derived.includes("nullif(trim(coalesce(new.lot_no,'')),'') is null"));
  assert.ok(derived.includes('coalesce(nullif(new.actual_pcs,0),new.planned_pcs,0)<=0'));
  assert.ok(derived.includes("basis:='CUTTING_ACTUAL'"));
  assert.ok(derived.includes('rr_cb_cutting_actual_requirement_refresh_v1'));
  assert.ok(derived.includes('rr_cb_multi_actual_requirement_refresh_v1'));
  assert.ok(derived.includes('drop trigger if exists rr_cb_derived_after_single_cutting_v1'));
  assert.ok(derived.includes('drop trigger if exists rr_cb_derived_after_multi_cutting_v1'));
});

test('WhatsApp requirement supports first send resend and revised send with history',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003102500_test71_cb_derived_requirement_whatsapp.sql');
  assert.ok(cb.includes("return'SEND WHATSAPP'"));
  assert.ok(cb.includes("return'SEND REVISED'"));
  assert.ok(cb.includes("return 'RESEND #'"));
  assert.ok(cb.includes('rr_cb_requirement_send_v1'));
  assert.ok(sql.includes('rr_cb_requirement_send_log_v1'));
  assert.ok(sql.includes("'FIRST'"));
  assert.ok(sql.includes("'REVISED'"));
  assert.ok(sql.includes("'RESEND'"));
  assert.ok(sql.includes('REQUIREMENT STILL PENDING'));
  assert.ok(sql.includes('RESENDING PURCHASE ORDER'));
  assert.ok(sql.includes('send_sequence'));
});

test('Supplier is auto mapped from existing masters and can be overridden',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003102500_test71_cb_derived_requirement_whatsapp.sql');
  assert.ok(cb.includes('rr_cb_requirement_supplier_set_v1'));
  assert.ok(cb.includes('SELECT SUPPLIER…'));
  assert.ok(sql.includes('rr_material_source_supplier_map_v805_31'));
  assert.ok(sql.includes('preferred_supplier_ledger_id'));
  assert.ok(sql.includes('supplier_override=true'));
});

test('All Sets generate one profile-aware Purchase Order from Yield',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes('GENERATE PURCHASE ORDER · ALL SETS'));
  assert.ok(cb.includes('generateAllSetPurchaseOrder'));
  assert.ok(cb.includes('activeProfileKeys()'));
  assert.ok(cb.includes('rr_cb_material_estimate_v3'));
  assert.ok(cb.includes('rr_cb_supplier_po_generate_v1'));
  assert.ok(!cb.includes('class="primary supplierPo"'));
});

test('Cutting no longer decides Single vs Multi and only opens the CB-planned profile Lot',()=>{
  const cut=read('real-cutting-master-pm.V719.3.js');
  assert.ok(cut.includes('OPEN CUTTING LOT'));
  assert.ok(cut.includes('Lot plan fixed in CB'));
  assert.ok(!cut.includes('data-multi='));
  assert.ok(!cut.includes('id="cmMultiPanel"'));
  assert.ok(!cut.includes('id="cmDevCount"'));
  assert.ok(!cut.includes('id="cmBuildDevRows"'));
  assert.ok(cut.includes('Sleeve · From CB Set'));
  assert.ok(cut.includes('Border Pounchi · From CB Set'));
});

test('Standalone Art Decision UI remains retired and CB stays the editing authority',()=>{
  const retired=read('real-art-decide-master-v9231.js');
  const chat=read('test70-real-chat-live-v70.js');
  const pm=read('real-product-master-art-decision-module-v9226.js');
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(retired.includes('ART_DECISION_RETIRED#setDecisionCard'));
  assert.ok(chat.includes('EDIT ART COMBO'));
  assert.ok(chat.includes('CB_ART_COMBO'));
  assert.ok(!chat.includes('>ART DECISION EDIT</a>'));
  assert.ok(!pm.includes('>ART DECISION MASTER</button>'));
  assert.ok(cb.includes('rr_pm_save_decision_bundle_v804'));
});

test('Existing assignment IDs remain the downstream authority for Print Sticker Metal',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const lot=read('supabase/migrations/20261003075100_test71_lot_parent_combo_inheritance.sql');
  assert.ok(cb.includes('rr_cb_art_assignments'));
  assert.ok(cb.includes('rr_cb_print_assignments'));
  assert.ok(cb.includes('rr_cb_sticker_assignments'));
  assert.ok(cb.includes('rr_cb_metal_id_assignments_v801'));
  assert.ok(cb.includes('rr_pm_save_decision_bundle_v804'));
  assert.ok(lot.includes('rr_cutting_lot_inherit_cb_set_combo_trg'));
  assert.ok(lot.includes('rr_production_lot_inherit_cb_set_combo_trg'));
});
