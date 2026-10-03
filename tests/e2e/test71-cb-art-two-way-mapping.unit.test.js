const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

test('CB starts with one Art & Material Decision planning authority',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  for(const token of [
    'Art &amp; Material Decision',
    'PENDING · NO DECISION',
    'DUE · DECIDE LATER',
    'SINGLE LOT · ALL SETS',
    'MULTI LOT / MIXED SETS',
    'id="setDecisionCard"'
  ]) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes('rr_cb_art_material_plan_set_v1'));
  assert.ok(cb.includes('rr_cb_plan_context_v1'));
});

test('Single and Multi Set planning is decided in CB, child profiles are real CB units',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003103000_test71_cb_art_material_multi_profile_planning.sql');
  assert.ok(cb.includes('rootPlanMode'));
  assert.ok(cb.includes('rootChildCount'));
  assert.ok(cb.includes('APPLY SPLIT'));
  assert.ok(cb.includes('data-root-set'));
  assert.ok(cb.includes('profile-card'));
  assert.ok(cb.includes('rr_cb_set_lot_plan_v1'));
  assert.ok(sql.includes('parent_unit_id'));
  assert.ok(sql.includes('clone_source_id'));
  assert.ok(sql.includes("combo_mode='multi'"));
  assert.ok(sql.includes('is_cutting_enabled=false'));
});

test('Art dropdown remains directly editable until exact profile Cutting save',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003103100_test71_cb_yield_requirements_whatsapp_revision.sql');
  const plan=read('supabase/migrations/20261003103000_test71_cb_art_material_multi_profile_planning.sql');
  assert.ok(cb.includes('class="canonicalSetArt"'));
  assert.ok(cb.includes('CATEGORY · AUTO MAPPED'));
  assert.ok(cb.includes('Art select होने पर Category auto map होगी.'));
  assert.ok(!cb.includes('CHANGE CATEGORY / ART'));
  assert.ok(cb.includes('FROZEN · CUTTING SAVED'));
  assert.ok(plan.includes('Lot No + Pieces save'));
  assert.ok(sql.includes('CB Set Art Combo is frozen after Cutting Lot No + Pieces save.'));
});

test('Category-aware defaults are configurable and preserve saved profiles',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003103000_test71_cb_art_material_multi_profile_planning.sql');
  for(const token of [
    'MAKE CURRENT VALUES DEFAULT',
    'canonicalSetSleeve',
    'canonicalSetFinish',
    'canonicalSetBorder',
    'canonicalSetSizes',
    'WITHOUT BORDER POUNCHI'
  ]) assert.ok(cb.includes(token),token);
  assert.ok(cb.includes('rr_cb_category_defaults_set_v1'));
  assert.ok(sql.includes("default_sleeve_type text not null default 'HALF'"));
  assert.ok(sql.includes("default_sleeve_finish text not null default 'CUFF'"));
  assert.ok(sql.includes("lower(category_code) in('crew-neck','drop-shoulder') then 'PLAIN'"));
  assert.ok(sql.includes("default_border_pounchi text not null default 'WITHOUT_BORDER_POUNCHI'"));
});

test('Print Sticker Metal pickers collapse after Done and show selected thumbnails',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes('comboOpen'));
  assert.ok(cb.includes('comboDone'));
  assert.ok(cb.includes('comboPreviewHtml'));
  assert.ok(cb.includes('combo-preview-grid'));
  assert.ok(cb.includes('combo-preview-tile'));
  assert.ok(cb.includes('comboPrintPreview'));
  assert.ok(cb.includes('frame-detail'));
  assert.ok(cb.includes('rr_print_frames'));
  assert.ok(cb.includes("btn.classList.toggle('open')"));
});

test('Existing Add New master flows remain embedded in CB Art Combo',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes('comboAddArt'));
  assert.ok(cb.includes('comboAddNew'));
  assert.ok(cb.includes('art-v9148/?v=9233&from=cb-combo'));
  assert.ok(cb.includes('real-print-master.html?v=9233&from=cb-combo'));
  assert.ok(cb.includes('real-sticker-master-v804.html?v=9233&from=cb-combo'));
  assert.ok(cb.includes('real-metal-id-master-v804.html?v=9233&from=cb-combo'));
});

test('Additional Material manual UI is retired; derived requirement is visible instead',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes('id="extraMaterialCard" hidden'));
  assert.ok(cb.includes('Yield · Consolidated Requirement'));
  assert.ok(cb.includes('Art Combo → Yield PCS → Collar/Rib/Sticker/Metal ID requirement.'));
  assert.ok(cb.includes('rr_cb_refresh_derived_requirements_v1'));
  assert.ok(cb.includes('rr_cb_requirement_context_v1'));
});

test('Yield drives initial Sticker and Metal ID planning and Cutting actual can revise it',()=>{
  const sql=read('supabase/migrations/20261003103100_test71_cb_yield_requirements_whatsapp_revision.sql');
  assert.ok(sql.includes("basis text not null default 'YIELD'"));
  assert.ok(sql.includes("basis in('YIELD','CUTTING_ACTUAL')"));
  assert.ok(sql.includes('rr_cb_profile_yield_v1'));
  assert.ok(sql.includes('rr_cb_cutting_actual_requirement_refresh_trg_v1'));
  assert.ok(sql.includes('after insert or update of cb_unit_id,lot_no,planned_pcs,actual_pcs,status'));
  assert.ok(sql.includes("'STICKER'"));
  assert.ok(sql.includes("'METAL_ID'"));
});

test('WhatsApp supports FIRST, RESEND and REVISED templates with send history',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003103100_test71_cb_yield_requirements_whatsapp_revision.sql');
  assert.ok(cb.includes('SEND WHATSAPP'));
  assert.ok(cb.includes('SEND REVISED'));
  assert.ok(cb.includes('RESEND #'));
  assert.ok(cb.includes('rr_cb_requirement_send_v1'));
  assert.ok(sql.includes("template_kind in('FIRST','RESEND','REVISED')"));
  assert.ok(sql.includes('REQUIREMENT STILL PENDING'));
  assert.ok(sql.includes('RESENDING PURCHASE ORDER'));
  assert.ok(sql.includes('REVISED PURCHASE ORDER / REQUIREMENT'));
  assert.ok(sql.includes('rr_cb_requirement_send_log_v1'));
});

test('Supplier selector uses canonical ledger id and can override auto supplier',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const sql=read('supabase/migrations/20261003103100_test71_cb_yield_requirements_whatsapp_revision.sql');
  assert.ok(cb.includes('x.ledger_id||x.id'));
  assert.ok(cb.includes('rr_cb_requirement_supplier_set_v1'));
  assert.ok(sql.includes('supplier_override boolean not null default false'));
  assert.ok(sql.includes('rr_material_source_supplier_map_v805_31'));
});

test('One all-Set material PO is rendered from profile-aware Yield rows',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes('GENERATE PURCHASE ORDER · ALL SETS'));
  assert.ok(cb.includes('generateAllSetPurchaseOrder'));
  assert.ok(cb.includes('rr_cb_material_estimate_v3'));
  assert.ok(cb.includes('profile_label'));
  assert.ok(cb.includes('rr_cb_supplier_po_generate_v1'));
  assert.ok(!cb.includes('class="primary supplierPo"'));
});

test('Standalone Art Decision remains retired into CB',()=>{
  const retired=read('real-art-decide-master-v9231.js');
  const chat=read('test70-real-chat-live-v70.js');
  const pm=read('real-product-master-art-decision-module-v9226.js');
  assert.ok(retired.includes('ART_DECISION_RETIRED#setDecisionCard'));
  assert.ok(chat.includes('EDIT ART COMBO'));
  assert.ok(chat.includes('CB_ART_COMBO'));
  assert.ok(!chat.includes('>ART DECISION EDIT</a>'));
  assert.ok(!pm.includes('>ART DECISION MASTER</button>'));
});

test('Cutting no longer offers a second Multi Lot decision',()=>{
  const cut=read('real-cutting-master-pm.V719.3.js');
  assert.ok(cut.includes('OPEN CUTTING LOT'));
  assert.ok(cut.includes('Lot plan fixed in CB'));
  assert.ok(cut.includes('EDIT CB ART COMBO'));
  assert.ok(!cut.includes('data-multi'));
  assert.ok(!cut.includes('data-art-decision'));
  assert.ok(cut.includes('currentLotMode = "single"'));
});

test('Only one actual-cutting derived requirement refresh trigger is retained per lot table',()=>{
  const sql=read('supabase/migrations/20261003103100_test71_cb_yield_requirements_whatsapp_revision.sql');
  assert.ok(sql.includes('drop trigger if exists rr_cb_derived_after_single_cutting_v1'));
  assert.ok(sql.includes('drop trigger if exists rr_cb_derived_after_multi_cutting_v1'));
  assert.ok(sql.includes('rr_cb_cutting_actual_requirement_refresh_v1'));
  assert.ok(sql.includes('rr_cb_multi_actual_requirement_refresh_v1'));
});

test('Legacy duplicate mapping engines are absent from active CB UI',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  for(const token of [
    'rr_cb_material_mapping_sync_v5',
    'rr_cb_set_requirement_sync_v5',
    'rr_cb_material_estimate_v2',
    'SET CONSTRUCTION · PRE-ART SPEC',
    'details class="allowedArtCats"',
    'CHANGE CATEGORY / ART'
  ]) assert.ok(!cb.includes(token),token);
});
