'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-common.js'),'utf8');
test('universal business uppercase authority is installed and protected',()=>{assert.match(source,/installBusinessUppercaseInputs/);assert.match(source,/toLocaleUpperCase/);assert.match(source,/password.*email.*url.*search/);assert.match(source,/remark\|remarks\|note\|notes\|description/);assert.match(source,/addEventListener\('submit'/);assert.match(source,/dataset\.rrUppercase==='off'/)});

test('number assist must normalize before matching',()=>{const accessory=fs.readFileSync(path.resolve(__dirname,'../../real-accessory-master-v804.js'),'utf8');assert.match(accessory,/uppercaseBusinessValue\?\.\(input\).*const rows=matches\(\)/s);});

test('active TEST71 business feeding surfaces are covered by common uppercase authority or exempt-only',()=>{const active=['real-cutting-master.html','real-finished-goods-v787.html','real-metal-id-master-v804.html','real-print-master.html','real-product-master-v720.html','real-sticker-master-v804.html','real-art-master.html','real-department-lite-v9127.html'];for(const file of active){const html=fs.readFileSync(path.resolve(__dirname,'../../'+file),'utf8');assert.match(html,/real-common\.js/,file+' must load real-common.js')}const exemptOnly=['real-accounts-suite-v857.html','test70-cb-purchase-real-chat-pilot.html'];for(const file of exemptOnly){const html=fs.readFileSync(path.resolve(__dirname,'../../'+file),'utf8');const fields=[...html.matchAll(/<(?:input|textarea)\b[^>]*>/gi)].map(m=>m[0]);assert.ok(fields.every(x=>/type=[\"']search[\"']/i.test(x)),file+' may omit common only while all manual fields are search-only')}});

test('accessory image stays before number and name',()=>{for(const file of ['real-sticker-master-v804.html','real-metal-id-master-v804.html']){const html=fs.readFileSync(path.resolve(__dirname,'../../'+file),'utf8'),image=html.indexOf('id="currentImageBox"'),no=html.indexOf('id="itemNo"'),name=html.indexOf('id="itemName"');assert.ok(image>=0&&image<no&&no<name,file+' must keep image -> number -> name DOM order')}});

test('division display authority is S-only while backend may remain D canonical',()=>{const common=fs.readFileSync(path.resolve(__dirname,'../../real-common.js'),'utf8'),cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8'),art=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8');assert.match(common,/displayDivision/);assert.match(common,/installDivisionDisplayAuthority/);assert.doesNotMatch(cb,/>D\\$\\{(?:di\\+1|i)\\}</);assert.match(cb,/id="divisionPreview">S1 · S2/);assert.ok(art.includes('function dNo(unit){return `S${Number(unit?.division_index||1)}`}'));});

test('CB edit keeps compact four-column S child Art thumbnail row before remarks',()=>{const html=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(html.indexOf('id="artThumbCard"')<html.indexOf('>Remarks</h3>'));assert.match(html,/grid-template-columns:repeat\(4,minmax\(0,1fr\)\)/);assert.match(html,/rr_cb_art_assignments/);assert.match(html,/entity_type','art'/);assert.match(html,/alt="S/);});

test('CB material allowed Art category mapping is persisted, defaulted and gated',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8'),art=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8'),sql=fs.readFileSync(path.resolve(__dirname,'../../supabase/migrations/20260930122000_test71_cb_material_allowed_art_categories.sql'),'utf8');assert.match(cb,/Allowed Art Categories/);assert.match(cb,/flat-polo/);assert.match(cb,/crew-neck/);assert.match(cb,/drop-shoulder/);assert.match(cb,/allowed_art_category_ids/);assert.match(art,/allowedArtCategoryIds/);assert.match(art,/rr_cb_material_allocations/);assert.match(sql,/rr_cb_art_category_gate_v1/);assert.match(sql,/allowed_art_category_ids/)});

test('Allowed Art Categories uses collapsed checkbox dropdown UX',()=>{const html=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(html,/details class="allowedArtCats"/);assert.match(html,/Select Categories/);assert.match(html,/allowedArtCheck/);assert.match(html,/allowedArtDone/);assert.doesNotMatch(html,/select class="allowedArtCats" multiple/)});

test('CB material and Art Decision mirror category authority by S-set',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8'),art=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8');assert.match(cb,/validateMaterialArtDivisionMatch/);assert.match(cb,/rr_cb_art_assignments/);assert.match(cb,/mirrored\.add\(String\(categoryId\)\)/);assert.match(cb,/decidedByUnit/);assert.match(cb,/allocationsByEntry/);assert.match(cb,/allocationAllowed/);assert.match(cb,/scope:selected\\.length\?'selected':'all'/);assert.match(cb,/effective=decided\?\[String\(decided\)\]/);assert.doesNotMatch(cb,/already has .* Art/);assert.match(art,/rr_cb_material_allocations/);assert.match(art,/allowed_art_category_ids/)});

test('Allowed Art category dropdown keeps compact checkbox and full label width',()=>{const html=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(html,/grid-template-columns:20px minmax\(0,1fr\)/);assert.match(html,/width:18px!important;height:18px!important/);assert.match(html,/white-space:normal;overflow:visible/)});

test('material mapping is explicit S-set first and allocation-specific',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8'),art=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8');assert.match(cb,/For which S set/);assert.match(cb,/artSetCheck/);assert.match(cb,/Select at least one S set first/);assert.match(art,/rr_cb_material_allocations/)});




test('present and future CB materials keep one independent division selector and configured category mirror',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/class="artSetAll"/);assert.match(cb,/class="artSetCheck"/);assert.match(cb,/Each material keeps its own division mapping/);assert.match(cb,/materialAppliesToArt/);assert.match(cb,/allowedArtCategoryIds/);assert.match(cb,/mirrorMaterialSetsFromDecidedArt/);assert.doesNotMatch(cb,/flat-polo\|polo/);assert.doesNotMatch(cb,/crew-neck\|drop-shoulder\|down-shoulder\|round-neck/)});
test('legacy CB material without canonical Art category mapping is exception-compatible',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/legacyUnmapped/);assert.match(cb,/if\(legacyUnmapped\)continue/)});


test('CB Art thumbnails render inside mapped material and direct no-material panel',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/DIRECT ART · NO MATERIAL/);assert.match(cb,/class="materialArtThumbs"/);assert.match(cb,/data-material-art/);assert.match(cb,/const mapped=new Set\(\)/);assert.match(cb,/!mapped\.has\(String\(unit\.id\)\)/)});


test('mapped thumbnail requires both selected S and eligible Art category',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/artCategoryByArt/);assert.match(cb,/eligible=new Set/);assert.match(cb,/eligible\.has\(String\(artCategoryId\|\|''\)\)/)});


test('CB user-facing division terminology is Set while individual identifiers remain S1 style',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/For which Set\? \*/);assert.match(cb,/All Sets/);assert.match(cb,/Selected Sets/);assert.match(cb,/>S\$\{di\+1\}</);assert.match(cb,/<small>Sets<\/small>/);assert.match(cb,/division_id/);assert.match(cb,/division_index/)});


test('CB group OPEN card renders edit action on first paint with canonical fallback href and Set label',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8');assert.match(chat,/fallbackEdit=c\.cb_id\?'real-cb-new-v9130-loader\.html\?cb_id='/);assert.match(chat,/editHref=String\(c\.edit_href\|\|fallbackEdit\|\|''\)/);assert.match(chat,/EDIT \/ CONTINUE/);assert.match(chat,/<span>Sets <b>/)});


test('saved and new Additional Material rows use one canonical shape without silent first-material selection',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.doesNotMatch(cb,/firstExtra=!reg\?materialCategories\(\)\[0\]/);assert.match(cb,/categoryId:cat\?\.id\|\|''/);assert.match(cb,/canonicalEntryById/);assert.match(cb,/material_category_id/);assert.match(cb,/vendor_bill_no/);assert.match(cb,/requirement_state/);assert.match(cb,/allocationAllowed\.length\?allocationAllowed/)});


test('CB supplier and material suggestions reuse canonical masters and refresh after creation',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/ensureCanonicalSupplier/);assert.match(cb,/rr_suppliers/);assert.match(cb,/normalizedMasterName/);assert.match(cb,/await loadOptions\(\);renderMaterials\(\)/);assert.match(cb,/for\(const c of materialCategories\(\)\)add\(fabricOpts/);assert.match(cb,/await loadCategories\(\);await loadOptions\(\)/)});


test('TEST70 pilot force-loads TEST71 instant CB edit renderer',()=>{const html=fs.readFileSync(path.resolve(__dirname,'../../test70-cb-purchase-real-chat-pilot.html'),'utf8');assert.match(html,/test70-real-chat-live-v70\.js\?v=TEST71-CB-INSTANT-EDIT-/);assert.doesNotMatch(html,/test70-real-chat-live-v70\.js\?v=9233-art-decision-runtime/)});


test('CB EDIT CONTINUE is a persistent primary action for the canonical OPEN card',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8');assert.match(chat,/class="cb-primary-edit"/);assert.match(chat,/canEdit&&state==='OPEN'&&editHref/);assert.doesNotMatch(chat,/state==='OPEN'\?'EDIT \/ CONTINUE':'UPDATE MATERIAL'/)});


test('CB OPEN card renders persistent ART DECISION beside EDIT CONTINUE',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8');assert.match(chat,/class="cb-primary-art"/);assert.match(chat,/data-action="ART_DECISION"/);assert.match(chat,/>ART DECISION<\/a>/);assert.match(chat,/real-art-decide-master\.html\?cb_unit_id=/);assert.match(chat,/card-actions.*edit\+artButton\+mapped/)});


test('Art Decision remains editable before Cutting and locks once a Cutting lot exists',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8'),art=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8');assert.match(chat,/ART LOCKED · CUTTING/);assert.match(chat,/artLocked=released>0/);assert.match(art,/artDecisionCuttingLock/);assert.match(art,/from\("rr_lots"\).*eq\("cb_id",id\)/);assert.match(art,/Art Decision locked: Cutting Lot has already been created\/released for this Set/)});


test('CB quantity reconciliation keeps Party Bill, physical roll stock and financial decision separate',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/QUANTITY RECONCILIATION/);assert.match(cb,/Party Bill Qty/);assert.match(cb,/Physical Roll \/ Stock-In Qty/);assert.match(cb,/ACCEPT PARTY BILL/);assert.match(cb,/MAKE DEBIT NOTE/);assert.match(cb,/rr_cb_quantity_reconciliation_get_v1/);assert.match(cb,/rr_cb_quantity_reconcile_v1/);assert.match(cb,/RECHECK REQUIRED/);assert.match(cb,/Quantity mismatch: ACCEPT PARTY BILL or MAKE DEBIT NOTE before final confirm/)});


test('CB EDIT and ART actions derive from parent CB identity on first paint, not child hydration',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8'),loader=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-loader.html'),'utf8'),editor=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8'),art=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8');assert.match(chat,/cbKey=String\(c\.cb_no\|\|c\.cb_code/);assert.match(chat,/real-cb-new-v9130-loader\.html\?cb_no=/);assert.match(chat,/real-art-decide-master\.html\?cb_no=/);assert.match(loader,/q\.get\('cb_no'\)/);assert.match(editor,/qp\.get\('cb_no'\)/);assert.match(art,/params\.get\("cb_no"\)/)});


test('live roll edits change Physical Stock-In only and never overwrite Party Bill Qty',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/regular\.rolls\[ci\]\[ri\]\.qty=e\.target\.value;markReconciliationDirty\(\);renderMaterials\(\);updateSummary\(\)/);assert.doesNotMatch(cb,/regular\.qty=String\(rollTotal\(regular\)/);assert.match(cb,/liveKey=bill\.toFixed\(3\).*physical\.toFixed\(3\)/);assert.match(cb,/stale\?'RECHECK_REQUIRED'/);assert.match(cb,/friendlySaveError/)});


test('CB OPEN actions render before actor role hydration while destination enforces permission',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8');assert.match(chat,/edit=state==='OPEN'&&editHref/);assert.match(chat,/artButton=state==='OPEN'&&artHref&&!artLocked/);assert.doesNotMatch(chat,/edit=canEdit&&state==='OPEN'/);assert.doesNotMatch(chat,/artButton=canEdit&&state==='OPEN'/)});


test('CB quantity reconciliation offers Debit Note for SHORT and Credit Note for EXCESS',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/MAKE DEBIT NOTE/);assert.match(cb,/MAKE CREDIT NOTE/);assert.match(cb,/decideReconciliation\('DEBIT_NOTE'\)/);assert.match(cb,/decideReconciliation\('CREDIT_NOTE'\)/);assert.match(cb,/Credit Note posted to supplier Accounts/)});
