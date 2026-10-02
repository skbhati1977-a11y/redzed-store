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


test('SHORT reconciliation can enter existing Damage Claim lifecycle without a duplicate damage engine',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/REPORT DAMAGE/);assert.match(cb,/rr_create_cb_damage_claim_v1/);assert.match(cb,/BEFORE_CUTTING/);assert.match(cb,/Owner verification\/approval required before supplier Accounts claim/);assert.doesNotMatch(cb,/rr_cb_reconciliation_damage/)});


test('SHORT reconciliation reports shortage to Admin Real Chat, not Damage Claim',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/REPORT SHORTAGE/);assert.match(cb,/rr_cb_shortage_report_v1/);assert.match(cb,/FORWARD TO SUPPLIER action/);assert.doesNotMatch(cb,/Create Damage Claim for/);assert.doesNotMatch(cb,/reportReconciliationDamage/)});


test('CB reconciliation reports both SHORT and EXCESS to Admin while financial decisions remain separate',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/REPORT SHORT/);assert.match(cb,/REPORT EXCESS/);assert.match(cb,/rr_cb_variance_report_v1/);assert.match(cb,/p_variance_type:type/);assert.match(cb,/Financial decision remains separate/)});


test('CB reconciliation has one working REPORT SHORT EXCESS action and no stale Damage action',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/REPORT SHORT \/ EXCESS/);assert.match(cb,/class="secondary reportVariance"/);assert.match(cb,/reportVariance'\)\?\.addEventListener\('click',reportReconciliationVariance\)/);assert.doesNotMatch(cb,/>REPORT DAMAGE<\/button>/);assert.doesNotMatch(cb,/class="secondary reportShortage"/)});


test('CB frontend sanitizes technical backend errors and variance report uses friendly failure copy',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/friendlyUserError/);assert.match(cb,/null value in column\|violates not-null\|constraint/);assert.match(cb,/SHORT \/ EXCESS report Admin को नहीं भेजा जा सका/);assert.match(cb,/console\.error\('CB variance report'/)});


test('CB variance report offers Super Admin WhatsApp send inside report success flow',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/sendReportToSuperAdmin/);assert.match(cb,/rr_report_send_superadmin_prepare_v1/);assert.match(cb,/SEND TO SUPER ADMIN on WhatsApp/);assert.match(cb,/rr_report_send_superadmin_confirm_v1/)});


test('existing CB renders before noncritical mirror reconciliation thumbnail enrichment',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/Loading saved CB…/);assert.match(cb,/ensureDefaultRolls\(\);renderMaterials\(\);renderColours\(\);updateSummary\(\);\$\('bootMsg'\)\.style\.display='none'/);assert.match(cb,/Promise\.allSettled\(\[mirrorMaterialSetsFromDecidedArt\(\),loadReconciliation\(\),loadArtThumbs\(\)\]\)/);assert.match(cb,/mastersPromise=Promise\.all/)});


test('fast existing CB render is retained and boot errors are user-friendly',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/Promise\.allSettled\(\[mirrorMaterialSetsFromDecidedArt\(\),loadReconciliation\(\),loadArtThumbs\(\)\]\)/);assert.match(cb,/Loading saved CB…/);assert.match(cb,/console\.error\('CB boot'/);assert.match(cb,/friendlyUserError\(err,'CB details load नहीं हो सकीं/);assert.doesNotMatch(cb,/\$\('bootMsg'\)\.textContent=err\?\.message\|\|String\(err\)/)});


test('TEST71 Real Chat has universal friendly error guard without changing business validation',()=>{const shell=fs.readFileSync(path.resolve(__dirname,'../../test70-cb-purchase-real-chat-pilot.html'),'utf8'),guard=fs.readFileSync(path.resolve(__dirname,'../../test71-user-friendly-errors.js'),'utf8');assert.match(shell,/test71-user-friendly-errors\.js/);assert.match(guard,/RRUserFriendlyError/);assert.match(guard,/null value in column/);assert.match(guard,/unhandledrejection/);assert.match(guard,/actionFrame/);assert.match(guard,/if\(!TECH\.test\(s\)\)return s/)});


test('final SEND TO SUPER ADMIN action marks WhatsApp delivery SENT without a second confirmation',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/rr_report_send_superadmin_confirm_v1/);assert.match(cb,/SENT mark कर दिया गया/);assert.doesNotMatch(cb,/क्या message Super Admin को send कर दिया/);assert.doesNotMatch(cb,/Report saved है\. WhatsApp send अभी confirm नहीं किया गया/)});


test('CB card keeps Sets label and Art Decision until actual Cutting lot evidence exists',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8'),shell=fs.readFileSync(path.resolve(__dirname,'../../test70-cb-purchase-real-chat-pilot.html'),'utf8');assert.match(chat,/<span>Sets <b>/);assert.match(chat,/ART DECISION/);assert.match(chat,/lot_numbers\|\|x\.lots/);assert.doesNotMatch(chat,/artLocked=released>0/);assert.match(shell,/TEST71-ART-SETS-PERSISTENT-/)});


test('Art Decision Edit remains editable until a real Lot Number exists and CB actions stay side by side',()=>{const chat=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8'),shell=fs.readFileSync(path.resolve(__dirname,'../../test70-cb-purchase-real-chat-pilot.html'),'utf8');assert.match(chat,/ART DECISION EDIT/);assert.match(chat,/ART DECISION FIXED/);assert.match(chat,/lot_no\|\|l\.lot_number/);assert.doesNotMatch(chat,/ART LOCKED · CUTTING/);assert.doesNotMatch(chat,/RELEASED_TO_CUTTING/);assert.match(shell,/grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/)});


test('WhatsApp handoff preserves current CB editor context for Android back return',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.match(cb,/RR_CB_WHATSAPP_RETURN_V1/);assert.match(cb,/href:location\.href,scrollY:window\.scrollY,cbId/);assert.match(cb,/pageshow.*restoreCbAfterWhatsApp/);assert.match(cb,/visibilitychange/);assert.match(cb,/window\.scrollTo/)});


test('CB GSM and Cutting exact roll yield foundation are wired without changing quantity reconciliation',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8'),cut=fs.readFileSync(path.resolve(__dirname,'../../redzed-cutting-cb-actions-v72035.js'),'utf8'),pm=fs.readFileSync(path.resolve(__dirname,'../../real-cutting-master-pm.V719.3.js'),'utf8');assert.match(cb,/class="colourGsm"/);assert.match(cb,/rr_cb_colour_gsm_save_v1/);assert.match(cb,/rr_cb_colour_gsm_v1/);assert.match(cb,/function reconciliationLocal/);assert.match(cut,/rr_cutting_regular_purchase_sources_v2/);assert.match(cut,/Physical Rolls · Lot Binding/);assert.match(cut,/RR_SELECTED_CUTTING_ROLL_IDS/);assert.match(pm,/rr_cutting_bind_rolls_v1/);assert.match(pm,/rr_cutting_capture_yield_v1/);assert.match(pm,/valid\.lotMode!=='multi'/)});


test('Multi Cutting uses per-lot roll selections and prevents one physical roll being selected twice',()=>{const cut=fs.readFileSync(path.resolve(__dirname,'../../redzed-cutting-cb-actions-v72035.js'),'utf8'),pm=fs.readFileSync(path.resolve(__dirname,'../../real-cutting-master-pm.V719.3.js'),'utf8');assert.match(cut,/selectedRollIdsByDev/);assert.match(cut,/RR_SELECTED_CUTTING_ROLLS_BY_DEV/);assert.match(cut,/data-roll-scope/);assert.match(pm,/selectedRollsByDev/);assert.match(pm,/for\(const lot of valid\.lots\)/);assert.match(pm,/rr_cutting_capture_yield_v1/)});


test('Additional Material keeps mapping first, Yield/PO planning second, supplier and bill details last',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const map=cb.indexOf('Allowed Art Categories'),yieldPos=cb.indexOf('YIELD ESTIMATION · PO PLANNING'),supplier=cb.indexOf('SUPPLIER / PURCHASE DETAILS'),bill=cb.indexOf('BILL NO.');assert.ok(map>=0&&yieldPos>map&&supplier>yieldPos&&bill>supplier);assert.match(cb,/rr_cb_material_estimate_v1/);assert.match(cb,/rr_cb_material_po_draft_create_v1/);assert.match(cb,/rr_material_types_v805/);assert.match(cb,/exact Material/)});


test('CB editor mobile workspace keeps header and save actions in normal document flow',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('.head{position:relative'));assert.ok(cb.includes('.actions{position:static'));assert.ok(!cb.includes('.head{position:sticky'));assert.ok(!cb.includes('.actions{position:fixed'))});


test('Additional Material renders three explicit layers with PO between mapping and purchase',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const a=cb.indexOf('A · MATERIAL SELECTION'),b=cb.indexOf('B · SET & ART MAPPING'),c=cb.indexOf('YIELD ESTIMATION · PO PLANNING'),d=cb.indexOf('D · PURCHASE DETAILS');assert.ok(a>=0&&b>a&&c>b&&d>c);assert.ok(cb.includes('QUALITY / VARIETY'));assert.ok(cb.includes('ITEM / MATERIAL *'));assert.ok(cb.includes('Allowed Art Categories'));assert.ok(cb.includes('rr_cb_material_estimate_v1'));assert.ok(cb.includes('rr_cb_material_po_draft_create_v1'))});


test('CB embedded editor header keeps active CB number visible',()=>{const js=fs.readFileSync(path.resolve(__dirname,'../../test70-real-chat-live-v70.js'),'utf8');assert.ok(js.includes("EDIT / CONTINUE · CB "));assert.ok(js.includes("EDIT / CONTINUE · NEW CB"));assert.ok(js.includes("actionUrl.searchParams.get('cb_no')"))});


test('Supplier PO is PCS-first, supplier-consolidated, thumbnail-aware and asks for physical cutting',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('+ ADD ANOTHER MATERIAL'));assert.ok(cb.includes('PURCHASE ORDER SUMMARY'));assert.ok(cb.includes('C'+"'"+'+esc(x.colour_no)'));assert.ok(cb.includes('rr_cb_material_estimate_v2'));assert.ok(cb.includes('rr_cb_supplier_po_generate_v1'));assert.ok(cb.includes('colour_image_url'));assert.ok(cb.includes('Physical cloth cutting/sample collect करें'));assert.ok(!cb.includes('rr_cb_material_po_draft_create_v1'))});


test('Multi-item multi-supplier PO remains dynamic and supplier grouped without hard supplier count',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('const groups=new Map()'));assert.ok(cb.includes('normalizedMasterName(m.vendor)'));assert.ok(cb.includes('groups.get(key).lines.push'));assert.ok(cb.includes('GENERATE PO · '));assert.ok(cb.includes('rr_cb_supplier_po_generate_v1'));assert.ok(cb.includes('po_no'));assert.ok(cb.includes('colour_image_url'));assert.ok(cb.includes('estimated_pcs'));assert.ok(cb.includes('Physical cloth cutting/sample collect करें'))});


test('Only add-another-material remains a large primary add action in Additional Material selection',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('+ ADD ANOTHER MATERIAL'));assert.ok(cb.includes('compact-master-row'));assert.ok(cb.includes('compact-new newMaterial'));assert.ok(cb.includes('compact-new addFabric'));assert.ok(!cb.includes('add-red newMaterial'));assert.ok(!cb.includes('add-red addFabric'))});


test('Every Additional Material selects category before decided-Art thumbnail and estimate',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const set=cb.indexOf('For which Set? *'),cat=cb.indexOf('Allowed Art Categories *'),thumb=cb.indexOf('MATCHED DECIDED ART'),estimate=cb.indexOf('C · REQUIREMENT ESTIMATE · PO BASIS');assert.ok(set>=0&&cat>set&&thumb>cat&&estimate>thumb);assert.ok(cb.includes('पहले Allowed Art Categories select करें.'));assert.ok(cb.includes('Selected Set का decided Art चुनी हुई category से match नहीं करता.'));assert.ok(cb.includes("if(!(m.allowedArtCategoryIds||[]).length)"))});


test('Additional Material uses progressive first-next chain and retires global add control',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('+ ADD FIRST MATERIAL'));assert.ok(cb.includes('+ ADD NEXT MATERIAL'));assert.ok(cb.includes('function addNextMaterial()'));assert.ok(cb.includes("querySelector('.addNextMaterial')"));assert.ok(!cb.includes('id="addMaterial"'));assert.ok(!cb.includes('+ ADD ANOTHER MATERIAL'));assert.ok(cb.includes('Current material selection complete करें, फिर अगला material add करें.'))});


test('Additional Material numbering excludes Regular Cloth and follows progressive sequence',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("materialNo=materials.slice(1,mi+1).filter(x=>x.type!=='regular').length"));assert.ok(cb.includes('MATERIAL ${materialNo}'));assert.ok(!cb.includes('<h4>Additional Material</h4>'))});


test('Material card uses alphabetic internal steps separate from material numbering',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('A · MATERIAL SELECTION'));assert.ok(cb.includes('B · SET & ART MAPPING'));assert.ok(cb.includes('C · REQUIREMENT ESTIMATE · PO BASIS'));assert.ok(cb.includes('D · PURCHASE DETAILS'));assert.ok(cb.includes('MATERIAL ${materialNo}'))});


test('CB supplier Add New persists canonical details and auto-selects saved supplier',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('CANONICAL SUPPLIER MASTER'));assert.ok(cb.includes('cbNewSupplierMobile'));assert.ok(cb.includes('cbNewSupplierAddress'));assert.ok(cb.includes('cbNewSupplierGstin'));assert.ok(cb.includes('rr_supplier_upsert_v1'));assert.ok(cb.includes('materials[supplierModalMaterialIndex].vendor=saved.supplier_name'));assert.ok(cb.includes('secondary compact-new addVendor'));assert.ok(!cb.includes("prompt('New Supplier Name'"))});


test('Supplier picker shows complete canonical active list and does not use filtered datalist',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('<select class="vendor"'));assert.ok(cb.includes('vendorOpts.map'));assert.ok(cb.includes('Select Supplier…'));assert.ok(cb.includes("querySelector('.vendor')?.addEventListener('change'"));assert.ok(!cb.includes('<input class="vendor" list="vendorHistory"'))});


test('New Additional Material never auto-selects all Sets or infers Art categories from material name',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("pricingDriver:'rate',scope:'selected',selected:[]"));assert.ok(cb.includes("m.scope='selected';m.selected=[];m.allowedArtCategoryIds=[]"));assert.ok(cb.includes('All Sets (manual)'))});


test('Set-wise Material Art constraint remains authoritative and decided Art cannot rewrite allowed categories',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('allowed_art_category_ids:allowed'));assert.ok(!cb.includes('effective=decided?'));assert.ok(cb.includes("existing decided Art does not match this Material's allowed categories"));assert.ok(cb.includes("decided Art category is outside this Material's Allowed Art Categories"))});


test('Art Decision picker consumes per-Set Material category constraint',()=>{const js=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8');assert.ok(js.includes("rr_cb_material_allocations"));assert.ok(js.includes("allowed_art_category_ids"));assert.ok(js.includes("list.filter(row=>state.allowedArtCategoryIds.includes(String(row.art_category_id||'')))"));assert.ok(js.includes('Material mapping applied · only allowed Art categories are shown for this Set.'))});


test('Existing decided Art reverse mirror runs after master hydration before thumbnails and estimates',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const seq="await loadExisting();await mastersPromise;await mirrorMaterialSetsFromDecidedArt();renderMaterials();renderColours();updateSummary();await loadArtThumbs();await loadMaterialEstimates()";assert.ok(cb.includes(seq));assert.ok(!cb.includes('Promise.allSettled([mirrorMaterialSetsFromDecidedArt(),loadReconciliation(),loadArtThumbs()])')});


test('Canonical material Art rules drive reverse Set mirror and Direct Art is complement only',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("rr_material_default_art_categories_v1"));assert.ok(cb.includes('await mirrorMaterialSetsFromDecidedArt()'));assert.ok(cb.includes("matched.forEach(unit=>mapped.add(String(unit.id)))"));assert.ok(cb.includes("const direct=units.filter(unit=>byUnit.get(String(unit.id))&&!mapped.has(String(unit.id)))"));assert.ok(cb.includes("for(const m of materials.filter(x=>x.type!=='regular'&&!(x.allowedArtCategoryIds||[]).length))"))});


test('Art Decision excludes category-less Arts and blocks category-less selection',()=>{const js=fs.readFileSync(path.resolve(__dirname,'../../real-art-decide-master-v9231.js'),'utf8');assert.ok(js.includes("if(step===\"art\")list=list.filter(row=>!!row.art_category_id)"));assert.ok(js.includes("if(!art?.art_category_id)"));assert.ok(js.includes('इस Art की category अभी mapped नहीं है.'))});


test('Canonical CB invokeSave exists and uses v600 idempotent save authority',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('async function invokeSave('));assert.ok(cb.includes("rr_cb_department_save_v601"));assert.ok(cb.includes('p_action_id:pa.actionId'));assert.ok(cb.includes('p_payload:body'))});


test('Technical errors never render raw through CB friendly error boundary',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('function isTechnicalError(raw)'));assert.ok(cb.includes('ReferenceError|TypeError|SyntaxError|is not defined'));assert.ok(cb.includes('Save पूरा नहीं हो सका. कृपया required details check करके दोबारा Save करें.'));assert.ok(!cb.includes('Canonical CB save service rejected the request'))});


test('Material Set Art mapping persists from save payload instead of post-save UI side effect',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('selected_sets:[...(m.selected||[])]'));assert.ok(cb.includes('allowed_art_category_ids:[...(m.allowedArtCategoryIds||[])]'));assert.ok(cb.includes("rr_cb_material_mapping_sync_v1"));assert.ok(!cb.includes("await syncAllowedArtMappings();$('stateChip')"))});


test('Save failures guide to exact relevant field or section with friendly message',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('function guideSaveError(ex)'));assert.ok(cb.includes("err.guide={selector:'.reconcile-box'}"));assert.ok(cb.includes("base+' .vendor'"));assert.ok(cb.includes("base+' .bill'"));assert.ok(cb.includes("base+' .date'"));assert.ok(cb.includes("base+' .rate'"));assert.ok(cb.includes("base+' .materialQty'"));assert.ok(cb.includes('const guided=guideSaveError(ex);setMessage(guided.message);focusGuidedIssue(guided)'))});


test('Save stage errors identify failing CB subsystem without raw technical text',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("e.saveStage='CB_SAVE'"));assert.ok(cb.includes("e.saveStage='MATERIAL_MAPPING'"));assert.ok(cb.includes("e.saveStage='GSM_SAVE'"));assert.ok(cb.includes('Material की Set / Art mapping save नहीं हो सकी.'));assert.ok(cb.includes('Colour GSM save नहीं हो सका.'));assert.ok(cb.includes("err.guide={selector:'.material-layer:nth-of-type(2)'}"))});


test('Statement timeout reports exact friendly reason instead of blaming required details',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('server save process timeout हुआ है'));assert.ok(cb.includes('/statement timeout|canceling statement|query canceled/i.test(raw)'))});


test('CB save uses bounded v601 wrapper while preserving canonical save authority',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("rr_cb_department_save_v601"));assert.ok(!cb.includes("sb().rpc('rr_cb_department_save_v600'"))});


test('CB save batches repeated Real Chat reconciliation through v601 authority',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("rr_cb_department_save_v601"))});


test('CB reconciliation report lifecycle uses idempotent v2 authorities',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconcile_v2'));assert.ok(cb.includes('rr_cb_shortage_report_v2'));assert.ok(!cb.includes("rpc('rr_cb_quantity_reconcile_v1'"));assert.ok(!cb.includes("rpc('rr_cb_shortage_report_v1'"))});


test('CB form shows view-only reconciliation decision history without reversed amount',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconcile_v3'));assert.ok(cb.includes('rr_cb_quantity_reconciliation_history_get_v1'));assert.ok(cb.includes('DECISION HISTORY'));assert.ok(cb.includes("h.status==='CURRENT'?'CURRENT':'REVERSED'"));assert.ok(!cb.includes('reconciliationHistory.map(h=>`<div><span>${esc(h.decision_date)} · ${esc(String(h.decision||\'\').replaceAll(\'_\',\' \'))} ₹'))});


test('CB reconciliation uses reversible v4 lifecycle and freezes actions after confirm',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconcile_v4'));assert.ok(cb.includes('function applyReconciliationFreeze()'));assert.ok(cb.includes("Decision frozen after SAVE & CONFIRM."))});


test('Normal Accounts Book uses reversal-pair filtered projections',()=>{const js=fs.readFileSync(path.resolve(__dirname,'../../real-accounts-v805.js'),'utf8');assert.ok(js.includes('rr_day_book_v807'));assert.ok(js.includes('rr_ledger_statement_v807'));assert.ok(!js.includes('rr_day_book_v806'));assert.ok(!js.includes('rr_ledger_statement_v806'))});


test('Decision change immediately refreshes view-only history',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_reconciliation_history_sync_v2'));assert.ok(cb.includes("const h=await sb().rpc('rr_cb_quantity_reconciliation_history_get_v1'"));assert.ok(cb.includes('reconciliationHistory=h.data||[];renderMaterials()'))});


test('CB form limits reconciliation view to previous and current while backend history remains complete',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("'CURRENT DECISION':'PREVIOUS DECISION'"));assert.ok(cb.includes('rows=[previous,current].filter(Boolean)'));assert.ok(!cb.includes('<strong>DECISION HISTORY</strong>'))});


test('CB reconciliation renders backend previous-current projection only without financial amount details',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconciliation_projection_v1'));assert.ok(cb.includes('${esc(h.view_role)} · ${esc(h.decision_date)}'));assert.ok(cb.includes('Decision: <b>${esc(x.decision)}</b> · Financial Qty'));assert.ok(!cb.includes('Debit ₹${Number(x.debit_amount'))});


test('Current detail remains above previous-current projection',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const detail=cb.indexOf('Decision: <b>${esc(x.decision)}</b> · Financial Qty'),projection=cb.indexOf('${esc(h.view_role)} · ${esc(h.decision_date)}');assert.ok(detail>=0&&projection>detail)});


test('CB boot rerenders reconciliation after projection load',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('Promise.allSettled([loadReconciliation()]).then(()=>{renderMaterials();updateSummary()});'))});


test('Reconciliation canonical load embeds decision projection in same backend snapshot',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconciliation_get_v2'));assert.ok(cb.includes('r.data?.decision_projection'));assert.ok(cb.includes('await loadReconciliation();renderMaterials();'))});


test('CB reconciliation decisions remain view-only until final confirm then post current decision',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_quantity_reconcile_draft_v5'));assert.ok(cb.includes('rr_cb_reconciliation_post_on_confirm_v1'));assert.ok(cb.includes('if(confirming&&cbId)'));assert.ok(cb.includes('Accounts posting will happen only on SAVE & CONFIRM.'))});


test('Optional CB projections cannot collapse canonical detail load',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("console.warn('CB optional art mirror'"));assert.ok(cb.includes("console.warn('CB optional art thumbnails'"));assert.ok(cb.includes("console.warn('CB optional material estimates'"))});


test('Canonical CB detail survives enrichment failures inside loadExisting',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("console.warn('CB optional GSM enrichment'"));assert.ok(cb.includes("console.warn('CB optional entry enrichment'"));assert.ok(cb.includes("console.warn('CB optional unit enrichment'"));assert.ok(cb.includes("console.warn('CB optional allocation enrichment'"));assert.ok(!cb.includes('if(mapRows.error)throw mapRows.error'));assert.ok(!cb.includes('if(unitRows.error)throw unitRows.error'));assert.ok(!cb.includes('if(ar.error)throw ar.error'))});


test('Saved CB canonical load is independent of optional master bootstrap while new CB still requires masters',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('savedMastersPromise=Promise.allSettled'));assert.ok(cb.includes("console.warn('CB saved-form optional master load'"));assert.ok(cb.includes('else{await mastersPromise;'))});


test('Saved CB master bootstrap runs once before canonical hydration and new CB stays strict',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('const masterResults=await Promise.allSettled([loadCanonicalMasters(),loadCategories(),loadOptions()]);await loadExisting();'));assert.ok(cb.includes('else{await Promise.all([loadCanonicalMasters(),loadCategories(),loadOptions()]);'));assert.ok(!cb.includes('savedMastersPromise'));assert.ok(!cb.includes('mastersPromise=Promise.all'))});


test('CB reconciliation render state is declared before use',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');const decl=cb.indexOf('reconciliation=null,reconciliationHistory=[]'),render=cb.indexOf('function reconciliationPanel()');assert.ok(decl>=0&&render>decl);assert.ok(!cb.includes("cbLoadStage"));assert.ok(!cb.includes("loadStage='RENDER'"))});


test('Additional Material decided Set ownership is unique in mirror and backend sync',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_material_mapping_sync_v2'));assert.ok(cb.includes('rr_cb_material_mapping_sync_v4'));assert.ok(cb.includes('function defaultUsageRoles(m)'))});


test('CB material usage role defaults and N A are canonical',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("role:'COLLAR'"));assert.ok(cb.includes("role:'CUFF'"));assert.ok(cb.includes("role:'NECK_RIB'"));assert.ok(cb.includes("role:'SLEEVE_RIB'"));assert.ok(cb.includes('N/A · NOT APPLICABLE'));assert.ok(cb.includes('rr_cb_material_mapping_sync_v4'))});
test('Used material category is hidden from later Additional Material cards',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("const used=new Set(materials.filter(x=>x.type!=='regular'&&x!==m&&x.categoryId)"))});


test('Duplicate Additional Material category is blocked canonically and hidden from later cards',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_cb_material_mapping_sync_v4'));assert.ok(cb.includes("const used=new Set(materials.filter(x=>x.type!=='regular'&&x!==m&&x.categoryId)"))});


test('Collar Cuff aliases expose one canonical material while legacy history remains immutable',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("c.is_active!==false"));assert.ok(cb.includes("!=='cuff-collar'"))});


test('Add New Material requires canonical duplicate guard before create',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('rr_material_canonical_guard_v1'));assert.ok(cb.includes("g.status==='EXACT'"));assert.ok(cb.includes("g.status==='SIMILAR'"));assert.ok(cb.includes('Press Save again only if this is genuinely a different material.'))});


test('CB pre Art Set specification binds category sleeve finish and sizes',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('SET CONSTRUCTION · PRE-ART SPEC'));assert.ok(cb.includes('HALF SLEEVE'));assert.ok(cb.includes('FULL SLEEVE'));assert.ok(cb.includes('WITH CUFF / TAPE'));assert.ok(cb.includes('WITH RIB'));assert.ok(cb.includes('rr_cb_set_requirement_sync_v2'))});


test('Cuff and Tape are one canonical sleeve finish',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('CUFF_TAPE'));assert.ok(cb.includes('WITH CUFF / TAPE'));assert.ok(cb.includes("role:'CUFF_TAPE'"))});


test('Collar and Cuff material uses independent Collar neck and Cuff sleeve switches',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes("role:'COLLAR'},{zone:'SLEEVE',role:'CUFF'"));assert.ok(cb.includes('>WITH CUFF</option>'));assert.ok(!cb.includes('>WITH CUFF / TAPE</option>'));assert.ok(cb.includes("['N_A','N/A · NOT APPLICABLE'],['CUFF','CUFF']"))});


test('CB construction defaults Half Sleeve Cuff and L XL XXL with canonical size groups',()=>{const cb=fs.readFileSync(path.resolve(__dirname,'../../real-cb-new-v9130-fix2.html'),'utf8');assert.ok(cb.includes('HALF SLEEVE'));assert.ok(cb.includes('WITH CUFF'));assert.ok(!cb.includes('WITH TAPE'));assert.ok(cb.includes('2XL, 3XL, 4XL'));assert.ok(cb.includes('3XL, 4XL, 5XL'));assert.ok(cb.includes('FREE SIZE'));assert.ok(cb.includes('rr_cb_set_requirement_sync_v2'))});
