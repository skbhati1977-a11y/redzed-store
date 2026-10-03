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
  assert.ok(cb.includes('Same Art in CB + Art Decision'));
  assert.ok(!cb.includes('SET CONSTRUCTION · PRE-ART SPEC'));
  assert.ok(!cb.includes('details class="allowedArtCats"'));
  assert.ok(!cb.includes('class="setArt"'));
  assert.ok(!cb.includes('class="directArt"'));
});

test('CB and Art Decision share one Art assignment authority in both directions',()=>{
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
